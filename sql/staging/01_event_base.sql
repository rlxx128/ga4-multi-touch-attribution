-- Phase 2A event grain. The runner executes this template in bounded monthly
-- chunks and appends them to one clustered destination table. The destination
-- is intentionally not partitioned by historical event_date because the target
-- dataset has a 60-day default partition expiration.
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  TIMESTAMP_MICROS(event_timestamp) AS event_ts,
  event_timestamp,
  event_name,
  user_pseudo_id,
  user_id,
  (SELECT ANY_VALUE(value.int_value) FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  (SELECT ANY_VALUE(value.int_value) FROM UNNEST(event_params) WHERE key = 'ga_session_number') AS ga_session_number,
  CASE
    WHEN user_pseudo_id IS NOT NULL
      AND (SELECT ANY_VALUE(value.int_value) FROM UNNEST(event_params) WHERE key = 'ga_session_id') IS NOT NULL
    THEN TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
      user_pseudo_id AS user_pseudo_id,
      (SELECT ANY_VALUE(value.int_value) FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
    ))))
  END AS session_key,
  NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'source')), '') AS event_source,
  NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'medium')), '') AS event_medium,
  NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'campaign')), '') AS event_campaign,
  NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_location')), '') AS page_location,
  NET.HOST(NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_location')), '')) AS page_location_host,
  NET.REG_DOMAIN(NET.HOST(NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_location')), ''))) AS page_location_reg_domain,
  NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_referrer')), '') AS page_referrer,
  NET.HOST(NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_referrer')), '')) AS page_referrer_host,
  NET.REG_DOMAIN(NET.HOST(NULLIF(TRIM((SELECT ANY_VALUE(value.string_value) FROM UNNEST(event_params) WHERE key = 'page_referrer')), ''))) AS page_referrer_reg_domain,
  NULLIF(TRIM(traffic_source.source), '') AS first_user_source,
  NULLIF(TRIM(traffic_source.medium), '') AS first_user_medium,
  NULLIF(TRIM(traffic_source.name), '') AS first_user_campaign,
  device.category AS device_category,
  device.operating_system,
  device.web_info.browser AS browser,
  geo.country,
  geo.region,
  geo.city,
  NULLIF(TRIM(ecommerce.transaction_id), '') AS transaction_id,
  ecommerce.purchase_revenue,
  ecommerce.purchase_revenue_in_usd
FROM `{{SOURCE_TABLE}}`
WHERE _TABLE_SUFFIX BETWEEN '{{CHUNK_START_SUFFIX}}' AND '{{CHUNK_END_SUFFIX}}';
