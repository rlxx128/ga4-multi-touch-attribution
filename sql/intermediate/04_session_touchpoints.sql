-- One row per retained Session. Internal admin traffic remains visible but is
-- not assigned a marketing channel and is ineligible for conversion paths.
WITH prepared_sessions AS (
  SELECT
    session_source_candidates.*,
    COALESCE(resolved_source_host, '') IN (
      'analytics.google.com',
      'moma.corp.google.com'
    ) AS is_internal_admin_traffic,
    CASE LOWER(COALESCE(resolved_source_host, ''))
      WHEN 'analytics.google.com' THEN 'approved_admin_host:analytics.google.com'
      WHEN 'moma.corp.google.com' THEN 'approved_admin_host:moma.corp.google.com'
    END AS internal_admin_reason,
    FALSE AS is_internal_admin_candidate,
    COALESCE(resolved_source_host, '') NOT IN (
      'analytics.google.com',
      'moma.corp.google.com'
    ) AS is_marketing_eligible,
    COALESCE(resolved_source_host, '') NOT IN (
      'analytics.google.com',
      'moma.corp.google.com'
    ) AS is_attribution_eligible
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
    AS session_source_candidates
),
mapped_sessions AS (
  SELECT
    prepared_sessions.*,
    {{CHANNEL_MAPPING_STRUCT}} AS mapping
  FROM prepared_sessions
)
SELECT
  user_pseudo_id,
  ga_session_id,
  session_key,
  session_start_ts,
  session_end_ts,
  session_date,
  event_count,
  session_start_event_count,
  purchase_event_count,
  source_resolution_tier,
  resolved_source,
  resolved_medium,
  resolved_campaign,
  resolved_source_host,
  resolved_source_reg_domain,
  source_missing_flag,
  source_quality,
  is_inferred_source,
  inference_rule,
  external_page_referrer,
  external_referrer_reg_domain,
  is_internal_admin_traffic,
  internal_admin_reason,
  is_internal_admin_candidate,
  is_marketing_eligible,
  is_attribution_eligible,
  mapping.channel AS channel,
  mapping.priority AS mapping_rule_priority,
  mapping.rule_name AS mapping_rule_name,
  'phase2b_channel_v2_20260806' AS mapping_version,
  resolution_version
FROM mapped_sessions
