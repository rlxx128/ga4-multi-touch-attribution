-- Channel-level funnel stage incidence. The denominator is every approved
-- attribution-eligible Session assigned to the channel; the rates do not imply
-- that funnel events occurred in a validated sequential order.
WITH event_flags AS (
  SELECT
    session_key,
    COUNTIF(event_name = 'view_item') > 0 AS has_view_item,
    COUNTIF(event_name = 'add_to_cart') > 0 AS has_add_to_cart,
    COUNTIF(event_name = 'begin_checkout') > 0 AS has_begin_checkout,
    COUNTIF(event_name = 'purchase') > 0 AS has_purchase
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.event_base`
  WHERE session_key IS NOT NULL
  GROUP BY session_key
),
eligible_sessions AS (
  SELECT
    sessions.session_key,
    sessions.channel,
    sessions.mapping_version,
    COALESCE(event_flags.has_view_item, FALSE) AS has_view_item,
    COALESCE(event_flags.has_add_to_cart, FALSE) AS has_add_to_cart,
    COALESCE(event_flags.has_begin_checkout, FALSE) AS has_begin_checkout,
    COALESCE(event_flags.has_purchase, FALSE) AS has_purchase
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints` AS sessions
  LEFT JOIN event_flags USING (session_key)
  WHERE sessions.is_attribution_eligible
    AND NOT sessions.is_internal_admin_traffic
    AND sessions.channel != 'Internal/Admin'
),
channel_counts AS (
  SELECT
    channel,
    ANY_VALUE(mapping_version) AS mapping_version,
    COUNT(DISTINCT session_key) AS sessions,
    COUNT(DISTINCT IF(has_view_item, session_key, NULL))
      AS sessions_with_view_item,
    COUNT(DISTINCT IF(has_add_to_cart, session_key, NULL))
      AS sessions_with_add_to_cart,
    COUNT(DISTINCT IF(has_begin_checkout, session_key, NULL))
      AS sessions_with_begin_checkout,
    COUNT(DISTINCT IF(has_purchase, session_key, NULL))
      AS sessions_with_purchase
  FROM eligible_sessions
  GROUP BY channel
)
SELECT
  channel,
  sessions,
  sessions_with_view_item,
  sessions_with_add_to_cart,
  sessions_with_begin_checkout,
  sessions_with_purchase,
  SAFE_DIVIDE(sessions_with_view_item, sessions) AS view_item_session_rate,
  SAFE_DIVIDE(sessions_with_add_to_cart, sessions) AS add_to_cart_session_rate,
  SAFE_DIVIDE(sessions_with_begin_checkout, sessions) AS checkout_session_rate,
  SAFE_DIVIDE(sessions_with_purchase, sessions) AS purchase_session_rate,
  'all_attribution_eligible_sessions_for_channel' AS denominator_definition,
  'channel_level_funnel_stage_incidence_rates' AS metric_definition,
  mapping_version,
  'phase6_business_reporting_v1_20260814' AS reporting_version
FROM channel_counts
