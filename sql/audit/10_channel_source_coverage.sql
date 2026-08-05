-- Mutually exclusive session-level coverage under the approved source priority.
WITH required_tiers AS (
  SELECT 1 AS sort_order, 'event_level_source' AS source_resolution_tier UNION ALL
  SELECT 2, 'external_referrer' UNION ALL
  SELECT 3, 'first_user_fallback' UNION ALL
  SELECT 4, 'Direct' UNION ALL
  SELECT 5, 'Unknown'
),
tier_counts AS (
  SELECT
    source_resolution_tier,
    COUNT(*) AS session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
  GROUP BY source_resolution_tier
),
session_total AS (
  SELECT COUNT(*) AS total_session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
)
SELECT
  required_tiers.sort_order,
  required_tiers.source_resolution_tier,
  COALESCE(tier_counts.session_count, 0) AS session_count,
  session_total.total_session_count,
  SAFE_DIVIDE(COALESCE(tier_counts.session_count, 0), session_total.total_session_count) AS session_share,
  100 * SAFE_DIVIDE(COALESCE(tier_counts.session_count, 0), session_total.total_session_count) AS session_percentage,
  'PROVISIONAL_PENDING_INTERNAL_DOMAIN_AND_MAPPING_APPROVAL' AS coverage_status
FROM required_tiers
LEFT JOIN tier_counts USING (source_resolution_tier)
CROSS JOIN session_total;
