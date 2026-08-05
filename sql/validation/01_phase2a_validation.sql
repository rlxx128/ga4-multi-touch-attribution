-- Phase 2A must contain no failing rows before the approval gate is reported.
WITH checks AS (
  SELECT 'event_base_row_count' AS check_id, COUNT(*) AS observed_value, 4295584 AS expected_value
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  UNION ALL
  SELECT 'event_base_distinct_dates', COUNT(DISTINCT event_date), 92
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  UNION ALL
  SELECT 'event_base_min_date', COUNTIF(event_date = DATE '2020-11-01'), 1
  FROM (SELECT MIN(event_date) AS event_date FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`)
  UNION ALL
  SELECT 'event_base_max_date', COUNTIF(event_date = DATE '2021-01-31'), 1
  FROM (SELECT MAX(event_date) AS event_date FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`)
  UNION ALL
  SELECT 'event_base_missing_user_id', COUNTIF(user_pseudo_id IS NULL), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  UNION ALL
  SELECT 'event_base_missing_session_key', COUNTIF(session_key IS NULL), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  UNION ALL
  SELECT 'eligible_deduplicated_orders', COUNT(*), 4466
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
  UNION ALL
  SELECT 'duplicate_order_keys', COUNT(*) - COUNT(DISTINCT order_key), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
  UNION ALL
  SELECT 'invalid_transaction_ids_in_orders', COUNTIF(
    transaction_id IS NULL OR TRIM(transaction_id) = '' OR LOWER(TRIM(transaction_id)) = '(not set)'
  ), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
  UNION ALL
  SELECT 'non_positive_order_revenue', COUNTIF(order_revenue_usd IS NULL OR order_revenue_usd <= 0), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders`
  UNION ALL
  SELECT 'session_source_candidate_count', COUNT(*), 360129
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
  UNION ALL
  SELECT 'duplicate_session_keys', COUNT(*) - COUNT(DISTINCT session_key), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
  UNION ALL
  SELECT 'sessions_ending_before_start', COUNTIF(session_end_ts < session_start_ts), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
  UNION ALL
  SELECT 'invalid_source_resolution_tier', COUNTIF(source_resolution_tier NOT IN (
    'event_level_source', 'external_referrer', 'first_user_fallback', 'Direct', 'Unknown'
  )), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
  UNION ALL
  SELECT 'coverage_session_reconciliation', ABS(
    SUM(session_count) - MAX(total_session_count)
  ), 0
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.channel_source_coverage_audit`
  UNION ALL
  SELECT 'mapping_proposal_rule_count', COUNT(*), 11
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.channel_mapping_proposal`
  UNION ALL
  SELECT 'mapping_proposal_unique_priorities', COUNT(DISTINCT priority), 11
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.channel_mapping_proposal`
)
SELECT
  check_id,
  observed_value,
  expected_value,
  IF(observed_value = expected_value, 'PASS', 'FAIL') AS validation_status
FROM checks;
