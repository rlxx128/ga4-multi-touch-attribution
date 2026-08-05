# Phase 2B Core Data Model

Last updated: 2026-08-06

## Status and scope

Phase 2B is executed and validated. It implements approved Session source
recovery, ordered channel mapping, Session touchpoints, disjoint conversion
cycles, unmatched-order reporting, and exception audits. It stops before Phase
3. No attribution, ROAS, budget, or dashboard output was created.

This is a portfolio analysis of the public obfuscated GA4 ecommerce sample. The
results do not represent actual Google Merchandise Store performance.

## Files changed

- Added the guarded Phase 2B runner: `scripts/run_phase2b.py`.
- Added source recovery, mapping, Session, order-cycle, conversion-path, and
  unmatched-order SQL under `sql/intermediate/`.
- Added the source, domain, channel, path, admin, same-Session, and distribution
  audits under `sql/audit/`.
- Added `sql/validation/02_phase2b_validation.sql` and
  `tests/test_phase2b_runner.py`.
- Updated `README.md`, `docs/decisions.md`, `docs/methodology.md`, and
  `docs/data_dictionary.md`.
- Added this Phase 2B report. Generated CSV review exports remain local-only and
  ignored by Git.

## BigQuery tables created or rebuilt

The following existing provisional tables were replaced after an audit snapshot
was preserved:

| Table | Rows | Result |
|---|---:|---|
| `session_source_candidates` | 360,129 | Approved source resolution, unique Session key |
| `channel_source_coverage_audit` | 5 | Tiers reconcile to 100% |
| `source_medium_campaign_frequency` | 248 | Final frequency/quality audit |

New Phase 2B tables are:

| Table | Rows | Purpose |
|---|---:|---|
| `source_reprocessing_session_audit` | 360,129 | Phase 2A before-values and Phase 2B after-values |
| `internal_domain_rules` | 3 | Storefront, approved admin, and audit-only candidate rules |
| `channel_mapping_rules` | 11 | Ordered versioned channel rules |
| `session_touchpoints` | 360,129 | One row per retained Session |
| `source_reprocessing_summary` | 37 | Before/after source and channel reconciliation |
| `channel_mapping_audit` | 248 | Source tuple to final channel audit |
| `conversion_touchpoints` | 9,172 | Eligible Session/order-cycle rows |
| `order_path_coverage_audit` | 4,466 | One coverage record per eligible order |
| `orders_without_touchpoints` | 423 | Explicit unmatched-order diagnostics |
| `internal_admin_path_impact_audit` | 1 | Admin exclusion impact |
| `admin_domain_candidate_audit` | 1 | `moma.corp.google.com` evidence and impact |
| `same_session_multiple_order_audit` | 236 | Multiple-order conversion Session audit |
| `path_length_distribution_audit` | 13 | Path lengths 0 through 12 |
| `phase2b_validation_summary` | 34 | All checks passed |

`event_base` remains 4,295,584 rows and `orders` remains exactly 4,466 rows;
neither order identity nor revenue logic was changed.

## Final source resolution

The five tiers are mutually exclusive and cover every Session:

| Source-resolution tier | Sessions | Percentage of all Sessions |
|---|---:|---:|
| Event-level source | 142,303 | 39.514452% |
| External referrer | 21 | 0.005831% |
| First-user fallback | 64,606 | 17.939683% |
| Direct | 69,105 | 19.188957% |
| Unknown | 84,094 | 23.351077% |
| **Total** | **360,129** | **100.000000%** |

Direct has explicit `(direct)` or `(none)` evidence. Unknown is retained as a
separate missing-evidence tier.

The rebuild removed every final resolved registered domain equal to
`googlemerchandisestore.com`. Matching uses exact normalized registered-domain
equality and therefore covers all subdomains without a substring predicate.

## Reconciliation of the 70,820 affected storefront Sessions

Every affected Session changed resolution and was run through the full approved
priority. The final source-tier destinations are:

| Final tier | Sessions | Percentage of affected Sessions |
|---|---:|---:|
| Unknown | 41,194 | 58.167184% |
| First-user fallback | 18,239 | 25.754024% |
| Direct | 9,886 | 13.959334% |
| Event-level source | 1,498 | 2.115222% |
| External referrer | 3 | 0.004236% |
| **Total** | **70,820** | **100.000000%** |

Their final channel destinations are:

| Final channel/state | Sessions | Percentage of affected Sessions |
|---|---:|---:|
| Unknown | 41,194 | 58.167184% |
| Organic Search | 13,433 | 18.967806% |
| Direct | 9,886 | 13.959334% |
| Referral | 4,821 | 6.807399% |
| Paid Search | 1,305 | 1.842700% |
| Internal admin, intentionally unmapped | 135 | 0.190624% |
| Affiliates | 33 | 0.046597% |
| Organic Social | 9 | 0.012708% |
| Email | 3 | 0.004236% |
| Other | 1 | 0.001412% |
| **Total** | **70,820** | **100.000000%** |

This confirms that the affected Sessions were not assigned wholesale to Direct
or Unknown.

Across all Sessions, the before-to-after tier changes were: event-level
203,880 to 142,303; external referrer 15 to 21; first-user fallback 53,368 to
64,606; Direct 59,966 to 69,105; and Unknown 42,900 to 84,094.

## Medium-only and inference quality

There are 34,225 null-source Sessions whose resolved medium is explicitly
`referral`: 20,830 event-level and 13,395 first-user fallback Sessions. They are
9.503539% of all Sessions. They remain Referral with
`source_missing_flag = TRUE` and `source_quality = 'medium_only'`; the data does
not identify a specific referral website.

Another 13,218 null-source Sessions have explicit `organic` medium and the same
medium-only quality label. Across both media, 47,443 Sessions are medium-only.

External `www.google.com` inference resolves 21 Sessions to Organic Search. All
21 preserve the external-referrer tier and raw referrer, set
`is_inferred_source = TRUE`, and use
`inference_rule = 'google_referrer_to_organic_search'`.

## Final channel mapping

There are 356,486 marketing-eligible Sessions. The approved first-match mapping
produces:

| Channel | Sessions | Percentage of marketing-eligible Sessions |
|---|---:|---:|
| Organic Search | 150,564 | 42.235600% |
| Unknown | 84,094 | 23.589706% |
| Direct | 69,105 | 19.385053% |
| Referral | 37,563 | 10.537020% |
| Paid Search | 13,250 | 3.716836% |
| Affiliates | 1,399 | 0.392442% |
| Organic Social | 308 | 0.086399% |
| Email | 200 | 0.056103% |
| Other | 3 | 0.000842% |
| Paid Social | 0 | 0.000000% |
| Display | 0 | 0.000000% |
| **Total** | **356,486** | **100.000000%** |

All marketing Sessions have exactly one channel and mapping version
`phase2b_channel_v1_20260806`. Creator Academy contributes 893 Sessions and 832
users to Referral. Paid Social and Display remain legal labels even though no
current Session matches them.

## Administrative and candidate-domain audits

`analytics.google.com` accounts for 3,643 retained Sessions (1.011582% of all
Sessions) and 2,773 users. These Sessions have no marketing channel and never
enter `conversion_touchpoints`. No order has a temporally eligible approved
admin Session, so covered orders remain 4,043 before and after exclusion and
coverage remains 90.528437%; the coverage change is zero.

`moma.corp.google.com` remains audit-only and is not excluded. It appears as
event-level source / referral and final Referral for 77 Sessions and 67 users.
It affects 17 orders and contributes 17 touchpoint rows. Excluding it later
would therefore change path composition and requires a new owner decision. No
broad `google.com` exclusion is applied.

## Order and Session reconciliation

- Eligible deduplicated orders: 4,466.
- Covered orders: 4,043 (90.528437%).
- Orders without touchpoints: 423 (9.471563%).
- Total deduplicated order revenue: USD 308,830.
- Revenue on covered orders: USD 286,611 (92.805427%).
- Revenue on unmatched orders: USD 22,219.
- All 423 unmatched orders have reason `NO_SESSION_AFTER_PREVIOUS_ORDER`.
- Conversion touchpoints: 9,172.
- Duplicate order/Session pairs: 0.
- Touchpoints after conversion, before the 30-day window, or on/before the
  previous-order boundary: 0.
- Sessions reused across order cycles: 0.

There are 236 conversion Sessions associated with multiple orders, representing
658 orders across 219 users. The per-Session order-count distribution is 153
Sessions with 2 orders, 43 with 3, 14 with 4, 10 with 5, 7 with 6, 4 with 7,
2 with 8, 2 with 9, and 1 with 13. Every `session_reuse_violation` flag is false.

## Path-length statistics

- Observed path lengths: 0 through 12 Sessions.
- Average across all 4,466 orders: 2.053739 Sessions.
- Average among the 4,043 covered orders: 2.268612 Sessions.
- Median: 1 across all orders and 2 among covered orders.
- 90th percentile: 4 across all orders and 5 among covered orders.
- One-touch covered orders: 1,909.
- Multi-touch covered orders: 2,134, or 52.782587% of covered orders and
  47.783251% of all eligible orders.

The complete 0-to-12 count and revenue distribution is stored in
`path_length_distribution_audit` and its local-only CSV export.

## Validation

All 34 checks in `phase2b_validation_summary` pass. They include the required
360,129 Session and 4,466 order counts; unique Session keys; 100% source-tier
coverage; 70,820 affected-Session reconciliation; zero final storefront sources;
valid/unique channels; zero admin Sessions in marketing paths; Direct, Unknown,
medium-only, Creator Academy, and Google inference rules; temporal boundaries;
unmatched-order reconciliation; zero Session reuse; and zero forbidden
attribution output tables.

Local tests also pass: 38 total pytest tests, including 12 Phase 2B runner tests.
Scoped Ruff checks for the new Phase 2B runner and tests pass. A repository-wide
Ruff run reports 10 pre-existing Phase 0/1 style findings in files not changed by
Phase 2B; they do not affect the Phase 2B validation result.

## Query safety and bytes

Every executable query was dry-run first and used a per-query
`maximum_bytes_billed` of 1,000,000,000 bytes. The largest accepted dry run was
883,137,495 bytes. Phase 2B reads materialized `event_base`; it does not add an
unbounded public wildcard scan.

The latest canonical execution for each query/recovery step is:

| Query | Dry-run estimate | Actual processed | Actual billed |
|---|---:|---:|---:|
| `01_source_reprocessing_session_audit` | 878,601,757 | 878,601,757 | 878,706,688 |
| `01c_source_reprocessing_audit_rebuild` | 883,137,495 | 883,137,495 | 883,949,568 |
| `01b_source_reprocessing_precheck` | 11,865,139 | 11,865,139 | 12,582,912 |
| `02_session_source_candidates_rebuild` | 831,477,825 | 831,477,825 | 831,520,768 |
| `03_channel_source_coverage_rebuild` | 5,512,871 | 5,512,871 | 10,485,760 |
| `04_source_frequency_rebuild` | 17,874,287 | 17,874,287 | 18,874,368 |
| `05_internal_domain_rules` | 0 | 0 | 0 |
| `06_channel_mapping_rules` | 0 | 0 | 0 |
| `07_session_touchpoints` | 79,959,778 | 79,959,778 | 80,740,352 |
| `08_source_reprocessing_summary` | 75,619,457 | 75,619,457 | 76,546,048 |
| `09_channel_mapping_audit` | 49,048,991 | 49,048,991 | 49,283,072 |
| `10_conversion_touchpoints` | 74,074,283 | 74,074,283 | 74,448,896 |
| `11_order_path_coverage_audit` | 40,238,679 | 40,238,679 | 40,894,464 |
| `12_orders_without_touchpoints` | 857,089 | 857,089 | 10,485,760 |
| `13_internal_admin_path_impact` | 7,853,538 | 7,853,538 | 20,971,520 |
| `14_admin_domain_candidate_audit` | 57,315,074 | 57,315,074 | 57,671,680 |
| `15_same_session_multiple_order_audit` | 1,928,271 | 1,928,271 | 20,971,520 |
| `16_path_length_distribution` | 71,456 | 71,456 | 10,485,760 |
| `17_phase2b_validation_summary` | 114,882,118 | 114,882,118 | 115,343,360 |
| **Canonical/recovery total** |  | **3,130,318,108** | **3,193,962,496** |

The complete local query log contains 47 execution records. Including partial
development runs, corrected rebuilds, prechecks, and final validation, actual
processing was 4,958,958,437 bytes and actual billed bytes were 5,112,856,576.
Dry runs themselves were not billed. A medium-only eligibility defect and an
earlier null-unsafe admin eligibility predicate were corrected, followed by full
source/path reconstruction and validation; the final tables and figures above
come only from the corrected build.

## Commands executed

Significant reproducible commands were:

```powershell
python -m pytest -q
python -m ruff check scripts/run_phase2b.py tests/test_phase2b_runner.py
python scripts/run_phase2b.py
python scripts/run_phase2b.py --execute
python scripts/run_phase2b.py --execute --resume
python scripts/run_phase2b.py --execute --resume --rebuild-derived
python scripts/run_phase2b.py --execute --resume --rebuild-source
python scripts/run_phase2b.py --execute --resume --rebuild-validation
```

The runner exported review tables as ignored local CSV files under
`reports/tables/`. They are intentionally not tracked by Git.

## Unresolved issues and next gate

- Decide whether `moma.corp.google.com` should remain Referral or become an
  excluded administrative host; the exact current impact is documented above.
- Existing BigQuery tables inherit the dataset's 60-day default expiration;
  changing retention needs separate approval.
- Phase 3 attribution models, time-decay settings, and all later sensitivity,
  Markov, cost, budget, and dashboard choices remain unimplemented.

Stop here. The next single phase is Phase 3 rule-based attribution, and it must
not begin without explicit owner approval.
