-- Phase 3 closes only when prerequisite, formula, grain, and reconciliation
-- checks all pass. Observed values are failure counts unless stated otherwise.
WITH phase2b_validation_stats AS (
  SELECT
    COUNT(*) AS check_count,
    COUNTIF(validation_status != 'PASS') AS failed_check_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase2b_validation_summary`
),
input_touchpoint_stats AS (
  SELECT
    COUNT(*) AS touchpoint_count,
    COUNT(DISTINCT order_key) AS attributable_order_count,
    COUNTIF(touchpoint_ts > order_ts) AS post_conversion_touchpoint_count,
    COUNTIF(seconds_before_conversion < 0) AS negative_seconds_before_conversion_count,
    COUNTIF(channel = 'Internal/Admin') AS internal_admin_touchpoint_count,
    COUNTIF(channel IS NULL OR channel NOT IN (
      'Direct', 'Paid Social', 'Paid Search', 'Display', 'Email', 'Affiliates',
      'Organic Search', 'Organic Social', 'Referral', 'Unknown', 'Other'
    )) AS invalid_channel_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(order_key, ':', session_key))
      AS duplicate_order_session_count,
    COUNTIF(mapping_version != 'phase2b_channel_v2_20260806')
      AS invalid_mapping_version_count,
    COUNTIF(path_definition_version != 'phase2b_closeout_v1_20260806')
      AS invalid_path_version_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
input_orders AS (
  SELECT
    order_key,
    ANY_VALUE(order_revenue_usd) AS order_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  GROUP BY order_key
),
input_order_stats AS (
  SELECT
    COUNT(*) AS order_count,
    SUM(order_revenue_usd) AS order_revenue_usd
  FROM input_orders
),
excluded_order_stats AS (
  SELECT
    COUNT(*) AS order_count,
    SUM(order_revenue_usd) AS order_revenue_usd,
    COUNTIF(exclusion_reason != 'NO_ELIGIBLE_TOUCHPOINT_AFTER_INTERNAL_EXCLUSION')
      AS invalid_exclusion_reason_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders_without_touchpoints`
),
total_order_stats AS (
  SELECT
    COUNT(*) AS order_count,
    SUM(order_revenue_usd) AS order_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
),
path_number_stats AS (
  SELECT
    COUNTIF(
      minimum_touchpoint_number != 1
      OR maximum_touchpoint_number != path_length
      OR touchpoint_count != path_length
      OR distinct_touchpoint_number_count != path_length
      OR distinct_path_length_count != 1
    ) AS invalid_order_path_number_count
  FROM (
    SELECT
      order_key,
      MIN(touchpoint_number) AS minimum_touchpoint_number,
      MAX(touchpoint_number) AS maximum_touchpoint_number,
      COUNT(*) AS touchpoint_count,
      COUNT(DISTINCT touchpoint_number) AS distinct_touchpoint_number_count,
      COUNT(DISTINCT path_length) AS distinct_path_length_count,
      ANY_VALUE(path_length) AS path_length
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
    GROUP BY order_key
  )
),
prepared_expected_touchpoints AS (
  SELECT
    order_key,
    channel,
    touchpoint_number,
    path_length,
    order_revenue_usd,
    MAX(IF(channel != 'Direct', touchpoint_number, NULL)) OVER (
      PARTITION BY order_key
    ) AS last_non_direct_touchpoint_number,
    POW(
      0.5,
      SAFE_DIVIDE(CAST(seconds_before_conversion AS FLOAT64), 7 * 24 * 60 * 60)
    ) AS time_decay_raw_weight
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
normalized_expected_touchpoints AS (
  SELECT
    order_key,
    channel,
    touchpoint_number,
    path_length,
    order_revenue_usd,
    last_non_direct_touchpoint_number,
    SAFE_DIVIDE(
      time_decay_raw_weight,
      SUM(time_decay_raw_weight) OVER (PARTITION BY order_key)
    ) AS time_decay_weight
  FROM prepared_expected_touchpoints
),
expected_touchpoint_weights AS (
  SELECT
    order_key,
    channel,
    order_revenue_usd,
    'First Click' AS model,
    IF(touchpoint_number = 1, 1.0, 0.0) AS attribution_weight
  FROM normalized_expected_touchpoints

  UNION ALL

  SELECT
    order_key,
    channel,
    order_revenue_usd,
    'Last Click' AS model,
    IF(touchpoint_number = path_length, 1.0, 0.0) AS attribution_weight
  FROM normalized_expected_touchpoints

  UNION ALL

  SELECT
    order_key,
    channel,
    order_revenue_usd,
    'Last Non-direct Click' AS model,
    IF(
      touchpoint_number = COALESCE(last_non_direct_touchpoint_number, path_length),
      1.0,
      0.0
    ) AS attribution_weight
  FROM normalized_expected_touchpoints

  UNION ALL

  SELECT
    order_key,
    channel,
    order_revenue_usd,
    'Linear' AS model,
    SAFE_DIVIDE(1.0, path_length) AS attribution_weight
  FROM normalized_expected_touchpoints

  UNION ALL

  SELECT
    order_key,
    channel,
    order_revenue_usd,
    'Time Decay' AS model,
    time_decay_weight AS attribution_weight
  FROM normalized_expected_touchpoints
),
expected_results AS (
  SELECT
    order_key,
    model,
    channel,
    SUM(attribution_weight) AS attribution_weight,
    SUM(order_revenue_usd * attribution_weight) AS attributed_revenue
  FROM expected_touchpoint_weights
  WHERE attribution_weight > 0
  GROUP BY order_key, model, channel
),
formula_comparison AS (
  SELECT
    COUNTIF(
      expected_results.order_key IS NULL
      OR attribution_results.order_key IS NULL
      OR ABS(expected_results.attribution_weight - attribution_results.attribution_weight) > 1e-9
      OR ABS(expected_results.attributed_revenue - attribution_results.attributed_revenue) > 1e-6
    ) AS formula_mismatch_count
  FROM expected_results
  FULL OUTER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
    AS attribution_results
    USING (order_key, model, channel)
),
attribution_stats AS (
  SELECT
    COUNT(DISTINCT model) AS model_count,
    COUNTIF(model NOT IN (
      'First Click', 'Last Click', 'Last Non-direct Click', 'Linear', 'Time Decay'
    )) AS invalid_model_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(order_key, ':', model, ':', channel))
      AS duplicate_grain_count,
    COUNTIF(
      user_pseudo_id IS NULL
      OR order_key IS NULL
      OR transaction_id IS NULL
      OR order_ts IS NULL
      OR order_date IS NULL
      OR model IS NULL
      OR channel IS NULL
      OR attribution_weight IS NULL
      OR attributed_conversion IS NULL
      OR attributed_revenue IS NULL
      OR order_revenue_usd IS NULL
      OR path_length IS NULL
    ) AS null_required_field_count,
    COUNTIF(
      attribution_weight <= 0
      OR IS_NAN(attribution_weight)
      OR IS_INF(attribution_weight)
      OR attributed_conversion <= 0
      OR IS_NAN(attributed_conversion)
      OR IS_INF(attributed_conversion)
      OR attributed_revenue <= 0
      OR IS_NAN(attributed_revenue)
      OR IS_INF(attributed_revenue)
    ) AS invalid_attribution_value_count,
    COUNTIF(channel = 'Internal/Admin') AS internal_admin_result_count,
    COUNTIF(attribution_version != 'phase3_rule_attribution_v1_20260809')
      AS invalid_attribution_version_count,
    COUNTIF(
      (model = 'Time Decay' AND time_decay_half_life_days != 7)
      OR (model != 'Time Decay' AND time_decay_half_life_days IS NOT NULL)
    ) AS invalid_half_life_metadata_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
),
excluded_result_stats AS (
  SELECT COUNT(*) AS excluded_result_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results` AS results
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders_without_touchpoints`
    AS excluded_orders USING (order_key)
),
per_order_model AS (
  SELECT
    order_key,
    model,
    SUM(attribution_weight) AS attribution_weight,
    SUM(attributed_conversion) AS attributed_conversion,
    SUM(attributed_revenue) AS attributed_revenue,
    ANY_VALUE(order_revenue_usd) AS order_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
  GROUP BY order_key, model
),
per_order_model_stats AS (
  SELECT
    COUNT(*) AS order_model_count,
    COUNTIF(ABS(attribution_weight - 1.0) > 1e-9) AS weight_failure_count,
    COUNTIF(ABS(attributed_conversion - 1.0) > 1e-9) AS conversion_failure_count,
    COUNTIF(ABS(attributed_revenue - order_revenue_usd) > 1e-6)
      AS revenue_failure_count
  FROM per_order_model
),
per_model AS (
  SELECT
    model,
    COUNT(DISTINCT order_key) AS order_count,
    SUM(attributed_conversion) AS attributed_conversion,
    SUM(attributed_revenue) AS attributed_revenue
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
  GROUP BY model
),
per_model_stats AS (
  SELECT
    COUNT(*) AS model_count,
    COUNTIF(order_count != 4457) AS order_count_failure_count,
    COUNTIF(ABS(attributed_conversion - 4457.0) > 1e-9)
      AS conversion_total_failure_count,
    COUNTIF(ABS(attributed_revenue - 308208.0) > 1e-6)
      AS revenue_total_failure_count
  FROM per_model
),
all_direct_orders AS (
  SELECT order_key
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  GROUP BY order_key
  HAVING COUNTIF(channel != 'Direct') = 0
),
all_direct_fallback_stats AS (
  SELECT
    COUNT(*) AS all_direct_order_count,
    COUNTIF(
      results.order_key IS NULL
      OR results.channel != 'Direct'
      OR ABS(results.attribution_weight - 1.0) > 1e-9
    ) AS fallback_failure_count
  FROM all_direct_orders
  LEFT JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results` AS results
    ON all_direct_orders.order_key = results.order_key
    AND results.model = 'Last Non-direct Click'
),
comparison_long AS (
  SELECT
    channel,
    'First Click' AS model,
    first_click_attributed_conversions AS attributed_conversion,
    first_click_attributed_revenue_usd AS attributed_revenue
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.model_comparison`

  UNION ALL

  SELECT
    channel,
    'Last Click',
    last_click_attributed_conversions,
    last_click_attributed_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.model_comparison`

  UNION ALL

  SELECT
    channel,
    'Last Non-direct Click',
    last_non_direct_attributed_conversions,
    last_non_direct_attributed_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.model_comparison`

  UNION ALL

  SELECT
    channel,
    'Linear',
    linear_attributed_conversions,
    linear_attributed_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.model_comparison`

  UNION ALL

  SELECT
    channel,
    'Time Decay',
    time_decay_attributed_conversions,
    time_decay_attributed_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.model_comparison`
),
result_channel_totals AS (
  SELECT
    channel,
    model,
    SUM(attributed_conversion) AS attributed_conversion,
    SUM(attributed_revenue) AS attributed_revenue
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
  GROUP BY channel, model
),
comparison_reconciliation_stats AS (
  SELECT
    COUNTIF(
      comparison_long.channel IS NULL
      OR result_channel_totals.channel IS NULL
      OR ABS(comparison_long.attributed_conversion - result_channel_totals.attributed_conversion) > 1e-9
      OR ABS(comparison_long.attributed_revenue - result_channel_totals.attributed_revenue) > 1e-6
    ) AS comparison_mismatch_count
  FROM comparison_long
  FULL OUTER JOIN result_channel_totals USING (channel, model)
),
comparison_stats AS (
  SELECT
    COUNT(*) AS channel_count,
    COUNT(*) - COUNT(DISTINCT channel) AS duplicate_channel_count,
    COUNTIF(channel = 'Internal/Admin') AS internal_admin_channel_count,
    COUNTIF(attribution_version != 'phase3_rule_attribution_v1_20260809')
      AS invalid_version_count,
    ABS(SUM(first_click_conversion_share) - 1.0) AS first_click_conversion_share_delta,
    ABS(SUM(first_click_revenue_share) - 1.0) AS first_click_revenue_share_delta,
    ABS(SUM(last_click_conversion_share) - 1.0) AS last_click_conversion_share_delta,
    ABS(SUM(last_click_revenue_share) - 1.0) AS last_click_revenue_share_delta,
    ABS(SUM(last_non_direct_conversion_share) - 1.0)
      AS last_non_direct_conversion_share_delta,
    ABS(SUM(last_non_direct_revenue_share) - 1.0)
      AS last_non_direct_revenue_share_delta,
    ABS(SUM(linear_conversion_share) - 1.0) AS linear_conversion_share_delta,
    ABS(SUM(linear_revenue_share) - 1.0) AS linear_revenue_share_delta,
    ABS(SUM(time_decay_conversion_share) - 1.0) AS time_decay_conversion_share_delta,
    ABS(SUM(time_decay_revenue_share) - 1.0) AS time_decay_revenue_share_delta
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.model_comparison`
),
comparison_share_stats AS (
  SELECT
    CAST(
      first_click_conversion_share_delta > 1e-9
      OR first_click_revenue_share_delta > 1e-9
      OR last_click_conversion_share_delta > 1e-9
      OR last_click_revenue_share_delta > 1e-9
      OR last_non_direct_conversion_share_delta > 1e-9
      OR last_non_direct_revenue_share_delta > 1e-9
      OR linear_conversion_share_delta > 1e-9
      OR linear_revenue_share_delta > 1e-9
      OR time_decay_conversion_share_delta > 1e-9
      OR time_decay_revenue_share_delta > 1e-9
      AS INT64
    ) AS share_failure_count
  FROM comparison_stats
),
forbidden_scope_stats AS (
  SELECT COUNTIF(table_name IN (
    'markov_attribution',
    'markov_transition_matrix',
    'non_converting_paths',
    'shapley_attribution',
    'budget_scenarios',
    'bootstrap_attribution'
  )) AS forbidden_table_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.INFORMATION_SCHEMA.TABLES`
),
checks AS (
  SELECT 'phase2b_prerequisite_check_count' AS check_id,
    phase2b_validation_stats.check_count AS observed_value, 70 AS expected_value
  FROM phase2b_validation_stats
  UNION ALL SELECT 'phase2b_prerequisite_failures', failed_check_count, 0
  FROM phase2b_validation_stats
  UNION ALL SELECT 'input_touchpoint_count', touchpoint_count, 9577
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_attributable_order_count', attributable_order_count, 4457
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_post_conversion_touchpoints', post_conversion_touchpoint_count, 0
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_negative_seconds_before_conversion', negative_seconds_before_conversion_count, 0
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_internal_admin_touchpoints', internal_admin_touchpoint_count, 0
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_invalid_channels', invalid_channel_count, 0
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_duplicate_order_session_pairs', duplicate_order_session_count, 0
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_invalid_mapping_versions', invalid_mapping_version_count, 0
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_invalid_path_versions', invalid_path_version_count, 0
  FROM input_touchpoint_stats
  UNION ALL SELECT 'input_order_count', order_count, 4457 FROM input_order_stats
  UNION ALL SELECT 'input_order_revenue_cents', CAST(ROUND(order_revenue_usd * 100) AS INT64), 30820800
  FROM input_order_stats
  UNION ALL SELECT 'excluded_order_count', order_count, 9 FROM excluded_order_stats
  UNION ALL SELECT 'excluded_order_revenue_cents', CAST(ROUND(order_revenue_usd * 100) AS INT64), 62200
  FROM excluded_order_stats
  UNION ALL SELECT 'invalid_exclusion_reasons', invalid_exclusion_reason_count, 0
  FROM excluded_order_stats
  UNION ALL SELECT 'total_order_count', order_count, 4466 FROM total_order_stats
  UNION ALL SELECT 'total_order_revenue_cents', CAST(ROUND(order_revenue_usd * 100) AS INT64), 30883000
  FROM total_order_stats
  UNION ALL SELECT 'invalid_path_numbering', invalid_order_path_number_count, 0
  FROM path_number_stats
  UNION ALL SELECT 'attribution_model_count', model_count, 5 FROM attribution_stats
  UNION ALL SELECT 'invalid_attribution_models', invalid_model_count, 0 FROM attribution_stats
  UNION ALL SELECT 'duplicate_attribution_grain', duplicate_grain_count, 0 FROM attribution_stats
  UNION ALL SELECT 'null_attribution_fields', null_required_field_count, 0 FROM attribution_stats
  UNION ALL SELECT 'invalid_attribution_values', invalid_attribution_value_count, 0 FROM attribution_stats
  UNION ALL SELECT 'internal_admin_attribution_results', internal_admin_result_count, 0 FROM attribution_stats
  UNION ALL SELECT 'invalid_attribution_versions', invalid_attribution_version_count, 0 FROM attribution_stats
  UNION ALL SELECT 'invalid_half_life_metadata', invalid_half_life_metadata_count, 0 FROM attribution_stats
  UNION ALL SELECT 'excluded_orders_in_attribution_results', excluded_result_count, 0 FROM excluded_result_stats
  UNION ALL SELECT 'order_model_count', order_model_count, 22285 FROM per_order_model_stats
  UNION ALL SELECT 'order_model_weight_failures', weight_failure_count, 0 FROM per_order_model_stats
  UNION ALL SELECT 'order_model_conversion_failures', conversion_failure_count, 0 FROM per_order_model_stats
  UNION ALL SELECT 'order_model_revenue_failures', revenue_failure_count, 0 FROM per_order_model_stats
  UNION ALL SELECT 'reconciled_model_count', model_count, 5 FROM per_model_stats
  UNION ALL SELECT 'model_order_count_failures', order_count_failure_count, 0 FROM per_model_stats
  UNION ALL SELECT 'model_conversion_total_failures', conversion_total_failure_count, 0 FROM per_model_stats
  UNION ALL SELECT 'model_revenue_total_failures', revenue_total_failure_count, 0 FROM per_model_stats
  UNION ALL SELECT 'model_formula_mismatches', formula_mismatch_count, 0 FROM formula_comparison
  UNION ALL SELECT 'all_direct_path_population_present', CAST(all_direct_order_count > 0 AS INT64), 1
  FROM all_direct_fallback_stats
  UNION ALL SELECT 'all_direct_last_non_direct_fallback_failures', fallback_failure_count, 0
  FROM all_direct_fallback_stats
  UNION ALL SELECT 'model_comparison_channel_count', channel_count, 8 FROM comparison_stats
  UNION ALL SELECT 'model_comparison_duplicate_channels', duplicate_channel_count, 0 FROM comparison_stats
  UNION ALL SELECT 'model_comparison_internal_admin_channels', internal_admin_channel_count, 0 FROM comparison_stats
  UNION ALL SELECT 'model_comparison_invalid_versions', invalid_version_count, 0 FROM comparison_stats
  UNION ALL SELECT 'model_comparison_reconciliation_failures', comparison_mismatch_count, 0
  FROM comparison_reconciliation_stats
  UNION ALL SELECT 'model_comparison_share_failures', share_failure_count, 0
  FROM comparison_share_stats
  UNION ALL SELECT 'forbidden_later_phase_tables', forbidden_table_count, 0
  FROM forbidden_scope_stats
)
SELECT
  check_id,
  observed_value,
  expected_value,
  IF(observed_value = expected_value, 'PASS', 'FAIL') AS validation_status
FROM checks
