# Decision Register

Last updated: 2026-08-05

This register separates owner-approved analytical definitions from proposals.
The public GA4 sample is used for portfolio analysis and does not represent the
actual business performance of Google Merchandise Store.

## Confirmed decisions

| Decision | Confirmed value | Scope | Confirmed on |
|---|---|---|---|
| Current phase | Phase 2A executed and validated; stop at mapping approval gate | Do not create Phase 2B tables yet | 2026-08-05 |
| GCP project | `ga4-multi-touch-attribution` | Configured execution project | 2026-08-03 |
| BigQuery dataset | `ga4_attribution` | Existing dataset only; do not create another dataset | 2026-08-03 |
| BigQuery location | `US` | All query jobs and destination tables | 2026-08-03 |
| GA4 source | `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` | Public read-only source | 2026-08-03 |
| Configured date range | 2020-11-01 to 2021-01-31 | `_TABLE_SUFFIX` `20201101` through `20210131` | 2026-08-03 |
| Maximum bytes billed | 1,000,000,000 bytes per query | Dry run before every executable query | 2026-08-03 |
| Authentication | Application Default Credentials | Never store or print credentials or tokens | 2026-08-03 |
| Conversion event | `purchase` | Phase 2 core model | 2026-08-05 |
| User identifier | `user_pseudo_id` | Journey and order ownership | 2026-08-05 |
| Session identifier | SHA-256 key over `user_pseudo_id` and `ga_session_id` | Prevent raw session-ID collisions across users | 2026-08-05 |
| Order identifier | SHA-256 key over `user_pseudo_id` and a valid trimmed `transaction_id` | Exclude null, blank, and case-insensitive `(not set)` IDs | 2026-08-05 |
| Order timestamp | Earliest eligible purchase timestamp | Deduplicated order grain | 2026-08-05 |
| Order revenue | Maximum observed `purchase_revenue_in_usd` | Deduplicated order grain | 2026-08-05 |
| Session-source priority | Earliest valid same-event source tuple; earliest external referrer after internal-domain exclusion; first-user fallback; explicit Direct or Unknown | Phase 2 source recovery | 2026-08-05 |
| Direct/Unknown distinction | Explicit `(direct)` source or `(none)` medium is Direct; no reliable evidence is Unknown | Provisional source-resolution output pending mapping approval | 2026-08-05 |
| Baseline lookback | 30 days | Phase 2 conversion paths | 2026-08-05 |
| Conversion cycle | After the previous order and ending at the current order | Phase 2 conversion paths | 2026-08-05 |
| Direct treatment | Retain Direct | Baseline paths | 2026-08-05 |
| Repeated sessions | Retain every distinct Session | Baseline paths | 2026-08-05 |
| Attribution interpretation | Descriptive only, never proof of causal incrementality | Entire project | Mandatory |

## Phase 2A executed evidence

- `event_base` contains 4,295,584 events over 92 dates.
- `orders` contains exactly 4,466 eligible deduplicated orders.
- `session_source_candidates` contains 360,129 unique composite Sessions.
- All 17 Phase 2A validation checks passed.
- Source-resolution coverage is provisional until the internal-domain list and
  channel-mapping decisions below are approved.
- No channel was assigned, and no Phase 2B or attribution output was created.

See `reports/phase2a_core_extraction_and_source_recovery.md` for exact coverage,
query costs, internal-referrer candidates, and mapping predicates.

## Pending decisions at the Phase 2A approval gate

| Decision required | Options | Recommendation | Expected impact / approval gate |
|---|---|---|---|
| Internal registered domain list | Treat `googlemerchandisestore.com` and all subdomains as internal, or approve a narrower host list | Approve the registered domain and its subdomains as internal; keep `google.com` external | Controls external-referrer eligibility. Four observed referrer hosts are covered by the store domain; `www.google.com` supplies 15 provisional external-referrer Sessions. |
| Internal storefront source tuples | Retain storefront-domain `referral` tuples, or exclude them as self-referrals and re-run the source fallback | Exclude and re-resolve them before channel assignment | Affects 70,820 provisional Sessions (19.665176%); retaining them would classify likely self-referrals as Referral under the current proposal. |
| Source-missing referral medium | Treat a valid `referral` medium with null source as Referral, or demote it to Unknown | Retain Referral because the medium is explicit, but label the limitation | Affects 29,400 Sessions (8.163741%). |
| Google administrative referrals | Keep sources such as `analytics.google.com` and `moma.corp.google.com` as Referral, classify as Other, or exclude as operational/internal traffic | Exclude only an explicitly approved administrative-host list; do not exclude all `google.com` traffic | `analytics.google.com` alone affects 3,455 Sessions; broad exclusion could remove legitimate search, mail, support, or content referrals. |
| YouTube/Creator Academy treatment | Classify all YouTube subdomains as Organic Social, or retain content/training subdomains as Referral | Keep `creatoracademy.youtube.com` as Referral and classify ordinary YouTube hosts as Organic Social | The current proposal would classify 889 Creator Academy Sessions as Organic Social. |
| Google referrer inference | Map external `www.google.com` referrers to Organic Search or Referral | Organic Search is defensible, with the inference documented | Affects 15 Sessions (0.004165%). |
| Ordered channel mapping | Approve the 11 exact predicates in the Phase 2A report, with any exceptions above, or provide revised rules | Approve only after resolving the internal and ambiguous-value rows above | Blocks `session_touchpoints` and every conversion path in Phase 2B. |

## Decisions that remain pending after Phase 2A but do not block mapping review

| Decision | When required | Current recommendation |
|---|---|---|
| Same-Session multiple-order handling | Phase 2B path validation | Report separately and avoid silently duplicating a Session across conversion cycles. |
| Non-converting journey definition | Before conversion-plus-non-conversion Markov | Produce a dedicated decision note. |
| Simulated channel costs | Phase 6 | Use owner-supplied simulated parameters only. |
| Dashboard tool | Phase 6 | Decide between approved reporting tools after analytical tables are stable. |
| Business recommendation language | Phase 6 | Keep attribution descriptive and propose an incrementality experiment. |
| BigQuery table retention | Before 2026-10-04 or before long-term handoff | Existing dataset defaults expire Phase 2A tables after 60 days; approve extension/removal only if persistence is needed. |
