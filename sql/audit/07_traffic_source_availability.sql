-- Measure coverage only for traffic fields confirmed by the schema audit.
WITH extracted_events AS (
  SELECT
    event_name,
    (
      SELECT ANY_VALUE(ep.value.int_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    (
      SELECT ANY_VALUE(ep.value.string_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'source'
    ) AS event_parameter_source,
    (
      SELECT ANY_VALUE(ep.value.string_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'medium'
    ) AS event_parameter_medium,
    (
      SELECT ANY_VALUE(ep.value.string_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'campaign'
    ) AS event_parameter_campaign,
    (
      SELECT ANY_VALUE(ep.value.string_value)
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'page_referrer'
    ) AS page_referrer,
    traffic_source.source AS first_user_source,
    traffic_source.medium AS first_user_medium,
    traffic_source.name AS first_user_campaign
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{CHUNK_START_SUFFIX}}' AND '{{CHUNK_END_SUFFIX}}'
),
scoped_events AS (
  SELECT
    'all_events' AS audit_scope,
    event_parameter_source,
    event_parameter_medium,
    event_parameter_campaign,
    page_referrer,
    first_user_source,
    first_user_medium,
    first_user_campaign
  FROM extracted_events
  UNION ALL
  SELECT
    'events_with_candidate_session_id' AS audit_scope,
    event_parameter_source,
    event_parameter_medium,
    event_parameter_campaign,
    page_referrer,
    first_user_source,
    first_user_medium,
    first_user_campaign
  FROM extracted_events
  WHERE ga_session_id IS NOT NULL
  UNION ALL
  SELECT
    'session_start_events' AS audit_scope,
    event_parameter_source,
    event_parameter_medium,
    event_parameter_campaign,
    page_referrer,
    first_user_source,
    first_user_medium,
    first_user_campaign
  FROM extracted_events
  WHERE event_name = 'session_start'
),
long_fields AS (
  SELECT
    audit_scope,
    field.field_name,
    field.field_value
  FROM scoped_events
  CROSS JOIN UNNEST([
    STRUCT('event_parameter.source' AS field_name, event_parameter_source AS field_value),
    STRUCT('event_parameter.medium' AS field_name, event_parameter_medium AS field_value),
    STRUCT('event_parameter.campaign' AS field_name, event_parameter_campaign AS field_value),
    STRUCT('event_parameter.page_referrer' AS field_name, page_referrer AS field_value),
    STRUCT('first_user.source' AS field_name, first_user_source AS field_value),
    STRUCT('first_user.medium' AS field_name, first_user_medium AS field_value),
    STRUCT('first_user.campaign' AS field_name, first_user_campaign AS field_value)
  ]) AS field
)
SELECT
  audit_scope,
  field_name,
  COUNT(*) AS denominator_event_count,
  COUNTIF(field_value IS NULL) AS null_count,
  SAFE_DIVIDE(COUNTIF(field_value IS NULL), COUNT(*)) AS null_rate,
  COUNTIF(field_value IS NOT NULL AND TRIM(field_value) = '') AS blank_count,
  SAFE_DIVIDE(
    COUNTIF(field_value IS NOT NULL AND TRIM(field_value) = ''),
    COUNT(*)
  ) AS blank_rate,
  COUNTIF(field_value IS NOT NULL AND TRIM(field_value) != '') AS nonblank_count,
  SAFE_DIVIDE(
    COUNTIF(field_value IS NOT NULL AND TRIM(field_value) != ''),
    COUNT(*)
  ) AS nonblank_rate,
  COUNTIF(
    LOWER(TRIM(field_value)) IN (
      '<other>',
      '(not set)',
      '(not provided)',
      '(data deleted)',
      'unknown'
    )
  ) AS placeholder_count,
  SAFE_DIVIDE(
    COUNTIF(
      LOWER(TRIM(field_value)) IN (
        '<other>',
        '(not set)',
        '(not provided)',
        '(data deleted)',
        'unknown'
      )
    ),
    COUNT(*)
  ) AS placeholder_rate,
  CASE
    WHEN COUNT(*) = 0 THEN 'FAIL_EMPTY_SCOPE'
    WHEN COUNTIF(field_value IS NOT NULL AND TRIM(field_value) != '') = 0
      THEN 'REVIEW_NO_USABLE_VALUES'
    WHEN COUNTIF(field_value IS NULL OR TRIM(field_value) = '') > 0
      THEN 'REVIEW_PARTIAL_COVERAGE'
    ELSE 'PASS'
  END AS validation_status
FROM long_fields
GROUP BY
  audit_scope,
  field_name
ORDER BY
  CASE audit_scope
    WHEN 'all_events' THEN 1
    WHEN 'events_with_candidate_session_id' THEN 2
    WHEN 'session_start_events' THEN 3
    ELSE 4
  END,
  field_name
