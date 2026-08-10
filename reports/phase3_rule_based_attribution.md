# Phase 3 Rule-Based Attribution

Last updated: 2026-08-09

## Status and scope

Phase 3 is executed and validated. It implements only First Click, Last Click,
Last Non-direct Click, Linear, and seven-day Time Decay on the finalized Phase 2B
`conversion_touchpoints` input. No Markov, non-converting-path, sensitivity,
bootstrap, Shapley, budget, or dashboard output was created.

This is descriptive attribution on the public obfuscated GA4 ecommerce sample.
It does not represent actual Google Merchandise Store performance and does not
establish causal incrementality.

## Population reconciliation

| Population | Orders | Revenue |
|---|---:|---:|
| Complete eligible order population | 4,466 | USD 308,830.00 |
| Attributable through revised Phase 2B paths | 4,457 | USD 308,208.00 |
| Excluded after Internal/Admin removal | 9 | USD 622.00 |

All excluded orders retain reason
`NO_ELIGIBLE_TOUCHPOINT_AFTER_INTERNAL_EXCLUSION` and appear in none of the five
attribution models.

## Model reconciliation

| Model | Attributed conversions | Attributed revenue |
|---|---:|---:|
| First Click | 4,457.000000 | USD 308,208.00 |
| Last Click | 4,457.000000 | USD 308,208.00 |
| Last Non-direct Click | 4,457.000000 | USD 308,208.00 |
| Linear | 4,457.000000 | USD 308,208.00 |
| Time Decay | 4,457.000000 | USD 308,208.00 |

The canonical `attribution_results` table contains 27,409 rows at
`order_key x model x channel` grain. Every eligible order appears in every
model. Per-order/model weights and conversions sum to 1, while revenue sums to
the order's `order_revenue_usd` within tolerance.

## Channel-level attributed revenue

| Channel | First Click | Last Click | Last Non-direct | Linear | Time Decay |
|---|---:|---:|---:|---:|---:|
| Direct | 33,212.00 | 33,722.00 | 13,369.00 | 35,155.68 | 34,415.15 |
| Organic Search | 140,228.00 | 128,655.00 | 136,651.00 | 130,030.12 | 130,969.78 |
| Email | 1,000.00 | 1,659.00 | 1,659.00 | 1,401.66 | 1,569.06 |
| Affiliates | 23.00 | 167.00 | 167.00 | 71.00 | 126.70 |
| Organic Social | 16.00 | 50.00 | 50.00 | 33.00 | 33.72 |
| Paid Search | 7,207.00 | 3,778.00 | 4,064.00 | 4,890.52 | 4,515.85 |
| Referral | 78,007.00 | 80,418.00 | 84,338.00 | 77,432.64 | 79,639.06 |
| Unknown | 48,515.00 | 59,759.00 | 67,910.00 | 59,193.38 | 56,938.68 |

These differences show model sensitivity to touchpoint position and timing; they
must not be interpreted as causal channel lift or as a budget recommendation.
Unknown remains separate from Direct and is eligible in Last Non-direct. An
all-Direct path falls back to its final Direct touchpoint. The executed input
contains 205 all-Direct orders, and all 205 pass the explicit fallback check.

## Validation

All 70 Phase 2B prerequisite checks and all 46 Phase 3 checks pass. Phase 3
validation confirms input versions and populations, exact formula reproduction,
unique canonical grain, five-model coverage, per-order and per-model conversion
and revenue reconciliation, the all-Direct fallback, exclusion reconciliation,
channel-comparison reconciliation, zero post-conversion touchpoints, zero
Internal/Admin output rows, and no later-phase tables.

Local verification passes 52 pytest tests, including 14 Phase 3 runner tests.
`git diff --check` passes. Ruff was not available in the existing virtual or
system environment and was not installed.

## Query safety and cost

Every executed query was dry-run first, used Standard SQL with query cache
disabled, and enforced `maximum_bytes_billed = 1,000,000,000`. Phase 3 did not
scan the public wildcard or replace any Phase 2/2B table.

| Query | Estimated / processed bytes | Billed bytes |
|---|---:|---:|
| Phase 2B prerequisite validation | 1,309,961 | 41,943,040 |
| Rule-based attribution | 2,044,517 | 10,485,760 |
| Model comparison | 1,124,009 | 10,485,760 |
| Phase 3 validation | 18,810,261 | 73,400,320 |
| **Canonical execution total** | **23,288,748** | **136,314,880** |

The earlier read-only preflight additionally processed 1,309,961 bytes and
billed 41,943,040 bytes for the prerequisite query. The final read-only model
reconciliation processed 3,348,299 bytes and billed 31,457,280 bytes. Across the
preflight, canonical build, and final reconciliation, 27,947,008 bytes were
processed and 209,715,200 bytes billed. Job-metadata queries processed 0 bytes;
dry runs do not incur query processing charges.

## Limitations and stop gate

- Attribution is descriptive, not causal.
- The baseline uses a fixed seven-day Time Decay half-life; alternatives are not
  evaluated in Phase 3.
- Repeated Sessions and channels are retained and not compressed.
- Unknown source evidence remains a distinct channel.
- Nine orders remain un-attributable after approved Internal/Admin exclusions.

Stop after Phase 3. Markov and all later-phase work require separate approval.
