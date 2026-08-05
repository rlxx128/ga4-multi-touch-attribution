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
    ) AS temporally_eligible_session_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (orders.previous_order_ts IS NULL OR sessions.session_start_ts > orders.previous_order_ts)
      AND sessions.is_internal_admin_traffic
    ) AS temporally_eligible_admin_session_count,
    COUNTIF(
      sessions.session_start_ts <= orders.order_ts
      AND sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
      AND (orders.previous_order_ts IS NULL OR sessions.session_start_ts > orders.previous_order_ts)
      AND sessions.is_marketing_eligible
      AND sessions.channel IS NOT NULL
    ) AS marketing_eligible_session_count
  FROM order_cycles AS orders
  LEFT JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints` AS sessions
    ON orders.user_pseudo_id = sessions.user_pseudo_id
  GROUP BY orders.order_key
),
path_counts AS (
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
  orders.order_revenue_usd,
  orders.previous_order_ts,
  orders.same_timestamp_order_count,
  orders.same_timestamp_order_sequence,
  session_counts.all_user_session_count,
  session_counts.session_on_or_before_order_count,
  session_counts.session_within_30_days_count,
  session_counts.temporally_eligible_session_count,
  session_counts.temporally_eligible_admin_session_count,
  session_counts.marketing_eligible_session_count,
  COALESCE(path_counts.conversion_touchpoint_count, 0) AS conversion_touchpoint_count,
  session_counts.temporally_eligible_session_count > 0 AS path_covered_before_admin_exclusion,
  COALESCE(path_counts.conversion_touchpoint_count, 0) > 0 AS path_covered_after_admin_exclusion,
  session_counts.temporally_eligible_session_count > 0
    AND COALESCE(path_counts.conversion_touchpoint_count, 0) = 0 AS coverage_lost_after_admin_exclusion
FROM order_cycles AS orders
INNER JOIN session_counts USING (order_key)
LEFT JOIN path_counts USING (order_key)
