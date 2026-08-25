-- Tagged, dashboard-ready summaries of the already-finalized converting paths.
-- Each non-OVERALL summary type independently reconciles to the same eligible
-- conversion and revenue population.
WITH order_paths AS (
  SELECT
    order_key,
    ANY_VALUE(order_revenue_usd) AS order_revenue_usd,
    ANY_VALUE(path_length) AS path_length,
    ARRAY_AGG(channel ORDER BY touchpoint_number LIMIT 1)[OFFSET(0)]
      AS first_touch_channel,
    ARRAY_AGG(channel ORDER BY touchpoint_number DESC LIMIT 1)[OFFSET(0)]
      AS last_touch_channel,
    STRING_AGG(channel, ' > ' ORDER BY touchpoint_number) AS converting_path,
    ANY_VALUE(mapping_version) AS mapping_version,
    ANY_VALUE(path_definition_version) AS path_definition_version
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  GROUP BY order_key
),
paths_with_median AS (
  SELECT
    order_paths.order_key,
    order_paths.order_revenue_usd,
    order_paths.path_length,
    order_paths.first_touch_channel,
    order_paths.last_touch_channel,
    order_paths.converting_path,
    order_paths.mapping_version,
    order_paths.path_definition_version,
    PERCENTILE_CONT(CAST(path_length AS FLOAT64), 0.5) OVER ()
      AS median_path_length
  FROM order_paths
),
totals AS (
  SELECT
    COUNT(*) AS attributable_conversions,
    SUM(order_revenue_usd) AS attributable_revenue,
    AVG(path_length) AS mean_path_length,
    ANY_VALUE(median_path_length) AS median_path_length,
    COUNTIF(path_length = 1) AS single_touch_conversions,
    COUNTIF(path_length > 1) AS multi_touch_conversions,
    ANY_VALUE(mapping_version) AS mapping_version,
    ANY_VALUE(path_definition_version) AS path_definition_version
  FROM paths_with_median
),
overall_rows AS (
  SELECT
    'OVERALL' AS summary_type,
    'all_attributable_conversions' AS dimension_key,
    'All attributable conversions' AS dimension_label,
    1 AS sort_order,
    totals.attributable_conversions,
    totals.attributable_revenue,
    1.0 AS conversion_share,
    1.0 AS revenue_share,
    totals.mean_path_length,
    totals.median_path_length,
    totals.single_touch_conversions,
    SAFE_DIVIDE(totals.single_touch_conversions, totals.attributable_conversions)
      AS single_touch_conversion_share,
    totals.multi_touch_conversions,
    SAFE_DIVIDE(totals.multi_touch_conversions, totals.attributable_conversions)
      AS multi_touch_conversion_share,
    totals.mapping_version,
    totals.path_definition_version
  FROM totals
),
path_length_rows AS (
  SELECT
    'PATH_LENGTH' AS summary_type,
    CAST(paths.path_length AS STRING) AS dimension_key,
    CONCAT(CAST(paths.path_length AS STRING), ' touchpoint(s)') AS dimension_label,
    paths.path_length AS sort_order,
    COUNT(*) AS attributable_conversions,
    SUM(paths.order_revenue_usd) AS attributable_revenue,
    SAFE_DIVIDE(COUNT(*), totals.attributable_conversions) AS conversion_share,
    SAFE_DIVIDE(SUM(paths.order_revenue_usd), totals.attributable_revenue)
      AS revenue_share,
    CAST(paths.path_length AS FLOAT64) AS mean_path_length,
    CAST(paths.path_length AS FLOAT64) AS median_path_length,
    CAST(NULL AS INT64) AS single_touch_conversions,
    CAST(NULL AS FLOAT64) AS single_touch_conversion_share,
    CAST(NULL AS INT64) AS multi_touch_conversions,
    CAST(NULL AS FLOAT64) AS multi_touch_conversion_share,
    ANY_VALUE(paths.mapping_version) AS mapping_version,
    ANY_VALUE(paths.path_definition_version) AS path_definition_version
  FROM paths_with_median AS paths
  CROSS JOIN totals
  GROUP BY paths.path_length, totals.attributable_conversions,
    totals.attributable_revenue
),
converting_path_aggregates AS (
  SELECT
    converting_path,
    COUNT(*) AS attributable_conversions,
    SUM(order_revenue_usd) AS attributable_revenue,
    ANY_VALUE(mapping_version) AS mapping_version,
    ANY_VALUE(path_definition_version) AS path_definition_version
  FROM paths_with_median
  GROUP BY converting_path
),
converting_path_rows AS (
  SELECT
    'CONVERTING_PATH' AS summary_type,
    converting_path AS dimension_key,
    converting_path AS dimension_label,
    ROW_NUMBER() OVER (
      ORDER BY converting_path_aggregates.attributable_conversions DESC,
        converting_path_aggregates.attributable_revenue DESC,
        converting_path
    ) AS sort_order,
    converting_path_aggregates.attributable_conversions,
    converting_path_aggregates.attributable_revenue,
    SAFE_DIVIDE(
      converting_path_aggregates.attributable_conversions,
      totals.attributable_conversions
    )
      AS conversion_share,
    SAFE_DIVIDE(
      converting_path_aggregates.attributable_revenue,
      totals.attributable_revenue
    )
      AS revenue_share,
    CAST(NULL AS FLOAT64) AS mean_path_length,
    CAST(NULL AS FLOAT64) AS median_path_length,
    CAST(NULL AS INT64) AS single_touch_conversions,
    CAST(NULL AS FLOAT64) AS single_touch_conversion_share,
    CAST(NULL AS INT64) AS multi_touch_conversions,
    CAST(NULL AS FLOAT64) AS multi_touch_conversion_share,
    converting_path_aggregates.mapping_version,
    converting_path_aggregates.path_definition_version
  FROM converting_path_aggregates
  CROSS JOIN totals
),
first_touch_aggregates AS (
  SELECT
    first_touch_channel AS channel,
    COUNT(*) AS attributable_conversions,
    SUM(order_revenue_usd) AS attributable_revenue,
    ANY_VALUE(mapping_version) AS mapping_version,
    ANY_VALUE(path_definition_version) AS path_definition_version
  FROM paths_with_median
  GROUP BY first_touch_channel
),
first_touch_rows AS (
  SELECT
    'FIRST_TOUCH_CHANNEL' AS summary_type,
    channel AS dimension_key,
    channel AS dimension_label,
    ROW_NUMBER() OVER (
      ORDER BY first_touch_aggregates.attributable_conversions DESC,
        first_touch_aggregates.attributable_revenue DESC, channel
    ) AS sort_order,
    first_touch_aggregates.attributable_conversions,
    first_touch_aggregates.attributable_revenue,
    SAFE_DIVIDE(
      first_touch_aggregates.attributable_conversions,
      totals.attributable_conversions
    )
      AS conversion_share,
    SAFE_DIVIDE(
      first_touch_aggregates.attributable_revenue,
      totals.attributable_revenue
    )
      AS revenue_share,
    CAST(NULL AS FLOAT64) AS mean_path_length,
    CAST(NULL AS FLOAT64) AS median_path_length,
    CAST(NULL AS INT64) AS single_touch_conversions,
    CAST(NULL AS FLOAT64) AS single_touch_conversion_share,
    CAST(NULL AS INT64) AS multi_touch_conversions,
    CAST(NULL AS FLOAT64) AS multi_touch_conversion_share,
    first_touch_aggregates.mapping_version,
    first_touch_aggregates.path_definition_version
  FROM first_touch_aggregates
  CROSS JOIN totals
),
last_touch_aggregates AS (
  SELECT
    last_touch_channel AS channel,
    COUNT(*) AS attributable_conversions,
    SUM(order_revenue_usd) AS attributable_revenue,
    ANY_VALUE(mapping_version) AS mapping_version,
    ANY_VALUE(path_definition_version) AS path_definition_version
  FROM paths_with_median
  GROUP BY last_touch_channel
),
last_touch_rows AS (
  SELECT
    'LAST_TOUCH_CHANNEL' AS summary_type,
    channel AS dimension_key,
    channel AS dimension_label,
    ROW_NUMBER() OVER (
      ORDER BY last_touch_aggregates.attributable_conversions DESC,
        last_touch_aggregates.attributable_revenue DESC, channel
    ) AS sort_order,
    last_touch_aggregates.attributable_conversions,
    last_touch_aggregates.attributable_revenue,
    SAFE_DIVIDE(
      last_touch_aggregates.attributable_conversions,
      totals.attributable_conversions
    )
      AS conversion_share,
    SAFE_DIVIDE(
      last_touch_aggregates.attributable_revenue,
      totals.attributable_revenue
    )
      AS revenue_share,
    CAST(NULL AS FLOAT64) AS mean_path_length,
    CAST(NULL AS FLOAT64) AS median_path_length,
    CAST(NULL AS INT64) AS single_touch_conversions,
    CAST(NULL AS FLOAT64) AS single_touch_conversion_share,
    CAST(NULL AS INT64) AS multi_touch_conversions,
    CAST(NULL AS FLOAT64) AS multi_touch_conversion_share,
    last_touch_aggregates.mapping_version,
    last_touch_aggregates.path_definition_version
  FROM last_touch_aggregates
  CROSS JOIN totals
),
all_rows AS (
  SELECT
    summary_type, dimension_key, dimension_label, sort_order,
    attributable_conversions, attributable_revenue, conversion_share,
    revenue_share, mean_path_length, median_path_length,
    single_touch_conversions, single_touch_conversion_share,
    multi_touch_conversions, multi_touch_conversion_share,
    mapping_version, path_definition_version
  FROM overall_rows
  UNION ALL
  SELECT
    summary_type, dimension_key, dimension_label, sort_order,
    attributable_conversions, attributable_revenue, conversion_share,
    revenue_share, mean_path_length, median_path_length,
    single_touch_conversions, single_touch_conversion_share,
    multi_touch_conversions, multi_touch_conversion_share,
    mapping_version, path_definition_version
  FROM path_length_rows
  UNION ALL
  SELECT
    summary_type, dimension_key, dimension_label, sort_order,
    attributable_conversions, attributable_revenue, conversion_share,
    revenue_share, mean_path_length, median_path_length,
    single_touch_conversions, single_touch_conversion_share,
    multi_touch_conversions, multi_touch_conversion_share,
    mapping_version, path_definition_version
  FROM converting_path_rows
  UNION ALL
  SELECT
    summary_type, dimension_key, dimension_label, sort_order,
    attributable_conversions, attributable_revenue, conversion_share,
    revenue_share, mean_path_length, median_path_length,
    single_touch_conversions, single_touch_conversion_share,
    multi_touch_conversions, multi_touch_conversion_share,
    mapping_version, path_definition_version
  FROM first_touch_rows
  UNION ALL
  SELECT
    summary_type, dimension_key, dimension_label, sort_order,
    attributable_conversions, attributable_revenue, conversion_share,
    revenue_share, mean_path_length, median_path_length,
    single_touch_conversions, single_touch_conversion_share,
    multi_touch_conversions, multi_touch_conversion_share,
    mapping_version, path_definition_version
  FROM last_touch_rows
)
SELECT
  summary_type,
  dimension_key,
  dimension_label,
  sort_order,
  attributable_conversions,
  attributable_revenue,
  conversion_share,
  revenue_share,
  mean_path_length,
  median_path_length,
  single_touch_conversions,
  single_touch_conversion_share,
  multi_touch_conversions,
  multi_touch_conversion_share,
  mapping_version,
  path_definition_version,
  'phase6_business_reporting_v1_20260814' AS reporting_version
FROM all_rows
