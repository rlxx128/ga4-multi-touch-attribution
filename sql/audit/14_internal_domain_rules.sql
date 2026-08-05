SELECT
  rule_priority,
  rule_type,
  match_field,
  match_value,
  decision_status,
  reason,
  'phase2b_source_v1_20260806' AS resolution_version
FROM UNNEST([
  STRUCT(
    1 AS rule_priority,
    'internal_storefront' AS rule_type,
    'registered_domain' AS match_field,
    'googlemerchandisestore.com' AS match_value,
    'APPROVED' AS decision_status,
    'Exclude exact registered-domain matches and all subdomains from every source tier.' AS reason
  ),
  STRUCT(
    2,
    'internal_admin',
    'normalized_host',
    'analytics.google.com',
    'APPROVED',
    'Retain the Session but exclude it from marketing conversion paths.'
  ),
  STRUCT(
    3,
    'internal_admin_candidate',
    'normalized_host',
    'moma.corp.google.com',
    'AUDIT_ONLY_NOT_EXCLUDED',
    'Report observed and order impact before any future exclusion decision.'
  )
])
