WITH frequencies AS (
  SELECT
    source_resolution_tier,
    resolved_source,
    resolved_medium,
    resolved_campaign,
    source_quality,
    is_inferred_source,
    COUNT(*) AS session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
  GROUP BY source_resolution_tier, resolved_source, resolved_medium, resolved_campaign, source_quality, is_inferred_source
),
session_total AS (
  SELECT COUNT(*) AS total_session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
)
SELECT
  frequencies.source_resolution_tier,
  frequencies.resolved_source,
  frequencies.resolved_medium,
  frequencies.resolved_campaign,
  frequencies.source_quality,
  frequencies.is_inferred_source,
  frequencies.session_count,
  session_total.total_session_count,
  SAFE_DIVIDE(frequencies.session_count, session_total.total_session_count) AS session_share,
  100 * SAFE_DIVIDE(frequencies.session_count, session_total.total_session_count) AS session_percentage,
  'phase2b_source_v1_20260806' AS resolution_version
FROM frequencies
CROSS JOIN session_total
