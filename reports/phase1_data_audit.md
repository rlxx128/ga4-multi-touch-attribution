# Phase 1 Data Audit

Last updated: 2026-08-04

## Status and scope

Phase 1 audit execution was accepted before Phase 2A began. The audit used the
public, obfuscated GA4 ecommerce sample; its findings do not represent the
actual business performance of Google Merchandise Store. The Phase 1 decision
requests are retained below as historical evidence; approved definitions and
remaining Phase 2A gate decisions are recorded in `docs/decisions.md`.

The audit was read-only. It created no BigQuery datasets or tables and used no
channel mapping, session model, order model, attribution model, Markov model,
Shapley model, or dashboard.

## Query safety and cost

- Source: `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`.
- Fixed source range: suffix `20201101` through `20210131`.
- BigQuery location: `US`.
- Physical query jobs: 12, including monthly chunks for the two wide
  traffic-source scans.
- All 12 jobs passed a dry run immediately before execution.
- Every job used `maximum_bytes_billed = 1,000,000,000`.
- Largest dry-run estimate: 995,193,539 bytes.
- Total bytes processed across all jobs: 4,577,686,286.
- Total bytes billed across all jobs: 4,583,325,696.
- No validation check failed: 8 passed without review and 23 passed with
  documented review items.

Exact per-job estimates, processed bytes, billed bytes, SQL hashes, and row
counts are in `reports/tables/phase1_query_costs.csv`.

## Source schema and date coverage

The configured range contains 92 daily shards. All 92 were present and nonempty,
and every row-level `event_date` agreed with its table suffix. The confirmed
source date range is 2020-11-01 through 2021-01-31.

The audit counted 4,295,584 events and 270,154 distinct `user_pseudo_id` values.
All required event, ecommerce, identifier, and first-user traffic-source fields
were present in every selected shard.

The historical sample contains:

- `event_params` with string and integer values;
- `ecommerce.transaction_id`;
- `ecommerce.purchase_revenue`;
- `ecommerce.purchase_revenue_in_usd`;
- `traffic_source.source`, `traffic_source.medium`, and `traffic_source.name`.

It does not contain `collected_traffic_source` or
`session_traffic_source_last_click`. Their absence prevents direct use of the
newer collected-traffic or session-last-click exports in this sample.

## Event distribution

The audit observed 17 event names. No null or blank event name was observed.
The principal funnel events required by the planned analysis were present:

| Event | Events | Distinct users |
|---|---:|---:|
| `session_start` | 354,970 | 267,116 |
| `view_item` | 386,068 | 61,252 |
| `add_to_cart` | 58,543 | 12,545 |
| `begin_checkout` | 38,757 | 9,715 |
| `add_shipping_info` | 19,722 | 9,714 |
| `add_payment_info` | 13,899 | 5,751 |
| `purchase` | 5,692 | 4,419 |

No `refund` event was observed. This audit does not interpret event counts as a
funnel conversion rate because session and order definitions remain unapproved.

## User and candidate session identifiers

`user_pseudo_id` and integer `ga_session_id` were present for all 4,295,584
events, all 354,970 `session_start` events, and all 5,692 purchase events. No
repeated `ga_session_id` parameter, non-integer value, or non-positive value was
observed.

The raw `ga_session_id` is not globally unique: 9,906 session-ID values were
associated with more than one user. Across all events there were 349,545 raw
session IDs but 360,129 distinct candidate `user_pseudo_id` plus `ga_session_id`
keys. This supports, but does not itself approve, the proposed composite session
key.

## Purchase-event and transaction quality

The `purchase` event was used only as an audit population. No final conversion
or order definition was implemented.

| Diagnostic | Observed value |
|---|---:|
| Purchase events | 5,692 |
| Purchase users | 4,419 |
| Null transaction-ID events | 23 |
| Blank transaction-ID events | 0 |
| `(not set)` transaction-ID events | 883 |
| Users associated with `(not set)` | 767 |
| Candidate user–transaction keys including `(not set)` | 5,233 |
| Candidate user–transaction keys excluding null and `(not set)` | 4,466 |
| Valid candidate keys with repeated purchase events | 314 |
| Extra events across those repeated valid keys | 320 |
| Valid duplicated keys with conflicting revenue | 0 |

There were 16 transaction-ID values associated with multiple users. One was the
`(not set)` placeholder; the other 15 show that transaction ID alone is not a
safe order key for this sample. Combining `user_pseudo_id` with a usable
transaction ID avoids these cross-user collisions.

The 314 repeated valid candidate keys contain 634 purchase events. Their finite
revenue values were consistent within each key, so using the maximum observed
revenue would not change revenue within these valid duplicate groups; it would
prevent repeated events from multiplying revenue. The order timestamp rule
remains pending, with the earliest purchase timestamp recommended.

## Revenue quality

At event level, `ecommerce.purchase_revenue` was null for 450 purchase events.
`ecommerce.purchase_revenue_in_usd` was present for every purchase event, but the
same 450 events had a non-positive USD value. After excluding null and `(not
set)` transaction IDs and grouping by candidate user–transaction key, all 4,466
candidate orders had a positive maximum USD revenue.

For this audited population:

- raw finite local purchase revenue: 362,165;
- raw finite USD purchase revenue: 362,165;
- maximum revenue over candidate keys including `(not set)`: 335,986;
- maximum revenue over candidate keys excluding `(not set)`: 308,830.

Local and USD totals reconcile under the audited candidate rules. The USD field
is recommended for a consistent explicit currency, but the owner must approve
the revenue field and the exclusion/deduplication rules before Phase 2.

## Traffic-source availability

The sample has no modern collected or session-last-click structures. First-user
traffic fields are populated on every event, but they describe acquisition and
must not be treated as the source of every later session.

Across all events:

| Candidate field | Nonblank coverage | Placeholder share of all events |
|---|---:|---:|
| Event-parameter source | 33.25% | 4.77% |
| Event-parameter medium | 33.50% | 2.76% |
| Event-parameter campaign | 33.50% | 3.38% |
| Event-parameter page referrer | 26.25% | 0.00% |
| First-user source | 100.00% | 33.52% |
| First-user medium | 100.00% | 21.22% |
| First-user campaign | 100.00% | 25.34% |

On `session_start` events, source, medium, and campaign event parameters had no
usable values. Page referrer was nonblank on 4.57% of `session_start` events.
First-user fields were fully populated there but contained substantial
`<Other>`, `(not set)`, `(data deleted)`, or `unknown` placeholders.

Frequency-ranked values show that event-level source is dominated by internal
or self-referral values, especially `shop.googlemerchandisestore.com`. Common
medium values include `referral`, `organic`, `(none)`, `<Other>`, `(data
deleted)`, `cpc`, `affiliate`, and `email`. The most frequent referrers are also
internal store pages. Referrer inference therefore requires an explicit
self-referral exclusion rule; it cannot be accepted as a generic fallback
without review.

## Acceptance result

All hard Phase 1 acceptance checks passed:

- required schema fields were present in all selected shards;
- all 92 expected dates passed suffix/date validation;
- event names were non-null and purchase events were present;
- user and candidate session identifiers were quantified and reconciled;
- purchase, transaction, duplicate, and revenue issues were quantified;
- traffic-source fields, null rates, placeholders, and sample values were
  produced;
- all jobs were read-only and within the fixed per-query cap.

The audit is complete, but Phase 2 must not start until the immediate decisions
below are approved.

## Decision requests before Phase 2

### 1. Conversion, order identity, and exclusions

- Option A: use `purchase`; key orders by `user_pseudo_id` plus non-null,
  nonblank, non-placeholder transaction ID; exclude the 23 null-ID events and
  883 `(not set)` events.
- Option B: retain placeholder or null-ID purchase events under a separately
  approved surrogate-order rule.
- Recommendation: Option A. It is explicit and reproducible and avoids merging
  767 users under the same `(not set)` identifier.

### 2. Duplicate purchase handling

- Option A: retain the earliest purchase timestamp, use the maximum observed
  revenue per approved order key, and report duplicate counts.
- Option B: use another timestamp or revenue aggregation.
- Recommendation: Option A. The 314 duplicated valid keys had consistent
  revenue, and the rule prevents 320 repeated valid events from multiplying
  revenue.

### 3. User and session key

- Option A: `user_pseudo_id` and the composite `user_pseudo_id` plus
  `ga_session_id` session key.
- Option B: approve a different user or session identity.
- Recommendation: Option A. Both fields are complete, and 9,906 raw session IDs
  collide across users.

### 4. Revenue field

- Option A: `ecommerce.purchase_revenue_in_usd`.
- Option B: `ecommerce.purchase_revenue`.
- Recommendation: Option A for explicit common-currency reporting. Both fields
  produce the same audited eligible total after the recommended exclusions and
  deduplication.

### 5. Session traffic-source priority

- Option A: within each approved candidate session, use the earliest usable
  event-parameter source/medium/campaign; then an external referrer under an
  approved self-referral rule; then first-user traffic source as an explicit
  fallback; finally Direct or Unknown.
- Option B: use first-user traffic source for every session.
- Option C: treat unsupported sessions as Direct or Unknown without a
  first-user fallback.
- Recommendation: Option A, with Phase 2 required to report coverage by fallback
  tier. Option B would incorrectly describe acquisition fields as session
  source. Option C is conservative but may classify too many sessions as
  Direct/Unknown.

### 6. Channel mapping

Channel mapping remains pending. The observed value table should be used to
draft mutually exclusive ordered rules only after the traffic-source priority
is approved. No mapping rule was implemented in this phase.

## Decisions that may remain pending

The lookback window, conversion-cycle boundary, Direct treatment, repeated-
channel compression, non-converting journey construction, simulated costs,
dashboard tool, and final business-recommendation interpretation can remain
pending until their documented later-phase gates.

## Reproducible outputs

The executed evidence is stored under `reports/tables/`, including source
schema, date coverage, event distribution, purchase quality, hashed duplicate
diagnostics, identifier quality, traffic-source availability and samples, query
costs, and validation results.
