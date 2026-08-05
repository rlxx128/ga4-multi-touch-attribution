WITH order_summary AS (
  SELECT
    COUNT(*) AS total_order_count,
    SUM(order_revenue_usd) AS total_order_revenue_usd,
    COUNTIF(path_covered_historical_baseline) AS historical_covered_order_count,
    SUM(IF(path_covered_historical_baseline, order_revenue_usd, 0))
      AS historical_covered_order_revenue_usd,
    SUM(historical_baseline_touchpoint_count) AS historical_touchpoint_count,
    COUNTIF(historical_baseline_touchpoint_count > 1)
      AS historical_multi_touch_order_count,
    COUNTIF(path_covered_strict) AS strict_covered_order_count,
    SUM(IF(path_covered_strict, order_revenue_usd, 0))
      AS strict_covered_order_revenue_usd,
    SUM(strict_conversion_touchpoint_count) AS strict_touchpoint_count,
    COUNTIF(strict_conversion_touchpoint_count > 1) AS strict_multi_touch_order_count,
    COUNTIF(path_covered_revised) AS revised_covered_order_count,
    SUM(IF(path_covered_revised, order_revenue_usd, 0))
      AS revised_covered_order_revenue_usd,
    SUM(conversion_touchpoint_count) AS revised_touchpoint_count,
    COUNTIF(conversion_touchpoint_count > 1) AS revised_multi_touch_order_count,
    COUNTIF(recovered_by_current_conversion_session_exception) AS recovered_order_count,
    COUNTIF(historical_unmatched_recovered_by_exception)
      AS historical_unmatched_recovered_order_count,
    COUNTIF(historical_covered_order_lost_after_closeout)
      AS historical_covered_order_lost_after_closeout,
    COUNTIF(NOT path_covered_revised) AS revised_unmatched_order_count,
    COUNTIF(coverage_lost_after_internal_exclusion)
      AS orders_lost_after_internal_exclusion
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
),
exception_summary AS (
  SELECT
    COUNTIF(is_same_session_multi_order_exception) AS exception_touchpoint_count,
    COUNT(DISTINCT IF(
      is_same_session_multi_order_exception,
      session_key,
      NULL
    )) AS exception_session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
reuse_summary AS (
  SELECT
    COUNT(*) AS reused_session_count,
    COALESCE(SUM(unapproved_historical_assignment_count), 0)
      AS unapproved_historical_assignment_count,
    COALESCE(SUM(exception_conversion_session_mismatch_count), 0)
      AS exception_conversion_session_mismatch_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.same_session_multiple_order_audit`
)
SELECT
  order_summary.total_order_count,
  order_summary.total_order_revenue_usd,
  order_summary.historical_covered_order_count,
  order_summary.total_order_count - order_summary.historical_covered_order_count
    AS historical_unmatched_order_count,
  order_summary.historical_covered_order_revenue_usd,
  order_summary.historical_touchpoint_count,
  SAFE_DIVIDE(
    order_summary.historical_touchpoint_count,
    order_summary.historical_covered_order_count
  ) AS historical_average_path_length,
  order_summary.historical_multi_touch_order_count,
  SAFE_DIVIDE(
    order_summary.historical_multi_touch_order_count,
    order_summary.historical_covered_order_count
  ) AS historical_multi_touch_rate,
  order_summary.strict_covered_order_count,
  order_summary.total_order_count - order_summary.strict_covered_order_count
    AS strict_unmatched_order_count,
  order_summary.strict_covered_order_revenue_usd,
  SAFE_DIVIDE(
    order_summary.strict_covered_order_count,
    order_summary.total_order_count
  ) AS strict_order_coverage_rate,
  SAFE_DIVIDE(
    order_summary.strict_covered_order_revenue_usd,
    order_summary.total_order_revenue_usd
  ) AS strict_revenue_coverage_rate,
  order_summary.strict_touchpoint_count,
  SAFE_DIVIDE(
    order_summary.strict_touchpoint_count,
    order_summary.strict_covered_order_count
  ) AS strict_average_path_length,
  order_summary.strict_multi_touch_order_count,
  SAFE_DIVIDE(
    order_summary.strict_multi_touch_order_count,
    order_summary.strict_covered_order_count
  ) AS strict_multi_touch_rate,
  order_summary.revised_covered_order_count,
  order_summary.revised_unmatched_order_count,
  order_summary.revised_covered_order_revenue_usd,
  SAFE_DIVIDE(
    order_summary.revised_covered_order_count,
    order_summary.total_order_count
  ) AS revised_order_coverage_rate,
  SAFE_DIVIDE(
    order_summary.revised_covered_order_revenue_usd,
    order_summary.total_order_revenue_usd
  ) AS revised_revenue_coverage_rate,
  order_summary.revised_touchpoint_count,
  SAFE_DIVIDE(
    order_summary.revised_touchpoint_count,
    order_summary.revised_covered_order_count
  ) AS revised_average_path_length,
  order_summary.revised_multi_touch_order_count,
  SAFE_DIVIDE(
    order_summary.revised_multi_touch_order_count,
    order_summary.revised_covered_order_count
  ) AS revised_multi_touch_rate,
  order_summary.recovered_order_count,
  order_summary.historical_unmatched_recovered_order_count,
  order_summary.historical_covered_order_lost_after_closeout,
  exception_summary.exception_touchpoint_count,
  exception_summary.exception_session_count,
  reuse_summary.reused_session_count,
  reuse_summary.unapproved_historical_assignment_count,
  reuse_summary.exception_conversion_session_mismatch_count,
  order_summary.orders_lost_after_internal_exclusion,
  'phase2b_closeout_v1_20260806' AS path_definition_version
FROM order_summary
CROSS JOIN exception_summary
CROSS JOIN reuse_summary
