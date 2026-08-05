-- Return deterministic top values; strip query strings and fragments from referrers.
WITH extracted_events AS (
  SELECT
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
long_values AS (
  SELECT
    field.field_name,
    CASE
      WHEN field.field_name = 'event_parameter.page_referrer'
        THEN SUBSTR(REGEXP_REPLACE(TRIM(field.field_value), r'[?#].*$', ''), 1, 500)
      ELSE SUBSTR(TRIM(field.field_value), 1, 500)
    END AS field_value,
    CASE
      WHEN field.field_name = 'event_parameter.page_referrer'
        THEN NET.HOST(field.field_value)
      ELSE NULL
    END AS referrer_host
  FROM extracted_events
  CROSS JOIN UNNEST([
    STRUCT('event_parameter.source' AS field_name, event_parameter_source AS field_value),
    STRUCT('event_parameter.medium' AS field_name, event_parameter_medium AS field_value),
    STRUCT('event_parameter.campaign' AS field_name, event_parameter_campaign AS field_value),
    STRUCT('event_parameter.page_referrer' AS field_name, page_referrer AS field_value),
    STRUCT('first_user.source' AS field_name, first_user_source AS field_value),
    STRUCT('first_user.medium' AS field_name, first_user_medium AS field_value),
    STRUCT('first_user.campaign' AS field_name, first_user_campaign AS field_value)
  ]) AS field
  WHERE field.field_value IS NOT NULL
    AND TRIM(field.field_value) != ''
),
value_counts AS (
  SELECT
    field_name,
    field_value,
    referrer_host,
    COUNT(*) AS event_count
  FROM long_values
  GROUP BY
    field_name,
    field_value,
    referrer_host
)
SELECT
  field_name,
  field_value,
  referrer_host,
  event_count
FROM value_counts
ORDER BY
  field_name,
  event_count DESC,
  field_value,
  COALESCE(referrer_host, '')
