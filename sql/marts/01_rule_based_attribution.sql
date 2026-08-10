-- Canonical Phase 3 rule-based attribution at order x model x channel grain.
-- Repeated Sessions and repeated channels remain separate during touchpoint-level
-- weighting and are aggregated only in the final SELECT.
WITH prepared_touchpoints AS (
  SELECT
    order_key,
    user_pseudo_id,
    transaction_id,
    order_ts,
    order_date,
    order_revenue_usd,
    session_key,
    touchpoint_number,
    path_length,
    seconds_before_conversion,
    channel,
    mapping_version,
    path_definition_version,
    MAX(IF(channel != 'Direct', touchpoint_number, NULL)) OVER (
      PARTITION BY order_key
    ) AS last_non_direct_touchpoint_number,
    POW(
      0.5,
      SAFE_DIVIDE(CAST(seconds_before_conversion AS FLOAT64), 7 * 24 * 60 * 60)
    ) AS time_decay_raw_weight
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
normalized_touchpoints AS (
  SELECT
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
      SUM(time_decay_raw_weight) OVER (PARTITION BY order_key)
    ) AS time_decay_weight
  FROM prepared_touchpoints
),
touchpoint_model_weights AS (
  SELECT
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
    'First Click' AS model,
    IF(touchpoint_number = 1, 1.0, 0.0) AS attribution_weight
  FROM normalized_touchpoints

  UNION ALL

  SELECT
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
    'Last Click' AS model,
    IF(touchpoint_number = path_length, 1.0, 0.0) AS attribution_weight
  FROM normalized_touchpoints

  UNION ALL

  SELECT
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
    'Last Non-direct Click' AS model,
    IF(
      touchpoint_number = COALESCE(last_non_direct_touchpoint_number, path_length),
      1.0,
      0.0
    ) AS attribution_weight
  FROM normalized_touchpoints

  UNION ALL

  SELECT
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
    'Linear' AS model,
    SAFE_DIVIDE(1.0, path_length) AS attribution_weight
  FROM normalized_touchpoints

  UNION ALL

  SELECT
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
    'Time Decay' AS model,
    time_decay_weight AS attribution_weight
  FROM normalized_touchpoints
),
positive_weight_rows AS (
  SELECT
    order_key,
    user_pseudo_id,
    transaction_id,
    order_ts,
    order_date,
    order_revenue_usd,
    path_length,
    model,
    channel,
    attribution_weight,
    mapping_version,
    path_definition_version
  FROM touchpoint_model_weights
  WHERE attribution_weight > 0
)
SELECT
  user_pseudo_id,
  order_key,
  transaction_id,
  order_ts,
  order_date,
  model,
  channel,
  SUM(attribution_weight) AS attribution_weight,
  SUM(attribution_weight) AS attributed_conversion,
  SUM(order_revenue_usd * attribution_weight) AS attributed_revenue,
  ANY_VALUE(order_revenue_usd) AS order_revenue_usd,
  ANY_VALUE(path_length) AS path_length,
  ANY_VALUE(mapping_version) AS mapping_version,
  ANY_VALUE(path_definition_version) AS path_definition_version,
  IF(model = 'Time Decay', 7, NULL) AS time_decay_half_life_days,
  'phase3_rule_attribution_v1_20260809' AS attribution_version
FROM positive_weight_rows
GROUP BY
  user_pseudo_id,
  order_key,
  transaction_id,
  order_ts,
  order_date,
  model,
  channel
