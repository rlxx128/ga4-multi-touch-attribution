# Phase 2B Core Data Model and Close-out

Last updated: 2026-08-06

## Status and scope

Phase 2B close-out is executed and validated. The dated amendment adds the
approved exact-host `moma.corp.google.com` Internal/Admin exception, preserves a
strict path table, and adds only the current order's own conversion-Session
boundary exception to the primary path. No attribution, ROAS, budget, or
dashboard output was created.

This is a portfolio analysis of the public obfuscated GA4 ecommerce sample. The
results do not represent actual Google Merchandise Store performance.

## Git checkpoint before close-out

The accepted pre-close-out Phase 2B implementation was reviewed with no
conflicts, credentials, tracked CSVs, or unintended outputs and committed on the
independent `phase2b-closeout` branch as:

`b7a3644e3ad5757b7e439a92b176b24ee91c2a1d`

The separate main worktree was clean and was not merged, reset, or overwritten.

## Close-out files and BigQuery tables

The close-out adds `channel_mapping_v2.sql`,
`05a_conversion_touchpoints_strict.sql`, and
`25_path_closeout_summary_audit.sql`; updates Session/path/audit/validation SQL,
the guarded runner and tests; and amends the README, decision register,
methodology, data dictionary, and this report.

Created table:

- `conversion_touchpoints_strict`: 9,155 rows.
- `path_closeout_summary_audit`: 1 row.

Rebuilt derived tables:

- `internal_domain_rules`: 3 rows.
- `channel_mapping_rules`: 11 rows.
- `session_touchpoints`: 360,129 rows.
- `source_reprocessing_summary`: 37 rows.
- `channel_mapping_audit`: 248 rows.
- `conversion_touchpoints`: 9,577 rows.
- `order_path_coverage_audit`: 4,466 rows.
- `orders_without_touchpoints`: 9 rows.
- `internal_admin_path_impact_audit`: 3 rows.
- `admin_domain_candidate_audit`: 1 compatibility row, now approved rather
  than candidate status.
- `same_session_multiple_order_audit`: 236 rows.
- `path_length_distribution_audit`: 26 strict/revised rows.
- `phase2b_validation_summary`: 70 rows.

`event_base`, `orders`, source resolution, and the 360,129-Session source
coverage were not changed. `orders` remains exactly 4,466 rows.

## Dated close-out amendment — 2026-08-06

### Exact-host Internal/Admin treatment

Only normalized hosts `analytics.google.com` and `moma.corp.google.com` are
approved Internal/Admin exceptions. No `google.com` registered-domain or
substring exclusion exists.

Matching Sessions retain their original source fields in `session_touchpoints`,
use `channel = 'Internal/Admin'`, have a host-specific
`internal_admin_reason`, and set `is_attribution_eligible = FALSE`. Both strict
and revised paths explicitly exclude them.

| Host | Sessions | Users | Revised pre-exclusion rows | Affected orders before | Revenue before | Orders still covered after | Revenue covered after | Orders lost | Revenue lost |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `analytics.google.com` | 3,643 | 2,773 | 0 | 0 | USD 0 | 0 | USD 0 | 0 | USD 0 |
| `moma.corp.google.com` | 77 | 67 | 18 | 16 | USD 1,455 | 7 | USD 833 | 9 | USD 622 |
| **Distinct total** | **3,720** | **2,840** | **18** | **16** | **USD 1,455** | **7** | **USD 833** | **9** | **USD 622** |

Moma's strict-cycle pre-exclusion impact was 17 rows across 15 orders and USD
1,430. After strict exclusion, 7 of those orders with USD 833 remain covered by
other marketing touchpoints; 8 orders and USD 597 are lost. Admin touchpoint
rows after exclusion are zero in both path variants.

No order is excluded merely for containing an admin Session: the 7 affected
orders with other eligible marketing touchpoints remain covered.

### Historical, strict, and revised paths

The accepted pre-close-out result is reconstructed and hard-validated as the
historical baseline. `conversion_touchpoints_strict` then applies both approved
admin exclusions. The primary path adds only the explicit current-conversion-
Session exception.

| Metric | Historical accepted baseline | Strict after both admin exclusions | Revised primary path |
|---|---:|---:|---:|
| Covered orders | 4,043 | 4,035 | 4,457 |
| Unmatched orders | 423 | 431 | 9 |
| Covered order revenue | USD 286,611 | USD 286,014 | USD 308,208 |
| Order coverage | 90.528437% | 90.349306% | 99.798477% |
| Revenue coverage | 92.805427% | 92.612117% | 99.798595% |
| Touchpoint rows | 9,172 | 9,155 | 9,577 |
| Average path length among covered orders | 2.268612 | 2.268897 | 2.148755 |
| Multi-touch covered orders | 2,134 | 2,133 | 2,133 |
| Multi-touch rate among covered orders | 52.782587% | 52.862454% | 47.857303% |

The exception recovers 422 of the accepted historical 423 unmatched orders.
Eight orders that were historically covered lose their sole moma touchpoint;
one historical unmatched order also has only a moma conversion Session. The
final result is therefore 4,457 covered and 9 unmatched orders.

All 9 unmatched orders, across 8 users and USD 622 revenue, use
`NO_ELIGIBLE_TOUCHPOINT_AFTER_INTERNAL_EXCLUSION`. Eight were historically
covered by moma and one belonged to the historical 423 unmatched population.

### Explicit exception and reuse audit

The revised path adds 422 rows labelled
`CURRENT_CONVERSION_SESSION_EXCEPTION` over 236 Sessions and 219 users. The
same 236 Sessions have 236 standard assignments and 422 exception assignments,
for 658 order assignments in total.

The exception requires `session_key = conversion_session_key`, Session start at
or before conversion, and Session start within 30 days. It may cross only the
previous-order boundary. Results:

- duplicate order/Session rows: 0;
- post-conversion touchpoints: 0;
- lookback violations: 0;
- standard rows crossing the previous-order boundary: 0;
- exception rows not matching the current conversion Session: 0;
- unapproved historical Session assignments: 0;
- strict-path Session reuse across cycles: 0.

Approved exception assignments are reported as explicit exceptions, not as
unqualified Session reuse violations.

## Source and channel reconciliation

Source-resolution tiers remain unchanged and still reconcile to 360,129 unique
Sessions and 100% coverage. There are 3,720 Internal/Admin Sessions. The final
marketing channels are unchanged except that the 77 moma Sessions move from
Referral to Internal/Admin; Referral therefore contains 37,486 Sessions.
Mapping version is `phase2b_channel_v2_20260806`, and path version is
`phase2b_closeout_v1_20260806`.

## Validation

All 70 BigQuery checks pass. In addition to the existing source, order, channel,
and coverage checks, close-out validation confirms:

- exact approved admin hosts and zero broad `google.com` rules;
- all admin Sessions have `Internal/Admin` and are attribution-ineligible;
- no admin rows enter either path table;
- accepted historical 4,043/423/9,172 reconciliation;
- strict and revised order/touchpoint reconciliation;
- zero duplicate, post-conversion, lookback, or invalid-boundary rows;
- every exception matches the current order's conversion Session;
- zero unapproved historical Session reuse;
- 9 unmatched orders reconcile to the required internal-exclusion reason;
- no attribution output table exists.

Local verification passes 38 pytest tests, including 12 Phase 2B runner tests.
Scoped Ruff checks pass, and `git diff --check` passes. Repository-wide Ruff
still reports 10 pre-existing Phase 0/1 findings in files outside this close-out.

## Query safety and cost

Every executable query was dry-run first and used
`maximum_bytes_billed = 1,000,000,000`. The largest close-out query estimate was
118,140,624 bytes. No public wildcard table was rescanned.

The latest successful execution for each final close-out query is:

| Query | Estimated/processed bytes | Actual billed bytes |
|---|---:|---:|
| Source reprocessing precheck | 11,865,139 | 12,582,912 |
| Internal-domain rules | 0 | 0 |
| Channel-mapping rules | 0 | 0 |
| Session touchpoints | 79,959,778 | 80,740,352 |
| Source reprocessing summary | 75,678,207 | 76,546,048 |
| Channel mapping audit | 49,599,918 | 50,331,648 |
| Strict conversion touchpoints | 74,427,789 | 74,448,896 |
| Revised conversion touchpoints | 74,427,789 | 74,448,896 |
| Order path coverage | 41,386,083 | 41,943,040 |
| Orders without touchpoints | 1,500,193 | 10,485,760 |
| Internal admin impact | 35,673,879 | 36,700,160 |
| Moma compatibility audit | 835 | 10,485,760 |
| Explicit Session reuse audit | 3,652,122 | 20,971,520 |
| Path-length distribution | 107,184 | 10,485,760 |
| Path close-out summary | 819,609 | 31,457,280 |
| Validation summary | 118,140,624 | 136,314,880 |
| **Final canonical total** | **567,239,149** | **667,942,912** |

Including the initial partial execution, the corrected full run, and the
audit-only historical-baseline rebuild, the close-out logged 33 successful
query jobs: 1,146,055,451 bytes processed and 1,348,468,736 bytes billed. One
destination-clustering metadata job failed before processing data and reported
no processed or billed byte statistics. It was corrected without deleting a
table by retaining compatibility clustering columns.

## Significant commands

```powershell
python -m pytest -q
python -m ruff check scripts/run_phase2b.py tests/test_phase2b_runner.py
python scripts/run_phase2b.py --execute --resume --closeout
python scripts/run_phase2b.py --execute --resume --closeout-audits
git diff --check
```

Generated CSV review files remain ignored and local-only; no CSV is tracked.

## Remaining decisions and stop gate

- Phase 3 attribution execution is not approved by this close-out.
- Time-decay half-life, non-converting paths, later sensitivity definitions,
  simulated costs, dashboard tool, and business recommendation language remain
  pending at their documented gates.
- Existing BigQuery tables retain the dataset's 60-day default expiration.

Stop after Phase 2B close-out. Do not create attribution outputs.
