-- Hash candidate order keys before exporting duplicate diagnostics locally.
WITH purchases AS (
  SELECT
    user_pseudo_id,
    NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
    LOWER(TRIM(ecommerce.transaction_id)) IN (
      '<other>',
      '(not set)',
      '(not provided)',
      '(data deleted)',
      'unknown'
    ) AS is_placeholder_transaction_id,
    event_timestamp,
    ecommerce.purchase_revenue AS purchase_revenue,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue_in_usd
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
    AND event_name = 'purchase'
),
duplicate_candidates AS (
  SELECT
    TO_HEX(
      SHA256(
        TO_JSON_STRING(
          STRUCT(user_pseudo_id AS user_pseudo_id, transaction_id AS transaction_id)
        )
      )
    ) AS audit_order_key_hash,
    LOGICAL_OR(is_placeholder_transaction_id) AS is_placeholder_transaction_id,
    COUNT(*) AS purchase_event_count,
    COUNT(DISTINCT event_timestamp) AS distinct_event_timestamp_count,
    TIMESTAMP_MICROS(MIN(event_timestamp)) AS first_purchase_event_ts,
    TIMESTAMP_MICROS(MAX(event_timestamp)) AS last_purchase_event_ts,
    COUNT(
      DISTINCT IF(
        purchase_revenue IS NOT NULL
          AND NOT IS_NAN(purchase_revenue)
          AND NOT IS_INF(purchase_revenue),
        CAST(purchase_revenue AS STRING),
        NULL
      )
    ) AS distinct_finite_revenue_count,
    MIN(
      IF(
        purchase_revenue IS NOT NULL
          AND NOT IS_NAN(purchase_revenue)
          AND NOT IS_INF(purchase_revenue),
        purchase_revenue,
        NULL
      )
    ) AS minimum_finite_revenue,
    MAX(
      IF(
        purchase_revenue IS NOT NULL
          AND NOT IS_NAN(purchase_revenue)
          AND NOT IS_INF(purchase_revenue),
        purchase_revenue,
        NULL
      )
    ) AS maximum_finite_revenue,
    COUNT(
      DISTINCT IF(
        purchase_revenue_in_usd IS NOT NULL
          AND NOT IS_NAN(purchase_revenue_in_usd)
          AND NOT IS_INF(purchase_revenue_in_usd),
        CAST(purchase_revenue_in_usd AS STRING),
        NULL
      )
    ) AS distinct_finite_revenue_usd_count,
    MIN(
      IF(
        purchase_revenue_in_usd IS NOT NULL
          AND NOT IS_NAN(purchase_revenue_in_usd)
          AND NOT IS_INF(purchase_revenue_in_usd),
        purchase_revenue_in_usd,
        NULL
      )
    ) AS minimum_finite_revenue_usd,
    MAX(
      IF(
        purchase_revenue_in_usd IS NOT NULL
          AND NOT IS_NAN(purchase_revenue_in_usd)
          AND NOT IS_INF(purchase_revenue_in_usd),
        purchase_revenue_in_usd,
        NULL
      )
    ) AS maximum_finite_revenue_usd
  FROM purchases
  WHERE user_pseudo_id IS NOT NULL
    AND transaction_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    transaction_id
  HAVING COUNT(*) > 1
)
SELECT
  audit_order_key_hash,
  is_placeholder_transaction_id,
  purchase_event_count,
  distinct_event_timestamp_count,
  first_purchase_event_ts,
  last_purchase_event_ts,
  TIMESTAMP_DIFF(last_purchase_event_ts, first_purchase_event_ts, SECOND) AS event_span_seconds,
  distinct_finite_revenue_count,
  minimum_finite_revenue,
  maximum_finite_revenue,
  distinct_finite_revenue_usd_count,
  minimum_finite_revenue_usd,
  maximum_finite_revenue_usd,
  CASE
    WHEN distinct_finite_revenue_count > 1 OR distinct_finite_revenue_usd_count > 1
      THEN 'REVIEW_REVENUE_CONFLICT'
    WHEN is_placeholder_transaction_id THEN 'REVIEW_PLACEHOLDER_TRANSACTION_ID'
    WHEN distinct_event_timestamp_count > 1 THEN 'REVIEW_REPEATED_EVENT'
    ELSE 'REVIEW_EXACT_TIMESTAMP_DUPLICATE'
  END AS validation_status
FROM duplicate_candidates
ORDER BY
  purchase_event_count DESC,
  audit_order_key_hash
