-- Long-form business reporting across the six already-validated attribution
-- models. Phase 5 fields reproduce stored sensitivity and bootstrap evidence;
-- no attribution model is rebuilt here.
WITH comparison AS (
  SELECT
    channel,
    model,
    attributed_conversions,
    attributed_revenue,
    attribution_share AS conversion_share,
    channel_rank AS conversion_rank,
    conversion_difference_vs_last_click,
    conversion_relative_difference_vs_last_click,
    revenue_difference_vs_last_click,
    revenue_relative_difference_vs_last_click,
    last_click_attributed_conversions,
    last_click_attributed_revenue,
    markov_version
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.rule_markov_comparison`
),
ranked_comparison AS (
  SELECT
    comparison.channel,
    comparison.model,
    comparison.attributed_conversions,
    comparison.attributed_revenue,
    comparison.conversion_share,
    comparison.conversion_rank,
    comparison.conversion_difference_vs_last_click,
    comparison.conversion_relative_difference_vs_last_click,
    comparison.revenue_difference_vs_last_click,
    comparison.revenue_relative_difference_vs_last_click,
    comparison.last_click_attributed_conversions,
    comparison.last_click_attributed_revenue,
    comparison.markov_version,
    SAFE_DIVIDE(
      attributed_revenue,
      SUM(attributed_revenue) OVER (PARTITION BY model)
    ) AS revenue_share,
    ROW_NUMBER() OVER (
      PARTITION BY model
      ORDER BY attributed_revenue DESC, channel
    ) AS revenue_rank
  FROM comparison
),
markov_last_click_differences AS (
  SELECT
    channel,
    conversion_difference_vs_last_click
      AS markov_minus_last_click_conversions,
    conversion_relative_difference_vs_last_click
      AS markov_minus_last_click_conversion_relative,
    revenue_difference_vs_last_click AS markov_minus_last_click_revenue,
    revenue_relative_difference_vs_last_click
      AS markov_minus_last_click_revenue_relative
  FROM ranked_comparison
  WHERE model = 'Markov'
),
deterministic_markov_stability AS (
  SELECT
    channel,
    COUNT(DISTINCT scenario_id) AS deterministic_scenario_count,
    MIN(conversion_rank) AS deterministic_min_rank,
    MAX(conversion_rank) AS deterministic_max_rank,
    SAFE_DIVIDE(COUNTIF(conversion_rank = 1), COUNT(*))
      AS deterministic_rank_1_frequency,
    SAFE_DIVIDE(COUNTIF(conversion_rank <= 3), COUNT(*))
      AS deterministic_top_3_frequency,
    MIN(conversion_share) AS deterministic_min_share,
    MAX(conversion_share) AS deterministic_max_share
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_sensitivity_results`
  WHERE model = 'Markov'
    AND cohort_view = 'completed_outcomes'
  GROUP BY channel
),
bootstrap AS (
  SELECT
    channel,
    seed AS bootstrap_seed,
    attempted_replicates AS bootstrap_attempted_replicates,
    successful_replicates AS bootstrap_successful_replicates,
    failed_replicates AS bootstrap_failed_replicates,
    bootstrap_mean_share,
    bootstrap_median_share,
    bootstrap_share_stddev,
    share_percentile_2_5 AS bootstrap_share_percentile_2_5,
    share_percentile_97_5 AS bootstrap_share_percentile_97_5,
    minimum_observed_rank AS bootstrap_min_rank,
    maximum_observed_rank AS bootstrap_max_rank,
    probability_top_1 AS bootstrap_probability_top_1,
    probability_top_3 AS bootstrap_probability_top_3,
    probability_top_5 AS bootstrap_probability_top_5,
    bootstrap_version
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_bootstrap_summary`
)
SELECT
  ranked_comparison.channel,
  ranked_comparison.model,
  ranked_comparison.attributed_conversions,
  ranked_comparison.attributed_revenue,
  ranked_comparison.conversion_share,
  ranked_comparison.revenue_share,
  ranked_comparison.conversion_rank,
  ranked_comparison.revenue_rank,
  differences.markov_minus_last_click_conversions,
  differences.markov_minus_last_click_conversion_relative,
  differences.markov_minus_last_click_revenue,
  differences.markov_minus_last_click_revenue_relative,
  stability.deterministic_scenario_count AS markov_deterministic_scenario_count,
  stability.deterministic_min_rank AS markov_deterministic_min_rank,
  stability.deterministic_max_rank AS markov_deterministic_max_rank,
  stability.deterministic_rank_1_frequency
    AS markov_deterministic_rank_1_frequency,
  stability.deterministic_top_3_frequency
    AS markov_deterministic_top_3_frequency,
  stability.deterministic_min_share AS markov_deterministic_min_share,
  stability.deterministic_max_share AS markov_deterministic_max_share,
  bootstrap.bootstrap_mean_share,
  bootstrap.bootstrap_median_share,
  bootstrap.bootstrap_share_stddev,
  bootstrap.bootstrap_share_percentile_2_5,
  bootstrap.bootstrap_share_percentile_97_5,
  bootstrap.bootstrap_min_rank,
  bootstrap.bootstrap_max_rank,
  bootstrap.bootstrap_probability_top_1,
  bootstrap.bootstrap_probability_top_3,
  bootstrap.bootstrap_probability_top_5,
  bootstrap.bootstrap_seed,
  bootstrap.bootstrap_attempted_replicates,
  bootstrap.bootstrap_successful_replicates,
  bootstrap.bootstrap_failed_replicates,
  ranked_comparison.channel NOT IN ('Unknown', 'Other')
    AS is_business_presentation_channel,
  ranked_comparison.markov_version,
  bootstrap.bootstrap_version,
  'phase6_business_reporting_v1_20260814' AS reporting_version
FROM ranked_comparison
INNER JOIN markov_last_click_differences AS differences USING (channel)
INNER JOIN deterministic_markov_stability AS stability USING (channel)
INNER JOIN bootstrap USING (channel)
