-- Phase 6 acceptance checks. Reporting tables must reconcile to the immutable
-- Phase 2B-5 sources and must not introduce a simulated budget object.
WITH upstream_validation_stats AS (
  SELECT
    (SELECT COUNT(*)
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase2b_validation_summary`)
      AS phase2b_checks,
    (SELECT COUNTIF(validation_status != 'PASS')
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase2b_validation_summary`)
      AS phase2b_failures,
    (SELECT COUNT(*)
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase3_validation_summary`)
      AS phase3_checks,
    (SELECT COUNTIF(validation_status != 'PASS')
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase3_validation_summary`)
      AS phase3_failures,
    (SELECT COUNT(*)
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase4_validation_summary`)
      AS phase4_checks,
    (SELECT COUNTIF(validation_status != 'PASS')
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase4_validation_summary`)
      AS phase4_failures,
    (SELECT COUNT(*)
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_validation_summary`)
      AS phase5_checks,
    (SELECT COUNTIF(validation_status != 'PASS')
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_validation_summary`)
      AS phase5_failures
),
eligible_sessions AS (
  SELECT session_key
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
  WHERE is_attribution_eligible
    AND NOT is_internal_admin_traffic
    AND channel != 'Internal/Admin'
),
source_event_flags AS (
  SELECT
    events.session_key,
    COUNTIF(events.event_name = 'view_item') > 0 AS has_view_item,
    COUNTIF(events.event_name = 'add_to_cart') > 0 AS has_add_to_cart,
    COUNTIF(events.event_name = 'begin_checkout') > 0 AS has_begin_checkout,
    COUNTIF(events.event_name = 'purchase') > 0 AS has_purchase
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base` AS events
  WHERE events.session_key IS NOT NULL
  GROUP BY events.session_key
),
source_funnel_totals AS (
  SELECT
    COUNT(DISTINCT eligible_sessions.session_key) AS sessions,
    COUNT(DISTINCT IF(flags.has_view_item, eligible_sessions.session_key, NULL))
      AS view_item_sessions,
    COUNT(DISTINCT IF(flags.has_add_to_cart, eligible_sessions.session_key, NULL))
      AS add_to_cart_sessions,
    COUNT(DISTINCT IF(flags.has_begin_checkout, eligible_sessions.session_key, NULL))
      AS checkout_sessions,
    COUNT(DISTINCT IF(flags.has_purchase, eligible_sessions.session_key, NULL))
      AS purchase_sessions
  FROM eligible_sessions
  LEFT JOIN source_event_flags AS flags USING (session_key)
),
funnel_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT channel) AS channel_count,
    SUM(sessions) AS sessions,
    SUM(sessions_with_view_item) AS view_item_sessions,
    SUM(sessions_with_add_to_cart) AS add_to_cart_sessions,
    SUM(sessions_with_begin_checkout) AS checkout_sessions,
    SUM(sessions_with_purchase) AS purchase_sessions,
    COUNTIF(
      sessions < 1
      OR sessions_with_view_item < 0 OR sessions_with_view_item > sessions
      OR sessions_with_add_to_cart < 0 OR sessions_with_add_to_cart > sessions
      OR sessions_with_begin_checkout < 0
      OR sessions_with_begin_checkout > sessions
      OR sessions_with_purchase < 0 OR sessions_with_purchase > sessions
    ) AS invalid_counts,
    COUNTIF(
      view_item_session_rate < 0 OR view_item_session_rate > 1
      OR add_to_cart_session_rate < 0 OR add_to_cart_session_rate > 1
      OR checkout_session_rate < 0 OR checkout_session_rate > 1
      OR purchase_session_rate < 0 OR purchase_session_rate > 1
      OR IS_NAN(view_item_session_rate) OR IS_INF(view_item_session_rate)
      OR IS_NAN(add_to_cart_session_rate) OR IS_INF(add_to_cart_session_rate)
      OR IS_NAN(checkout_session_rate) OR IS_INF(checkout_session_rate)
      OR IS_NAN(purchase_session_rate) OR IS_INF(purchase_session_rate)
    ) AS invalid_rates,
    COUNTIF(
      denominator_definition != 'all_attribution_eligible_sessions_for_channel'
      OR metric_definition != 'channel_level_funnel_stage_incidence_rates'
      OR mapping_version != 'phase2b_channel_v2_20260806'
      OR reporting_version != 'phase6_business_reporting_v1_20260814'
    ) AS invalid_definitions
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.channel_funnel_summary`
),
source_journeys AS (
  SELECT
    order_key,
    ANY_VALUE(order_revenue_usd) AS order_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  GROUP BY order_key
),
source_journey_totals AS (
  SELECT
    COUNT(*) AS conversions,
    SUM(order_revenue_usd) AS revenue
  FROM source_journeys
),
journey_overall AS (
  SELECT
    COUNT(*) AS row_count,
    ANY_VALUE(attributable_conversions) AS conversions,
    ANY_VALUE(attributable_revenue) AS revenue,
    ANY_VALUE(single_touch_conversions) AS single_touch_conversions,
    ANY_VALUE(multi_touch_conversions) AS multi_touch_conversions,
    ANY_VALUE(single_touch_conversion_share) AS single_touch_share,
    ANY_VALUE(multi_touch_conversion_share) AS multi_touch_share,
    ANY_VALUE(mean_path_length) AS mean_path_length,
    ANY_VALUE(median_path_length) AS median_path_length
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.journey_summary`
  WHERE summary_type = 'OVERALL'
),
journey_group_totals AS (
  SELECT
    summary_type,
    SUM(attributable_conversions) AS conversions,
    SUM(attributable_revenue) AS revenue,
    SUM(conversion_share) AS conversion_share,
    SUM(revenue_share) AS revenue_share
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.journey_summary`
  WHERE summary_type != 'OVERALL'
  GROUP BY summary_type
),
journey_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT summary_type) AS summary_type_count,
    COUNTIF(
      reporting_version != 'phase6_business_reporting_v1_20260814'
      OR mapping_version != 'phase2b_channel_v2_20260806'
      OR path_definition_version != 'phase2b_closeout_v1_20260806'
    ) AS invalid_versions,
    COUNTIF(
      conversion_share < 0 OR conversion_share > 1
      OR revenue_share < 0 OR revenue_share > 1
      OR IS_NAN(conversion_share) OR IS_INF(conversion_share)
      OR IS_NAN(revenue_share) OR IS_INF(revenue_share)
    ) AS invalid_shares
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.journey_summary`
),
journey_group_stats AS (
  SELECT
    COUNT(*) AS group_count,
    COUNTIF(
      ABS(grouped.conversions - source.conversions) > 1e-9
      OR ABS(grouped.revenue - source.revenue) > 1e-6
      OR ABS(grouped.conversion_share - 1.0) > 1e-9
      OR ABS(grouped.revenue_share - 1.0) > 1e-9
    ) AS reconciliation_failures
  FROM journey_group_totals AS grouped
  CROSS JOIN source_journey_totals AS source
),
attribution_model_totals AS (
  SELECT
    model,
    COUNT(*) AS channel_count,
    SUM(attributed_conversions) AS conversions,
    SUM(attributed_revenue) AS revenue,
    SUM(conversion_share) AS conversion_share,
    SUM(revenue_share) AS revenue_share,
    COUNT(DISTINCT conversion_rank) AS conversion_rank_count,
    COUNT(DISTINCT revenue_rank) AS revenue_rank_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_business_summary`
  GROUP BY model
),
attribution_model_stats AS (
  SELECT
    COUNT(*) AS model_count,
    COUNTIF(
      channel_count != 9
      OR ABS(conversions - 4457.0) > 1e-6
      OR ABS(revenue - 308208.0) > 1e-4
      OR ABS(conversion_share - 1.0) > 1e-9
      OR ABS(revenue_share - 1.0) > 1e-9
      OR conversion_rank_count != 9
      OR revenue_rank_count != 9
    ) AS reconciliation_failures
  FROM attribution_model_totals
),
attribution_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT channel) AS channel_count,
    COUNT(DISTINCT model) AS model_count,
    COUNTIF(
      reporting_version != 'phase6_business_reporting_v1_20260814'
      OR bootstrap_version != 'phase5_sensitivity_stability_v1_20260812'
      OR markov_version != 'phase4_markov_30d_anderl_v2_20260811'
    ) AS invalid_versions,
    COUNTIF(
      markov_deterministic_scenario_count != 4
      OR bootstrap_seed != 20260812
      OR bootstrap_attempted_replicates != 500
      OR bootstrap_successful_replicates != 500
      OR bootstrap_failed_replicates != 0
    ) AS invalid_stability_contracts
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_business_summary`
),
markov_difference_reproduction AS (
  SELECT
    COUNTIF(
      ABS(
        markov_minus_last_click_conversions
          - source.conversion_difference_vs_last_click
      ) > 1e-9
      OR ABS(
        markov_minus_last_click_revenue
          - source.revenue_difference_vs_last_click
      ) > 1e-6
      OR (
        markov_minus_last_click_conversion_relative IS NULL
      ) != (
        source.conversion_relative_difference_vs_last_click IS NULL
      )
      OR (
        markov_minus_last_click_revenue_relative IS NULL
      ) != (
        source.revenue_relative_difference_vs_last_click IS NULL
      )
      OR ABS(
        COALESCE(markov_minus_last_click_conversion_relative, 0.0)
          - COALESCE(source.conversion_relative_difference_vs_last_click, 0.0)
      ) > 1e-12
      OR ABS(
        COALESCE(markov_minus_last_click_revenue_relative, 0.0)
          - COALESCE(source.revenue_relative_difference_vs_last_click, 0.0)
      ) > 1e-12
    ) AS mismatch_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_business_summary`
    AS report
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.rule_markov_comparison`
    AS source USING (channel, model)
  WHERE report.model = 'Markov'
),
bootstrap_reproduction AS (
  SELECT
    COUNTIF(
      ABS(report.bootstrap_mean_share - source.bootstrap_mean_share) > 1e-12
      OR ABS(report.bootstrap_share_percentile_2_5
        - source.share_percentile_2_5) > 1e-12
      OR ABS(report.bootstrap_share_percentile_97_5
        - source.share_percentile_97_5) > 1e-12
      OR report.bootstrap_min_rank != source.minimum_observed_rank
      OR report.bootstrap_max_rank != source.maximum_observed_rank
      OR ABS(report.bootstrap_probability_top_1
        - source.probability_top_1) > 1e-12
      OR ABS(report.bootstrap_probability_top_3
        - source.probability_top_3) > 1e-12
    ) AS mismatch_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_business_summary`
    AS report
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_bootstrap_summary`
    AS source USING (channel)
),
organic_stability AS (
  SELECT
    MIN(markov_deterministic_min_rank) AS deterministic_min_rank,
    MAX(markov_deterministic_max_rank) AS deterministic_max_rank,
    MIN(bootstrap_probability_top_1) AS bootstrap_top_1_probability
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_business_summary`
  WHERE channel = 'Organic Search'
),
technical_top3 AS (
  SELECT
    COUNTIF(
      channel IN ('Organic Search', 'Referral', 'Unknown')
      AND probability_top_3 = 1.0
    ) AS always_top3_channels
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_bootstrap_summary`
),
budget_object AS (
  SELECT COUNTIF(table_name = 'budget_scenario_summary') AS table_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.INFORMATION_SCHEMA.TABLES`
),
checks AS (
  SELECT 'upstream_phase2b_check_count' AS check_id,
    CAST(phase2b_checks AS STRING) AS observed_value, '70' AS expected_value
  FROM upstream_validation_stats
  UNION ALL SELECT 'upstream_phase2b_failures', CAST(phase2b_failures AS STRING), '0' FROM upstream_validation_stats
  UNION ALL SELECT 'upstream_phase3_check_count', CAST(phase3_checks AS STRING), '46' FROM upstream_validation_stats
  UNION ALL SELECT 'upstream_phase3_failures', CAST(phase3_failures AS STRING), '0' FROM upstream_validation_stats
  UNION ALL SELECT 'upstream_phase4_check_count', CAST(phase4_checks AS STRING), '70' FROM upstream_validation_stats
  UNION ALL SELECT 'upstream_phase4_failures', CAST(phase4_failures AS STRING), '0' FROM upstream_validation_stats
  UNION ALL SELECT 'upstream_phase5_check_count', CAST(phase5_checks AS STRING), '56' FROM upstream_validation_stats
  UNION ALL SELECT 'upstream_phase5_failures', CAST(phase5_failures AS STRING), '0' FROM upstream_validation_stats
  UNION ALL SELECT 'funnel_unique_channel_grain', CAST(row_count - channel_count AS STRING), '0' FROM funnel_stats
  UNION ALL SELECT 'funnel_invalid_counts', CAST(invalid_counts AS STRING), '0' FROM funnel_stats
  UNION ALL SELECT 'funnel_invalid_rates', CAST(invalid_rates AS STRING), '0' FROM funnel_stats
  UNION ALL SELECT 'funnel_invalid_definitions', CAST(invalid_definitions AS STRING), '0' FROM funnel_stats
  UNION ALL SELECT 'funnel_session_reconciliation', CAST(funnel.sessions - source.sessions AS STRING), '0' FROM funnel_stats AS funnel CROSS JOIN source_funnel_totals AS source
  UNION ALL SELECT 'funnel_view_item_reconciliation', CAST(funnel.view_item_sessions - source.view_item_sessions AS STRING), '0' FROM funnel_stats AS funnel CROSS JOIN source_funnel_totals AS source
  UNION ALL SELECT 'funnel_add_to_cart_reconciliation', CAST(funnel.add_to_cart_sessions - source.add_to_cart_sessions AS STRING), '0' FROM funnel_stats AS funnel CROSS JOIN source_funnel_totals AS source
  UNION ALL SELECT 'funnel_checkout_reconciliation', CAST(funnel.checkout_sessions - source.checkout_sessions AS STRING), '0' FROM funnel_stats AS funnel CROSS JOIN source_funnel_totals AS source
  UNION ALL SELECT 'funnel_purchase_reconciliation', CAST(funnel.purchase_sessions - source.purchase_sessions AS STRING), '0' FROM funnel_stats AS funnel CROSS JOIN source_funnel_totals AS source
  UNION ALL SELECT 'journey_summary_type_count', CAST(summary_type_count AS STRING), '5' FROM journey_stats
  UNION ALL SELECT 'journey_invalid_versions', CAST(invalid_versions AS STRING), '0' FROM journey_stats
  UNION ALL SELECT 'journey_invalid_shares', CAST(invalid_shares AS STRING), '0' FROM journey_stats
  UNION ALL SELECT 'journey_overall_row_count', CAST(row_count AS STRING), '1' FROM journey_overall
  UNION ALL SELECT 'journey_overall_conversion_reconciliation', CAST(overall.conversions - source.conversions AS STRING), '0' FROM journey_overall AS overall CROSS JOIN source_journey_totals AS source
  UNION ALL SELECT 'journey_overall_revenue_reconciliation', CAST(ROUND(overall.revenue - source.revenue, 6) AS STRING), '0' FROM journey_overall AS overall CROSS JOIN source_journey_totals AS source
  UNION ALL SELECT 'journey_touch_class_reconciliation', CAST(single_touch_conversions + multi_touch_conversions - conversions AS STRING), '0' FROM journey_overall
  UNION ALL SELECT 'journey_touch_share_reconciliation', CAST(ROUND(single_touch_share + multi_touch_share - 1.0, 12) AS STRING), '0' FROM journey_overall
  UNION ALL SELECT 'journey_mean_path_positive', CAST(COUNTIF(mean_path_length <= 0 OR median_path_length <= 0) AS STRING), '0' FROM journey_overall
  UNION ALL SELECT 'journey_distribution_group_count', CAST(group_count AS STRING), '4' FROM journey_group_stats
  UNION ALL SELECT 'journey_distribution_reconciliation_failures', CAST(reconciliation_failures AS STRING), '0' FROM journey_group_stats
  UNION ALL SELECT 'attribution_row_count', CAST(row_count AS STRING), '54' FROM attribution_stats
  UNION ALL SELECT 'attribution_channel_count', CAST(channel_count AS STRING), '9' FROM attribution_stats
  UNION ALL SELECT 'attribution_model_count', CAST(model_count AS STRING), '6' FROM attribution_stats
  UNION ALL SELECT 'attribution_invalid_versions', CAST(invalid_versions AS STRING), '0' FROM attribution_stats
  UNION ALL SELECT 'attribution_invalid_stability_contracts', CAST(invalid_stability_contracts AS STRING), '0' FROM attribution_stats
  UNION ALL SELECT 'attribution_markov_difference_reproduction_mismatches', CAST(mismatch_count AS STRING), '0' FROM markov_difference_reproduction
  UNION ALL SELECT 'attribution_model_group_count', CAST(model_count AS STRING), '6' FROM attribution_model_stats
  UNION ALL SELECT 'attribution_model_reconciliation_failures', CAST(reconciliation_failures AS STRING), '0' FROM attribution_model_stats
  UNION ALL SELECT 'phase5_bootstrap_reproduction_mismatches', CAST(mismatch_count AS STRING), '0' FROM bootstrap_reproduction
  UNION ALL SELECT 'organic_search_deterministic_min_rank', CAST(deterministic_min_rank AS STRING), '1' FROM organic_stability
  UNION ALL SELECT 'organic_search_deterministic_max_rank', CAST(deterministic_max_rank AS STRING), '1' FROM organic_stability
  UNION ALL SELECT 'organic_search_bootstrap_top1', CAST(bootstrap_top_1_probability AS STRING), '1' FROM organic_stability
  UNION ALL SELECT 'bootstrap_always_top3_channel_count', CAST(always_top3_channels AS STRING), '3' FROM technical_top3
  UNION ALL SELECT 'approved_budget_scenario_omission', CAST(table_count AS STRING), '0' FROM budget_object
)
SELECT
  check_id,
  observed_value,
  expected_value,
  IF(observed_value = expected_value, 'PASS', 'FAIL') AS validation_status,
  'phase6_business_reporting_v1_20260814' AS validation_version
FROM checks
