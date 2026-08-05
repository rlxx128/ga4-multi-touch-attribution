# Data Dictionary

Last updated: 2026-08-06

## Current implementation status

Phase 2B has created or rebuilt the approved core Session and conversion-path
layers in `ga4-multi-touch-attribution.ga4_attribution`. All tables inherit the
existing dataset's 60-day default table expiration. No attribution-result or
model-comparison table exists.

## Core tables

### `event_base`

- Grain: one row per GA4 event.
- Validated rows: 4,295,584 over 92 dates.
- Physical design: clustered by `user_pseudo_id`, `session_key`, `event_name`.
- Event fields: `event_date`, `event_ts`, `event_timestamp`, `event_name`.
- User/Session fields: `user_pseudo_id`, `user_id`, `ga_session_id`,
  `ga_session_number`, `session_key`.
- Source/page fields: event source/medium/campaign, page location and referrer
  values plus normalized host and registered domain, and first-user source
  fields.
- Context fields: device, operating system, browser, country, region, city.
- Commerce fields: `transaction_id`, `purchase_revenue`,
  `purchase_revenue_in_usd`.

### `orders`

- Grain: one valid `user_pseudo_id` plus trimmed `transaction_id`.
- Validated rows: 4,466.
- Keys: `order_key`, `user_pseudo_id`, `transaction_id`.
- Timing: `order_ts`, `order_date`, `conversion_session_key`.
- Value: `order_revenue_usd`, the maximum observed USD purchase revenue.
- Diagnostics: purchase-event count, duplicate count, distinct/minimum/maximum
  observed revenue.

The earliest eligible purchase timestamp defines the order timestamp.

### `session_source_candidates`

- Grain: one composite user Session.
- Validated rows: 360,129; duplicate Session keys: 0.
- Physical design: clustered by `user_pseudo_id`, `source_resolution_tier`.
- Identity/time: `user_pseudo_id`, `ga_session_id`, `session_key`,
  `session_start_ts`, `session_end_ts`, `session_date`.
- Counts: event, Session-start, purchase, and raw event-tuple counts.
- Resolution: `source_resolution_tier`, `resolved_source`, `resolved_medium`,
  `resolved_campaign`, `resolved_source_host`,
  `resolved_source_reg_domain`.
- Quality: `source_missing_flag`, `source_quality`, `is_inferred_source`,
  `inference_rule`.
- Evidence: event tuple, external referrer, first-user fallback, and Direct
  evidence timestamps; raw external page referrer and registered domain.
- Internal evidence flags: event source, page referrer, first-user source, and
  total evidence-type count.
- Version: `resolution_version = 'phase2b_source_v1_20260806'`.

Allowed mutually exclusive tiers are `event_level_source`,
`external_referrer`, `first_user_fallback`, `Direct`, and `Unknown`.

### `session_touchpoints`

- Grain: one composite user Session.
- Validated rows: 360,129; duplicate Session keys: 0.
- Carries the Session timing, source resolution, quality, inference, raw
  referrer, and version fields required by path construction.
- Administrative fields: `is_internal_admin_traffic`,
  `internal_admin_reason`, `is_internal_admin_candidate`,
  `is_marketing_eligible`.
- Mapping fields: `channel`, `mapping_rule_priority`, `mapping_rule_name`,
  `mapping_version`.

Approved admin Sessions remain in this table but have null `channel` and are not
marketing-eligible. Every marketing-eligible Session has exactly one approved
channel.

### `conversion_touchpoints`

- Grain: one eligible Session per order conversion cycle.
- Validated rows: 9,172 for 4,043 covered orders.
- Order fields: order identity, timestamp/date, revenue, previous-order
  timestamp, and same-timestamp order diagnostics.
- Touchpoint fields: `session_key`, `ga_session_id`, `touchpoint_ts`,
  `session_end_ts`, `touchpoint_number`, `path_length`,
  `seconds_before_conversion`.
- Source/channel fields: resolution tier, source/medium/campaign, source quality,
  inference metadata, admin-candidate flag, channel, and mapping version.

Touchpoints are at or before conversion, within 30 days, strictly after the
previous order, and exclude approved internal admin Sessions.

### `orders_without_touchpoints`

- Grain: one eligible order without a marketing touchpoint.
- Validated rows: 423.
- Includes order/cycle fields and counts of all user Sessions, Sessions on or
  before the order, Sessions in the 30-day window, temporally eligible Sessions,
  internal-admin Sessions, and marketing-eligible Sessions.
- `exclusion_reason` records the first applicable path failure reason.

All 423 current rows have `NO_SESSION_AFTER_PREVIOUS_ORDER`.

## Rule and audit tables

### `internal_domain_rules`

- Grain: one approved or audit-only domain rule; 3 rows.
- Records the exact storefront registered-domain rule, approved
  `analytics.google.com` admin host, and audit-only `moma.corp.google.com`
  candidate with status and reason.

### `channel_mapping_rules`

- Grain: one ordered channel rule; 11 rows.
- Fields: priority, channel, rule name, predicate description, decision status,
  and mapping version.

### `source_reprocessing_session_audit`

- Grain: one Session; 360,129 rows.
- Stores Phase 2A before-values and rebuilt Phase 2B after-values, internal
  evidence flags, after-quality/inference fields, `resolution_changed`, and
  `was_internal_storefront_resolved_referral`.
- Exactly 70,820 rows are marked as affected storefront referrals.

### `source_reprocessing_summary`

- Grain: one before/after tier, proposed/approved channel, affected flag, and
  changed-status combination; 37 rows.
- Purpose: reconcile the redistribution of all Sessions and the 70,820 affected
  subset.

### `channel_source_coverage_audit`

- Grain: one approved source tier; 5 rows.
- Contains count, share, percentage, coverage status, and resolution version.
- Counts reconcile to 360,129 Sessions and 100% coverage.

### `source_medium_campaign_frequency`

- Grain: one tier/source/medium/campaign/quality/inference combination; 248 rows.
- Contains Session/user counts and Session share/percentage.

### `channel_mapping_audit`

- Grain: one source tuple, quality, admin state, mapping result, and version
  combination; 248 rows.
- Contains Session and user counts and is the mapping-review/reconciliation
  table.

### `order_path_coverage_audit`

- Grain: one eligible order; 4,466 rows.
- Contains Session eligibility counts, conversion-touchpoint count, coverage
  before/after admin exclusion, and coverage-loss flag.

### `internal_admin_path_impact_audit`

- Grain: one approved admin-host summary; 1 row.
- Reports affected Sessions/users/orders and order coverage before and after
  exclusion.

### `admin_domain_candidate_audit`

- Grain: one observed tuple for `moma.corp.google.com`; 1 row.
- Reports tier, source, medium, channel, Sessions, users, affected orders,
  touchpoint rows, and `AUDIT_ONLY_NOT_EXCLUDED` status.

### `same_session_multiple_order_audit`

- Grain: one conversion Session associated with multiple orders; 236 rows.
- Contains order counts/timestamps/keys, assigned-path order count, and
  `session_reuse_violation`.

### `path_length_distribution_audit`

- Grain: one observed path length; 13 rows for lengths 0 through 12.
- Contains order count/revenue, total count/revenue, and order/revenue shares.

### `phase2b_validation_summary`

- Grain: one Phase 2B check; 34 rows.
- Fields: `check_id`, `observed_value`, `expected_value`,
  `validation_status`.
- Result: all 34 checks pass.

## Historical Phase 2A review tables

`internal_referrer_domain_audit`, `channel_mapping_proposal`, and
`phase2a_validation_summary` remain as historical approval evidence. The
proposal is superseded by the approved versioned Phase 2B rules; it is not the
mapping used by `session_touchpoints`.

## Not implemented

`attribution_results`, `model_comparison`, and all First Click, Last Click, Last
Non-direct, Linear, Time Decay, Markov, Shapley, ROAS, budget, and dashboard
outputs are outside Phase 2B and do not exist.
