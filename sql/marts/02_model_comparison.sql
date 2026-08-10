-- One row per observed attribution channel, comparing all five approved models.
WITH channel_model_totals AS (
  SELECT
    channel,
    model,
    SUM(attributed_conversion) AS attributed_conversions,
    SUM(attributed_revenue) AS attributed_revenue_usd
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
  GROUP BY channel, model
),
channel_metrics AS (
  SELECT
    channel,
    SUM(IF(model = 'First Click', attributed_conversions, 0))
      AS first_click_attributed_conversions,
    SUM(IF(model = 'First Click', attributed_revenue_usd, 0))
      AS first_click_attributed_revenue_usd,
    SUM(IF(model = 'Last Click', attributed_conversions, 0))
      AS last_click_attributed_conversions,
    SUM(IF(model = 'Last Click', attributed_revenue_usd, 0))
      AS last_click_attributed_revenue_usd,
    SUM(IF(model = 'Last Non-direct Click', attributed_conversions, 0))
      AS last_non_direct_attributed_conversions,
    SUM(IF(model = 'Last Non-direct Click', attributed_revenue_usd, 0))
      AS last_non_direct_attributed_revenue_usd,
    SUM(IF(model = 'Linear', attributed_conversions, 0))
      AS linear_attributed_conversions,
    SUM(IF(model = 'Linear', attributed_revenue_usd, 0))
      AS linear_attributed_revenue_usd,
    SUM(IF(model = 'Time Decay', attributed_conversions, 0))
      AS time_decay_attributed_conversions,
    SUM(IF(model = 'Time Decay', attributed_revenue_usd, 0))
      AS time_decay_attributed_revenue_usd
  FROM channel_model_totals
  GROUP BY channel
),
model_totals AS (
  SELECT
    SUM(first_click_attributed_conversions) AS first_click_conversion_total,
    SUM(first_click_attributed_revenue_usd) AS first_click_revenue_total,
    SUM(last_click_attributed_conversions) AS last_click_conversion_total,
    SUM(last_click_attributed_revenue_usd) AS last_click_revenue_total,
    SUM(last_non_direct_attributed_conversions) AS last_non_direct_conversion_total,
    SUM(last_non_direct_attributed_revenue_usd) AS last_non_direct_revenue_total,
    SUM(linear_attributed_conversions) AS linear_conversion_total,
    SUM(linear_attributed_revenue_usd) AS linear_revenue_total,
    SUM(time_decay_attributed_conversions) AS time_decay_conversion_total,
    SUM(time_decay_attributed_revenue_usd) AS time_decay_revenue_total
  FROM channel_metrics
)
SELECT
  channel_metrics.channel,
  channel_metrics.first_click_attributed_conversions,
  channel_metrics.first_click_attributed_revenue_usd,
  SAFE_DIVIDE(
    channel_metrics.first_click_attributed_conversions,
    model_totals.first_click_conversion_total
  ) AS first_click_conversion_share,
  SAFE_DIVIDE(
    channel_metrics.first_click_attributed_revenue_usd,
    model_totals.first_click_revenue_total
  ) AS first_click_revenue_share,
  channel_metrics.last_click_attributed_conversions,
  channel_metrics.last_click_attributed_revenue_usd,
  SAFE_DIVIDE(
    channel_metrics.last_click_attributed_conversions,
    model_totals.last_click_conversion_total
  ) AS last_click_conversion_share,
  SAFE_DIVIDE(
    channel_metrics.last_click_attributed_revenue_usd,
    model_totals.last_click_revenue_total
  ) AS last_click_revenue_share,
  channel_metrics.last_non_direct_attributed_conversions,
  channel_metrics.last_non_direct_attributed_revenue_usd,
  SAFE_DIVIDE(
    channel_metrics.last_non_direct_attributed_conversions,
    model_totals.last_non_direct_conversion_total
  ) AS last_non_direct_conversion_share,
  SAFE_DIVIDE(
    channel_metrics.last_non_direct_attributed_revenue_usd,
    model_totals.last_non_direct_revenue_total
  ) AS last_non_direct_revenue_share,
  channel_metrics.linear_attributed_conversions,
  channel_metrics.linear_attributed_revenue_usd,
  SAFE_DIVIDE(
    channel_metrics.linear_attributed_conversions,
    model_totals.linear_conversion_total
  ) AS linear_conversion_share,
  SAFE_DIVIDE(
    channel_metrics.linear_attributed_revenue_usd,
    model_totals.linear_revenue_total
  ) AS linear_revenue_share,
  channel_metrics.time_decay_attributed_conversions,
  channel_metrics.time_decay_attributed_revenue_usd,
  SAFE_DIVIDE(
    channel_metrics.time_decay_attributed_conversions,
    model_totals.time_decay_conversion_total
  ) AS time_decay_conversion_share,
  SAFE_DIVIDE(
    channel_metrics.time_decay_attributed_revenue_usd,
    model_totals.time_decay_revenue_total
  ) AS time_decay_revenue_share,
  channel_metrics.last_click_attributed_revenue_usd
    - channel_metrics.first_click_attributed_revenue_usd
    AS last_click_vs_first_click_revenue_delta,
  channel_metrics.last_click_attributed_revenue_usd
    - channel_metrics.linear_attributed_revenue_usd
    AS last_click_vs_linear_revenue_delta,
  channel_metrics.last_click_attributed_revenue_usd
    - channel_metrics.time_decay_attributed_revenue_usd
    AS last_click_vs_time_decay_revenue_delta,
  'phase3_rule_attribution_v1_20260809' AS attribution_version
FROM channel_metrics
CROSS JOIN model_totals
