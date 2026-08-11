-- Long-form channel comparison across the five Phase 3 models and Markov.
WITH observed_channels AS (
  SELECT DISTINCT channel
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`

  UNION DISTINCT

  SELECT channel
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_attribution`
),
models AS (
  SELECT 'First Click' AS model
  UNION ALL SELECT 'Last Click'
  UNION ALL SELECT 'Last Non-direct Click'
  UNION ALL SELECT 'Linear'
  UNION ALL SELECT 'Time Decay'
  UNION ALL SELECT 'Markov'
),
rule_totals AS (
  SELECT
    channel,
    model,
    SUM(attributed_conversion) AS attributed_conversions,
    SUM(attributed_revenue) AS attributed_revenue
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
  GROUP BY channel, model
),
all_model_totals AS (
  SELECT
    channel,
    model,
    attributed_conversions,
    attributed_revenue
  FROM rule_totals

  UNION ALL

  SELECT
    channel,
    'Markov' AS model,
    attributed_conversions,
    attributed_revenue
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_attribution`
),
complete_grid AS (
  SELECT
    observed_channels.channel,
    models.model,
    COALESCE(all_model_totals.attributed_conversions, 0.0)
      AS attributed_conversions,
    COALESCE(all_model_totals.attributed_revenue, 0.0)
      AS attributed_revenue
  FROM observed_channels
  CROSS JOIN models
  LEFT JOIN all_model_totals
    USING (channel, model)
),
with_model_metrics AS (
  SELECT
    channel,
    model,
    attributed_conversions,
    attributed_revenue,
    SAFE_DIVIDE(
      attributed_conversions,
      SUM(attributed_conversions) OVER (PARTITION BY model)
    ) AS attribution_share,
    DENSE_RANK() OVER (
      PARTITION BY model
      ORDER BY attributed_conversions DESC, channel
    ) AS channel_rank
  FROM complete_grid
),
last_click_baseline AS (
  SELECT
    channel,
    attributed_conversions AS last_click_attributed_conversions,
    attributed_revenue AS last_click_attributed_revenue
  FROM with_model_metrics
  WHERE model = 'Last Click'
)
SELECT
  with_model_metrics.channel,
  with_model_metrics.model,
  with_model_metrics.attributed_conversions,
  with_model_metrics.attributed_revenue,
  with_model_metrics.attribution_share,
  with_model_metrics.channel_rank,
  with_model_metrics.attributed_conversions
    - last_click_baseline.last_click_attributed_conversions
    AS conversion_difference_vs_last_click,
  SAFE_DIVIDE(
    with_model_metrics.attributed_conversions
      - last_click_baseline.last_click_attributed_conversions,
    last_click_baseline.last_click_attributed_conversions
  ) AS conversion_relative_difference_vs_last_click,
  with_model_metrics.attributed_revenue
    - last_click_baseline.last_click_attributed_revenue
    AS revenue_difference_vs_last_click,
  SAFE_DIVIDE(
    with_model_metrics.attributed_revenue
      - last_click_baseline.last_click_attributed_revenue,
    last_click_baseline.last_click_attributed_revenue
  ) AS revenue_relative_difference_vs_last_click,
  last_click_baseline.last_click_attributed_conversions,
  last_click_baseline.last_click_attributed_revenue,
  'phase4_markov_30d_anderl_v2_20260811' AS markov_version
FROM with_model_metrics
INNER JOIN last_click_baseline USING (channel)
