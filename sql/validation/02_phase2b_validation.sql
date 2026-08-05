WITH source_stats AS (
  SELECT
    COUNT(*) AS session_count,
    COUNT(*) - COUNT(DISTINCT session_key) AS duplicate_session_key_count,
    COUNTIF(source_resolution_tier NOT IN ('event_level_source', 'external_referrer', 'first_user_fallback', 'Direct', 'Unknown')) AS invalid_tier_count,
    COUNTIF(resolved_source_reg_domain = 'googlemerchandisestore.com') AS internal_storefront_resolved_count,
    COUNTIF(resolved_source IS NULL AND resolved_medium = 'referral' AND source_quality != 'medium_only') AS invalid_medium_only_quality_count,
    CAST(COUNTIF(resolved_source IS NULL AND resolved_medium = 'referral' AND source_quality = 'medium_only') > 0 AS INT64) AS medium_only_referral_present,
    COUNTIF(source_resolution_tier = 'Unknown' AND (resolved_source IS NOT NULL OR resolved_medium IS NOT NULL)) AS invalid_unknown_evidence_count,
    COUNTIF(source_resolution_tier = 'Direct' AND NOT (LOWER(resolved_source) = '(direct)' OR LOWER(resolved_medium) = '(none)')) AS invalid_direct_evidence_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
),
session_stats AS (
  SELECT
    COUNT(*) AS session_count,
    COUNT(*) - COUNT(DISTINCT session_key) AS duplicate_session_key_count,
    COUNTIF(channel NOT IN ('Internal/Admin', 'Direct', 'Paid Social', 'Paid Search', 'Display', 'Email', 'Affiliates', 'Organic Search', 'Organic Social', 'Referral', 'Unknown', 'Other')) AS invalid_channel_count,
    COUNTIF(is_attribution_eligible AND channel IS NULL) AS eligible_session_missing_channel_count,
    COUNTIF(is_internal_admin_traffic AND channel != 'Internal/Admin') AS admin_session_channel_error_count,
    COUNTIF(NOT is_internal_admin_traffic AND channel = 'Internal/Admin') AS non_admin_internal_channel_count,
    COUNTIF(is_internal_admin_traffic AND is_attribution_eligible) AS admin_attribution_eligible_count,
    COUNTIF(is_internal_admin_traffic AND is_marketing_eligible) AS admin_marketing_eligible_count,
    COUNTIF(resolved_source_host = 'moma.corp.google.com' AND NOT is_internal_admin_traffic) AS moma_not_admin_count,
    COUNTIF(
      is_internal_admin_traffic
      AND resolved_source_host NOT IN ('analytics.google.com', 'moma.corp.google.com')
    ) AS unapproved_admin_host_count,
    COUNTIF(
      resolved_source_host = 'analytics.google.com'
      AND internal_admin_reason != 'approved_admin_host:analytics.google.com'
    ) AS analytics_reason_error_count,
    COUNTIF(
      resolved_source_host = 'moma.corp.google.com'
      AND internal_admin_reason != 'approved_admin_host:moma.corp.google.com'
    ) AS moma_reason_error_count,
    COUNTIF(resolved_source_host = 'creatoracademy.youtube.com' AND channel != 'Referral') AS creator_academy_channel_error_count,
    COUNTIF(is_inferred_source AND inference_rule = 'google_referrer_to_organic_search' AND channel != 'Organic Search') AS google_inference_channel_error_count,
    COUNTIF(mapping_version != 'phase2b_channel_v2_20260806') AS invalid_mapping_version_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
),
channel_assignment_stats AS (
  SELECT COUNTIF(channel_count != 1) AS invalid_channel_assignment_count
  FROM (
    SELECT session_key, COUNT(DISTINCT channel) AS channel_count
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
    GROUP BY session_key
  )
),
order_stats AS (
  SELECT COUNT(*) AS order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
),
coverage_stats AS (
  SELECT
    SUM(session_count) AS covered_session_count,
    MAX(total_session_count) AS expected_session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.channel_source_coverage_audit`
),
reprocessing_stats AS (
  SELECT
    COUNT(*) AS audit_session_count,
    COUNTIF(was_internal_storefront_resolved_referral) AS affected_internal_storefront_session_count,
    COUNTIF(session_key IS NULL) AS missing_session_key_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.source_reprocessing_session_audit`
),
internal_rule_stats AS (
  SELECT
    COUNTIF(rule_type = 'internal_admin' AND decision_status = 'APPROVED')
      AS approved_admin_rule_count,
    COUNTIF(
      rule_type = 'internal_admin'
      AND match_field = 'normalized_host'
      AND match_value = 'moma.corp.google.com'
      AND decision_status = 'APPROVED'
    ) AS approved_moma_rule_count,
    COUNTIF(match_value = 'google.com') AS broad_google_rule_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.internal_domain_rules`
),
strict_touchpoint_stats AS (
  SELECT
    COUNT(*) AS touchpoint_count,
    COUNTIF(touchpoint_ts > order_ts) AS touchpoint_after_order_count,
    COUNTIF(touchpoint_ts < TIMESTAMP_SUB(order_ts, INTERVAL 30 DAY)) AS touchpoint_before_lookback_count,
    COUNTIF(previous_order_ts IS NOT NULL AND touchpoint_ts <= previous_order_ts) AS touchpoint_before_cycle_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(order_key, ':', session_key)) AS duplicate_order_session_pair_count,
    COUNTIF(touchpoint_eligibility_rule != 'STANDARD_CONVERSION_CYCLE') AS invalid_rule_count,
    COUNTIF(is_same_session_multi_order_exception) AS invalid_exception_flag_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints_strict`
),
revised_touchpoint_stats AS (
  SELECT
    COUNT(*) AS touchpoint_count,
    COUNTIF(touchpoint_ts > order_ts) AS touchpoint_after_order_count,
    COUNTIF(touchpoint_ts < TIMESTAMP_SUB(order_ts, INTERVAL 30 DAY)) AS touchpoint_before_lookback_count,
    COUNTIF(
      touchpoint_eligibility_rule = 'STANDARD_CONVERSION_CYCLE'
      AND previous_order_ts IS NOT NULL
      AND touchpoint_ts <= previous_order_ts
    ) AS standard_touchpoint_before_cycle_count,
    COUNTIF(
      touchpoint_eligibility_rule = 'CURRENT_CONVERSION_SESSION_EXCEPTION'
      AND NOT is_same_session_multi_order_exception
    ) AS exception_rule_flag_mismatch_count,
    COUNTIF(
      is_same_session_multi_order_exception
      AND touchpoint_eligibility_rule != 'CURRENT_CONVERSION_SESSION_EXCEPTION'
    ) AS exception_flag_rule_mismatch_count,
    COUNTIF(
      is_same_session_multi_order_exception
      AND session_key != conversion_session_key
    ) AS exception_conversion_session_mismatch_count,
    COUNTIF(
      is_same_session_multi_order_exception
      AND (previous_order_ts IS NULL OR touchpoint_ts > previous_order_ts)
    ) AS unnecessary_exception_count,
    COUNTIF(touchpoint_eligibility_rule NOT IN ('STANDARD_CONVERSION_CYCLE', 'CURRENT_CONVERSION_SESSION_EXCEPTION')) AS invalid_rule_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(order_key, ':', session_key)) AS duplicate_order_session_pair_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
admin_path_stats AS (
  SELECT
    COUNTIF(path_variant = 'STRICT') AS strict_admin_touchpoint_count,
    COUNTIF(path_variant = 'REVISED') AS revised_admin_touchpoint_count
  FROM (
    SELECT 'STRICT' AS path_variant, strict_paths.session_key
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints_strict` AS strict_paths
    INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints` AS sessions
      USING (session_key)
    WHERE sessions.is_internal_admin_traffic

    UNION ALL

    SELECT 'REVISED' AS path_variant, revised_paths.session_key
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints` AS revised_paths
    INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints` AS sessions
      USING (session_key)
    WHERE sessions.is_internal_admin_traffic
  )
),
strict_reuse_stats AS (
  SELECT COUNTIF(order_count > 1) AS reused_session_count
  FROM (
    SELECT session_key, COUNT(DISTINCT order_key) AS order_count
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints_strict`
    GROUP BY session_key
  )
),
revised_reuse_stats AS (
  SELECT
    COALESCE(SUM(unapproved_historical_assignment_count), 0)
      AS unapproved_historical_assignment_count,
    COALESCE(SUM(exception_conversion_session_mismatch_count), 0)
      AS exception_conversion_session_mismatch_count,
    COUNTIF(NOT reuse_is_explicitly_approved_exception) AS invalid_reuse_row_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.same_session_multiple_order_audit`
),
path_stats AS (
  SELECT
    COUNT(*) AS audited_order_count,
    COUNTIF(path_covered_historical_baseline) AS historical_matched_order_count,
    COUNTIF(NOT path_covered_historical_baseline) AS historical_unmatched_order_count,
    SUM(historical_baseline_touchpoint_count) AS historical_touchpoint_count,
    COUNTIF(path_covered_strict) AS strict_matched_order_count,
    COUNTIF(NOT path_covered_strict) AS strict_unmatched_order_count,
    COUNTIF(path_covered_revised) AS revised_matched_order_count,
    COUNTIF(NOT path_covered_revised) AS revised_unmatched_order_count,
    COUNTIF(recovered_by_current_conversion_session_exception) AS recovered_order_count,
    SUM(strict_conversion_touchpoint_count) AS strict_touchpoint_count,
    SUM(conversion_touchpoint_count) AS revised_touchpoint_count,
    COUNTIF(coverage_lost_after_internal_exclusion) AS internal_exclusion_lost_order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
),
unmatched_stats AS (
  SELECT
    COUNT(*) AS unmatched_order_count,
    COUNTIF(exclusion_reason = 'NO_ELIGIBLE_TOUCHPOINT_AFTER_INTERNAL_EXCLUSION')
      AS internal_exclusion_unmatched_order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders_without_touchpoints`
),
closeout_summary_stats AS (
  SELECT
    COUNT(*) AS summary_row_count,
    COALESCE(SUM(unapproved_historical_assignment_count), 0)
      AS unapproved_historical_assignment_count,
    COALESCE(SUM(exception_conversion_session_mismatch_count), 0)
      AS exception_conversion_session_mismatch_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.path_closeout_summary_audit`
),
attribution_output_stats AS (
  SELECT COUNTIF(
    table_name IN (
      'attribution_results',
      'model_comparison',
      'first_click_attribution',
      'last_click_attribution',
      'last_non_direct_attribution',
      'linear_attribution',
      'time_decay_attribution',
      'markov_attribution',
      'shapley_attribution'
    )
  ) AS forbidden_attribution_table_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.INFORMATION_SCHEMA.TABLES`
),
checks AS (
  SELECT 'rebuilt_session_count' AS check_id, source_stats.session_count AS observed_value, 360129 AS expected_value FROM source_stats
  UNION ALL SELECT 'rebuilt_duplicate_session_keys', source_stats.duplicate_session_key_count, 0 FROM source_stats
  UNION ALL SELECT 'invalid_source_tiers', source_stats.invalid_tier_count, 0 FROM source_stats
  UNION ALL SELECT 'internal_storefront_final_sources', source_stats.internal_storefront_resolved_count, 0 FROM source_stats
  UNION ALL SELECT 'invalid_medium_only_quality', source_stats.invalid_medium_only_quality_count, 0 FROM source_stats
  UNION ALL SELECT 'medium_only_referral_present', source_stats.medium_only_referral_present, 1 FROM source_stats
  UNION ALL SELECT 'invalid_unknown_evidence', source_stats.invalid_unknown_evidence_count, 0 FROM source_stats
  UNION ALL SELECT 'invalid_direct_evidence', source_stats.invalid_direct_evidence_count, 0 FROM source_stats
  UNION ALL SELECT 'session_touchpoint_count', session_stats.session_count, 360129 FROM session_stats
  UNION ALL SELECT 'session_touchpoint_duplicate_keys', session_stats.duplicate_session_key_count, 0 FROM session_stats
  UNION ALL SELECT 'invalid_channel_labels', session_stats.invalid_channel_count, 0 FROM session_stats
  UNION ALL SELECT 'eligible_session_missing_channel', session_stats.eligible_session_missing_channel_count, 0 FROM session_stats
  UNION ALL SELECT 'admin_session_channel_errors', session_stats.admin_session_channel_error_count, 0 FROM session_stats
  UNION ALL SELECT 'non_admin_internal_channels', session_stats.non_admin_internal_channel_count, 0 FROM session_stats
  UNION ALL SELECT 'admin_sessions_attribution_eligible', session_stats.admin_attribution_eligible_count, 0 FROM session_stats
  UNION ALL SELECT 'admin_sessions_marketing_eligible', session_stats.admin_marketing_eligible_count, 0 FROM session_stats
  UNION ALL SELECT 'moma_not_internal_admin', session_stats.moma_not_admin_count, 0 FROM session_stats
  UNION ALL SELECT 'unapproved_admin_hosts', session_stats.unapproved_admin_host_count, 0 FROM session_stats
  UNION ALL SELECT 'analytics_admin_reason_errors', session_stats.analytics_reason_error_count, 0 FROM session_stats
  UNION ALL SELECT 'moma_admin_reason_errors', session_stats.moma_reason_error_count, 0 FROM session_stats
  UNION ALL SELECT 'creator_academy_channel_errors', session_stats.creator_academy_channel_error_count, 0 FROM session_stats
  UNION ALL SELECT 'google_inference_channel_errors', session_stats.google_inference_channel_error_count, 0 FROM session_stats
  UNION ALL SELECT 'invalid_mapping_versions', session_stats.invalid_mapping_version_count, 0 FROM session_stats
  UNION ALL SELECT 'invalid_channel_assignments', channel_assignment_stats.invalid_channel_assignment_count, 0 FROM channel_assignment_stats
  UNION ALL SELECT 'eligible_order_count', order_stats.order_count, 4466 FROM order_stats
  UNION ALL SELECT 'source_coverage_reconciliation', ABS(coverage_stats.covered_session_count - coverage_stats.expected_session_count), 0 FROM coverage_stats
  UNION ALL SELECT 'source_coverage_total', coverage_stats.covered_session_count, 360129 FROM coverage_stats
  UNION ALL SELECT 'reprocessing_audit_session_count', reprocessing_stats.audit_session_count, 360129 FROM reprocessing_stats
  UNION ALL SELECT 'reprocessed_internal_storefront_sessions', reprocessing_stats.affected_internal_storefront_session_count, 70820 FROM reprocessing_stats
  UNION ALL SELECT 'reprocessing_missing_session_keys', reprocessing_stats.missing_session_key_count, 0 FROM reprocessing_stats
  UNION ALL SELECT 'approved_admin_rule_count', internal_rule_stats.approved_admin_rule_count, 2 FROM internal_rule_stats
  UNION ALL SELECT 'approved_moma_rule_count', internal_rule_stats.approved_moma_rule_count, 1 FROM internal_rule_stats
  UNION ALL SELECT 'broad_google_admin_rules', internal_rule_stats.broad_google_rule_count, 0 FROM internal_rule_stats
  UNION ALL SELECT 'strict_touchpoints_after_order', strict_touchpoint_stats.touchpoint_after_order_count, 0 FROM strict_touchpoint_stats
  UNION ALL SELECT 'strict_touchpoints_before_lookback', strict_touchpoint_stats.touchpoint_before_lookback_count, 0 FROM strict_touchpoint_stats
  UNION ALL SELECT 'strict_touchpoints_before_cycle', strict_touchpoint_stats.touchpoint_before_cycle_count, 0 FROM strict_touchpoint_stats
  UNION ALL SELECT 'strict_duplicate_order_session_pairs', strict_touchpoint_stats.duplicate_order_session_pair_count, 0 FROM strict_touchpoint_stats
  UNION ALL SELECT 'strict_invalid_eligibility_rules', strict_touchpoint_stats.invalid_rule_count, 0 FROM strict_touchpoint_stats
  UNION ALL SELECT 'strict_invalid_exception_flags', strict_touchpoint_stats.invalid_exception_flag_count, 0 FROM strict_touchpoint_stats
  UNION ALL SELECT 'revised_touchpoints_after_order', revised_touchpoint_stats.touchpoint_after_order_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_touchpoints_before_lookback', revised_touchpoint_stats.touchpoint_before_lookback_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_standard_touchpoints_before_cycle', revised_touchpoint_stats.standard_touchpoint_before_cycle_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_exception_rule_flag_mismatch', revised_touchpoint_stats.exception_rule_flag_mismatch_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_exception_flag_rule_mismatch', revised_touchpoint_stats.exception_flag_rule_mismatch_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_exception_conversion_session_mismatch', revised_touchpoint_stats.exception_conversion_session_mismatch_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_unnecessary_exceptions', revised_touchpoint_stats.unnecessary_exception_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_invalid_eligibility_rules', revised_touchpoint_stats.invalid_rule_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'revised_duplicate_order_session_pairs', revised_touchpoint_stats.duplicate_order_session_pair_count, 0 FROM revised_touchpoint_stats
  UNION ALL SELECT 'strict_admin_touchpoints', admin_path_stats.strict_admin_touchpoint_count, 0 FROM admin_path_stats
  UNION ALL SELECT 'revised_admin_touchpoints', admin_path_stats.revised_admin_touchpoint_count, 0 FROM admin_path_stats
  UNION ALL SELECT 'strict_sessions_reused_across_cycles', strict_reuse_stats.reused_session_count, 0 FROM strict_reuse_stats
  UNION ALL SELECT 'unapproved_historical_session_reuse', revised_reuse_stats.unapproved_historical_assignment_count, 0 FROM revised_reuse_stats
  UNION ALL SELECT 'reuse_exception_conversion_session_mismatch', revised_reuse_stats.exception_conversion_session_mismatch_count, 0 FROM revised_reuse_stats
  UNION ALL SELECT 'invalid_reuse_audit_rows', revised_reuse_stats.invalid_reuse_row_count, 0 FROM revised_reuse_stats
  UNION ALL SELECT 'audited_order_count', path_stats.audited_order_count, 4466 FROM path_stats
  UNION ALL SELECT 'historical_baseline_matched_orders', path_stats.historical_matched_order_count, 4043 FROM path_stats
  UNION ALL SELECT 'historical_baseline_unmatched_orders', path_stats.historical_unmatched_order_count, 423 FROM path_stats
  UNION ALL SELECT 'historical_baseline_touchpoints', path_stats.historical_touchpoint_count, 9172 FROM path_stats
  UNION ALL SELECT 'strict_order_reconciliation', path_stats.strict_matched_order_count + path_stats.strict_unmatched_order_count, 4466 FROM path_stats
  UNION ALL SELECT 'revised_order_reconciliation', path_stats.revised_matched_order_count + path_stats.revised_unmatched_order_count, 4466 FROM path_stats
  UNION ALL SELECT 'revised_coverage_not_below_strict', CAST(path_stats.revised_matched_order_count < path_stats.strict_matched_order_count AS INT64), 0 FROM path_stats
  UNION ALL SELECT 'recovered_order_reconciliation', ABS(path_stats.revised_matched_order_count - path_stats.strict_matched_order_count - path_stats.recovered_order_count), 0 FROM path_stats
  UNION ALL SELECT 'strict_touchpoint_reconciliation', ABS(path_stats.strict_touchpoint_count - strict_touchpoint_stats.touchpoint_count), 0 FROM path_stats CROSS JOIN strict_touchpoint_stats
  UNION ALL SELECT 'revised_touchpoint_reconciliation', ABS(path_stats.revised_touchpoint_count - revised_touchpoint_stats.touchpoint_count), 0 FROM path_stats CROSS JOIN revised_touchpoint_stats
  UNION ALL SELECT 'unmatched_order_reconciliation', ABS(path_stats.revised_unmatched_order_count - unmatched_stats.unmatched_order_count), 0 FROM path_stats CROSS JOIN unmatched_stats
  UNION ALL SELECT 'internal_exclusion_reason_reconciliation', ABS(path_stats.internal_exclusion_lost_order_count - unmatched_stats.internal_exclusion_unmatched_order_count), 0 FROM path_stats CROSS JOIN unmatched_stats
  UNION ALL SELECT 'closeout_summary_row_count', closeout_summary_stats.summary_row_count, 1 FROM closeout_summary_stats
  UNION ALL SELECT 'closeout_summary_unapproved_reuse', closeout_summary_stats.unapproved_historical_assignment_count, 0 FROM closeout_summary_stats
  UNION ALL SELECT 'closeout_summary_exception_mismatch', closeout_summary_stats.exception_conversion_session_mismatch_count, 0 FROM closeout_summary_stats
  UNION ALL SELECT 'forbidden_attribution_output_tables', attribution_output_stats.forbidden_attribution_table_count, 0 FROM attribution_output_stats
)
SELECT
  check_id,
  observed_value,
  expected_value,
  IF(observed_value = expected_value, 'PASS', 'FAIL') AS validation_status
FROM checks
