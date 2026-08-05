-- Row-level before/after evidence retained before the provisional source table
-- is replaced. This supports exact reconciliation of all 70,820 affected rows.
WITH previous_candidates AS (
  SELECT
    user_pseudo_id,
    session_key,
    source_resolution_tier,
    resolved_source,
    resolved_medium,
    resolved_campaign,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(resolved_source), r'^[a-z][a-z0-9+.-]*://')
        THEN LOWER(NET.HOST(resolved_source))
      WHEN REGEXP_CONTAINS(LOWER(resolved_source), r'^(?:[a-z0-9-]+\.)+[a-z]{2,}$')
        THEN LOWER(resolved_source)
    END AS resolved_source_host,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(resolved_source), r'^(?:[a-z][a-z0-9+.-]*://)?(?:[a-z0-9-]+\.)+[a-z]{2,}$')
        THEN LOWER(NET.REG_DOMAIN(IF(
          REGEXP_CONTAINS(LOWER(resolved_source), r'^[a-z][a-z0-9+.-]*://'),
          resolved_source,
          CONCAT('https://', resolved_source)
        )))
    END AS resolved_source_reg_domain
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_source_candidates`
),
rebuilt_candidates AS (
  {{SOURCE_RESOLUTION_QUERY}}
)
SELECT
  previous_candidates.user_pseudo_id,
  previous_candidates.session_key,
  previous_candidates.source_resolution_tier AS before_source_resolution_tier,
  rebuilt_candidates.source_resolution_tier AS after_source_resolution_tier,
  previous_candidates.resolved_source AS before_resolved_source,
  rebuilt_candidates.resolved_source AS after_resolved_source,
  previous_candidates.resolved_medium AS before_resolved_medium,
  rebuilt_candidates.resolved_medium AS after_resolved_medium,
  previous_candidates.resolved_campaign AS before_resolved_campaign,
  rebuilt_candidates.resolved_campaign AS after_resolved_campaign,
  previous_candidates.resolved_source_host AS before_resolved_source_host,
  rebuilt_candidates.resolved_source_host AS after_resolved_source_host,
  previous_candidates.resolved_source_reg_domain AS before_resolved_source_reg_domain,
  rebuilt_candidates.resolved_source_reg_domain AS after_resolved_source_reg_domain,
  previous_candidates.resolved_source_reg_domain = 'googlemerchandisestore.com'
    AND LOWER(previous_candidates.resolved_medium) = 'referral'
    AS was_internal_storefront_resolved_referral,
  rebuilt_candidates.has_internal_event_source,
  rebuilt_candidates.has_internal_page_referrer,
  rebuilt_candidates.has_internal_first_user_source,
  rebuilt_candidates.source_missing_flag AS after_source_missing_flag,
  rebuilt_candidates.source_quality AS after_source_quality,
  rebuilt_candidates.is_inferred_source AS after_is_inferred_source,
  TO_JSON_STRING(STRUCT(
    previous_candidates.source_resolution_tier,
    previous_candidates.resolved_source,
    previous_candidates.resolved_medium,
    previous_candidates.resolved_campaign
  )) != TO_JSON_STRING(STRUCT(
    rebuilt_candidates.source_resolution_tier,
    rebuilt_candidates.resolved_source,
    rebuilt_candidates.resolved_medium,
    rebuilt_candidates.resolved_campaign
  )) AS resolution_changed,
  'phase2b_source_v1_20260806' AS resolution_version
FROM previous_candidates
FULL OUTER JOIN rebuilt_candidates USING (session_key)
