-- Full frequency table for review at the Phase 2A approval gate.
WITH frequencies AS (
  SELECT
    source_resolution_tier,
    resolved_source,
    resolved_medium,
    resolved_campaign,
    COUNT(*) AS session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
  GROUP BY source_resolution_tier, resolved_source, resolved_medium, resolved_campaign
),
session_total AS (
  SELECT COUNT(*) AS total_session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
)
SELECT
  source_resolution_tier,
  resolved_source,
  resolved_medium,
  resolved_campaign,
  session_count,
  session_total.total_session_count,
  SAFE_DIVIDE(session_count, session_total.total_session_count) AS session_share,
  100 * SAFE_DIVIDE(session_count, session_total.total_session_count) AS session_percentage
FROM frequencies
CROSS JOIN session_total;
