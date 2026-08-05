-- Compatibility audit table: moma is no longer a candidate. Its approved
-- exact-host exclusion and before/after path impact are recorded here.
SELECT
  admin_host,
  affected_session_count AS session_count,
  affected_user_count AS user_count,
  retained_session_count_after_exclusion,
  attribution_eligible_session_count_after_exclusion,
  strict_touchpoint_rows_before_exclusion,
  strict_admin_touchpoint_rows_after_exclusion,
  strict_orders_before_exclusion,
  strict_order_revenue_before_exclusion,
  strict_orders_covered_after_exclusion,
  strict_order_revenue_covered_after_exclusion,
  strict_orders_lost_after_exclusion,
  strict_order_revenue_lost_after_exclusion,
  revised_touchpoint_rows_before_exclusion,
  revised_admin_touchpoint_rows_after_exclusion,
  revised_orders_before_exclusion,
  revised_order_revenue_before_exclusion,
  revised_orders_covered_after_exclusion,
  revised_order_revenue_covered_after_exclusion,
  revised_orders_lost_after_exclusion,
  revised_order_revenue_lost_after_exclusion,
  decision_status,
  mapping_version,
  path_definition_version
FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.internal_admin_path_impact_audit`
WHERE admin_host = 'moma.corp.google.com'
