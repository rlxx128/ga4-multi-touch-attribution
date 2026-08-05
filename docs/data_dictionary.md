# Data Dictionary

Last updated: 2026-08-05

## Current implementation status

Phase 2A created eight tables in
`ga4-multi-touch-attribution.ga4_attribution`. The source-candidate and mapping
tables are explicitly provisional pending the approval gate. No channel,
session touchpoint, conversion path, or attribution output has been created.

All Phase 2A tables inherit the existing dataset's 60-day table expiration.

## `event_base`

- Grain: one row per GA4 event.
- Row count at validation: 4,295,584.
- Physical design: clustered by `user_pseudo_id`, `session_key`, `event_name`;
  not date-partitioned because the dataset's default partition expiration would
  immediately expire historical partitions.
- Event fields: `event_date`, `event_ts`, `event_timestamp`, `event_name`.
- User/session fields: `user_pseudo_id`, `user_id`, `ga_session_id`,
  `ga_session_number`, `session_key`.
- Event source fields: `event_source`, `event_medium`, `event_campaign`.
- Page fields: `page_location`, `page_location_host`,
  `page_location_reg_domain`, `page_referrer`, `page_referrer_host`,
  `page_referrer_reg_domain`.
- First-user fields: `first_user_source`, `first_user_medium`,
  `first_user_campaign`.
- Context fields: `device_category`, `operating_system`, `browser`, `country`,
  `region`, `city`.
- Commerce fields: `transaction_id`, `purchase_revenue`,
  `purchase_revenue_in_usd`.

`session_key` is a deterministic SHA-256 hexadecimal key over the JSON
representation of `user_pseudo_id` and `ga_session_id`.

## `orders`

- Grain: one row per valid `user_pseudo_id` plus trimmed `transaction_id`.
- Row count at validation: 4,466.
- Physical design: clustered by `user_pseudo_id`, `transaction_id`.
- Key fields: `order_key`, `user_pseudo_id`, `transaction_id`.
- Timing fields: `order_ts`, `order_date`, `conversion_session_key`.
- Value field: `order_revenue_usd`, defined as maximum observed
  `purchase_revenue_in_usd`.
- Diagnostics: `purchase_event_count`, `duplicate_purchase_event_count`,
  `distinct_revenue_value_count`, `minimum_observed_revenue_usd`,
  `maximum_observed_revenue_usd`.

`order_key` is a deterministic SHA-256 hexadecimal key over the user and valid
transaction identifier. The earliest eligible timestamp defines the order.

## `internal_referrer_domain_audit`

- Grain: one observed `page_referrer_host` and registered-domain pair.
- Row count at validation: 5.
- Purpose: compare referrer domains with domains observed in `page_location`.
- Evidence fields: `referrer_event_count`, `referrer_session_count`,
  `referrer_user_count`, `first_observed_ts`, `last_observed_ts`,
  `exact_host_page_location_event_count`,
  `registered_domain_page_location_event_count`, and
  `registered_domain_page_location_session_count`.
- Proposal fields: `proposed_is_internal`, `proposal_reason`,
  `approval_status`.

The proposal is not a final internal-domain list.

## `session_source_candidates`

- Grain: one composite user Session.
- Row count at validation: 360,129.
- Physical design: clustered by `user_pseudo_id`, `source_resolution_tier`.
- Identity/time fields: `user_pseudo_id`, `ga_session_id`, `session_key`,
  `session_start_ts`, `session_end_ts`, `session_date`.
- Counts: `event_count`, `session_start_event_count`, `purchase_event_count`,
  `raw_event_tuple_event_count`.
- Resolution fields: `source_resolution_tier`, `resolved_source`,
  `resolved_medium`, `resolved_campaign`.
- Evidence timestamps/details: `event_tuple_ts`, `external_referrer_ts`,
  `external_page_referrer`, `external_referrer_reg_domain`,
  `first_user_tuple_ts`.
- Status: `resolution_status` is
  `PROVISIONAL_PENDING_INTERNAL_DOMAIN_AND_MAPPING_APPROVAL`.

Allowed resolution tiers are `event_level_source`, `external_referrer`,
`first_user_fallback`, `Direct`, and `Unknown`. This table does not contain a
channel field.

## `channel_source_coverage_audit`

- Grain: one required source-resolution tier.
- Row count: 5.
- Fields: `sort_order`, `source_resolution_tier`, `session_count`,
  `total_session_count`, `session_share`, `session_percentage`,
  `coverage_status`.
- Purpose: reconcile mutually exclusive source resolution to all candidate
  Sessions.

## `source_medium_campaign_frequency`

- Grain: one resolution-tier/source/medium/campaign combination.
- Row count: 251.
- Fields: `source_resolution_tier`, `resolved_source`, `resolved_medium`,
  `resolved_campaign`, `session_count`, `total_session_count`, `session_share`,
  `session_percentage`.
- Purpose: provide the full observed-value review input for mapping approval.

## `channel_mapping_proposal`

- Grain: one ordered proposed channel predicate.
- Row count: 11.
- Fields: `priority`, `proposed_channel`, `predicate_sql`, `rationale`,
  `approval_status`.
- Status: every row is `PROPOSED_NOT_APPROVED`; the rules have not been applied.

## `phase2a_validation_summary`

- Grain: one Phase 2A validation check.
- Row count: 17.
- Fields: `check_id`, `observed_value`, `expected_value`,
  `validation_status`.
- Result at gate: all 17 checks passed.

## Planned but not implemented

`session_touchpoints`, `conversion_touchpoints`, and
`orders_without_touchpoints` belong to Phase 2B and are blocked by mapping
approval. `attribution_results` and `model_comparison` belong to later phases.
They do not exist.
