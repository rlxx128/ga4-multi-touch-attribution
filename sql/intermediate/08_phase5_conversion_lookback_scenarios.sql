-- Phase 5 rule-based lookback scenarios. The approved conversion touchpoints
-- remain immutable; each scenario filters them into an isolated derived path.
WITH scenario_windows AS (
  SELECT 'P5_B_LB7_V1' AS scenario_id, 7 AS lookback_days
  UNION ALL
  SELECT 'P5_A_LB14_V1', 14
  UNION ALL
  SELECT 'P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1', 30
),
eligible_touchpoints AS (
  SELECT
    scenario_windows.scenario_id,
    scenario_windows.lookback_days,
    conversion_touchpoints.order_key,
    conversion_touchpoints.user_pseudo_id,
    conversion_touchpoints.transaction_id,
    conversion_touchpoints.order_ts,
    conversion_touchpoints.order_date,
    conversion_touchpoints.order_revenue_usd,
    conversion_touchpoints.session_key,
    conversion_touchpoints.touchpoint_number AS baseline_touchpoint_number,
    conversion_touchpoints.seconds_before_conversion,
    conversion_touchpoints.channel,
    conversion_touchpoints.mapping_version,
    conversion_touchpoints.path_definition_version
  FROM scenario_windows
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
    AS conversion_touchpoints
    ON conversion_touchpoints.seconds_before_conversion
      <= scenario_windows.lookback_days * 24 * 60 * 60
),
common_cohort_orders AS (
  SELECT order_key
  FROM eligible_touchpoints
  GROUP BY order_key
  HAVING COUNT(DISTINCT scenario_id) = 3
),
scenario_cohort_views AS (
  SELECT 'P5_B_LB7_V1' AS scenario_id, 'population_impact' AS cohort_view
  UNION ALL SELECT 'P5_B_LB7_V1', 'common_cohort'
  UNION ALL SELECT 'P5_A_LB14_V1', 'population_impact'
  UNION ALL SELECT 'P5_A_LB14_V1', 'common_cohort'
  UNION ALL
  SELECT 'P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1', 'baseline'
  UNION ALL
  SELECT 'P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1', 'common_cohort'
),
cohort_touchpoints AS (
  SELECT
    eligible_touchpoints.scenario_id,
    scenario_cohort_views.cohort_view,
    eligible_touchpoints.lookback_days,
    eligible_touchpoints.order_key,
    eligible_touchpoints.user_pseudo_id,
    eligible_touchpoints.transaction_id,
    eligible_touchpoints.order_ts,
    eligible_touchpoints.order_date,
    eligible_touchpoints.order_revenue_usd,
    eligible_touchpoints.session_key,
    eligible_touchpoints.baseline_touchpoint_number,
    eligible_touchpoints.seconds_before_conversion,
    eligible_touchpoints.channel,
    eligible_touchpoints.mapping_version,
    eligible_touchpoints.path_definition_version
  FROM eligible_touchpoints
  INNER JOIN scenario_cohort_views
    ON scenario_cohort_views.scenario_id = eligible_touchpoints.scenario_id
  LEFT JOIN common_cohort_orders
    ON common_cohort_orders.order_key = eligible_touchpoints.order_key
  WHERE scenario_cohort_views.cohort_view != 'common_cohort'
    OR common_cohort_orders.order_key IS NOT NULL
),
numbered_touchpoints AS (
  SELECT
    scenario_id,
    cohort_view,
    lookback_days,
    order_key,
    user_pseudo_id,
    transaction_id,
    order_ts,
    order_date,
    order_revenue_usd,
    session_key,
    seconds_before_conversion,
    channel,
    mapping_version,
    path_definition_version,
    ROW_NUMBER() OVER (
      PARTITION BY scenario_id, cohort_view, order_key
      ORDER BY baseline_touchpoint_number, session_key
    ) AS touchpoint_number,
    COUNT(*) OVER (
      PARTITION BY scenario_id, cohort_view, order_key
    ) AS path_length
  FROM cohort_touchpoints
),
prepared_touchpoints AS (
  SELECT
    scenario_id,
    cohort_view,
    lookback_days,
    order_key,
    user_pseudo_id,
    transaction_id,
    order_ts,
    order_date,
    order_revenue_usd,
    touchpoint_number,
    path_length,
    seconds_before_conversion,
    channel,
    mapping_version,
    path_definition_version,
    MAX(IF(channel != 'Direct', touchpoint_number, NULL)) OVER (
      PARTITION BY scenario_id, cohort_view, order_key
    ) AS last_non_direct_touchpoint_number,
    POW(
      0.5,
      SAFE_DIVIDE(CAST(seconds_before_conversion AS FLOAT64), 7 * 24 * 60 * 60)
    ) AS time_decay_raw_weight
  FROM numbered_touchpoints
),
normalized_touchpoints AS (
  SELECT
    scenario_id,
    cohort_view,
    lookback_days,
    order_key,
    user_pseudo_id,
    transaction_id,
    order_ts,
    order_date,
    order_revenue_usd,
    touchpoint_number,
    path_length,
    channel,
    mapping_version,
    path_definition_version,
    last_non_direct_touchpoint_number,
    SAFE_DIVIDE(
      time_decay_raw_weight,
      SUM(time_decay_raw_weight) OVER (
        PARTITION BY scenario_id, cohort_view, order_key
      )
    ) AS time_decay_weight
  FROM prepared_touchpoints
),
touchpoint_model_weights AS (
  SELECT scenario_id, cohort_view, lookback_days, order_key, user_pseudo_id,
    transaction_id, order_ts, order_date, order_revenue_usd, path_length,
    channel, mapping_version, path_definition_version,
    'First Click' AS model,
    IF(touchpoint_number = 1, 1.0, 0.0) AS attribution_weight
  FROM normalized_touchpoints
  UNION ALL
  SELECT scenario_id, cohort_view, lookback_days, order_key, user_pseudo_id,
    transaction_id, order_ts, order_date, order_revenue_usd, path_length,
    channel, mapping_version, path_definition_version,
    'Last Click', IF(touchpoint_number = path_length, 1.0, 0.0)
  FROM normalized_touchpoints
  UNION ALL
  SELECT scenario_id, cohort_view, lookback_days, order_key, user_pseudo_id,
    transaction_id, order_ts, order_date, order_revenue_usd, path_length,
    channel, mapping_version, path_definition_version,
    'Last Non-direct Click',
    IF(
      touchpoint_number = COALESCE(last_non_direct_touchpoint_number, path_length),
      1.0,
      0.0
    )
  FROM normalized_touchpoints
  UNION ALL
  SELECT scenario_id, cohort_view, lookback_days, order_key, user_pseudo_id,
    transaction_id, order_ts, order_date, order_revenue_usd, path_length,
    channel, mapping_version, path_definition_version,
    'Linear', SAFE_DIVIDE(1.0, path_length)
  FROM normalized_touchpoints
  UNION ALL
  SELECT scenario_id, cohort_view, lookback_days, order_key, user_pseudo_id,
    transaction_id, order_ts, order_date, order_revenue_usd, path_length,
    channel, mapping_version, path_definition_version,
    'Time Decay', time_decay_weight
  FROM normalized_touchpoints
),
aggregated_attribution AS (
  SELECT
    scenario_id,
    cohort_view,
    ANY_VALUE(lookback_days) AS lookback_days,
    model,
    channel,
    SUM(attribution_weight) AS attributed_conversions,
    SUM(order_revenue_usd * attribution_weight) AS attributed_revenue
  FROM touchpoint_model_weights
  WHERE attribution_weight > 0
  GROUP BY scenario_id, cohort_view, model, channel
),
order_paths AS (
  SELECT
    scenario_id,
    cohort_view,
    order_key,
    ANY_VALUE(order_revenue_usd) AS order_revenue_usd,
    ANY_VALUE(path_length) AS path_length
  FROM normalized_touchpoints
  GROUP BY scenario_id, cohort_view, order_key
),
path_medians AS (
  SELECT
    scenario_id,
    cohort_view,
    ANY_VALUE(median_path_length) AS median_path_length
  FROM (
    SELECT
      scenario_id,
      cohort_view,
      PERCENTILE_CONT(path_length, 0.5) OVER (
        PARTITION BY scenario_id, cohort_view
      ) AS median_path_length
    FROM order_paths
  )
  GROUP BY scenario_id, cohort_view
),
path_summaries AS (
  SELECT
    order_paths.scenario_id,
    order_paths.cohort_view,
    COUNT(*) AS attributable_order_count,
    ROUND(SUM(order_revenue_usd), 2) AS attributable_revenue,
    AVG(path_length) AS average_path_length,
    ANY_VALUE(path_medians.median_path_length) AS median_path_length,
    SAFE_DIVIDE(COUNTIF(path_length > 1), COUNT(*)) AS multi_touch_share
  FROM order_paths
  INNER JOIN path_medians
    ON path_medians.scenario_id = order_paths.scenario_id
    AND path_medians.cohort_view = order_paths.cohort_view
  GROUP BY order_paths.scenario_id, order_paths.cohort_view
),
channel_touchpoints AS (
  SELECT
    scenario_id,
    cohort_view,
    channel,
    COUNT(*) AS channel_touchpoint_count
  FROM normalized_touchpoints
  GROUP BY scenario_id, cohort_view, channel
),
channel_totals AS (
  SELECT scenario_id, cohort_view, SUM(channel_touchpoint_count) AS touchpoint_count
  FROM channel_touchpoints
  GROUP BY scenario_id, cohort_view
)
SELECT
  aggregated_attribution.scenario_id,
  aggregated_attribution.cohort_view,
  aggregated_attribution.lookback_days,
  aggregated_attribution.model,
  aggregated_attribution.channel,
  path_summaries.attributable_order_count,
  path_summaries.attributable_revenue,
  path_summaries.average_path_length,
  path_summaries.median_path_length,
  path_summaries.multi_touch_share,
  channel_touchpoints.channel_touchpoint_count,
  SAFE_DIVIDE(
    channel_touchpoints.channel_touchpoint_count,
    channel_totals.touchpoint_count
  ) AS channel_touchpoint_share,
  aggregated_attribution.attributed_conversions,
  aggregated_attribution.attributed_revenue,
  SAFE_DIVIDE(
    aggregated_attribution.attributed_conversions,
    path_summaries.attributable_order_count
  ) AS conversion_share,
  SAFE_DIVIDE(
    aggregated_attribution.attributed_revenue,
    path_summaries.attributable_revenue
  ) AS revenue_share
FROM aggregated_attribution
INNER JOIN path_summaries
  ON path_summaries.scenario_id = aggregated_attribution.scenario_id
  AND path_summaries.cohort_view = aggregated_attribution.cohort_view
INNER JOIN channel_touchpoints
  ON channel_touchpoints.scenario_id = aggregated_attribution.scenario_id
  AND channel_touchpoints.cohort_view = aggregated_attribution.cohort_view
  AND channel_touchpoints.channel = aggregated_attribution.channel
INNER JOIN channel_totals
  ON channel_totals.scenario_id = aggregated_attribution.scenario_id
  AND channel_totals.cohort_view = aggregated_attribution.cohort_view
