WITH before_prepared AS (
  SELECT
    source_reprocessing_session_audit.*,
    before_resolved_source AS resolved_source,
    before_resolved_medium AS resolved_medium,
    before_resolved_source_host AS resolved_source_host,
    before_resolved_source_reg_domain AS resolved_source_reg_domain,
    before_source_resolution_tier AS source_resolution_tier,
    COALESCE(before_resolved_source_host, '') IN (
      'analytics.google.com',
      'moma.corp.google.com'
    ) AS is_internal_admin_traffic
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.source_reprocessing_session_audit`
    AS source_reprocessing_session_audit
),
before_mapped AS (
  SELECT
    before_prepared.*,
    {{CHANNEL_MAPPING_STRUCT}} AS before_mapping
  FROM before_prepared
),
joined_results AS (
  SELECT
    before_mapped.before_source_resolution_tier,
    session_touchpoints.source_resolution_tier AS after_source_resolution_tier,
    before_mapped.before_mapping.channel AS proposed_before_channel,
    session_touchpoints.channel AS approved_after_channel,
    before_mapped.was_internal_storefront_resolved_referral,
    before_mapped.resolution_changed
  FROM before_mapped
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
    AS session_touchpoints
    USING (session_key)
)
SELECT
  before_source_resolution_tier,
  after_source_resolution_tier,
  proposed_before_channel,
  approved_after_channel,
  was_internal_storefront_resolved_referral,
  resolution_changed,
  COUNT(*) AS session_count,
  'phase2b_source_v1_20260806' AS resolution_version,
  'phase2b_channel_v2_20260806' AS mapping_version
FROM joined_results
GROUP BY
  before_source_resolution_tier,
  after_source_resolution_tier,
  proposed_before_channel,
  approved_after_channel,
  was_internal_storefront_resolved_referral,
  resolution_changed
