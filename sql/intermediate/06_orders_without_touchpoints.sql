SELECT
  order_key,
  user_pseudo_id,
  transaction_id,
  order_ts,
  order_date,
  conversion_session_key,
  order_revenue_usd,
  previous_order_ts,
  same_timestamp_order_count,
  same_timestamp_order_sequence,
  all_user_session_count,
  session_on_or_before_order_count,
  session_within_30_days_count,
  strict_pre_internal_exclusion_session_count,
  historical_baseline_touchpoint_count,
  strict_internal_admin_session_count,
  strict_attribution_eligible_session_count,
  revised_pre_internal_exclusion_session_count,
  revised_internal_admin_session_count,
  revised_attribution_eligible_session_count,
  current_conversion_session_exception_candidate_count,
  strict_conversion_touchpoint_count,
  conversion_touchpoint_count,
  CASE
    WHEN revised_pre_internal_exclusion_session_count > 0
      AND revised_attribution_eligible_session_count = 0
      THEN 'NO_ELIGIBLE_TOUCHPOINT_AFTER_INTERNAL_EXCLUSION'
    WHEN all_user_session_count = 0 THEN 'NO_USER_SESSIONS'
    WHEN session_on_or_before_order_count = 0 THEN 'NO_SESSION_ON_OR_BEFORE_ORDER'
    WHEN session_within_30_days_count = 0 THEN 'NO_SESSION_WITHIN_30_DAYS'
    WHEN revised_pre_internal_exclusion_session_count = 0
      THEN 'NO_STANDARD_OR_CURRENT_CONVERSION_SESSION'
    ELSE 'NO_ATTRIBUTION_ELIGIBLE_TOUCHPOINT'
  END AS exclusion_reason,
  path_definition_version
FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
WHERE conversion_touchpoint_count = 0
