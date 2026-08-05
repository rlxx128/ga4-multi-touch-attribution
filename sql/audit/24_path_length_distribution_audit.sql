WITH path_counts AS (
  SELECT
    'STRICT_AFTER_ADMIN_EXCLUSION' AS path_variant,
    strict_conversion_touchpoint_count AS path_length,
    COUNT(*) AS order_count,
    SUM(order_revenue_usd) AS order_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
  GROUP BY strict_conversion_touchpoint_count

  UNION ALL

  SELECT
    'REVISED_WITH_CONVERSION_SESSION_EXCEPTION' AS path_variant,
    conversion_touchpoint_count AS path_length,
    COUNT(*) AS order_count,
    SUM(order_revenue_usd) AS order_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
  GROUP BY conversion_touchpoint_count
),
totals AS (
  SELECT
    COUNT(*) AS total_order_count,
    SUM(order_revenue_usd) AS total_order_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
)
SELECT
  path_counts.path_variant,
  path_counts.path_length,
  path_counts.order_count,
  path_counts.order_revenue_usd,
  totals.total_order_count,
  totals.total_order_revenue_usd,
  SAFE_DIVIDE(path_counts.order_count, totals.total_order_count) AS order_share,
  SAFE_DIVIDE(path_counts.order_revenue_usd, totals.total_order_revenue_usd)
    AS revenue_share,
  'phase2b_closeout_v1_20260806' AS path_definition_version
FROM path_counts
CROSS JOIN totals
