-- Compact immutable Phase 4 baseline extract used by local Phase 5 Markov
-- transformations and the user-level cluster bootstrap.
SELECT
  journey_id,
  user_pseudo_id,
  outcome_state,
  channel_path,
  session_count,
  journey_status,
  is_left_boundary_truncated,
  inactivity_cutoff_days,
  mapping_version,
  journey_definition_version
FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.markov_journeys`
WHERE is_markov_included
