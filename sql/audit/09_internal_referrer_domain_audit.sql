-- Candidate internal domains are derived from domains actually observed in
-- page_location. They remain proposals until the owner approves the list.
WITH location_domains AS (
  SELECT
    page_location_reg_domain,
    COUNT(*) AS page_location_event_count,
    COUNT(DISTINCT session_key) AS page_location_session_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  WHERE page_location_reg_domain IS NOT NULL
  GROUP BY page_location_reg_domain
),
location_hosts AS (
  SELECT
    page_location_host,
    COUNT(*) AS page_location_host_event_count
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  WHERE page_location_host IS NOT NULL
  GROUP BY page_location_host
),
referrer_domains AS (
  SELECT
    page_referrer_host,
    page_referrer_reg_domain,
    COUNT(*) AS referrer_event_count,
    COUNT(DISTINCT session_key) AS referrer_session_count,
    COUNT(DISTINCT user_pseudo_id) AS referrer_user_count,
    MIN(event_ts) AS first_observed_ts,
    MAX(event_ts) AS last_observed_ts
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  WHERE page_referrer_host IS NOT NULL
  GROUP BY page_referrer_host, page_referrer_reg_domain
)
SELECT
  referrer_domains.page_referrer_host,
  referrer_domains.page_referrer_reg_domain,
  referrer_domains.referrer_event_count,
  referrer_domains.referrer_session_count,
  referrer_domains.referrer_user_count,
  referrer_domains.first_observed_ts,
  referrer_domains.last_observed_ts,
  COALESCE(location_hosts.page_location_host_event_count, 0) AS exact_host_page_location_event_count,
  COALESCE(location_domains.page_location_event_count, 0) AS registered_domain_page_location_event_count,
  COALESCE(location_domains.page_location_session_count, 0) AS registered_domain_page_location_session_count,
  location_domains.page_location_reg_domain IS NOT NULL AS proposed_is_internal,
  CASE
    WHEN location_domains.page_location_reg_domain IS NOT NULL
    THEN 'registered domain appears in page_location'
    ELSE 'registered domain not observed in page_location'
  END AS proposal_reason,
  'PROPOSED_NOT_APPROVED' AS approval_status
FROM referrer_domains
LEFT JOIN location_domains
  ON referrer_domains.page_referrer_reg_domain = location_domains.page_location_reg_domain
LEFT JOIN location_hosts
  ON referrer_domains.page_referrer_host = location_hosts.page_location_host;
