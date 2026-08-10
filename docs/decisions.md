# Decision Register

Last updated: 2026-08-09

This register separates owner-approved analytical definitions from unresolved
choices. The public GA4 sample is used for portfolio analysis and does not
represent the actual business performance of Google Merchandise Store.

## Confirmed decisions

| Decision | Confirmed value | Scope | Confirmed on |
|---|---|---|---|
| Current phase | Phase 3 rule-based attribution executed and validated; stop before Phase 4 | No Markov or later-phase output is approved | 2026-08-09 |
| GCP project | `ga4-multi-touch-attribution` | Configured execution project | 2026-08-03 |
| BigQuery dataset | `ga4_attribution` | Existing dataset only | 2026-08-03 |
| BigQuery location | `US` | Query jobs and destination tables | 2026-08-03 |
| GA4 source | `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` | Public read-only source | 2026-08-03 |
| Date range | 2020-11-01 through 2021-01-31 | `_TABLE_SUFFIX` `20201101` through `20210131` | 2026-08-03 |
| Query guardrail | Dry run plus `maximum_bytes_billed = 1,000,000,000` per query | Every executable query | 2026-08-03 |
| Conversion event | `purchase` | Core model | 2026-08-05 |
| User identifier | `user_pseudo_id` | Journey and order ownership | 2026-08-05 |
| Session identifier | SHA-256 key over `user_pseudo_id` and `ga_session_id` | One composite Session key | 2026-08-05 |
| Order identifier | SHA-256 key over `user_pseudo_id` and valid trimmed `transaction_id` | Excludes null, blank, and case-insensitive `(not set)` | 2026-08-05 |
| Order timestamp and revenue | Earliest eligible purchase timestamp; maximum observed `purchase_revenue_in_usd` | Deduplicated order grain | 2026-08-05 |
| Internal storefront | Exact normalized registered-domain match to `googlemerchandisestore.com`, including all subdomains | Exclude from event, referrer, and first-user source evidence; no substring matching | 2026-08-06 |
| Session source priority | Earliest non-internal same-event tuple; earliest external referrer; non-internal first-user fallback; explicit Direct; Unknown | Rebuilt source candidates | 2026-08-06 |
| Medium-only evidence | Retain null-source `referral` medium as Referral; label `source_missing_flag` and `source_quality = 'medium_only'` | Do not claim a specific referring website | 2026-08-06 |
| Google referrer inference | External `www.google.com` referrer becomes Organic Search | Preserve raw referrer and label inference/tier | 2026-08-06 |
| Internal admin traffic | Exact normalized host match to `analytics.google.com` or `moma.corp.google.com` | Retain as `Internal/Admin`, preserve source fields, set `is_attribution_eligible = FALSE`, and never exclude all `google.com` | 2026-08-06 |
| Creator Academy | `creatoracademy.youtube.com` maps to Referral | Explicit exception before ordinary YouTube social mapping | 2026-08-06 |
| YouTube and paid social | Ordinary YouTube is Organic Social; explicit paid-social evidence is Paid Social | Paid Social remains a valid label even when unobserved | 2026-08-06 |
| Direct and Unknown | Direct requires explicit `(direct)` source or `(none)` medium; missing reliable evidence remains Unknown | Never merge Unknown into Direct | 2026-08-06 |
| Channel mapping | Internal/Admin interception, then first-match-wins marketing order: Direct, Paid Social, Paid Search, Display, Email, Affiliates, Organic Search, Organic Social, Referral, Unknown, Other | Version `phase2b_channel_v2_20260806` | 2026-08-06 |
| Baseline lookback | 30 days | Conversion paths | 2026-08-05 |
| Strict conversion cycle | Strictly after the previous order and through the current order | Preserved as `conversion_touchpoints_strict` after both admin-host exclusions | 2026-08-06 |
| Current conversion-Session exception | The current order's own `conversion_session_key` may cross the previous-order boundary while remaining at/before conversion and inside 30 days | Label every exception; no other historical Session can cross the boundary | 2026-08-06 |
| Direct treatment | Retain Direct | Baseline paths | 2026-08-05 |
| Repeated sessions | Retain every distinct Session; reuse is permitted only for the explicitly flagged current-conversion-Session exception | Phase 2B close-out paths | 2026-08-06 |
| Same-Session multiple orders | Report exception reuse separately; do not call approved exception assignments unqualified reuse violations | Phase 2B exception audit | 2026-08-06 |
| Attribution interpretation | Descriptive only, never proof of causal incrementality | Entire project | Mandatory |
| Phase 3 primary input | `conversion_touchpoints` revised close-out path | Do not substitute `conversion_touchpoints_strict` | 2026-08-09 |
| Time-decay half-life | 7 days, using `0.5 ^ (seconds_before_conversion / 604800)` and within-order normalization | Phase 3 baseline only; no alternative half-life | 2026-08-09 |
| Last Non-direct | Latest channel not exactly Direct; Unknown remains eligible; all-Direct paths fall back to final Direct | No eligible order is dropped for being Direct-only | 2026-08-09 |
| Phase 3 revenue allocation | Apply the same normalized attribution weight to one conversion and `order_revenue_usd` | Reconcile both measures within numerical tolerance | 2026-08-09 |

## Phase 2B executed evidence

- Rebuilt source candidates and `session_touchpoints` each contain 360,129
  unique Sessions.
- `orders` remains exactly 4,466 eligible deduplicated orders.
- All 70,820 storefront-affected provisional Sessions were re-resolved
  individually and reconciled.
- The accepted pre-close-out historical baseline is preserved in audit evidence:
  9,172 touchpoints, 4,043 covered orders, and 423 unmatched orders.
- After both admin exclusions, `conversion_touchpoints_strict` contains 9,155
  rows covering 4,035 orders.
- Revised `conversion_touchpoints` contains 9,577 rows covering 4,457 orders;
  422 of the historical 423 unmatched orders are recovered and 9 final unmatched
  orders are explicitly reported.
- All 70 Phase 2B close-out validation checks passed.
- No First Click, Last Click, Last Non-direct, Linear, Time Decay, Markov,
  Shapley, ROAS, budget, or dashboard output was created.

See `reports/phase2b_core_data_model.md` for the executed coverage, channel,
path, exception, and query-cost results.

## Phase 3 executed evidence

- `attribution_results` contains 27,409 rows at the approved
  `order_key x model x channel` grain.
- `model_comparison` contains one row for each of 8 observed path channels.
- All five models cover all 4,457 attributable orders and each reconciles to
  4,457 attributed conversions and USD 308,208.00.
- All 9 excluded orders and USD 622.00 remain outside every model and visible in
  reconciliation, yielding 4,466 total orders and USD 308,830.00.
- All 70 Phase 2B prerequisite checks and all 46 Phase 3 checks pass.
- No Markov, non-converting-path, sensitivity, bootstrap, Shapley, budget, or
  dashboard output was created.

See `reports/phase3_rule_based_attribution.md` for executed model and channel
results, validation, query cost, and limitations.

## Decisions still pending after Phase 2B

| Decision | When required | Evidence / expected impact |
|---|---|---|
| Repeated-channel compression sensitivity | Phase 5 | Baseline retains every distinct Session; compression would change path length and some model weights. |
| Non-converting journey definition | Before conversion-plus-non-conversion Markov | Requires observation window, inactivity cutoff, path ending, repeat-journey, and right-boundary decisions. |
| Simulated channel costs | Phase 6 | Use owner-supplied simulated parameters only; do not imply observed spend. |
| Dashboard tool | Phase 6 | Decide after analytical tables are stable. |
| Business recommendation language | Phase 6 | Keep attribution descriptive and propose an incrementality experiment. |
| BigQuery table retention | Before the dataset's 60-day default expiry or long-term handoff | Changing expiration metadata requires separate approval. |

## Phase 2B close-out amendment — 2026-08-06

The owner approved `moma.corp.google.com` as a second exact-host Internal/Admin
exception and approved the current conversion-Session boundary exception. The
executed close-out found 77 moma Sessions and 67 users. Under revised temporal
eligibility, moma contributed 18 pre-exclusion touchpoint rows across 16 orders
with USD 1,455 of order revenue; after exclusion, 7 of those orders remain
covered by other marketing touchpoints and 9 orders with USD 622 remain
unmatched.

The conversion-Session exception adds 422 flagged touchpoints over 236 Sessions.
Those Sessions may appear across multiple orders only through the explicit
exception. Unapproved historical Session assignments, duplicate order/Session
rows, post-conversion rows, and lookback violations are all zero.
