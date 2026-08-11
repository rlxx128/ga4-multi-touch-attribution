-- Phase 4 closes only when journey, transition, removal, attribution, and
-- regression checks all pass. Observed values are failures unless stated.
WITH journey_stats AS (
  SELECT
    COUNT(*) AS total_journey_rows,
    COUNT(*) - COUNT(DISTINCT journey_id) AS duplicate_journey_ids,
    COUNTIF(journey_status = 'Conversion') AS conversion_journeys,
    COUNT(DISTINCT IF(journey_status = 'Conversion', user_pseudo_id, NULL))
      AS conversion_users,
    SUM(IF(journey_status = 'Conversion', session_count, 0))
      AS conversion_touchpoints,
    SUM(IF(journey_status = 'Conversion', attributable_revenue_usd, 0))
      AS conversion_revenue,
    COUNTIF(journey_status = 'Null') AS null_journeys,
    COUNT(DISTINCT IF(journey_status = 'Null', user_pseudo_id, NULL))
      AS null_users,
    SUM(IF(journey_status = 'Null', session_count, 0)) AS null_sessions,
    COUNTIF(journey_status = 'Right Censored') AS right_censored_journeys,
    COUNT(DISTINCT IF(journey_status = 'Right Censored', user_pseudo_id, NULL))
      AS right_censored_users,
    SUM(IF(journey_status = 'Right Censored', session_count, 0))
      AS right_censored_sessions,
    COUNTIF(journey_status = 'Null' AND is_left_boundary_truncated)
      AS left_boundary_null_journeys,
    COUNTIF(
      journey_status = 'Null'
      AND (SELECT COUNTIF(channel != 'Direct') FROM UNNEST(channel_path) AS channel) = 0
    ) AS direct_only_null_journeys,
    COUNTIF(
      journey_status = 'Null'
      AND 'Unknown' IN UNNEST(channel_path)
    ) AS unknown_containing_null_journeys,
    COUNTIF(
      journey_status = 'Null'
      AND 'Other' IN UNNEST(channel_path)
    ) AS other_containing_null_journeys,
    COUNTIF(ARRAY_LENGTH(channel_path) != session_count)
      AS invalid_channel_path_lengths,
    COUNTIF(ARRAY_LENGTH(session_key_path) != session_count)
      AS invalid_session_path_lengths,
    COUNTIF(session_count <= 0) AS invalid_session_counts,
    COUNTIF(
      EXISTS (
        SELECT 1
        FROM UNNEST(channel_path) AS channel
        WHERE channel IN ('Start', 'Conversion', 'Null', 'Internal/Admin')
      )
    ) AS invalid_channel_states,
    COUNTIF(
      (journey_status = 'Conversion'
        AND (NOT is_markov_included OR outcome_state != 'Conversion'))
      OR (journey_status = 'Null'
        AND (NOT is_markov_included OR outcome_state != 'Null'))
      OR (journey_status = 'Right Censored'
        AND (is_markov_included OR outcome_state IS NOT NULL))
    ) AS invalid_status_metadata,
    COUNTIF(
      journey_status = 'Null'
      AND inactivity_expiry_ts >= dataset_end_boundary
    ) AS invalid_completed_null_boundaries,
    COUNTIF(
      journey_status = 'Right Censored'
      AND inactivity_expiry_ts < dataset_end_boundary
    ) AS invalid_censored_boundaries,
    COUNTIF(
      journey_status = 'Null'
      AND next_purchase_ts IS NOT NULL
      AND next_purchase_ts <= inactivity_expiry_ts
    ) AS null_purchase_boundary_failures,
    COUNTIF(inactivity_cutoff_days != 30) AS invalid_inactivity_cutoffs,
    COUNTIF(mapping_version != 'phase2b_channel_v2_20260806')
      AS invalid_mapping_versions,
    COUNTIF(journey_definition_version != 'phase4_markov_30d_v1_20260811')
      AS invalid_journey_versions
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_journeys`
),
conversion_sessions AS (
  SELECT DISTINCT session_key
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_journeys`
  CROSS JOIN UNNEST(session_key_path) AS session_key
  WHERE journey_status = 'Conversion'
),
null_sessions AS (
  SELECT DISTINCT session_key
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_journeys`
  CROSS JOIN UNNEST(session_key_path) AS session_key
  WHERE journey_status = 'Null'
),
overlap_stats AS (
  SELECT COUNT(*) AS overlapping_session_count
  FROM conversion_sessions
  INNER JOIN null_sessions USING (session_key)
),
transition_state_stats AS (
  SELECT
    COUNT(DISTINCT from_state) AS state_count,
    COUNT(*) AS matrix_cell_count,
    COUNTIF(from_state = 'Internal/Admin' OR to_state = 'Internal/Admin')
      AS internal_admin_matrix_cells,
    COUNTIF(
      transition_count < 0
      OR transition_probability < 0
      OR transition_probability > 1
      OR IS_NAN(transition_probability)
      OR IS_INF(transition_probability)
    ) AS invalid_transition_cells,
    COUNTIF(NOT can_reach_absorbing) AS states_without_absorption_path,
    COUNTIF(markov_version != 'phase4_markov_30d_anderl_v2_20260811')
      AS invalid_transition_versions,
    SUM(transition_count) AS observed_transition_count,
    COUNT(DISTINCT baseline_conversion_probability)
      AS distinct_baseline_probability_count,
    ANY_VALUE(baseline_conversion_probability) AS baseline_conversion_probability
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_transition_matrix`
),
transition_row_stats AS (
  SELECT
    COUNTIF(ABS(row_probability - 1.0) > 1e-12) AS invalid_row_sums,
    COUNTIF(
      from_state NOT IN ('Conversion', 'Null')
      AND row_probability <= 0
    ) AS transient_zero_outgoing_rows
  FROM (
    SELECT from_state, SUM(transition_probability) AS row_probability
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_transition_matrix`
    GROUP BY from_state
  )
),
absorbing_state_stats AS (
  SELECT COUNTIF(
    (from_state = 'Conversion'
      AND ((to_state = 'Conversion' AND transition_probability != 1.0)
        OR (to_state != 'Conversion' AND transition_probability != 0.0)))
    OR (from_state = 'Null'
      AND ((to_state = 'Null' AND transition_probability != 1.0)
        OR (to_state != 'Null' AND transition_probability != 0.0)))
  ) AS absorbing_probability_failures
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_transition_matrix`
  WHERE from_state IN ('Conversion', 'Null')
),
removal_stats AS (
  SELECT
    COUNT(*) AS channel_count,
    COUNT(*) - COUNT(DISTINCT channel) AS duplicate_channels,
    COUNTIF(channel IN ('Start', 'Conversion', 'Null', 'Internal/Admin'))
      AS invalid_removal_channels,
    COUNTIF(materially_negative) AS materially_negative_effects,
    COUNTIF(
      IS_NAN(removal_effect)
      OR IS_INF(removal_effect)
      OR IS_NAN(conversion_probability_without_channel)
      OR IS_INF(conversion_probability_without_channel)
    ) AS nonfinite_removal_values,
    COUNT(DISTINCT baseline_conversion_probability)
      AS distinct_removal_baseline_count,
    COUNTIF(markov_version != 'phase4_markov_30d_anderl_v2_20260811')
      AS invalid_removal_versions
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_removal_effects`
),
attribution_stats AS (
  SELECT
    COUNT(*) AS channel_count,
    COUNT(*) - COUNT(DISTINCT channel) AS duplicate_channels,
    COUNTIF(channel IN ('Start', 'Conversion', 'Null', 'Internal/Admin'))
      AS invalid_channels,
    COUNTIF(
      markov_share < 0
      OR IS_NAN(markov_share)
      OR IS_INF(markov_share)
      OR ABS(markov_share - conversion_share) > 1e-12
      OR ABS(markov_share - revenue_share) > 1e-12
    ) AS invalid_share_rows,
    ABS(SUM(markov_share) - 1.0) AS share_delta,
    ABS(SUM(attributed_conversions) - 4457.0) AS conversion_delta,
    ABS(SUM(attributed_revenue) - 308208.0) AS revenue_delta,
    COUNTIF(markov_version != 'phase4_markov_30d_anderl_v2_20260811')
      AS invalid_attribution_versions
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_attribution`
),
comparison_stats AS (
  SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT model) AS model_count,
    COUNT(DISTINCT channel) AS channel_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(channel, ':', model)) AS duplicate_rows,
    COUNTIF(model NOT IN (
      'First Click', 'Last Click', 'Last Non-direct Click', 'Linear',
      'Time Decay', 'Markov'
    )) AS invalid_models,
    COUNTIF(channel = 'Internal/Admin') AS internal_admin_rows,
    COUNTIF(markov_version != 'phase4_markov_30d_anderl_v2_20260811')
      AS invalid_comparison_versions
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.rule_markov_comparison`
),
phase3_regression_stats AS (
  SELECT
    (SELECT COUNT(*)
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase2b_validation_summary`)
      AS phase2b_check_count,
    (SELECT COUNTIF(validation_status != 'PASS')
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase2b_validation_summary`)
      AS phase2b_failure_count,
    (SELECT COUNT(*)
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase3_validation_summary`)
      AS phase3_check_count,
    (SELECT COUNTIF(validation_status != 'PASS')
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.phase3_validation_summary`)
      AS phase3_failure_count,
    (SELECT COUNT(*)
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`)
      AS phase3_result_rows,
    (SELECT COUNTIF(attribution_version != 'phase3_rule_attribution_v1_20260809')
     FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`)
      AS invalid_phase3_versions
),
phase3_model_stats AS (
  SELECT
    COUNT(*) AS model_count,
    COUNTIF(
      order_count != 4457
      OR ABS(attributed_conversions - 4457.0) > 1e-9
      OR ABS(attributed_revenue - 308208.0) > 1e-6
    ) AS reconciliation_failures
  FROM (
    SELECT
      model,
      COUNT(DISTINCT order_key) AS order_count,
      SUM(attributed_conversion) AS attributed_conversions,
      SUM(attributed_revenue) AS attributed_revenue
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.attribution_results`
    GROUP BY model
  )
),
checks AS (
  SELECT 'journey_total_rows' AS check_id, total_journey_rows AS observed_value,
    273683 AS expected_value FROM journey_stats
  UNION ALL SELECT 'duplicate_journey_ids', duplicate_journey_ids, 0 FROM journey_stats
  UNION ALL SELECT 'conversion_journeys', conversion_journeys, 4457 FROM journey_stats
  UNION ALL SELECT 'conversion_users', conversion_users, 3705 FROM journey_stats
  UNION ALL SELECT 'conversion_touchpoints', conversion_touchpoints, 9577 FROM journey_stats
  UNION ALL SELECT 'conversion_revenue_cents',
    CAST(ROUND(conversion_revenue * 100) AS INT64), 30820800 FROM journey_stats
  UNION ALL SELECT 'null_journeys', null_journeys, 177632 FROM journey_stats
  UNION ALL SELECT 'null_users', null_users, 177156 FROM journey_stats
  UNION ALL SELECT 'null_sessions', null_sessions, 229522 FROM journey_stats
  UNION ALL SELECT 'right_censored_journeys', right_censored_journeys, 91594 FROM journey_stats
  UNION ALL SELECT 'right_censored_users', right_censored_users, 91594 FROM journey_stats
  UNION ALL SELECT 'right_censored_sessions', right_censored_sessions, 117470 FROM journey_stats
  UNION ALL SELECT 'left_boundary_null_journeys', left_boundary_null_journeys, 77918 FROM journey_stats
  UNION ALL SELECT 'direct_only_null_journeys', direct_only_null_journeys, 32991 FROM journey_stats
  UNION ALL SELECT 'unknown_containing_null_journeys', unknown_containing_null_journeys, 49693 FROM journey_stats
  UNION ALL SELECT 'other_containing_null_journeys', other_containing_null_journeys, 3 FROM journey_stats
  UNION ALL SELECT 'invalid_channel_path_lengths', invalid_channel_path_lengths, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_session_path_lengths', invalid_session_path_lengths, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_session_counts', invalid_session_counts, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_channel_states', invalid_channel_states, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_status_metadata', invalid_status_metadata, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_completed_null_boundaries', invalid_completed_null_boundaries, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_censored_boundaries', invalid_censored_boundaries, 0 FROM journey_stats
  UNION ALL SELECT 'null_purchase_boundary_failures', null_purchase_boundary_failures, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_inactivity_cutoffs', invalid_inactivity_cutoffs, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_mapping_versions', invalid_mapping_versions, 0 FROM journey_stats
  UNION ALL SELECT 'invalid_journey_versions', invalid_journey_versions, 0 FROM journey_stats
  UNION ALL SELECT 'conversion_null_overlap_sessions', overlapping_session_count, 0 FROM overlap_stats
  UNION ALL SELECT 'transition_state_count', state_count, 12 FROM transition_state_stats
  UNION ALL SELECT 'transition_matrix_cells', matrix_cell_count, 144 FROM transition_state_stats
  UNION ALL SELECT 'observed_transition_count', observed_transition_count, 421188 FROM transition_state_stats
  UNION ALL SELECT 'internal_admin_matrix_cells', internal_admin_matrix_cells, 0 FROM transition_state_stats
  UNION ALL SELECT 'invalid_transition_cells', invalid_transition_cells, 0 FROM transition_state_stats
  UNION ALL SELECT 'states_without_absorption_path', states_without_absorption_path, 0 FROM transition_state_stats
  UNION ALL SELECT 'invalid_transition_versions', invalid_transition_versions, 0 FROM transition_state_stats
  UNION ALL SELECT 'transition_baseline_count', distinct_baseline_probability_count, 1 FROM transition_state_stats
  UNION ALL SELECT 'baseline_probability_scaled',
    CAST(ROUND(baseline_conversion_probability * 1e12) AS INT64),
    CAST(ROUND(SAFE_DIVIDE(4457.0, 4457.0 + 177632.0) * 1e12) AS INT64)
    FROM transition_state_stats
  UNION ALL SELECT 'invalid_transition_row_sums', invalid_row_sums, 0 FROM transition_row_stats
  UNION ALL SELECT 'transient_zero_outgoing_rows', transient_zero_outgoing_rows, 0 FROM transition_row_stats
  UNION ALL SELECT 'absorbing_probability_failures', absorbing_probability_failures, 0 FROM absorbing_state_stats
  UNION ALL SELECT 'removal_channel_count', channel_count, 9 FROM removal_stats
  UNION ALL SELECT 'duplicate_removal_channels', duplicate_channels, 0 FROM removal_stats
  UNION ALL SELECT 'invalid_removal_channels', invalid_removal_channels, 0 FROM removal_stats
  UNION ALL SELECT 'materially_negative_removal_effects', materially_negative_effects, 0 FROM removal_stats
  UNION ALL SELECT 'nonfinite_removal_values', nonfinite_removal_values, 0 FROM removal_stats
  UNION ALL SELECT 'removal_baseline_count', distinct_removal_baseline_count, 1 FROM removal_stats
  UNION ALL SELECT 'invalid_removal_versions', invalid_removal_versions, 0 FROM removal_stats
  UNION ALL SELECT 'attribution_channel_count', channel_count, 9 FROM attribution_stats
  UNION ALL SELECT 'duplicate_attribution_channels', duplicate_channels, 0 FROM attribution_stats
  UNION ALL SELECT 'invalid_attribution_channels', invalid_channels, 0 FROM attribution_stats
  UNION ALL SELECT 'invalid_attribution_share_rows', invalid_share_rows, 0 FROM attribution_stats
  UNION ALL SELECT 'attribution_share_failures', CAST(share_delta > 1e-12 AS INT64), 0 FROM attribution_stats
  UNION ALL SELECT 'attribution_conversion_failures', CAST(conversion_delta > 1e-9 AS INT64), 0 FROM attribution_stats
  UNION ALL SELECT 'attribution_revenue_failures', CAST(revenue_delta > 1e-6 AS INT64), 0 FROM attribution_stats
  UNION ALL SELECT 'invalid_attribution_versions', invalid_attribution_versions, 0 FROM attribution_stats
  UNION ALL SELECT 'comparison_row_count', row_count, 54 FROM comparison_stats
  UNION ALL SELECT 'comparison_model_count', model_count, 6 FROM comparison_stats
  UNION ALL SELECT 'comparison_channel_count', channel_count, 9 FROM comparison_stats
  UNION ALL SELECT 'comparison_duplicate_rows', duplicate_rows, 0 FROM comparison_stats
  UNION ALL SELECT 'comparison_invalid_models', invalid_models, 0 FROM comparison_stats
  UNION ALL SELECT 'comparison_internal_admin_rows', internal_admin_rows, 0 FROM comparison_stats
  UNION ALL SELECT 'invalid_comparison_versions', invalid_comparison_versions, 0 FROM comparison_stats
  UNION ALL SELECT 'phase2b_check_count', phase2b_check_count, 70 FROM phase3_regression_stats
  UNION ALL SELECT 'phase2b_failures', phase2b_failure_count, 0 FROM phase3_regression_stats
  UNION ALL SELECT 'phase3_check_count', phase3_check_count, 46 FROM phase3_regression_stats
  UNION ALL SELECT 'phase3_failures', phase3_failure_count, 0 FROM phase3_regression_stats
  UNION ALL SELECT 'phase3_result_rows', phase3_result_rows, 27409 FROM phase3_regression_stats
  UNION ALL SELECT 'invalid_phase3_versions', invalid_phase3_versions, 0 FROM phase3_regression_stats
  UNION ALL SELECT 'phase3_model_count', model_count, 5 FROM phase3_model_stats
  UNION ALL SELECT 'phase3_model_reconciliation_failures', reconciliation_failures, 0 FROM phase3_model_stats
)
SELECT
  check_id,
  observed_value,
  expected_value,
  IF(observed_value = expected_value, 'PASS', 'FAIL') AS validation_status
FROM checks
