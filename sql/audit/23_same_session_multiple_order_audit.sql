WITH strict_assignments AS (
  SELECT
    session_key,
    COUNT(DISTINCT order_key) AS strict_assigned_order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints_strict`
  GROUP BY session_key
),
ranked_revised_assignments AS (
  SELECT
    session_key,
    user_pseudo_id,
    order_key,
    order_ts,
    conversion_session_key,
    touchpoint_eligibility_rule,
    is_same_session_multi_order_exception,
    ROW_NUMBER() OVER (
      PARTITION BY session_key
      ORDER BY order_ts, order_key
    ) AS session_assignment_sequence
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
reused_revised_sessions AS (
  SELECT
    session_key,
    ANY_VALUE(user_pseudo_id) AS user_pseudo_id,
    COUNT(DISTINCT order_key) AS revised_assigned_order_count,
    COUNTIF(touchpoint_eligibility_rule = 'STANDARD_CONVERSION_CYCLE')
      AS standard_assignment_count,
    COUNTIF(touchpoint_eligibility_rule = 'CURRENT_CONVERSION_SESSION_EXCEPTION')
      AS exception_assignment_count,
    COUNTIF(
      session_assignment_sequence > 1
      AND touchpoint_eligibility_rule != 'CURRENT_CONVERSION_SESSION_EXCEPTION'
    ) AS unapproved_historical_assignment_count,
    COUNTIF(
      is_same_session_multi_order_exception
      AND session_key != conversion_session_key
    ) AS exception_conversion_session_mismatch_count,
    MIN(order_ts) AS first_assigned_order_ts,
    MAX(order_ts) AS last_assigned_order_ts,
    ARRAY_AGG(order_key ORDER BY order_ts, order_key) AS order_keys
  FROM ranked_revised_assignments
  GROUP BY session_key
  HAVING COUNT(DISTINCT order_key) > 1
)
SELECT
  reused_revised_sessions.session_key,
  reused_revised_sessions.user_pseudo_id,
  COALESCE(strict_assignments.strict_assigned_order_count, 0)
    AS strict_assigned_order_count,
  reused_revised_sessions.revised_assigned_order_count,
  reused_revised_sessions.standard_assignment_count,
  reused_revised_sessions.exception_assignment_count,
  reused_revised_sessions.unapproved_historical_assignment_count,
  reused_revised_sessions.exception_conversion_session_mismatch_count,
  reused_revised_sessions.first_assigned_order_ts,
  reused_revised_sessions.last_assigned_order_ts,
  reused_revised_sessions.order_keys,
  reused_revised_sessions.exception_assignment_count > 0
    AND reused_revised_sessions.unapproved_historical_assignment_count = 0
    AND reused_revised_sessions.exception_conversion_session_mismatch_count = 0
    AS reuse_is_explicitly_approved_exception,
  reused_revised_sessions.unapproved_historical_assignment_count > 0
    OR reused_revised_sessions.exception_conversion_session_mismatch_count > 0
    AS session_reuse_violation,
  'phase2b_closeout_v1_20260806' AS path_definition_version
FROM reused_revised_sessions
LEFT JOIN strict_assignments USING (session_key)
