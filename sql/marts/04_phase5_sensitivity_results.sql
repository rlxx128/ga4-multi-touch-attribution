-- Canonical read-only Phase 5 result projection used for report generation.
SELECT
  scenario_id,
  scenario_version,
  cohort_view,
  model,
  channel,
  attributable_order_count,
  attributable_revenue,
  conversion_journey_count,
  null_journey_count,
  right_censored_journey_count,
  average_path_length,
  median_path_length,
  multi_touch_share,
  channel_touchpoint_count,
  channel_touchpoint_share,
  removal_effect,
  attributed_conversions,
  attributed_revenue,
  conversion_share,
  revenue_share,
  conversion_rank,
  revenue_rank,
  baseline_conversion_probability,
  sensitivity_version
FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase5_sensitivity_results`
ORDER BY scenario_id, cohort_view, model, conversion_rank, channel
