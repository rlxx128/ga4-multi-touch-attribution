SELECT
  priority,
  channel,
  rule_name,
  rule_description,
  'APPROVED' AS decision_status,
  'phase2b_channel_v1_20260806' AS mapping_version
FROM UNNEST([
  STRUCT(1 AS priority, 'Direct' AS channel, 'direct_explicit' AS rule_name, 'Explicit Direct tier, (direct) source, or (none) medium.' AS rule_description),
  STRUCT(2, 'Paid Social', 'paid_social', 'Explicit paid-social medium, or social source with an approved paid medium.'),
  STRUCT(3, 'Paid Search', 'paid_search', 'Remaining cpc, ppc, paidsearch, paid search, or sem medium.'),
  STRUCT(4, 'Display', 'display', 'Display, banner, cpm, or programmatic medium.'),
  STRUCT(5, 'Email', 'email', 'Email, e-mail, or e_mail medium.'),
  STRUCT(6, 'Affiliates', 'affiliates', 'Affiliate or affiliates medium.'),
  STRUCT(7, 'Organic Search', 'organic_search', 'Organic medium, including approved www.google.com referrer inference.'),
  STRUCT(8, 'Organic Social', 'organic_social', 'Approved social medium/domain; creatoracademy.youtube.com is excluded from this rule.'),
  STRUCT(9, 'Referral', 'referral', 'External referrer tier or referral medium; includes Creator Academy and medium-only Referral.'),
  STRUCT(10, 'Unknown', 'unknown', 'No reliable source evidence; never silently reassigned to Direct.'),
  STRUCT(11, 'Other', 'other', 'Mutually exclusive terminal fallback.')
])
