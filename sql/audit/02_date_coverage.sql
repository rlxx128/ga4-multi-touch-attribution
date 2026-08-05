-- Confirm each expected daily shard and agreement between suffix and event_date.
WITH expected_dates AS (
  SELECT
    expected_date,
    FORMAT_DATE('%Y%m%d', expected_date) AS expected_suffix
  FROM UNNEST(
    GENERATE_DATE_ARRAY(DATE '{{START_DATE}}', DATE '{{END_DATE}}')
  ) AS expected_date
),
source_by_suffix AS (
  SELECT
    _TABLE_SUFFIX AS table_suffix,
    COUNT(*) AS event_count,
    COUNT(DISTINCT event_date) AS distinct_embedded_event_dates,
    COUNTIF(event_date IS NULL OR event_date != _TABLE_SUFFIX) AS mismatched_event_count,
    MIN(event_date) AS minimum_embedded_event_date,
    MAX(event_date) AS maximum_embedded_event_date
  FROM `{{SOURCE_TABLE}}`
  WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
  GROUP BY
    table_suffix
)
SELECT
  expected_dates.expected_date,
  expected_dates.expected_suffix,
  source_by_suffix.table_suffix IS NOT NULL AS shard_present,
  COALESCE(source_by_suffix.event_count, 0) AS event_count,
  COALESCE(source_by_suffix.distinct_embedded_event_dates, 0) AS distinct_embedded_event_dates,
  COALESCE(source_by_suffix.mismatched_event_count, 0) AS mismatched_event_count,
  source_by_suffix.minimum_embedded_event_date,
  source_by_suffix.maximum_embedded_event_date,
  CASE
    WHEN source_by_suffix.table_suffix IS NULL THEN 'FAIL_MISSING_SHARD'
    WHEN source_by_suffix.event_count = 0 THEN 'FAIL_EMPTY_SHARD'
    WHEN source_by_suffix.distinct_embedded_event_dates != 1 THEN 'FAIL_EMBEDDED_DATE_COUNT'
    WHEN source_by_suffix.mismatched_event_count != 0 THEN 'FAIL_SUFFIX_DATE_MISMATCH'
    ELSE 'PASS'
  END AS validation_status
FROM expected_dates
LEFT JOIN source_by_suffix
  ON expected_dates.expected_suffix = source_by_suffix.table_suffix
ORDER BY
  expected_dates.expected_date
