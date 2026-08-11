# Phase 4 Markov Attribution — Validated Graph-State Removal

Last updated: 2026-08-11

## Status and scope

Phase 4 is implemented and validated using the approved 30-day Null population
and first-order Markov chain. All six create-only BigQuery outputs exist, and
all 70 Phase 4 validation checks pass. Phase 2, Phase 2B, and Phase 3 tables and
finalized conversion paths were not changed.

This is descriptive attribution on the public obfuscated GA4 sample. Removal
sensitivity measures structural path contribution under an explicit graph
counterfactual; it does not estimate causal incrementality or real-world lost
sales.

## Removal decision history

The predecessor-successor reconnect rule was executed first and rejected. It
deleted channel occurrences from each path, reconnected the remaining states,
and preserved every journey's original Conversion or Null endpoint. This made
the baseline absorption probability invariant under deletion: total removal
effect was `2.886579864025407e-15`, numerical zero under the `1e-12` tolerance.
The normalization gate correctly created no tables.

The final approved Anderl-style rule removes a channel state from the original baseline
graph. For channel `C`, every remaining row redirects its original `i -> C`
probability to Null:

```text
P_removed(i, Null) = P_baseline(i, Null) + P_baseline(i, C)
P_removed(i, j) = P_baseline(i, j), for j != C and j != Null
```

The row and column for `C` are dropped. Other probabilities are not
renormalized, Conversion and Null remain absorbing, and every channel removal
starts independently from the same baseline matrix. The interpretation is that
probability mass that would next enter the removed channel becomes
non-converting; real-world channel substitution is not modelled.

## Journey population and regression baseline

| Population | Journeys | Users | Sessions/touchpoints |
|---|---:|---:|---:|
| Finalized Conversion | 4,457 | 3,705 | 9,577 |
| Completed 30-day Null | 177,632 | 177,156 | 229,522 |
| Right Censored | 91,594 | 91,594 | 117,470 |

- Conversion revenue: USD 308,208.
- Completed-outcome journeys used for estimation: 182,089.
- Right-censored journeys used for estimation: 0; all 91,594 remain audit rows.
- Left-boundary completed Null journeys: 77,918, retained with an explicit flag
  for incomplete pre-window history.
- Conversion/Null Session overlap: 0.
- Internal/Admin states: 0.
- Phase 2B checks: 70, failures: 0.
- Phase 3 checks: 46, failures: 0.
- All five Phase 3 models still reconcile to 4,457 conversions and USD 308,208.

## Baseline transition model

The state order is:

1. Start
2. Affiliates
3. Direct
4. Email
5. Organic Search
6. Organic Social
7. Other
8. Paid Search
9. Referral
10. Unknown
11. Conversion
12. Null

The dense baseline matrix is 12 x 12 with 144 cells and 421,188 observed
transitions. Repeated-channel self-transitions are retained. All rows sum to one
within `1e-12`, all transient states can reach an absorber, and Conversion and
Null have explicit probability-one self-loops. Transitions are journey-count
weighted and are not revenue weighted.

The executed Markov journey conversion probability is:

```text
4457 / (4457 + 177632) = 0.02447704144676505
```

This is not a website, user, or GA4 Session conversion rate.

## Removal effects

| Channel | Conversion probability without channel | Removal effect |
|---|---:|---:|
| Affiliates | 0.024430976437189184 | 0.0018819680342516687 |
| Direct | 0.020707750869656410 | 0.15399289923606352 |
| Email | 0.024363502513641756 | 0.004638588914850250 |
| Organic Search | 0.012470437897642385 | 0.49052511412524036 |
| Organic Social | 0.024462471009049445 | 0.000595269560959566 |
| Other | 0.024476923733980440 | 0.000004809109992565119 |
| Paid Search | 0.023915791470445532 | 0.022929649301782540 |
| Referral | 0.017493512706542600 | 0.28530934816656162 |
| Unknown | 0.018289127601560512 | 0.25280481134382971 |

Materially negative effects: 0. Exact-zero effects: 0. Floating-point adjusted
effects: 0. The valid total effect is `1.2126824577935318`.

## Normalized Markov attribution

The global share vector sums to one. It is applied to 4,457 conversions and
USD 308,208. Because one global share vector is used, conversion share and
attributed-revenue share are identical.

| Channel | Markov share | Attributed conversions | Attributed revenue (USD) | Rank |
|---|---:|---:|---:|---:|
| Organic Search | 40.449593% | 1,802.838344 | 124,668.88 | 1 |
| Referral | 23.527128% | 1,048.604073 | 72,512.49 | 2 |
| Unknown | 20.846744% | 929.139394 | 64,251.33 | 3 |
| Direct | 12.698534% | 565.973679 | 39,137.90 | 4 |
| Paid Search | 1.890821% | 84.273873 | 5,827.66 | 5 |
| Email | 0.382506% | 17.048314 | 1,178.92 | 6 |
| Affiliates | 0.155191% | 6.916841 | 478.31 | 7 |
| Organic Social | 0.049087% | 2.187808 | 151.29 | 8 |
| Other | 0.000397% | 0.017675 | 1.22 | 9 |

## Markov versus Last Click

| Channel | Markov conversions | Last Click conversions | Difference | Markov revenue | Last Click revenue | Difference |
|---|---:|---:|---:|---:|---:|---:|
| Affiliates | 6.917 | 2 | +4.917 | 478.31 | 167.00 | +311.31 |
| Direct | 565.974 | 467 | +98.974 | 39,137.90 | 33,722.00 | +5,415.90 |
| Email | 17.048 | 20 | -2.952 | 1,178.92 | 1,659.00 | -480.08 |
| Organic Search | 1,802.838 | 1,855 | -52.162 | 124,668.88 | 128,655.00 | -3,986.12 |
| Organic Social | 2.188 | 2 | +0.188 | 151.29 | 50.00 | +101.29 |
| Other | 0.018 | 0 | +0.018 | 1.22 | 0.00 | +1.22 |
| Paid Search | 84.274 | 61 | +23.274 | 5,827.66 | 3,778.00 | +2,049.66 |
| Referral | 1,048.604 | 1,163 | -114.396 | 72,512.49 | 80,418.00 | -7,905.51 |
| Unknown | 929.139 | 887 | +42.139 | 64,251.33 | 59,759.00 | +4,492.33 |

These differences are attribution redistribution under the approved structural
assumption, not incremental lift.

`Unknown` is the unresolved-source state remaining after Phase 2B source
recovery. It is intentionally separate from Direct, but it is not a real
marketing channel or a directly actionable budget channel.

## BigQuery outputs and validation

| Object | Rows |
|---|---:|
| `markov_journeys` | 273,683 |
| `markov_transition_matrix` | 144 |
| `markov_removal_effects` | 9 |
| `markov_attribution` | 9 |
| `rule_markov_comparison` | 54 |
| `phase4_validation_summary` | 70 |

All 70 Phase 4 checks pass, including population, right-censoring, left-boundary
diagnostics, zero Session overlap, matrix normalization, absorbing-state logic,
removal validity, share/conversion/revenue reconciliation, comparison shape,
and Phase 2B/3 regression.

## Tests and query cost

- Phase 4 Markov and runner tests: 38 passed.
- Full repository suite: 90 passed.
- Python compile checks: passed.
- `git diff --check`: passed.
- Ruff was not available in the existing virtual environment; no dependency
  was installed.

The successful create-and-validate pipeline processed 236,962,012 bytes and
billed 295,698,432 bytes. The final read-only result verification processed
9,658 bytes and billed 41,943,040 bytes. The targeted correction therefore
processed 236,971,670 bytes and billed 337,641,472 bytes in total. All queries
were dry-run first where applicable, enforced the 1,000,000,000-byte cap, used
existing local BigQuery tables, and did not scan the public events wildcard.

The earlier superseded reconnect-rule work processed 400,998,804 bytes and
billed 627,048,448 bytes. Including that preserved analytical history, known
Phase 4 work processed 637,970,474 bytes and billed 964,689,920 bytes.

The final close-out audit independently reread eligible paths, reconstructed
the matrix and all nine counterfactuals, and compared them with persisted
tables. Two read-only attempts (the first stopped on a diagnostic SQL syntax
error) processed 136,486,744 bytes and billed 146,800,640 bytes. No table was
created or modified. Cumulative known Phase 4 processing is therefore
774,457,218 bytes processed and 1,111,490,560 bytes billed.

## Limitations

- Right censoring excludes 91,594 candidate journeys.
- The 77,918 retained left-boundary Null journeys do not have fully observed
  pre-window history.
- Redirecting incoming channel probability to Null assumes no substitution by
  another channel and may overstate dependency when substitution occurs.
- First-order aggregation loses higher-order path context.
- The global share vector makes conversion and revenue shares identical.
- `Unknown` is unresolved source data, not a directly actionable budget channel.
- Markov attribution is structural path contribution, not a causal effect,
  incremental lift, true lost revenue, real-world sales loss, an actual optimal
  budget, or real-world channel substitution.

Phase 4 is complete. Stop before Phase 5 pending review.
