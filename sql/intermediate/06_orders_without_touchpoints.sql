SELECT
  order_key,
  user_pseudo_id,
  transaction_id,
  order_ts,
  order_date,
  order_revenue_usd,
  previous_order_ts,
  same_timestamp_order_count,
  same_timestamp_order_sequence,
  all_user_session_count,
  session_on_or_before_order_count,
  session_within_30_days_count,
  temporally_eligible_session_count,
  temporally_eligible_admin_session_count,
  marketing_eligible_session_count,
  CASE
    WHEN same_timestamp_order_count > 1 AND same_timestamp_order_sequence > 1
      THEN 'SAME_TIMESTAMP_ORDER_CYCLE_BOUNDARY'
    WHEN all_user_session_count = 0 THEN 'NO_USER_SESSIONS'
    WHEN session_on_or_before_order_count = 0 THEN 'NO_SESSION_ON_OR_BEFORE_ORDER'
    WHEN session_within_30_days_count = 0 THEN 'NO_SESSION_WITHIN_30_DAYS'
    WHEN temporally_eligible_session_count = 0 THEN 'NO_SESSION_AFTER_PREVIOUS_ORDER'
    WHEN marketing_eligible_session_count = 0 AND temporally_eligible_admin_session_count > 0
      THEN 'ONLY_INTERNAL_ADMIN_TOUCHPOINTS'
    ELSE 'NO_MARKETING_ELIGIBLE_TOUCHPOINT'
  END AS exclusion_reason
FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
WHERE conversion_touchpoint_count = 0
