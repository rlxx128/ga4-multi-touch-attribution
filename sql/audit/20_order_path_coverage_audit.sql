WITH order_cycles AS (
  {{ORDER_CYCLES_QUERY}}
),
session_counts AS (
  SELECT
    orders.order_key,
    COUNT(sessions.session_key) AS all_user_session_count,
    COUNTIF(sessions.session_start_ts <= orders.order_ts) AS session_on_or_before_order_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
    ) AS session_within_30_days_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (orders.previous_order_ts IS NULL OR sessions.session_start_ts > orders.previous_order_ts)
    ) AS strict_pre_internal_exclusion_session_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (orders.previous_order_ts IS NULL OR sessions.session_start_ts > orders.previous_order_ts)
      AND COALESCE(sessions.resolved_source_host, '') != 'analytics.google.com'
    ) AS historical_baseline_touchpoint_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (orders.previous_order_ts IS NULL OR sessions.session_start_ts > orders.previous_order_ts)
      AND sessions.is_internal_admin_traffic
    ) AS strict_internal_admin_session_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (orders.previous_order_ts IS NULL OR sessions.session_start_ts > orders.previous_order_ts)
      AND sessions.is_attribution_eligible
      AND NOT sessions.is_internal_admin_traffic
      AND sessions.channel != 'Internal/Admin'
    ) AS strict_attribution_eligible_session_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (
        orders.previous_order_ts IS NULL
        OR sessions.session_start_ts > orders.previous_order_ts
        OR sessions.session_key = orders.conversion_session_key
      )
    ) AS revised_pre_internal_exclusion_session_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (
        orders.previous_order_ts IS NULL
        OR sessions.session_start_ts > orders.previous_order_ts
        OR sessions.session_key = orders.conversion_session_key
      )
      AND sessions.is_internal_admin_traffic
    ) AS revised_internal_admin_session_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (
        orders.previous_order_ts IS NULL
        OR sessions.session_start_ts > orders.previous_order_ts
        OR sessions.session_key = orders.conversion_session_key
      )
      AND sessions.is_attribution_eligible
      AND NOT sessions.is_internal_admin_traffic
      AND sessions.channel != 'Internal/Admin'
    ) AS revised_attribution_eligible_session_count,
    COUNTIF(
      orders.previous_order_ts IS NOT NULL
      AND sessions.session_start_ts <= orders.previous_order_ts
      AND sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND sessions.session_key = orders.conversion_session_key
    ) AS current_conversion_session_exception_candidate_count
  FROM order_cycles AS orders
  LEFT JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints` AS sessions
    ON orders.user_pseudo_id = sessions.user_pseudo_id
  GROUP BY orders.order_key
),
strict_path_counts AS (
  SELECT order_key, COUNT(*) AS strict_conversion_touchpoint_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints_strict`
  GROUP BY order_key
),
revised_path_counts AS (
  SELECT order_key, COUNT(*) AS conversion_touchpoint_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  GROUP BY order_key
)
SELECT
  orders.order_key,
  orders.user_pseudo_id,
  orders.transaction_id,
  orders.order_ts,
  orders.order_date,
  orders.conversion_session_key,
  orders.order_revenue_usd,
  orders.previous_order_ts,
  orders.same_timestamp_order_count,
  orders.same_timestamp_order_sequence,
  session_counts.all_user_session_count,
  session_counts.session_on_or_before_order_count,
  session_counts.session_within_30_days_count,
  session_counts.strict_pre_internal_exclusion_session_count,
  session_counts.historical_baseline_touchpoint_count,
  session_counts.strict_internal_admin_session_count,
  session_counts.strict_attribution_eligible_session_count,
  session_counts.revised_pre_internal_exclusion_session_count,
  session_counts.revised_internal_admin_session_count,
  session_counts.revised_attribution_eligible_session_count,
  session_counts.current_conversion_session_exception_candidate_count,
  COALESCE(strict_path_counts.strict_conversion_touchpoint_count, 0)
    AS strict_conversion_touchpoint_count,
  COALESCE(revised_path_counts.conversion_touchpoint_count, 0)
    AS conversion_touchpoint_count,
  COALESCE(strict_path_counts.strict_conversion_touchpoint_count, 0) > 0
    AS path_covered_strict,
  session_counts.historical_baseline_touchpoint_count > 0
    AS path_covered_historical_baseline,
  COALESCE(revised_path_counts.conversion_touchpoint_count, 0) > 0
    AS path_covered_revised,
  COALESCE(revised_path_counts.conversion_touchpoint_count, 0) > 0
    AS path_covered_after_admin_exclusion,
  COALESCE(strict_path_counts.strict_conversion_touchpoint_count, 0) = 0
    AND COALESCE(revised_path_counts.conversion_touchpoint_count, 0) > 0
    AS recovered_by_current_conversion_session_exception,
  session_counts.historical_baseline_touchpoint_count = 0
    AND COALESCE(revised_path_counts.conversion_touchpoint_count, 0) > 0
    AS historical_unmatched_recovered_by_exception,
  session_counts.historical_baseline_touchpoint_count > 0
    AND COALESCE(revised_path_counts.conversion_touchpoint_count, 0) = 0
    AS historical_covered_order_lost_after_closeout,
  session_counts.revised_pre_internal_exclusion_session_count > 0
    AND COALESCE(revised_path_counts.conversion_touchpoint_count, 0) = 0
    AS coverage_lost_after_internal_exclusion,
  'phase2b_closeout_v1_20260806' AS path_definition_version
FROM order_cycles AS orders
INNER JOIN session_counts USING (order_key)
LEFT JOIN strict_path_counts USING (order_key)
LEFT JOIN revised_path_counts USING (order_key)
