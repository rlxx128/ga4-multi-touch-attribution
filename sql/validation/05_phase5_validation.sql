-- Phase 5 acceptance checks. Prior-phase tables are read-only prerequisites;
-- scenario and bootstrap outputs must be internally coherent and versioned.
WITH phase3_models AS (
  SELECT
    model,
    COUNT(DISTINCT order_key) AS order_count,
    SUM(attributed_conversion) AS conversions,
    SUM(attributed_revenue) AS revenue
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
  GROUP BY model
),
manifest_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT scenario_id) AS distinct_scenarios,
    COUNTIF(is_baseline AND changed_assumption_count != 0) AS invalid_baselines,
    COUNTIF(NOT is_baseline AND changed_assumption_count != 1)
      AS invalid_sensitivities,
    COUNTIF(NOT is_owner_approved) AS unapproved_scenarios,
    COUNTIF(right_censored_in_model_count != 0) AS censored_model_scenarios,
    COUNTIF(internal_admin_state_count != 0) AS internal_admin_scenarios,
    COUNTIF(invalid_transition_row_count != 0) AS invalid_transition_scenarios,
    COUNTIF(invalid_absorbing_state_count != 0) AS invalid_absorber_scenarios,
    COUNTIF(materially_negative_effect_count != 0) AS negative_effect_scenarios,
    COUNT(DISTINCT baseline_fingerprint_sha256) AS fingerprint_count,
    COUNTIF(rank_tie_break_rule != 'share_desc_channel_name_asc')
      AS invalid_tie_rules
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_scenario_manifest`
),
result_group_stats AS (
  SELECT
    scenario_id,
    cohort_view,
    model,
    COUNT(*) AS channel_count,
    SUM(conversion_share) AS conversion_share_sum,
    SUM(revenue_share) AS revenue_share_sum,
    SUM(attributed_conversions) AS conversions,
    SUM(attributed_revenue) AS revenue,
    ANY_VALUE(attributable_order_count) AS expected_conversions,
    ANY_VALUE(attributable_revenue) AS expected_revenue,
    COUNT(DISTINCT conversion_rank) AS conversion_rank_count,
    COUNT(DISTINCT revenue_rank) AS revenue_rank_count,
    MIN(conversion_rank) AS minimum_conversion_rank,
    MAX(conversion_rank) AS maximum_conversion_rank,
    MIN(revenue_rank) AS minimum_revenue_rank,
    MAX(revenue_rank) AS maximum_revenue_rank,
    COUNTIF(
      IS_NAN(conversion_share) OR IS_INF(conversion_share)
      OR IS_NAN(revenue_share) OR IS_INF(revenue_share)
      OR conversion_share < 0 OR revenue_share < 0
    ) AS invalid_shares,
    COUNTIF(
      removal_effect IS NOT NULL
      AND (IS_NAN(removal_effect) OR IS_INF(removal_effect))
    ) AS nonfinite_effects,
    COUNTIF(removal_effect < -1e-12) AS materially_negative_effects
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_sensitivity_results`
  GROUP BY scenario_id, cohort_view, model
),
result_stats AS (
  SELECT
    COUNT(*) AS group_count,
    COUNTIF(ABS(conversion_share_sum - 1.0) > 1e-9) AS invalid_conversion_sums,
    COUNTIF(ABS(revenue_share_sum - 1.0) > 1e-9) AS invalid_revenue_sums,
    COUNTIF(ABS(conversions - expected_conversions) > 1e-6)
      AS conversion_reconciliation_failures,
    COUNTIF(ABS(revenue - expected_revenue) > 1e-4)
      AS revenue_reconciliation_failures,
    COUNTIF(
      conversion_rank_count != channel_count
      OR minimum_conversion_rank != 1
      OR maximum_conversion_rank != channel_count
    ) AS invalid_conversion_ranks,
    COUNTIF(
      revenue_rank_count != channel_count
      OR minimum_revenue_rank != 1
      OR maximum_revenue_rank != channel_count
    ) AS invalid_revenue_ranks,
    SUM(invalid_shares) AS invalid_shares,
    SUM(nonfinite_effects) AS nonfinite_effects,
    SUM(materially_negative_effects) AS materially_negative_effects
  FROM result_group_stats
),
common_cohort_stats AS (
  SELECT
    COUNT(DISTINCT attributable_order_count) AS distinct_order_counts,
    COUNT(DISTINCT attributable_revenue) AS distinct_revenue_totals,
    MIN(attributable_order_count) AS minimum_order_count,
    MAX(attributable_order_count) AS maximum_order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_sensitivity_results`
  WHERE cohort_view = 'common_cohort'
),
rank_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COUNTIF(
      spearman_rank_correlation < -1 OR spearman_rank_correlation > 1
      OR top_3_overlap < 0 OR top_3_overlap > 3
      OR maximum_absolute_rank_shift < 0
      OR absolute_rank_shift < 0
      OR IS_NAN(absolute_percentage_point_change)
      OR IS_INF(absolute_percentage_point_change)
    ) AS invalid_rows
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_rank_stability`
),
bootstrap_replicate_stats AS (
  SELECT
    COUNT(DISTINCT replicate_id) AS attempted_replicates,
    COUNT(DISTINCT IF(replicate_status = 'SUCCESS', replicate_id, NULL))
      AS successful_replicates,
    COUNT(DISTINCT IF(replicate_status = 'FAILED', replicate_id, NULL))
      AS failed_replicates,
    COUNT(DISTINCT seed) AS seed_count,
    MIN(seed) AS minimum_seed,
    COUNTIF(replicate_status = 'SUCCESS' AND channel IS NULL)
      AS successful_rows_without_channel,
    COUNTIF(replicate_status = 'FAILED' AND failure_reason IS NULL)
      AS failed_rows_without_reason,
    COUNTIF(
      replicate_status = 'SUCCESS'
      AND (
        markov_share < 0 OR markov_share > 1
        OR removal_effect < -1e-12
        OR channel_rank < 1 OR channel_rank > 9
        OR IS_NAN(markov_share) OR IS_INF(markov_share)
        OR IS_NAN(removal_effect) OR IS_INF(removal_effect)
      )
    ) AS invalid_success_rows
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_bootstrap_replicates`
),
bootstrap_per_replicate AS (
  SELECT
    replicate_id,
    COUNT(*) AS channel_count,
    COUNT(DISTINCT channel_rank) AS rank_count,
    SUM(markov_share) AS share_sum
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_bootstrap_replicates`
  WHERE replicate_status = 'SUCCESS'
  GROUP BY replicate_id
),
bootstrap_per_replicate_stats AS (
  SELECT
    COUNTIF(channel_count != 9) AS invalid_channel_counts,
    COUNTIF(rank_count != 9) AS invalid_rank_counts,
    COUNTIF(ABS(share_sum - 1.0) > 1e-9) AS invalid_share_sums
  FROM bootstrap_per_replicate
),
bootstrap_summary_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT channel) AS channel_count,
    COUNT(DISTINCT seed) AS seed_count,
    MIN(seed) AS minimum_seed,
    COUNT(DISTINCT attempted_replicates) AS attempted_count_values,
    MIN(attempted_replicates) AS minimum_attempted,
    COUNTIF(
      probability_top_1 < 0 OR probability_top_1 > 1
      OR probability_top_3 < 0 OR probability_top_3 > 1
      OR probability_top_5 < 0 OR probability_top_5 > 1
      OR share_percentile_2_5 > share_percentile_97_5
      OR removal_effect_percentile_2_5 > removal_effect_percentile_97_5
    ) AS invalid_summary_rows
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_bootstrap_summary`
),
checks AS (
  SELECT 'phase2b_check_count' AS check_id,
    CAST(COUNT(*) AS STRING) AS observed_value, '70' AS expected_value
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase2b_validation_summary`
  UNION ALL SELECT 'phase2b_failures', CAST(COUNTIF(validation_status != 'PASS') AS STRING), '0'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase2b_validation_summary`
  UNION ALL SELECT 'phase3_check_count', CAST(COUNT(*) AS STRING), '46'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase3_validation_summary`
  UNION ALL SELECT 'phase3_failures', CAST(COUNTIF(validation_status != 'PASS') AS STRING), '0'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase3_validation_summary`
  UNION ALL SELECT 'phase4_check_count', CAST(COUNT(*) AS STRING), '70'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase4_validation_summary`
  UNION ALL SELECT 'phase4_failures', CAST(COUNTIF(validation_status != 'PASS') AS STRING), '0'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase4_validation_summary`
  UNION ALL SELECT 'baseline_order_count', CAST(COUNT(*) AS STRING), '4466'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
  UNION ALL SELECT 'baseline_conversion_touchpoints', CAST(COUNT(*) AS STRING), '9577'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  UNION ALL SELECT 'baseline_markov_journeys', CAST(COUNT(*) AS STRING), '273683'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_journeys`
  UNION ALL SELECT 'baseline_markov_transitions', CAST(SUM(transition_count) AS STRING), '421188'
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_transition_matrix`
  UNION ALL SELECT 'phase3_model_reconciliations',
    CAST(COUNTIF(order_count != 4457 OR ABS(conversions - 4457) > 1e-9
      OR ABS(revenue - 308208) > 1e-6) AS STRING), '0' FROM phase3_models
  UNION ALL SELECT 'manifest_rows', CAST(row_count AS STRING), '7' FROM manifest_stats
  UNION ALL SELECT 'manifest_unique_scenarios', CAST(distinct_scenarios AS STRING), '7' FROM manifest_stats
  UNION ALL SELECT 'manifest_invalid_baselines', CAST(invalid_baselines AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'manifest_invalid_sensitivities', CAST(invalid_sensitivities AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'manifest_unapproved_scenarios', CAST(unapproved_scenarios AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'right_censored_in_model', CAST(censored_model_scenarios AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'internal_admin_scenarios', CAST(internal_admin_scenarios AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'invalid_transition_scenarios', CAST(invalid_transition_scenarios AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'invalid_absorbing_scenarios', CAST(invalid_absorber_scenarios AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'negative_effect_scenarios', CAST(negative_effect_scenarios AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'baseline_fingerprint_count', CAST(fingerprint_count AS STRING), '1' FROM manifest_stats
  UNION ALL SELECT 'invalid_tie_rules', CAST(invalid_tie_rules AS STRING), '0' FROM manifest_stats
  UNION ALL SELECT 'result_group_count_positive', CAST(COUNTIF(group_count > 0) AS STRING), '1' FROM result_stats
  UNION ALL SELECT 'invalid_conversion_share_sums', CAST(invalid_conversion_sums AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'invalid_revenue_share_sums', CAST(invalid_revenue_sums AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'conversion_reconciliation_failures', CAST(conversion_reconciliation_failures AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'revenue_reconciliation_failures', CAST(revenue_reconciliation_failures AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'invalid_conversion_ranks', CAST(invalid_conversion_ranks AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'invalid_revenue_ranks', CAST(invalid_revenue_ranks AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'invalid_result_shares', CAST(invalid_shares AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'nonfinite_removal_effects', CAST(nonfinite_effects AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'materially_negative_removal_effects', CAST(materially_negative_effects AS STRING), '0' FROM result_stats
  UNION ALL SELECT 'common_cohort_order_sets', CAST(distinct_order_counts AS STRING), '1' FROM common_cohort_stats
  UNION ALL SELECT 'common_cohort_revenue_sets', CAST(distinct_revenue_totals AS STRING), '1' FROM common_cohort_stats
  UNION ALL SELECT 'common_cohort_minimum_orders', CAST(minimum_order_count AS STRING), '4457' FROM common_cohort_stats
  UNION ALL SELECT 'common_cohort_maximum_orders', CAST(maximum_order_count AS STRING), '4457' FROM common_cohort_stats
  UNION ALL SELECT 'rank_stability_rows_positive', CAST(COUNTIF(row_count > 0) AS STRING), '1' FROM rank_stats
  UNION ALL SELECT 'invalid_rank_stability_rows', CAST(invalid_rows AS STRING), '0' FROM rank_stats
  UNION ALL SELECT 'bootstrap_attempted_replicates', CAST(attempted_replicates AS STRING), '500' FROM bootstrap_replicate_stats
  UNION ALL SELECT 'bootstrap_seed_count', CAST(seed_count AS STRING), '1' FROM bootstrap_replicate_stats
  UNION ALL SELECT 'bootstrap_seed', CAST(minimum_seed AS STRING), '20260812' FROM bootstrap_replicate_stats
  UNION ALL SELECT 'bootstrap_attempted_reconciliation',
    CAST(successful_replicates + failed_replicates AS STRING), '500' FROM bootstrap_replicate_stats
  UNION ALL SELECT 'bootstrap_success_rows_without_channel', CAST(successful_rows_without_channel AS STRING), '0' FROM bootstrap_replicate_stats
  UNION ALL SELECT 'bootstrap_failed_rows_without_reason', CAST(failed_rows_without_reason AS STRING), '0' FROM bootstrap_replicate_stats
  UNION ALL SELECT 'bootstrap_invalid_success_rows', CAST(invalid_success_rows AS STRING), '0' FROM bootstrap_replicate_stats
  UNION ALL SELECT 'bootstrap_invalid_channel_counts', CAST(invalid_channel_counts AS STRING), '0' FROM bootstrap_per_replicate_stats
  UNION ALL SELECT 'bootstrap_invalid_rank_counts', CAST(invalid_rank_counts AS STRING), '0' FROM bootstrap_per_replicate_stats
  UNION ALL SELECT 'bootstrap_invalid_share_sums', CAST(invalid_share_sums AS STRING), '0' FROM bootstrap_per_replicate_stats
  UNION ALL SELECT 'bootstrap_summary_rows', CAST(row_count AS STRING), '9' FROM bootstrap_summary_stats
  UNION ALL SELECT 'bootstrap_summary_channels', CAST(channel_count AS STRING), '9' FROM bootstrap_summary_stats
  UNION ALL SELECT 'bootstrap_summary_seed_count', CAST(seed_count AS STRING), '1' FROM bootstrap_summary_stats
  UNION ALL SELECT 'bootstrap_summary_seed', CAST(minimum_seed AS STRING), '20260812' FROM bootstrap_summary_stats
  UNION ALL SELECT 'bootstrap_summary_attempted_values', CAST(attempted_count_values AS STRING), '1' FROM bootstrap_summary_stats
  UNION ALL SELECT 'bootstrap_summary_attempted', CAST(minimum_attempted AS STRING), '500' FROM bootstrap_summary_stats
  UNION ALL SELECT 'bootstrap_invalid_summary_rows', CAST(invalid_summary_rows AS STRING), '0' FROM bootstrap_summary_stats
)
SELECT
  check_id,
  observed_value,
  expected_value,
  IF(observed_value = expected_value, 'PASS', 'FAIL') AS validation_status,
  'phase5_sensitivity_stability_v1_20260812' AS validation_version
FROM checks
