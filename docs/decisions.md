# Decision Register

Last updated: 2026-08-06

This register separates owner-approved analytical definitions from unresolved
choices. The public GA4 sample is used for portfolio analysis and does not
represent the actual business performance of Google Merchandise Store.

## Confirmed decisions

| Decision | Confirmed value | Scope | Confirmed on |
|---|---|---|---|
| Current phase | Phase 2B executed and validated; stop before Phase 3 | No attribution output is approved | 2026-08-06 |
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
| Internal admin traffic | `analytics.google.com` is internal/administrative | Retain Session, assign no channel, exclude from marketing conversion paths | 2026-08-06 |
| Creator Academy | `creatoracademy.youtube.com` maps to Referral | Explicit exception before ordinary YouTube social mapping | 2026-08-06 |
| YouTube and paid social | Ordinary YouTube is Organic Social; explicit paid-social evidence is Paid Social | Paid Social remains a valid label even when unobserved | 2026-08-06 |
| Direct and Unknown | Direct requires explicit `(direct)` source or `(none)` medium; missing reliable evidence remains Unknown | Never merge Unknown into Direct | 2026-08-06 |
| Channel mapping | First-match-wins order: Direct, Paid Social, Paid Search, Display, Email, Affiliates, Organic Search, Organic Social, Referral, Unknown, Other | Version `phase2b_channel_v1_20260806` | 2026-08-06 |
| Baseline lookback | 30 days | Conversion paths | 2026-08-05 |
| Conversion cycle | Strictly after the previous order and through the current order | Disjoint order cycles | 2026-08-05 |
| Direct treatment | Retain Direct | Baseline paths | 2026-08-05 |
| Repeated sessions | Retain every distinct Session; do not silently reuse a Session across cycles | Phase 2B paths | 2026-08-06 |
| Same-Session multiple orders | Report separately and validate no path reuse | Phase 2B exception audit | 2026-08-06 |
| Attribution interpretation | Descriptive only, never proof of causal incrementality | Entire project | Mandatory |

## Phase 2B executed evidence

- Rebuilt source candidates and `session_touchpoints` each contain 360,129
  unique Sessions.
- `orders` remains exactly 4,466 eligible deduplicated orders.
- All 70,820 storefront-affected provisional Sessions were re-resolved
  individually and reconciled.
- `conversion_touchpoints` contains 9,172 eligible Session/order rows covering
  4,043 orders; 423 orders are explicitly reported without a touchpoint.
- All 34 Phase 2B validation checks passed.
- No First Click, Last Click, Last Non-direct, Linear, Time Decay, Markov,
  Shapley, ROAS, budget, or dashboard output was created.

See `reports/phase2b_core_data_model.md` for the executed coverage, channel,
path, exception, and query-cost results.

## Decisions still pending after Phase 2B

| Decision | When required | Evidence / expected impact |
|---|---|---|
| Whether to exclude `moma.corp.google.com` as administrative traffic | Before changing Phase 2 paths or beginning final attribution inputs | Currently audit-only and not excluded: 77 Sessions, 67 users, 17 affected orders and 17 touchpoint rows. Exclusion would remove those rows and can change path composition. |
| Phase 3 attribution implementation approval | Before any attribution table is created | The core paths pass validation, but no model has been approved for execution in this phase. |
| Time-decay half-life | Before Time Decay implementation | Different half-lives change within-path credit allocation. |
| Repeated-channel compression sensitivity | Phase 5 | Baseline retains every distinct Session; compression would change path length and some model weights. |
| Non-converting journey definition | Before conversion-plus-non-conversion Markov | Requires observation window, inactivity cutoff, path ending, repeat-journey, and right-boundary decisions. |
| Simulated channel costs | Phase 6 | Use owner-supplied simulated parameters only; do not imply observed spend. |
| Dashboard tool | Phase 6 | Decide after analytical tables are stable. |
| Business recommendation language | Phase 6 | Keep attribution descriptive and propose an incrementality experiment. |
| BigQuery table retention | Before the dataset's 60-day default expiry or long-term handoff | Changing expiration metadata requires separate approval. |
