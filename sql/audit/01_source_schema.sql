-- Inspect nested source fields across every configured daily shard.
WITH selected_tables AS (
  SELECT
    table_name
  FROM `{{SOURCE_DATASET}}.INFORMATION_SCHEMA.TABLES`
  WHERE table_name BETWEEN 'events_{{START_SUFFIX}}' AND 'events_{{END_SUFFIX}}'
),
selected_table_count AS (
  SELECT
    COUNT(*) AS shard_count
  FROM selected_tables
),
field_paths AS (
  SELECT
    table_name,
    column_name,
    field_path,
    data_type
  FROM `{{SOURCE_DATASET}}.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
  WHERE table_name BETWEEN 'events_{{START_SUFFIX}}' AND 'events_{{END_SUFFIX}}'
)
SELECT
  field_path,
  ANY_VALUE(column_name) AS top_level_column,
  data_type,
  COUNT(DISTINCT table_name) AS shards_containing_field,
  MIN(table_name) AS first_table,
  MAX(table_name) AS last_table,
  selected_table_count.shard_count AS selected_shard_count,
  COUNT(DISTINCT table_name) = selected_table_count.shard_count AS present_in_all_shards
FROM field_paths
CROSS JOIN selected_table_count
GROUP BY
  field_path,
  data_type,
  selected_table_count.shard_count
ORDER BY
  field_path,
  data_type
