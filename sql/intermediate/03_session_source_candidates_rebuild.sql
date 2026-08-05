-- Approved Phase 2B Session source recovery. Internal storefront matching uses
-- exact normalized registered-domain equality, never substring matching.
WITH cleaned_events AS (
  SELECT
    event_ts,
    event_name,
    user_pseudo_id,
    ga_session_id,
    session_key,
    CASE
      WHEN LOWER(TRIM(event_source)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE TRIM(event_source)
    END AS clean_event_source,
    CASE
      WHEN LOWER(TRIM(event_medium)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE TRIM(event_medium)
    END AS clean_event_medium,
    CASE
      WHEN LOWER(TRIM(event_campaign)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE TRIM(event_campaign)
    END AS clean_event_campaign,
    page_referrer,
    LOWER(page_referrer_host) AS page_referrer_host,
    LOWER(page_referrer_reg_domain) AS page_referrer_reg_domain,
    CASE
      WHEN LOWER(TRIM(first_user_source)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE TRIM(first_user_source)
    END AS clean_first_user_source,
    CASE
      WHEN LOWER(TRIM(first_user_medium)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE TRIM(first_user_medium)
    END AS clean_first_user_medium,
    CASE
      WHEN LOWER(TRIM(first_user_campaign)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE TRIM(first_user_campaign)
    END AS clean_first_user_campaign
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  WHERE user_pseudo_id IS NOT NULL
    AND ga_session_id IS NOT NULL
    AND session_key IS NOT NULL
),
normalized_sources AS (
  SELECT
    cleaned_events.*,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(clean_event_source), r'^[a-z][a-z0-9+.-]*://')
        THEN LOWER(NET.HOST(clean_event_source))
      WHEN REGEXP_CONTAINS(LOWER(clean_event_source), r'^(?:[a-z0-9-]+\.)+[a-z]{2,}$')
        THEN LOWER(clean_event_source)
    END AS event_source_host,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(clean_event_source), r'^(?:[a-z][a-z0-9+.-]*://)?(?:[a-z0-9-]+\.)+[a-z]{2,}$')
        THEN LOWER(NET.REG_DOMAIN(IF(
          REGEXP_CONTAINS(LOWER(clean_event_source), r'^[a-z][a-z0-9+.-]*://'),
          clean_event_source,
          CONCAT('https://', clean_event_source)
        )))
    END AS event_source_reg_domain,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(clean_first_user_source), r'^[a-z][a-z0-9+.-]*://')
        THEN LOWER(NET.HOST(clean_first_user_source))
      WHEN REGEXP_CONTAINS(LOWER(clean_first_user_source), r'^(?:[a-z0-9-]+\.)+[a-z]{2,}$')
        THEN LOWER(clean_first_user_source)
    END AS first_user_source_host,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(clean_first_user_source), r'^(?:[a-z][a-z0-9+.-]*://)?(?:[a-z0-9-]+\.)+[a-z]{2,}$')
        THEN LOWER(NET.REG_DOMAIN(IF(
          REGEXP_CONTAINS(LOWER(clean_first_user_source), r'^[a-z][a-z0-9+.-]*://'),
          clean_first_user_source,
          CONCAT('https://', clean_first_user_source)
        )))
    END AS first_user_source_reg_domain
  FROM cleaned_events
),
session_candidates AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    session_key,
    MIN(event_ts) AS session_start_ts,
    MAX(event_ts) AS session_end_ts,
    COUNT(*) AS event_count,
    COUNTIF(event_name = 'session_start') AS session_start_event_count,
    COUNTIF(event_name = 'purchase') AS purchase_event_count,
    COUNTIF(
      clean_event_source IS NOT NULL
      OR clean_event_medium IS NOT NULL
      OR clean_event_campaign IS NOT NULL
    ) AS raw_event_tuple_event_count,
    ARRAY_AGG(
      IF(
        (clean_event_source IS NOT NULL OR clean_event_medium IS NOT NULL OR clean_event_campaign IS NOT NULL)
        AND COALESCE(LOWER(clean_event_source), '') != '(direct)'
        AND COALESCE(LOWER(clean_event_medium), '') != '(none)'
        AND COALESCE(event_source_reg_domain, '') != 'googlemerchandisestore.com',
        STRUCT(
          event_ts,
          event_name,
          clean_event_source AS source,
          clean_event_medium AS medium,
          clean_event_campaign AS campaign,
          event_source_host AS source_host,
          event_source_reg_domain AS source_reg_domain
        ),
        NULL
      ) IGNORE NULLS
      ORDER BY event_ts, event_name, clean_event_source, clean_event_medium, clean_event_campaign
      LIMIT 1
    )[SAFE_OFFSET(0)] AS event_tuple,
    ARRAY_AGG(
      IF(
        page_referrer_host IS NOT NULL
        AND COALESCE(page_referrer_reg_domain, '') != 'googlemerchandisestore.com',
        STRUCT(
          event_ts,
          page_referrer AS referrer,
          page_referrer_host AS source_host,
          page_referrer_reg_domain AS source_reg_domain
        ),
        NULL
      ) IGNORE NULLS
      ORDER BY event_ts, page_referrer_host, page_referrer
      LIMIT 1
    )[SAFE_OFFSET(0)] AS external_referrer,
    ARRAY_AGG(
      IF(
        (clean_first_user_source IS NOT NULL OR clean_first_user_medium IS NOT NULL OR clean_first_user_campaign IS NOT NULL)
        AND COALESCE(LOWER(clean_first_user_source), '') != '(direct)'
        AND COALESCE(LOWER(clean_first_user_medium), '') != '(none)'
        AND COALESCE(first_user_source_reg_domain, '') != 'googlemerchandisestore.com',
        STRUCT(
          event_ts,
          clean_first_user_source AS source,
          clean_first_user_medium AS medium,
          clean_first_user_campaign AS campaign,
          first_user_source_host AS source_host,
          first_user_source_reg_domain AS source_reg_domain
        ),
        NULL
      ) IGNORE NULLS
      ORDER BY event_ts, clean_first_user_source, clean_first_user_medium, clean_first_user_campaign
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_user_tuple,
    ARRAY_AGG(
      IF(
        LOWER(clean_event_source) = '(direct)'
        OR LOWER(clean_event_medium) = '(none)'
        OR LOWER(clean_first_user_source) = '(direct)'
        OR LOWER(clean_first_user_medium) = '(none)',
        STRUCT(event_ts, 'explicit_direct' AS evidence_type),
        NULL
      ) IGNORE NULLS
      ORDER BY event_ts
      LIMIT 1
    )[SAFE_OFFSET(0)] AS direct_evidence,
    LOGICAL_OR(event_source_reg_domain = 'googlemerchandisestore.com') AS has_internal_event_source,
    LOGICAL_OR(page_referrer_reg_domain = 'googlemerchandisestore.com') AS has_internal_page_referrer,
    LOGICAL_OR(first_user_source_reg_domain = 'googlemerchandisestore.com') AS has_internal_first_user_source
  FROM normalized_sources
  GROUP BY user_pseudo_id, ga_session_id, session_key
),
resolved_sessions AS (
  SELECT
    session_candidates.*,
    CASE
      WHEN event_tuple IS NOT NULL THEN 'event_level_source'
      WHEN external_referrer IS NOT NULL THEN 'external_referrer'
      WHEN first_user_tuple IS NOT NULL THEN 'first_user_fallback'
      WHEN direct_evidence IS NOT NULL THEN 'Direct'
      ELSE 'Unknown'
    END AS source_resolution_tier
  FROM session_candidates
),
resolved_values AS (
  SELECT
    resolved_sessions.*,
    CASE source_resolution_tier
      WHEN 'event_level_source' THEN event_tuple.source
      WHEN 'external_referrer' THEN external_referrer.source_host
      WHEN 'first_user_fallback' THEN first_user_tuple.source
      WHEN 'Direct' THEN '(direct)'
    END AS resolved_source,
    CASE
      WHEN source_resolution_tier = 'event_level_source' THEN event_tuple.medium
      WHEN source_resolution_tier = 'external_referrer' AND external_referrer.source_host = 'www.google.com' THEN 'organic'
      WHEN source_resolution_tier = 'external_referrer' THEN 'referral'
      WHEN source_resolution_tier = 'first_user_fallback' THEN first_user_tuple.medium
      WHEN source_resolution_tier = 'Direct' THEN '(none)'
    END AS resolved_medium,
    CASE source_resolution_tier
      WHEN 'event_level_source' THEN event_tuple.campaign
      WHEN 'first_user_fallback' THEN first_user_tuple.campaign
    END AS resolved_campaign,
    CASE source_resolution_tier
      WHEN 'event_level_source' THEN event_tuple.source_host
      WHEN 'external_referrer' THEN external_referrer.source_host
      WHEN 'first_user_fallback' THEN first_user_tuple.source_host
    END AS resolved_source_host,
    CASE source_resolution_tier
      WHEN 'event_level_source' THEN event_tuple.source_reg_domain
      WHEN 'external_referrer' THEN external_referrer.source_reg_domain
      WHEN 'first_user_fallback' THEN first_user_tuple.source_reg_domain
    END AS resolved_source_reg_domain,
    source_resolution_tier = 'external_referrer'
      AND external_referrer.source_host = 'www.google.com' AS is_inferred_source
  FROM resolved_sessions
)
SELECT
  user_pseudo_id,
  ga_session_id,
  session_key,
  session_start_ts,
  session_end_ts,
  DATE(session_start_ts) AS session_date,
  event_count,
  session_start_event_count,
  purchase_event_count,
  raw_event_tuple_event_count,
  source_resolution_tier,
  resolved_source,
  resolved_medium,
  resolved_campaign,
  resolved_source_host,
  resolved_source_reg_domain,
  resolved_source IS NULL AS source_missing_flag,
  CASE
    WHEN resolved_source IS NULL AND resolved_medium IS NOT NULL THEN 'medium_only'
    WHEN is_inferred_source THEN 'inferred'
    WHEN source_resolution_tier = 'first_user_fallback' THEN 'first_user_fallback'
    WHEN source_resolution_tier = 'Direct' THEN 'explicit_direct'
    WHEN source_resolution_tier = 'Unknown' THEN 'missing'
    WHEN source_resolution_tier = 'event_level_source' THEN 'event_observed'
    WHEN source_resolution_tier = 'external_referrer' THEN 'referrer_observed'
  END AS source_quality,
  is_inferred_source,
  IF(is_inferred_source, 'google_referrer_to_organic_search', NULL) AS inference_rule,
  event_tuple.event_ts AS event_tuple_ts,
  external_referrer.event_ts AS external_referrer_ts,
  external_referrer.referrer AS external_page_referrer,
  external_referrer.source_reg_domain AS external_referrer_reg_domain,
  first_user_tuple.event_ts AS first_user_tuple_ts,
  direct_evidence.event_ts AS direct_evidence_ts,
  has_internal_event_source,
  has_internal_page_referrer,
  has_internal_first_user_source,
  CAST(has_internal_event_source AS INT64)
    + CAST(has_internal_page_referrer AS INT64)
    + CAST(has_internal_first_user_source AS INT64) AS internal_storefront_evidence_type_count,
  'phase2b_source_v1_20260806' AS resolution_version
FROM resolved_values
