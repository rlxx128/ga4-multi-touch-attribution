-- Phase 4 journey population. Finalized conversion paths are reused directly;
-- non-converting journeys use the approved 30-complete-day inactivity rule.
WITH eligible_sessions AS (
  SELECT
    user_pseudo_id,
    session_key,
    session_start_ts,
    session_end_ts,
    channel,
    mapping_version
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
  WHERE is_attribution_eligible
    AND NOT is_internal_admin_traffic
    AND channel != 'Internal/Admin'
),
sequenced_sessions AS (
  SELECT
    user_pseudo_id,
    session_key,
    session_start_ts,
    session_end_ts,
    channel,
    mapping_version,
    LAG(session_start_ts) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY session_start_ts, session_key
    ) AS previous_session_start_ts,
    LAG(session_end_ts) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY session_start_ts, session_key
    ) AS previous_session_end_ts
  FROM eligible_sessions
),
session_purchase_context AS (
  SELECT
    sequenced_sessions.user_pseudo_id,
    sequenced_sessions.session_key,
    sequenced_sessions.session_start_ts,
    sequenced_sessions.session_end_ts,
    sequenced_sessions.channel,
    sequenced_sessions.mapping_version,
    sequenced_sessions.previous_session_start_ts,
    sequenced_sessions.previous_session_end_ts,
    (
      SELECT MAX(orders.order_ts)
      FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders` AS orders
      WHERE orders.user_pseudo_id = sequenced_sessions.user_pseudo_id
        AND orders.order_ts < sequenced_sessions.session_start_ts
    ) AS last_order_before_session_ts
  FROM sequenced_sessions
),
marked_sessions AS (
  SELECT
    user_pseudo_id,
    session_key,
    session_start_ts,
    session_end_ts,
    channel,
    mapping_version,
    CASE
      WHEN previous_session_start_ts IS NULL THEN 1
      WHEN session_start_ts >= TIMESTAMP_ADD(
        previous_session_end_ts,
        INTERVAL 30 DAY
      ) THEN 1
      WHEN last_order_before_session_ts >= previous_session_start_ts THEN 1
      ELSE 0
    END AS starts_new_journey
  FROM session_purchase_context
),
assigned_sessions AS (
  SELECT
    user_pseudo_id,
    session_key,
    session_start_ts,
    session_end_ts,
    channel,
    mapping_version,
    SUM(starts_new_journey) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY session_start_ts, session_key
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS journey_number
  FROM marked_sessions
),
segmented_journeys AS (
  SELECT
    user_pseudo_id,
    journey_number,
    MIN(session_start_ts) AS journey_start_ts,
    MAX(session_end_ts) AS last_activity_ts,
    TIMESTAMP_ADD(MAX(session_end_ts), INTERVAL 30 DAY) AS inactivity_expiry_ts,
    ARRAY_AGG(channel ORDER BY session_start_ts, session_key) AS channel_path,
    ARRAY_AGG(session_key ORDER BY session_start_ts, session_key) AS session_key_path,
    COUNT(*) AS session_count,
    ANY_VALUE(mapping_version) AS mapping_version
  FROM assigned_sessions
  GROUP BY user_pseudo_id, journey_number
),
classified_segmented_journeys AS (
  SELECT
    segmented_journeys.user_pseudo_id,
    segmented_journeys.journey_number,
    segmented_journeys.journey_start_ts,
    segmented_journeys.last_activity_ts,
    segmented_journeys.inactivity_expiry_ts,
    segmented_journeys.channel_path,
    segmented_journeys.session_key_path,
    segmented_journeys.session_count,
    segmented_journeys.mapping_version,
    (
      SELECT MIN(orders.order_ts)
      FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.orders` AS orders
      WHERE orders.user_pseudo_id = segmented_journeys.user_pseudo_id
        AND orders.order_ts >= segmented_journeys.journey_start_ts
    ) AS next_purchase_ts
  FROM segmented_journeys
),
nonconverting_diagnostics AS (
  SELECT
    CONCAT(
      'SESSION_JOURNEY:',
      TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
        user_pseudo_id AS user_pseudo_id,
        journey_number AS journey_number,
        'phase4_markov_30d_v1_20260811' AS definition_version
      ))))
    ) AS journey_id,
    user_pseudo_id,
    CAST(NULL AS STRING) AS order_key,
    CAST(NULL AS TIMESTAMP) AS order_ts,
    CAST(NULL AS FLOAT64) AS attributable_revenue_usd,
    journey_start_ts,
    last_activity_ts,
    inactivity_expiry_ts,
    next_purchase_ts,
    TIMESTAMP('2021-02-01 00:00:00+00') AS dataset_end_boundary,
    channel_path,
    session_key_path,
    session_count,
    CASE
      WHEN (next_purchase_ts IS NULL OR next_purchase_ts > inactivity_expiry_ts)
        AND inactivity_expiry_ts < TIMESTAMP('2021-02-01 00:00:00+00')
        THEN 'Null'
      ELSE 'Right Censored'
    END AS journey_status,
    CASE
      WHEN (next_purchase_ts IS NULL OR next_purchase_ts > inactivity_expiry_ts)
        AND inactivity_expiry_ts < TIMESTAMP('2021-02-01 00:00:00+00')
        THEN 'Null'
    END AS outcome_state,
    (next_purchase_ts IS NULL OR next_purchase_ts > inactivity_expiry_ts)
      AND inactivity_expiry_ts < TIMESTAMP('2021-02-01 00:00:00+00')
      AS is_markov_included,
    journey_start_ts < TIMESTAMP('2020-12-01 00:00:00+00')
      AS is_left_boundary_truncated,
    30 AS inactivity_cutoff_days,
    mapping_version,
    'phase4_markov_30d_v1_20260811' AS journey_definition_version
  FROM classified_segmented_journeys
  WHERE (
      (next_purchase_ts IS NULL OR next_purchase_ts > inactivity_expiry_ts)
      AND inactivity_expiry_ts < TIMESTAMP('2021-02-01 00:00:00+00')
    )
    OR (
      inactivity_expiry_ts >= TIMESTAMP('2021-02-01 00:00:00+00')
      AND (
        next_purchase_ts IS NULL
        OR next_purchase_ts >= TIMESTAMP('2021-02-01 00:00:00+00')
      )
    )
),
finalized_conversion_journeys AS (
  SELECT
    CONCAT('CONVERSION:', order_key) AS journey_id,
    ANY_VALUE(user_pseudo_id) AS user_pseudo_id,
    order_key,
    ANY_VALUE(order_ts) AS order_ts,
    ANY_VALUE(order_revenue_usd) AS attributable_revenue_usd,
    MIN(touchpoint_ts) AS journey_start_ts,
    MAX(touchpoint_ts) AS last_activity_ts,
    CAST(NULL AS TIMESTAMP) AS inactivity_expiry_ts,
    ANY_VALUE(order_ts) AS next_purchase_ts,
    TIMESTAMP('2021-02-01 00:00:00+00') AS dataset_end_boundary,
    ARRAY_AGG(channel ORDER BY touchpoint_number) AS channel_path,
    ARRAY_AGG(session_key ORDER BY touchpoint_number) AS session_key_path,
    COUNT(*) AS session_count,
    'Conversion' AS journey_status,
    'Conversion' AS outcome_state,
    TRUE AS is_markov_included,
    MIN(touchpoint_ts) < TIMESTAMP('2020-12-01 00:00:00+00')
      AS is_left_boundary_truncated,
    30 AS inactivity_cutoff_days,
    ANY_VALUE(mapping_version) AS mapping_version,
    'phase4_markov_30d_v1_20260811' AS journey_definition_version
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
  GROUP BY order_key
)
SELECT
  journey_id,
  user_pseudo_id,
  order_key,
  order_ts,
  attributable_revenue_usd,
  journey_start_ts,
  last_activity_ts,
  inactivity_expiry_ts,
  next_purchase_ts,
  dataset_end_boundary,
  channel_path,
  session_key_path,
  session_count,
  journey_status,
  outcome_state,
  is_markov_included,
  is_left_boundary_truncated,
  inactivity_cutoff_days,
  mapping_version,
  journey_definition_version
FROM finalized_conversion_journeys

UNION ALL

SELECT
  journey_id,
  user_pseudo_id,
  order_key,
  order_ts,
  attributable_revenue_usd,
  journey_start_ts,
  last_activity_ts,
  inactivity_expiry_ts,
  next_purchase_ts,
  dataset_end_boundary,
  channel_path,
  session_key_path,
  session_count,
  journey_status,
  outcome_state,
  is_markov_included,
  is_left_boundary_truncated,
  inactivity_cutoff_days,
  mapping_version,
  journey_definition_version
FROM nonconverting_diagnostics
