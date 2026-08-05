-- Audit purchase candidates without adopting final conversion or order rules.
WITH purchases AS (
  SELECT
    user_pseudo_id,
    ecommerce.transaction_id AS raw_transaction_id,
    NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
    LOWER(TRIM(ecommerce.transaction_id)) IN (
      '<other>',
      '(not set)',
      '(not provided)',
      '(data deleted)',
      'unknown'
    ) AS is_placeholder_transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    ecommerce.purchase_revenue_in_usd AS purchase_revenue_in_usd
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
    AND event_name = 'purchase'
),
candidate_orders AS (
  SELECT
    user_pseudo_id,
    transaction_id,
    is_placeholder_transaction_id,
    COUNT(*) AS purchase_event_count,
    MAX(
      IF(
        purchase_revenue IS NOT NULL
          AND NOT IS_NAN(purchase_revenue)
          AND NOT IS_INF(purchase_revenue),
        purchase_revenue,
        NULL
      )
    ) AS maximum_finite_purchase_revenue,
    MAX(
      IF(
        purchase_revenue_in_usd IS NOT NULL
          AND NOT IS_NAN(purchase_revenue_in_usd)
          AND NOT IS_INF(purchase_revenue_in_usd),
        purchase_revenue_in_usd,
        NULL
      )
    ) AS maximum_finite_purchase_revenue_usd
  FROM purchases
  WHERE user_pseudo_id IS NOT NULL
    AND transaction_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    transaction_id,
    is_placeholder_transaction_id
),
candidate_order_summary AS (
  SELECT
    COUNT(*) AS candidate_order_count,
    COUNTIF(NOT is_placeholder_transaction_id) AS candidate_order_count_excluding_placeholders,
    COUNTIF(
      NOT is_placeholder_transaction_id
        AND maximum_finite_purchase_revenue_usd > 0
    ) AS positive_revenue_candidate_order_count_excluding_placeholders,
    COUNTIF(
      NOT is_placeholder_transaction_id
        AND (
          maximum_finite_purchase_revenue_usd IS NULL
          OR maximum_finite_purchase_revenue_usd <= 0
        )
    ) AS nonpositive_revenue_candidate_order_count_excluding_placeholders,
    COUNTIF(purchase_event_count > 1) AS duplicate_candidate_order_count,
    COUNTIF(
      purchase_event_count > 1 AND NOT is_placeholder_transaction_id
    ) AS duplicate_candidate_order_count_excluding_placeholders,
    SUM(GREATEST(purchase_event_count - 1, 0)) AS duplicate_extra_event_count,
    SUM(maximum_finite_purchase_revenue) AS candidate_max_revenue_total,
    SUM(
      IF(NOT is_placeholder_transaction_id, maximum_finite_purchase_revenue, NULL)
    ) AS candidate_max_revenue_total_excluding_placeholders,
    SUM(maximum_finite_purchase_revenue_usd) AS candidate_max_revenue_usd_total,
    SUM(
      IF(
        NOT is_placeholder_transaction_id,
        maximum_finite_purchase_revenue_usd,
        NULL
      )
    ) AS candidate_max_revenue_usd_total_excluding_placeholders
  FROM candidate_orders
),
transaction_user_counts AS (
  SELECT
    transaction_id,
    LOGICAL_OR(is_placeholder_transaction_id) AS is_placeholder_transaction_id,
    COUNT(DISTINCT user_pseudo_id) AS distinct_users
  FROM purchases
  WHERE user_pseudo_id IS NOT NULL
    AND transaction_id IS NOT NULL
  GROUP BY
    transaction_id
),
shared_transaction_summary AS (
  SELECT
    COUNTIF(distinct_users > 1) AS transaction_ids_shared_across_users,
    COUNTIF(
      distinct_users > 1 AND is_placeholder_transaction_id
    ) AS placeholder_transaction_ids_shared_across_users,
    MAX(distinct_users) AS maximum_users_per_transaction_id
  FROM transaction_user_counts
)
SELECT
  COUNT(*) AS purchase_event_count,
  COUNT(DISTINCT user_pseudo_id) AS purchase_user_count,
  COUNTIF(user_pseudo_id IS NULL OR TRIM(user_pseudo_id) = '') AS missing_user_count,
  COUNTIF(raw_transaction_id IS NULL) AS null_transaction_id_count,
  COUNTIF(raw_transaction_id IS NOT NULL AND transaction_id IS NULL) AS blank_transaction_id_count,
  COUNTIF(transaction_id IS NOT NULL AND is_placeholder_transaction_id) AS placeholder_transaction_id_event_count,
  COUNT(
    DISTINCT IF(is_placeholder_transaction_id, transaction_id, NULL)
  ) AS distinct_placeholder_transaction_id_count,
  STRING_AGG(
    DISTINCT IF(is_placeholder_transaction_id, transaction_id, NULL),
    ' | '
    ORDER BY IF(is_placeholder_transaction_id, transaction_id, NULL)
  ) AS placeholder_transaction_id_values,
  COUNTIF(transaction_id IS NOT NULL) AS nonblank_transaction_id_event_count,
  COUNT(DISTINCT transaction_id) AS distinct_transaction_id_count,
  candidate_order_summary.candidate_order_count,
  candidate_order_summary.candidate_order_count_excluding_placeholders,
  candidate_order_summary.positive_revenue_candidate_order_count_excluding_placeholders,
  candidate_order_summary.nonpositive_revenue_candidate_order_count_excluding_placeholders,
  candidate_order_summary.duplicate_candidate_order_count,
  candidate_order_summary.duplicate_candidate_order_count_excluding_placeholders,
  candidate_order_summary.duplicate_extra_event_count,
  shared_transaction_summary.transaction_ids_shared_across_users,
  shared_transaction_summary.placeholder_transaction_ids_shared_across_users,
  shared_transaction_summary.maximum_users_per_transaction_id,
  COUNTIF(purchase_revenue IS NULL) AS null_purchase_revenue_count,
  COUNTIF(
    purchase_revenue IS NOT NULL
      AND (IS_NAN(purchase_revenue) OR IS_INF(purchase_revenue))
  ) AS nonfinite_purchase_revenue_count,
  COUNTIF(
    purchase_revenue IS NOT NULL
      AND NOT IS_NAN(purchase_revenue)
      AND NOT IS_INF(purchase_revenue)
      AND purchase_revenue <= 0
  ) AS nonpositive_purchase_revenue_count,
  SUM(
    IF(
      purchase_revenue IS NOT NULL
        AND NOT IS_NAN(purchase_revenue)
        AND NOT IS_INF(purchase_revenue),
      purchase_revenue,
      NULL
    )
  ) AS raw_finite_purchase_revenue_total,
  candidate_order_summary.candidate_max_revenue_total,
  candidate_order_summary.candidate_max_revenue_total_excluding_placeholders,
  COUNTIF(purchase_revenue_in_usd IS NULL) AS null_purchase_revenue_usd_count,
  COUNTIF(
    purchase_revenue_in_usd IS NOT NULL
      AND (IS_NAN(purchase_revenue_in_usd) OR IS_INF(purchase_revenue_in_usd))
  ) AS nonfinite_purchase_revenue_usd_count,
  COUNTIF(
    purchase_revenue_in_usd IS NOT NULL
      AND NOT IS_NAN(purchase_revenue_in_usd)
      AND NOT IS_INF(purchase_revenue_in_usd)
      AND purchase_revenue_in_usd <= 0
  ) AS nonpositive_purchase_revenue_usd_count,
  COUNTIF(
    purchase_revenue IS NULL
      AND purchase_revenue_in_usd IS NOT NULL
      AND NOT IS_NAN(purchase_revenue_in_usd)
      AND NOT IS_INF(purchase_revenue_in_usd)
      AND purchase_revenue_in_usd > 0
  ) AS local_revenue_null_usd_positive_count,
  SUM(
    IF(
      purchase_revenue_in_usd IS NOT NULL
        AND NOT IS_NAN(purchase_revenue_in_usd)
        AND NOT IS_INF(purchase_revenue_in_usd),
      purchase_revenue_in_usd,
      NULL
    )
  ) AS raw_finite_purchase_revenue_usd_total,
  candidate_order_summary.candidate_max_revenue_usd_total,
  candidate_order_summary.candidate_max_revenue_usd_total_excluding_placeholders,
  CASE
    WHEN COUNT(*) = 0 THEN 'FAIL_NO_PURCHASE_EVENTS'
    WHEN COUNTIF(
      raw_transaction_id IS NULL OR transaction_id IS NULL OR is_placeholder_transaction_id
    ) > 0
      OR candidate_order_summary.duplicate_candidate_order_count > 0
      OR COUNTIF(purchase_revenue IS NULL) > 0
      OR COUNTIF(
        purchase_revenue IS NOT NULL
          AND (
            IS_NAN(purchase_revenue)
            OR IS_INF(purchase_revenue)
            OR purchase_revenue <= 0
          )
      ) > 0
      THEN 'REVIEW_DATA_QUALITY'
    ELSE 'PASS'
  END AS validation_status
FROM purchases
CROSS JOIN candidate_order_summary
CROSS JOIN shared_transaction_summary
GROUP BY
  candidate_order_summary.candidate_order_count,
  candidate_order_summary.candidate_order_count_excluding_placeholders,
  candidate_order_summary.positive_revenue_candidate_order_count_excluding_placeholders,
  candidate_order_summary.nonpositive_revenue_candidate_order_count_excluding_placeholders,
  candidate_order_summary.duplicate_candidate_order_count,
  candidate_order_summary.duplicate_candidate_order_count_excluding_placeholders,
  candidate_order_summary.duplicate_extra_event_count,
  candidate_order_summary.candidate_max_revenue_total,
  candidate_order_summary.candidate_max_revenue_total_excluding_placeholders,
  candidate_order_summary.candidate_max_revenue_usd_total,
  candidate_order_summary.candidate_max_revenue_usd_total_excluding_placeholders,
  shared_transaction_summary.transaction_ids_shared_across_users,
  shared_transaction_summary.placeholder_transaction_ids_shared_across_users,
  shared_transaction_summary.maximum_users_per_transaction_id
