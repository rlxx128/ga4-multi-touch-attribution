-- One row per approved user_pseudo_id plus valid transaction_id order key.
WITH eligible_purchase_events AS (
  SELECT
    user_pseudo_id,
    TRIM(transaction_id) AS transaction_id,
    event_ts,
    session_key,
    purchase_revenue_in_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  WHERE event_name = 'purchase'
    AND user_pseudo_id IS NOT NULL
    AND transaction_id IS NOT NULL
    AND TRIM(transaction_id) != ''
    AND LOWER(TRIM(transaction_id)) != '(not set)'
),
deduplicated_orders AS (
  SELECT
    TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      user_pseudo_id AS user_pseudo_id,
      transaction_id AS transaction_id
    )))) AS order_key,
    user_pseudo_id,
    transaction_id,
    MIN(event_ts) AS order_ts,
    ARRAY_AGG(session_key IGNORE NULLS ORDER BY event_ts LIMIT 1)[SAFE_OFFSET(0)] AS conversion_session_key,
    MAX(purchase_revenue_in_usd) AS order_revenue_usd,
    COUNT(*) AS purchase_event_count,
    COUNT(*) - 1 AS duplicate_purchase_event_count,
    COUNT(DISTINCT purchase_revenue_in_usd) AS distinct_revenue_value_count,
    MIN(purchase_revenue_in_usd) AS minimum_observed_revenue_usd,
    MAX(purchase_revenue_in_usd) AS maximum_observed_revenue_usd
  FROM eligible_purchase_events
  GROUP BY user_pseudo_id, transaction_id
)
SELECT
  order_key,
  user_pseudo_id,
  transaction_id,
  order_ts,
  DATE(order_ts) AS order_date,
  conversion_session_key,
  order_revenue_usd,
  purchase_event_count,
  duplicate_purchase_event_count,
  distinct_revenue_value_count,
  minimum_observed_revenue_usd,
  maximum_observed_revenue_usd
FROM deduplicated_orders;
