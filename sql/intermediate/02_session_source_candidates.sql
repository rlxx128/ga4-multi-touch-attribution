-- One row per composite GA4 session. This resolves source evidence only; it
-- deliberately does not assign a marketing channel.
WITH normalized_events AS (
  SELECT
    event_ts,
    event_name,
    user_pseudo_id,
    ga_session_id,
    session_key,
    CASE
      WHEN LOWER(TRIM(event_source)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE event_source
    END AS valid_event_source,
    CASE
      WHEN LOWER(TRIM(event_medium)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE event_medium
    END AS valid_event_medium,
    CASE
      WHEN LOWER(TRIM(event_campaign)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE event_campaign
    END AS valid_event_campaign,
    event_source IS NOT NULL OR event_medium IS NOT NULL OR event_campaign IS NOT NULL AS has_raw_event_tuple,
    event_base.page_referrer,
    event_base.page_referrer_host,
    event_base.page_referrer_reg_domain,
    COALESCE(internal_domains.proposed_is_internal, FALSE) AS proposed_is_internal_referrer,
    CASE
      WHEN LOWER(TRIM(first_user_source)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE first_user_source
    END AS valid_first_user_source,
    CASE
      WHEN LOWER(TRIM(first_user_medium)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE first_user_medium
    END AS valid_first_user_medium,
    CASE
      WHEN LOWER(TRIM(first_user_campaign)) IN ('', '(not set)', '(not provided)', '(data deleted)', '<other>', 'unknown') THEN NULL
      ELSE first_user_campaign
    END AS valid_first_user_campaign
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base` AS event_base
  LEFT JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.internal_referrer_domain_audit` AS internal_domains
    ON event_base.page_referrer_host = internal_domains.page_referrer_host
  WHERE event_base.user_pseudo_id IS NOT NULL
    AND event_base.ga_session_id IS NOT NULL
    AND event_base.session_key IS NOT NULL
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
    ARRAY_AGG(
      IF(
        valid_event_source IS NOT NULL OR valid_event_medium IS NOT NULL OR valid_event_campaign IS NOT NULL,
        STRUCT(event_ts, valid_event_source AS source, valid_event_medium AS medium, valid_event_campaign AS campaign),
        NULL
      ) IGNORE NULLS
      ORDER BY event_ts
      LIMIT 1
    )[SAFE_OFFSET(0)] AS event_tuple,
    ARRAY_AGG(
      IF(
        page_referrer_host IS NOT NULL AND NOT proposed_is_internal_referrer,
        STRUCT(event_ts, page_referrer AS referrer, page_referrer_host AS source, page_referrer_reg_domain AS registered_domain),
        NULL
      ) IGNORE NULLS
      ORDER BY event_ts
      LIMIT 1
    )[SAFE_OFFSET(0)] AS external_referrer,
    ARRAY_AGG(
      IF(
        valid_first_user_source IS NOT NULL OR valid_first_user_medium IS NOT NULL OR valid_first_user_campaign IS NOT NULL,
        STRUCT(event_ts, valid_first_user_source AS source, valid_first_user_medium AS medium, valid_first_user_campaign AS campaign),
        NULL
      ) IGNORE NULLS
      ORDER BY event_ts
      LIMIT 1
    )[SAFE_OFFSET(0)] AS first_user_tuple,
    COUNTIF(has_raw_event_tuple) AS raw_event_tuple_event_count
  FROM normalized_events
  GROUP BY user_pseudo_id, ga_session_id, session_key
),
resolved_sessions AS (
  SELECT
    session_candidates.*,
    CASE
      WHEN event_tuple IS NOT NULL
        AND (LOWER(event_tuple.source) = '(direct)' OR LOWER(event_tuple.medium) = '(none)') THEN 'Direct'
      WHEN event_tuple IS NOT NULL THEN 'event_level_source'
      WHEN external_referrer IS NOT NULL THEN 'external_referrer'
      WHEN first_user_tuple IS NOT NULL
        AND (LOWER(first_user_tuple.source) = '(direct)' OR LOWER(first_user_tuple.medium) = '(none)') THEN 'Direct'
      WHEN first_user_tuple IS NOT NULL THEN 'first_user_fallback'
      ELSE 'Unknown'
    END AS source_resolution_tier
  FROM session_candidates
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
  CASE source_resolution_tier
    WHEN 'event_level_source' THEN event_tuple.source
    WHEN 'external_referrer' THEN external_referrer.source
    WHEN 'first_user_fallback' THEN first_user_tuple.source
    WHEN 'Direct' THEN '(direct)'
  END AS resolved_source,
  CASE source_resolution_tier
    WHEN 'event_level_source' THEN event_tuple.medium
    WHEN 'external_referrer' THEN 'referral'
    WHEN 'first_user_fallback' THEN first_user_tuple.medium
    WHEN 'Direct' THEN '(none)'
  END AS resolved_medium,
  CASE source_resolution_tier
    WHEN 'event_level_source' THEN event_tuple.campaign
    WHEN 'first_user_fallback' THEN first_user_tuple.campaign
  END AS resolved_campaign,
  event_tuple.event_ts AS event_tuple_ts,
  external_referrer.event_ts AS external_referrer_ts,
  external_referrer.referrer AS external_page_referrer,
  external_referrer.registered_domain AS external_referrer_reg_domain,
  first_user_tuple.event_ts AS first_user_tuple_ts,
  'PROVISIONAL_PENDING_INTERNAL_DOMAIN_AND_MAPPING_APPROVAL' AS resolution_status
FROM resolved_sessions;
