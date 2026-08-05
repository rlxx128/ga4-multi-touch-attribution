CASE
  WHEN {{ROW_ALIAS}}.is_internal_admin_traffic
    THEN STRUCT(0 AS priority, 'Internal/Admin' AS channel, 'internal_admin_exact_host' AS rule_name)
  WHEN {{ROW_ALIAS}}.source_resolution_tier = 'Direct'
    OR LOWER({{ROW_ALIAS}}.resolved_source) = '(direct)'
    OR LOWER({{ROW_ALIAS}}.resolved_medium) = '(none)'
    THEN STRUCT(1 AS priority, 'Direct' AS channel, 'direct_explicit' AS rule_name)
  WHEN REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^(paid[_ -]?social|social[_ -]?paid)$')
    OR (
      REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^(cpc|ppc|paidsearch|paid search|sem)$')
      AND (
        {{ROW_ALIAS}}.resolved_source_reg_domain IN ('facebook.com', 'instagram.com', 'twitter.com', 't.co', 'linkedin.com', 'tiktok.com', 'youtube.com')
        OR REGEXP_CONTAINS(COALESCE({{ROW_ALIAS}}.resolved_source_reg_domain, ''), r'^pinterest\.[a-z.]+$')
      )
    )
    THEN STRUCT(2 AS priority, 'Paid Social' AS channel, 'paid_social' AS rule_name)
  WHEN REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^(cpc|ppc|paidsearch|paid search|sem)$')
    THEN STRUCT(3 AS priority, 'Paid Search' AS channel, 'paid_search' AS rule_name)
  WHEN REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^(display|banner|cpm|programmatic)$')
    THEN STRUCT(4 AS priority, 'Display' AS channel, 'display' AS rule_name)
  WHEN REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^(email|e-mail|e_mail)$')
    THEN STRUCT(5 AS priority, 'Email' AS channel, 'email' AS rule_name)
  WHEN REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^affiliate(s)?$')
    THEN STRUCT(6 AS priority, 'Affiliates' AS channel, 'affiliates' AS rule_name)
  WHEN REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^organic$')
    THEN STRUCT(7 AS priority, 'Organic Search' AS channel, 'organic_search' AS rule_name)
  WHEN LOWER(COALESCE({{ROW_ALIAS}}.resolved_source_host, '')) != 'creatoracademy.youtube.com'
    AND (
      REGEXP_CONTAINS(LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')), r'^(social|social-network|social-media|sm)$')
      OR {{ROW_ALIAS}}.resolved_source_reg_domain IN ('facebook.com', 'instagram.com', 'twitter.com', 't.co', 'linkedin.com', 'tiktok.com', 'youtube.com')
      OR REGEXP_CONTAINS(COALESCE({{ROW_ALIAS}}.resolved_source_reg_domain, ''), r'^pinterest\.[a-z.]+$')
    )
    THEN STRUCT(8 AS priority, 'Organic Social' AS channel, 'organic_social' AS rule_name)
  WHEN {{ROW_ALIAS}}.source_resolution_tier = 'external_referrer'
    OR LOWER(COALESCE({{ROW_ALIAS}}.resolved_medium, '')) = 'referral'
    THEN STRUCT(9 AS priority, 'Referral' AS channel, 'referral' AS rule_name)
  WHEN {{ROW_ALIAS}}.source_resolution_tier = 'Unknown'
    OR ({{ROW_ALIAS}}.resolved_source IS NULL AND {{ROW_ALIAS}}.resolved_medium IS NULL)
    THEN STRUCT(10 AS priority, 'Unknown' AS channel, 'unknown' AS rule_name)
  ELSE STRUCT(11 AS priority, 'Other' AS channel, 'other' AS rule_name)
END
