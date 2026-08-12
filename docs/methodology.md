# Methodology

Last updated: 2026-08-12

## Current implementation status

Phase 3 rule-based attribution, Phase 4 first-order Markov attribution, and
Phase 5 sensitivity and stability analysis are implemented. The six Phase 5
outputs exist and all 56 Phase 5 checks pass against immutable prior-phase
baselines.

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

## Phase 4 journey and Markov gate

Finalized `conversion_touchpoints` is the sole converting-path source. Each
order becomes `Start -> channel(s) -> Conversion`; the Phase 4 process does not
reconstruct conversion paths from the Session timeline.

Non-converting Sessions are limited to attribution-eligible, non-admin rows.
A journey starts after a valid purchase or at the first observed eligible
Session. It splits when the next Session begins at or after 30 complete days
from the previous `session_end_ts`, or when an intervening valid purchase has
occurred. A purchase at or before inactivity expiry makes that segmented
journey converting. Only the separately finalized conversion paths enter the
Conversion population.

The observation boundary is exclusive `2021-02-01 00:00:00 UTC`. A Null expiry
must be strictly earlier, so a completed Null requires its full 30-day future
horizon inside the observation window. Otherwise the candidate is
right-censored, retained only as an audit row, and excluded from transition
estimation. Journeys starting before `2020-12-01 00:00:00 UTC` remain included
with an explicit left-boundary flag; the flag records incomplete pre-window
history rather than a fully observed journey start.

The executed population contains 4,457 Conversion journeys and 177,632 Null
journeys. The Markov state sequence retains repeated Sessions and channels:

```text
Start -> channel(s) -> Conversion
Start -> channel(s) -> Null
```

Every adjacent transition is counted once. Transition estimation is based on
journey transition counts and is not revenue weighted. Conversion and Null
receive explicit probability-one self-loops. The first-order absorption
probability from Start is `0.024477041446765`, which reconciles to the Markov
journey conversion proportion `4457 / (4457 + 177632)`.

The original removal attempt deleted channel occurrences from paths,
reconnected predecessor and successor, and rebuilt the matrix. It was rejected
after execution because every journey retained its original Conversion or Null
endpoint. The resulting total effect, `2.886579864025407e-15`, was numerical
zero and the normalization gate correctly created no tables.

The final approved Anderl-style removal algorithm operates on the baseline
graph. For each channel `C` independently, it starts from the same original
matrix, removes `C`'s row and column, and redirects every remaining state's
original incoming probability for `C` to Null:

```text
P_removed(i, Null) = P_baseline(i, Null) + P_baseline(i, C)
```

Every other remaining transition probability is preserved and is not
proportionally renormalized. Conversion and Null keep probability-one
self-loops. Each reduced row must sum to one, every transient state must reach
an absorber, and eventual Conversion probability is solved from Start.

The counterfactual treats probability mass that would next enter the removed
channel as non-converting. It does not model substitution by another channel.
The executed effects are all finite and positive, sum to
`1.2126824577935318`, and normalize to one. The global shares are applied to
4,457 conversions and USD 308,208; consequently conversion and revenue shares
are identical in this baseline.

`Unknown` remains separate from Direct. It represents source evidence that
remained unresolved after Phase 2B recovery; it is not a real marketing channel
or a directly actionable budget target.

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
later-phase outputs. All 46 Phase 3 checks pass. Phase 4 revalidated the stored
70-check Phase 2B and 46-check Phase 3 gates plus current model populations
before executing journey diagnostics. Its 70 checks validate the journey
population, censoring, overlap, baseline transition matrix, absorption,
removal effects, normalized attribution, comparison shape, and regressions.
All pass.

## Phase 5 sensitivity and stability

Every deterministic scenario begins independently from the approved baseline;
no scenario stacks two modeling changes.

### Conversion lookback

The approved `conversion_touchpoints` table remains unchanged. A scenario keeps
touchpoints whose `seconds_before_conversion` is at most 7, 14, or 30 complete
days, then recomputes touchpoint numbering and all five Phase 3 formulas. The
primary comparison uses the intersection of orders attributable in every
window. A parallel population-impact view reports each natural scenario
population. Both executed views contain the same 4,457 orders, but remain
explicit to protect future comparisons from denominator drift.

### Null inactivity

The 14-day sensitivity repeats the Phase 4 segmentation with 14 complete
inactivity days from `session_end_ts`. Expiry remains strictly before the
exclusive observation boundary. Finalized Conversion paths remain authoritative.
A completed Null candidate sharing any Session with a finalized Conversion path
is excluded as a whole; right-censored candidates never enter the model.

### Repeated channels and Direct

Consecutive compression replaces adjacent identical channel states with one
state and leaves non-consecutive repeats untouched. The Direct scenario deletes
every Direct state only when another channel exists. Direct-only paths and the
original Conversion/Null endpoints remain unchanged. Newly adjacent identical
non-Direct states are not compressed. This is a Markov path sensitivity, not
the Phase 3 Last Non-direct Click rule.

### User-level cluster bootstrap

Completed Phase 4 journeys are grouped by `user_pseudo_id`. Each of 500
replicates draws all 179,498 users with replacement using NumPy generator seed
`20260812`. A selected user's full set of Conversion and Null journeys enters
with the user's sampling multiplicity. Sparse user-level edge counts rebuild
the transition matrix, approved graph-state removal effects, normalized shares,
and ranks for every replicate. Right-censored journeys are excluded. Failures
are retained with reasons; the executed run has zero failures.

Ranks use descending share and channel name ascending only as a deterministic
secondary key. Exact ties retain a tie flag, so the secondary ordering does not
imply substantive superiority.

Phase 5 remains descriptive. It does not establish causal incrementality,
incremental revenue, or an optimal budget and stops before Phase 6.
