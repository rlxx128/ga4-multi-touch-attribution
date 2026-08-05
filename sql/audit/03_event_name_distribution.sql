-- Report observed event names without imposing a funnel definition.
WITH event_counts AS (
  SELECT
    COALESCE(NULLIF(TRIM(event_name), ''), '[NULL_OR_BLANK]') AS event_name,
    COUNT(*) AS event_count,
    COUNT(DISTINCT user_pseudo_id) AS distinct_users,
    MIN(SAFE.PARSE_DATE('%Y%m%d', event_date)) AS first_event_date,
    MAX(SAFE.PARSE_DATE('%Y%m%d', event_date)) AS last_event_date
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
  GROUP BY
    event_name
)
SELECT
  event_name,
  event_count,
  distinct_users,
  SAFE_DIVIDE(event_count, SUM(event_count) OVER ()) AS event_share,
  first_event_date,
  last_event_date,
  CASE
    WHEN event_name = '[NULL_OR_BLANK]' THEN 'REVIEW_NULL_OR_BLANK'
    ELSE 'OBSERVED'
  END AS validation_status
FROM event_counts
ORDER BY
  event_count DESC,
  event_name
