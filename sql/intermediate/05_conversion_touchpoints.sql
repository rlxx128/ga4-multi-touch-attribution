-- Disjoint conversion cycles: after the previous order and through the current
-- order, bounded to 30 days. Equal-timestamp orders are deterministically
-- sequenced so a Session cannot be silently reused.
WITH order_cycles AS (
  {{ORDER_CYCLES_QUERY}}
),
eligible_touchpoints AS (
  SELECT
    orders.order_key,
    orders.user_pseudo_id,
    orders.transaction_id,
    orders.order_ts,
    orders.order_date,
    orders.order_revenue_usd,
    orders.previous_order_ts,
    orders.same_timestamp_order_count,
    orders.same_timestamp_order_sequence,
    sessions.session_key,
    sessions.ga_session_id,
    sessions.session_start_ts,
    sessions.session_end_ts,
    sessions.source_resolution_tier,
    sessions.resolved_source,
    sessions.resolved_medium,
    sessions.resolved_campaign,
    sessions.source_missing_flag,
    sessions.source_quality,
    sessions.is_inferred_source,
    sessions.inference_rule,
    sessions.is_internal_admin_candidate,
    sessions.channel,
    sessions.mapping_version
  FROM order_cycles AS orders
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints` AS sessions
    ON orders.user_pseudo_id = sessions.user_pseudo_id
    AND sessions.session_start_ts <= orders.order_ts
    AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
    AND (orders.previous_order_ts IS NULL OR sessions.session_start_ts > orders.previous_order_ts)
  WHERE sessions.is_marketing_eligible
    AND sessions.channel IS NOT NULL
),
numbered_touchpoints AS (
  SELECT
    eligible_touchpoints.*,
    ROW_NUMBER() OVER (
      PARTITION BY order_key
      ORDER BY session_start_ts, session_key
    ) AS touchpoint_number,
    COUNT(*) OVER (PARTITION BY order_key) AS path_length
  FROM eligible_touchpoints
)
SELECT
  order_key,
  user_pseudo_id,
  transaction_id,
  order_ts,
  order_date,
  order_revenue_usd,
  previous_order_ts,
  same_timestamp_order_count,
  same_timestamp_order_sequence,
  session_key,
  ga_session_id,
  session_start_ts AS touchpoint_ts,
  session_end_ts,
  touchpoint_number,
  path_length,
  TIMESTAMP_DIFF(order_ts, session_start_ts, SECOND) AS seconds_before_conversion,
  source_resolution_tier,
  resolved_source,
  resolved_medium,
  resolved_campaign,
  source_missing_flag,
  source_quality,
  is_inferred_source,
  inference_rule,
  is_internal_admin_candidate,
  channel,
  mapping_version
FROM numbered_touchpoints
