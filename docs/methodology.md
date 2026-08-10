# Methodology

Last updated: 2026-08-09

## Current implementation status

Phase 3 rule-based attribution is implemented and validated on the finalized
Phase 2B revised conversion paths. The implemented scope includes First Click,
Last Click, Last Non-direct Click, Linear, seven-day Time Decay, reconciliation,
and channel-level model comparison. Markov and all later analyses remain out of
scope.

## Core event and order definitions

`event_base` extracts the audited fields for suffixes `20201101` through
`20210131`. The source scan is split into monthly bounded queries. Historical
event-date partitioning is not used because the existing dataset has a 60-day
default partition expiration; tables are clustered instead.

Orders are purchase events grouped by `user_pseudo_id` and a trimmed valid
`transaction_id`. Null, blank, and case-insensitive `(not set)` identifiers are
excluded. The earliest eligible purchase timestamp is the order timestamp, and
the maximum observed `purchase_revenue_in_usd` is the deduplicated order value.

Session identity is a deterministic SHA-256 key over `user_pseudo_id` and the
integer `ga_session_id`.

## Approved Session source recovery

Before selecting source evidence, blank values and `(not set)`,
`(not provided)`, `(data deleted)`, `<other>`, and `unknown` placeholders are
normalized to null. Host-like sources are normalized with `NET.HOST`; registered
domains use `NET.REG_DOMAIN`.

The internal storefront rule is exact normalized registered-domain equality to
`googlemerchandisestore.com`. It therefore covers the registered domain and its
subdomains without using a substring predicate. The rule is applied separately
to event-level source, page referrer, and first-user source evidence.

Each Session is then resolved once in this order:

1. the earliest non-internal valid event-level source/medium/campaign tuple,
   with all tuple components taken from the same event;
2. the earliest non-internal page referrer;
3. the earliest non-internal first-user tuple, explicitly labelled
   `first_user_fallback`;
4. explicit Direct evidence from `(direct)` source or `(none)` medium;
5. Unknown when no reliable evidence remains.

A missing source with a usable medium is retained with
`source_missing_flag = TRUE` and `source_quality = 'medium_only'`. In particular,
a null-source `referral` medium remains Referral, but does not identify a
specific referring website.

For the approved external `www.google.com` referrer inference, the raw page
referrer remains available, `source_resolution_tier = 'external_referrer'`,
`is_inferred_source = TRUE`, and
`inference_rule = 'google_referrer_to_organic_search'`. It is not represented as
native event-level evidence.

## Administrative traffic and channel mapping

`analytics.google.com` and `moma.corp.google.com` are matched only by exact
normalized host equality. Their Sessions retain original source fields and are
labelled `channel = 'Internal/Admin'`, `is_internal_admin_traffic = TRUE`, and
`is_attribution_eligible = FALSE`, with a host-specific reason. They remain in
`session_touchpoints` but are excluded from both strict and revised conversion
paths. No broad `google.com` exclusion is used, and an order remains covered
when another eligible marketing touchpoint exists.

Mapping is a single ordered CASE expression with version
`phase2b_channel_v2_20260806`. Internal/Admin interception occurs first; for
attribution-eligible Sessions the first matching marketing rule wins:

1. Direct
2. Paid Social
3. Paid Search
4. Display
5. Email
6. Affiliates
7. Organic Search
8. Organic Social
9. Referral
10. Unknown
11. Other

The Creator Academy exception maps `creatoracademy.youtube.com` to Referral.
Ordinary YouTube/social domains map to Organic Social unless explicit
paid-social evidence matches the earlier Paid Social rule. Direct requires
explicit evidence; Unknown is not folded into Direct. Administrative Sessions
are intercepted before the marketing mapping.

## Conversion-cycle construction

Orders are sequenced within each user by `order_ts` and `order_key`.
`conversion_touchpoints_strict` preserves the strict rule after applying both
approved admin exclusions. A strict touchpoint must:

- have the same `user_pseudo_id`;
- start at or before the order timestamp;
- start no earlier than 30 days before the order;
- start strictly after the previous order timestamp when a previous order
  exists;
- be attribution-eligible, not Internal/Admin, and have one approved marketing
  channel.

The primary `conversion_touchpoints` adds one narrowly scoped alternative. The
Session must be the current order's own `conversion_session_key`, start at or
before the order, remain within 30 days, and be attribution-eligible. It may
start on or before the previous-order timestamp. No other Session can cross that
boundary. Rows are labelled `STANDARD_CONVERSION_CYCLE` or
`CURRENT_CONVERSION_SESSION_EXCEPTION`; the latter also sets
`is_same_session_multi_order_exception = TRUE`.

All distinct eligible Sessions, including Direct, are retained. Touchpoints are
ordered by Session start and Session key. Path length is the number of retained
Sessions for the order. Strict paths remain disjoint. A Session can appear for
multiple revised orders only when every later assignment is the explicitly
flagged current-conversion-Session exception.

Orders with no retained touchpoint are kept in `orders_without_touchpoints`
with a specific diagnostic reason. Administrative impact is measured both
before and after its exclusion.

The accepted pre-close-out result is reconstructed in the coverage audit as a
historical baseline of 4,043 covered and 423 unmatched orders. It is not used as
the primary close-out path table.

## Phase 3 rule-based attribution

The sole primary attribution input is `conversion_touchpoints`, version
`phase2b_closeout_v1_20260806`. The 9,577 retained Session touchpoints represent
4,457 attributable orders and USD 308,208.00. The 9 orders in
`orders_without_touchpoints`, representing USD 622.00, are excluded from all
models but retained in reconciliation reporting.

Weights are first calculated at touchpoint grain. Repeated Sessions and repeated
channels are not compressed. The final `attribution_results` table aggregates
touchpoint credit to `order_key x model x channel`:

- First Click assigns 1 to `touchpoint_number = 1`.
- Last Click assigns 1 to `touchpoint_number = path_length`.
- Last Non-direct Click assigns 1 to the latest channel not exactly `Direct`.
  Unknown remains eligible; an all-Direct path falls back to the final Direct
  touchpoint.
- Linear assigns `1 / path_length` to every retained Session.
- Time Decay calculates `0.5 ^ (seconds_before_conversion / 604800)` and then
  divides each raw weight by the order's raw-weight total.

For every model, `attributed_conversion` equals the normalized attribution
weight and `attributed_revenue` equals `order_revenue_usd` multiplied by that
weight. Within every order and model, conversion credit sums to 1 and attributed
revenue reconciles to order revenue within the approved numerical tolerance.
These allocations are descriptive and are not estimates of causal
incrementality.

## Validation and query safety

Every executable BigQuery query is dry-run first and uses the configured
1,000,000,000-byte `maximum_bytes_billed` ceiling. Any wildcard source scan is
bounded by `_TABLE_SUFFIX`. Phase 2B validation covers Session and order counts,
key uniqueness, source-tier reconciliation, internal-domain exclusion, Direct
and Unknown evidence, medium-only quality, channel validity and uniqueness,
admin-path exclusion, Creator Academy and Google inference exceptions, temporal
path boundaries, unmatched-order reconciliation, explicit exception reuse, and the absence
of attribution output tables. Phase 3 first reruns the 70-check prerequisite
gate, then validates input versions/populations, exact model formulas, canonical
grain uniqueness, all-Direct fallback, per-order and per-model conversion and
revenue reconciliation, exclusions, channel comparison, and absence of
later-phase outputs. All 46 Phase 3 checks pass.

## Later analytical workflow

The next phase may implement Markov attribution only after separate approval.
The rule-based weights, conversion totals, and revenue totals now reconcile.
Non-converting paths still require a separate owner decision before they can be
used, and are not implied by Phase 3 completion.

All future attribution is descriptive. Neither rule-based credit nor Markov
removal effects establish causal incrementality; causal budget decisions require
an experiment or another defensible causal design.
