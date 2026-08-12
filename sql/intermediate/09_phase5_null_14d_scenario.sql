-- Read-only Phase 5 Null sensitivity population. A completed candidate that
-- shares any Session with a finalized Conversion journey is excluded whole so
-- its path remains internally coherent and no Session is double-counted.
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
      PARTITION BY user_pseudo_id ORDER BY session_start_ts, session_key
    ) AS previous_session_start_ts,
    LAG(session_end_ts) OVER (
      PARTITION BY user_pseudo_id ORDER BY session_start_ts, session_key
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
      WHEN session_start_ts >= TIMESTAMP_ADD(previous_session_end_ts, INTERVAL 14 DAY)
        THEN 1
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
    TIMESTAMP_ADD(MAX(session_end_ts), INTERVAL 14 DAY) AS inactivity_expiry_ts,
    ARRAY_AGG(channel ORDER BY session_start_ts, session_key) AS channel_path,
    ARRAY_AGG(session_key ORDER BY session_start_ts, session_key) AS session_key_path,
    COUNT(*) AS session_count,
    ANY_VALUE(mapping_version) AS mapping_version
  FROM assigned_sessions
  GROUP BY user_pseudo_id, journey_number
),
classified_journeys AS (
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
diagnostic_candidates AS (
  SELECT
    CONCAT(
      'SESSION_JOURNEY:',
      TO_HEX(SHA256(TO_JSON_STRING(STRUCT(
        user_pseudo_id AS user_pseudo_id,
        journey_number AS journey_number,
        'phase5_null_14d_v1_20260812' AS definition_version
      ))))
    ) AS journey_id,
    user_pseudo_id,
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
    END AS candidate_status,
    journey_start_ts < TIMESTAMP('2020-11-15 00:00:00+00')
      AS is_left_boundary_truncated,
    mapping_version
  FROM classified_journeys
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
conversion_sessions AS (
  SELECT DISTINCT session_key
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.conversion_touchpoints`
),
candidate_overlap AS (
  SELECT
    diagnostic_candidates.journey_id,
    COUNT(DISTINCT candidate_session_key) AS overlapping_session_count
  FROM diagnostic_candidates
  CROSS JOIN UNNEST(diagnostic_candidates.session_key_path) AS candidate_session_key
  INNER JOIN conversion_sessions
    ON conversion_sessions.session_key = candidate_session_key
  WHERE diagnostic_candidates.candidate_status = 'Null'
  GROUP BY diagnostic_candidates.journey_id
)
SELECT
  diagnostic_candidates.journey_id,
  diagnostic_candidates.user_pseudo_id,
  diagnostic_candidates.journey_start_ts,
  diagnostic_candidates.last_activity_ts,
  diagnostic_candidates.inactivity_expiry_ts,
  diagnostic_candidates.next_purchase_ts,
  diagnostic_candidates.dataset_end_boundary,
  diagnostic_candidates.channel_path,
  diagnostic_candidates.session_key_path,
  diagnostic_candidates.session_count,
  diagnostic_candidates.candidate_status,
  IFNULL(candidate_overlap.overlapping_session_count, 0) AS overlapping_session_count,
  diagnostic_candidates.candidate_status = 'Null'
    AND IFNULL(candidate_overlap.overlapping_session_count, 0) > 0
    AS is_overlap_excluded,
  diagnostic_candidates.candidate_status = 'Null'
    AND IFNULL(candidate_overlap.overlapping_session_count, 0) = 0
    AS is_markov_included,
  diagnostic_candidates.is_left_boundary_truncated,
  14 AS inactivity_cutoff_days,
  diagnostic_candidates.mapping_version,
  'phase5_null_14d_v1_20260812' AS journey_definition_version
FROM diagnostic_candidates
LEFT JOIN candidate_overlap
  ON candidate_overlap.journey_id = diagnostic_candidates.journey_id
