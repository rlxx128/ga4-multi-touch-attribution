WITH candidate_sessions AS (
  SELECT
    session_key,
    user_pseudo_id,
    source_resolution_tier,
    resolved_source,
    resolved_medium,
    channel,
    mapping_version
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
  WHERE resolved_source_host = 'moma.corp.google.com'
),
candidate_assignments AS (
  SELECT
    candidate_sessions.session_key,
    COUNT(DISTINCT conversion_touchpoints.order_key) AS affected_order_count,
    COUNT(conversion_touchpoints.order_key) AS touchpoint_row_count
  FROM candidate_sessions
  LEFT JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
    AS conversion_touchpoints
    USING (session_key)
  GROUP BY candidate_sessions.session_key
)
SELECT
  'moma.corp.google.com' AS candidate_host,
  candidate_sessions.source_resolution_tier,
  candidate_sessions.resolved_source,
  candidate_sessions.resolved_medium,
  candidate_sessions.channel,
  COUNT(*) AS session_count,
  COUNT(DISTINCT candidate_sessions.user_pseudo_id) AS user_count,
  SUM(candidate_assignments.affected_order_count) AS affected_order_count,
  SUM(candidate_assignments.touchpoint_row_count) AS touchpoint_row_count,
  'AUDIT_ONLY_NOT_EXCLUDED' AS decision_status,
  candidate_sessions.mapping_version
FROM candidate_sessions
INNER JOIN candidate_assignments USING (session_key)
GROUP BY
  candidate_sessions.source_resolution_tier,
  candidate_sessions.resolved_source,
  candidate_sessions.resolved_medium,
  candidate_sessions.channel,
  candidate_sessions.mapping_version
