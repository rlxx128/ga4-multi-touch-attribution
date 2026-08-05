SELECT
  order_key,
  user_pseudo_id,
  transaction_id,
  order_ts,
  order_date,
  conversion_session_key,
  order_revenue_usd,
  LAG(order_ts) OVER (
    PARTITION BY user_pseudo_id
    ORDER BY order_ts, order_key
  ) AS previous_order_ts,
  COUNT(*) OVER (
    PARTITION BY user_pseudo_id, order_ts
  ) AS same_timestamp_order_count,
  ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id, order_ts
    ORDER BY order_key
  ) AS same_timestamp_order_sequence
FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
