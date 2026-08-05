WITH repeated_conversion_sessions AS (
  SELECT
    conversion_session_key AS session_key,
    user_pseudo_id,
    COUNT(*) AS order_count,
    COUNT(DISTINCT order_ts) AS distinct_order_timestamp_count,
    MIN(order_ts) AS first_order_ts,
    MAX(order_ts) AS last_order_ts,
    ARRAY_AGG(order_key ORDER BY order_ts, order_key) AS order_keys
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
  WHERE conversion_session_key IS NOT NULL
  GROUP BY conversion_session_key, user_pseudo_id
  HAVING COUNT(*) > 1
),
path_assignments AS (
  SELECT
    session_key,
    COUNT(DISTINCT order_key) AS assigned_path_order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  GROUP BY session_key
)
SELECT
  repeated_conversion_sessions.session_key,
  repeated_conversion_sessions.user_pseudo_id,
  repeated_conversion_sessions.order_count,
  repeated_conversion_sessions.distinct_order_timestamp_count,
  repeated_conversion_sessions.first_order_ts,
  repeated_conversion_sessions.last_order_ts,
  repeated_conversion_sessions.order_keys,
  COALESCE(path_assignments.assigned_path_order_count, 0) AS assigned_path_order_count,
  COALESCE(path_assignments.assigned_path_order_count, 0) > 1 AS session_reuse_violation
FROM repeated_conversion_sessions
LEFT JOIN path_assignments USING (session_key)
