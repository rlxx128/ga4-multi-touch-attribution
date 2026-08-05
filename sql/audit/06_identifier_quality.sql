-- Evaluate user and ga_session_id quality without constructing a session table.
WITH extracted_events AS (
  SELECT
    event_name,
    user_pseudo_id,
    ARRAY_LENGTH(
      ARRAY(
        SELECT ep.key
        FROM UNNEST(event_params) AS ep
        WHERE ep.key = 'ga_session_id'
      )
    ) AS session_parameter_count,
    (
      SELECT ANY_VALUE(ep.value.int_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
),
scoped_events AS (
  SELECT 'all_events' AS audit_scope, event_name, user_pseudo_id, session_parameter_count, ga_session_id
  FROM extracted_events
  UNION ALL
  SELECT 'session_start_events' AS audit_scope, event_name, user_pseudo_id, session_parameter_count, ga_session_id
  FROM extracted_events
  WHERE event_name = 'session_start'
  UNION ALL
  SELECT 'purchase_events' AS audit_scope, event_name, user_pseudo_id, session_parameter_count, ga_session_id
  FROM extracted_events
  WHERE event_name = 'purchase'
),
session_id_users AS (
  SELECT
    ga_session_id,
    COUNT(DISTINCT user_pseudo_id) AS distinct_users
  FROM extracted_events
  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
  GROUP BY
    ga_session_id
),
collision_summary AS (
  SELECT
    COUNTIF(distinct_users > 1) AS session_ids_shared_across_users
  FROM session_id_users
)
SELECT
  audit_scope,
  COUNT(*) AS event_count,
  COUNTIF(user_pseudo_id IS NULL OR TRIM(user_pseudo_id) = '') AS missing_user_count,
  SAFE_DIVIDE(
    COUNTIF(user_pseudo_id IS NULL OR TRIM(user_pseudo_id) = ''),
    COUNT(*)
  ) AS missing_user_rate,
  COUNTIF(session_parameter_count = 0) AS missing_session_parameter_count,
  COUNTIF(session_parameter_count > 1) AS repeated_session_parameter_count,
  COUNTIF(session_parameter_count > 0 AND ga_session_id IS NULL) AS noninteger_session_id_count,
  COUNTIF(ga_session_id IS NULL) AS missing_session_id_count,
  SAFE_DIVIDE(COUNTIF(ga_session_id IS NULL), COUNT(*)) AS missing_session_id_rate,
  COUNTIF(ga_session_id <= 0) AS nonpositive_session_id_count,
  COUNT(DISTINCT user_pseudo_id) AS distinct_user_count,
  COUNT(DISTINCT ga_session_id) AS distinct_session_id_count,
  COUNT(
    DISTINCT IF(
      user_pseudo_id IS NOT NULL AND ga_session_id IS NOT NULL,
      TO_JSON_STRING(
        STRUCT(user_pseudo_id AS user_pseudo_id, ga_session_id AS ga_session_id)
      ),
      NULL
    )
  ) AS distinct_candidate_user_session_count,
  collision_summary.session_ids_shared_across_users,
  CASE
    WHEN COUNT(*) = 0 THEN 'FAIL_EMPTY_SCOPE'
    WHEN COUNTIF(session_parameter_count > 1) > 0 THEN 'REVIEW_REPEATED_PARAMETER'
    WHEN COUNTIF(user_pseudo_id IS NULL OR TRIM(user_pseudo_id) = '') > 0
      OR COUNTIF(ga_session_id IS NULL) > 0
      OR COUNTIF(ga_session_id <= 0) > 0
      THEN 'REVIEW_IDENTIFIER_QUALITY'
    ELSE 'PASS'
  END AS validation_status
FROM scoped_events
CROSS JOIN collision_summary
GROUP BY
  audit_scope,
  collision_summary.session_ids_shared_across_users
ORDER BY
  CASE audit_scope
    WHEN 'all_events' THEN 1
    WHEN 'session_start_events' THEN 2
    WHEN 'purchase_events' THEN 3
    ELSE 4
  END
