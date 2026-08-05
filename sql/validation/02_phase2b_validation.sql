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
    COUNTIF(
      channel IS NOT NULL
      AND channel NOT IN ('Direct', 'Paid Social', 'Paid Search', 'Display', 'Email', 'Affiliates', 'Organic Search', 'Organic Social', 'Referral', 'Unknown', 'Other')
    ) AS invalid_channel_count,
    COUNTIF(is_marketing_eligible AND channel IS NULL) AS marketing_session_missing_channel_count,
    COUNTIF(is_internal_admin_traffic AND channel IS NOT NULL) AS admin_session_with_channel_count,
    COUNTIF(is_internal_admin_traffic AND is_marketing_eligible) AS admin_session_marketing_eligible_count,
    COUNTIF(resolved_source_host = 'creatoracademy.youtube.com' AND channel != 'Referral') AS creator_academy_channel_error_count,
    COUNTIF(is_inferred_source AND inference_rule = 'google_referrer_to_organic_search' AND channel != 'Organic Search') AS google_inference_channel_error_count,
    COUNTIF(mapping_version != 'phase2b_channel_v1_20260806') AS invalid_mapping_version_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
),
channel_assignment_stats AS (
  SELECT COUNTIF(channel_count > 1) AS multiple_channel_session_count
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
touchpoint_stats AS (
  SELECT
    COUNTIF(touchpoint_ts > order_ts) AS touchpoint_after_order_count,
    COUNTIF(touchpoint_ts < TIMESTAMP_SUB(order_ts, INTERVAL 30 DAY)) AS touchpoint_before_lookback_count,
    COUNTIF(previous_order_ts IS NOT NULL AND touchpoint_ts <= previous_order_ts) AS touchpoint_before_cycle_count,
    COUNT(*) - COUNT(DISTINCT CONCAT(order_key, ':', session_key)) AS duplicate_order_session_pair_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
session_reuse_stats AS (
  SELECT COUNTIF(order_count > 1) AS reused_session_count
  FROM (
    SELECT session_key, COUNT(DISTINCT order_key) AS order_count
    FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
    GROUP BY session_key
  )
),
path_stats AS (
  SELECT
    COUNT(*) AS audited_order_count,
    COUNTIF(conversion_touchpoint_count > 0) AS matched_order_count,
    COUNTIF(conversion_touchpoint_count = 0) AS unmatched_order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
),
unmatched_stats AS (
  SELECT COUNT(*) AS unmatched_order_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders_without_touchpoints`
),
admin_path_stats AS (
  SELECT COUNT(*) AS admin_touchpoint_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints` AS paths
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints` AS sessions
    USING (session_key)
  WHERE sessions.is_internal_admin_traffic
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
  UNION ALL SELECT 'marketing_sessions_missing_channel', session_stats.marketing_session_missing_channel_count, 0 FROM session_stats
  UNION ALL SELECT 'admin_sessions_with_channel', session_stats.admin_session_with_channel_count, 0 FROM session_stats
  UNION ALL SELECT 'admin_sessions_marketing_eligible', session_stats.admin_session_marketing_eligible_count, 0 FROM session_stats
  UNION ALL SELECT 'creator_academy_channel_errors', session_stats.creator_academy_channel_error_count, 0 FROM session_stats
  UNION ALL SELECT 'google_inference_channel_errors', session_stats.google_inference_channel_error_count, 0 FROM session_stats
  UNION ALL SELECT 'invalid_mapping_versions', session_stats.invalid_mapping_version_count, 0 FROM session_stats
  UNION ALL SELECT 'sessions_with_multiple_channels', channel_assignment_stats.multiple_channel_session_count, 0 FROM channel_assignment_stats
  UNION ALL SELECT 'eligible_order_count', order_stats.order_count, 4466 FROM order_stats
  UNION ALL SELECT 'source_coverage_reconciliation', ABS(coverage_stats.covered_session_count - coverage_stats.expected_session_count), 0 FROM coverage_stats
  UNION ALL SELECT 'source_coverage_total', coverage_stats.covered_session_count, 360129 FROM coverage_stats
  UNION ALL SELECT 'reprocessing_audit_session_count', reprocessing_stats.audit_session_count, 360129 FROM reprocessing_stats
  UNION ALL SELECT 'reprocessed_internal_storefront_sessions', reprocessing_stats.affected_internal_storefront_session_count, 70820 FROM reprocessing_stats
  UNION ALL SELECT 'reprocessing_missing_session_keys', reprocessing_stats.missing_session_key_count, 0 FROM reprocessing_stats
  UNION ALL SELECT 'touchpoints_after_order', touchpoint_stats.touchpoint_after_order_count, 0 FROM touchpoint_stats
  UNION ALL SELECT 'touchpoints_before_lookback', touchpoint_stats.touchpoint_before_lookback_count, 0 FROM touchpoint_stats
  UNION ALL SELECT 'touchpoints_before_cycle', touchpoint_stats.touchpoint_before_cycle_count, 0 FROM touchpoint_stats
  UNION ALL SELECT 'duplicate_order_session_pairs', touchpoint_stats.duplicate_order_session_pair_count, 0 FROM touchpoint_stats
  UNION ALL SELECT 'sessions_reused_across_order_cycles', session_reuse_stats.reused_session_count, 0 FROM session_reuse_stats
  UNION ALL SELECT 'audited_order_count', path_stats.audited_order_count, 4466 FROM path_stats
  UNION ALL SELECT 'matched_plus_unmatched_orders', path_stats.matched_order_count + path_stats.unmatched_order_count, 4466 FROM path_stats
  UNION ALL SELECT 'unmatched_order_reconciliation', ABS(path_stats.unmatched_order_count - unmatched_stats.unmatched_order_count), 0 FROM path_stats CROSS JOIN unmatched_stats
  UNION ALL SELECT 'admin_sessions_in_conversion_paths', admin_path_stats.admin_touchpoint_count, 0 FROM admin_path_stats
  UNION ALL SELECT 'forbidden_attribution_output_tables', attribution_output_stats.forbidden_attribution_table_count, 0 FROM attribution_output_stats
)
SELECT
  check_id,
  observed_value,
  expected_value,
  IF(observed_value = expected_value, 'PASS', 'FAIL') AS validation_status
FROM checks
