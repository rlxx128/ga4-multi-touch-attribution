WITH session_impact AS (
  SELECT
    COUNTIF(is_internal_admin_traffic) AS affected_session_count,
    COUNT(DISTINCT IF(is_internal_admin_traffic, user_pseudo_id, NULL)) AS affected_user_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
),
order_impact AS (
  SELECT
    COUNT(*) AS total_order_count,
    COUNTIF(temporally_eligible_admin_session_count > 0) AS affected_order_count,
    COUNTIF(path_covered_before_admin_exclusion) AS covered_order_count_before_exclusion,
    COUNTIF(path_covered_after_admin_exclusion) AS covered_order_count_after_exclusion,
    COUNTIF(coverage_lost_after_admin_exclusion) AS order_count_lost_after_exclusion
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
)
SELECT
  session_impact.affected_session_count,
  session_impact.affected_user_count,
  order_impact.total_order_count,
  order_impact.affected_order_count,
  order_impact.covered_order_count_before_exclusion,
  order_impact.covered_order_count_after_exclusion,
  order_impact.order_count_lost_after_exclusion,
  SAFE_DIVIDE(order_impact.covered_order_count_before_exclusion, order_impact.total_order_count) AS coverage_before_exclusion,
  SAFE_DIVIDE(order_impact.covered_order_count_after_exclusion, order_impact.total_order_count) AS coverage_after_exclusion,
  SAFE_DIVIDE(order_impact.covered_order_count_after_exclusion, order_impact.total_order_count)
    - SAFE_DIVIDE(order_impact.covered_order_count_before_exclusion, order_impact.total_order_count)
    AS coverage_rate_change,
  'analytics.google.com' AS approved_internal_admin_host,
  'phase2b_channel_v1_20260806' AS mapping_version
FROM session_impact
CROSS JOIN order_impact
