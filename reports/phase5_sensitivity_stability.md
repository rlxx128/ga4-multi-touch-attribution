# Phase 5 Sensitivity and Stability — Executed Results

Last updated: 2026-08-12

## Status and scope

Phase 5 is implemented and validated on branch
`phase5-sensitivity-stability`. All six create-only BigQuery outputs exist and
all 56 Phase 5 checks pass. Stored Phase 2B, Phase 3, and Phase 4 validation
gates also remain passing, and the runner verified the same metadata fingerprint
for every prior-phase baseline before and after execution.

This analysis tests descriptive attribution robustness. It does not create a
new attribution model, prove causal incrementality, estimate real marketing
lift, or recommend an actual budget. It uses the public obfuscated GA4 sample
for a portfolio analysis and does not represent actual Google Merchandise Store
performance.

## Scenario contract

| Scenario | Sole changed assumption |
|---|---|
| `P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1` | None; approved Phase 4 reference |
| `P5_A_LB14_V1` | Conversion lookback = 14 days |
| `P5_B_LB7_V1` | Conversion lookback = 7 days |
| `P5_C_NULL14_V1` | Null inactivity = 14 complete days |
| `P5_D_COMPRESS_CONSECUTIVE_V1` | Consecutive identical channels compressed |
| `P5_E_DIRECT_MIXED_OMIT_V1` | Direct omitted from mixed paths, Direct-only fallback retained |
| `P5_F_BOOTSTRAP_USER_500_V1` | User-cluster sampling variation, 500 replicates, seed `20260812` |

Every deterministic scenario starts independently from the approved baseline.
Unknown and Other remain separate technical states in every model.

## Baseline regression

- Total valid orders: 4,466 and USD 308,830.
- Attributable orders: 4,457 and USD 308,208.
- Excluded orders: 9 and USD 622.
- Every Phase 3 model still reconciles to 4,457 conversions and USD 308,208.
- Phase 4 remains 4,457 Conversion journeys, 177,632 completed Null journeys,
  91,594 right-censored journeys, 12 states, and 421,188 observed transitions.
- Baseline Markov journey conversion probability remains
  `0.02447704144676505`.
- Phase 2B checks: 70/70 pass; Phase 3: 46/46; Phase 4: 70/70.

## Conversion-lookback sensitivity

The primary common cohort and secondary population-impact view both contain the
same 4,457 orders and USD 308,208. No order loses all eligible touchpoints at 7
or 14 days because the approved conversion-Session exception supplies an
eligible current conversion Session.

| Lookback | Orders | Revenue | Average path | Median path | Multi-touch share |
|---|---:|---:|---:|---:|---:|
| 7 days | 4,457 | USD 308,208 | 1.763967 | 1 | 38.1647% |
| 14 days | 4,457 | USD 308,208 | 1.946376 | 1 | 43.1681% |
| 30 days | 4,457 | USD 308,208 | 2.148755 | 1 | 47.8573% |

For the primary common cohort:

| Scenario/model | Spearman | Top-3 overlap | Max rank shift | Largest absolute share change |
|---|---:|---:|---:|---:|
| 14d First Click | 1.0000 | 3/3 | 0 | 1.0321 pp |
| 14d Last Click | 1.0000 | 3/3 | 0 | 0.0000 pp |
| 14d Last Non-direct | 1.0000 | 3/3 | 0 | 0.4487 pp |
| 14d Linear | 0.9762 | 3/3 | 1 | 0.4509 pp |
| 14d Time Decay | 1.0000 | 3/3 | 0 | 0.1129 pp |
| 7d First Click | 1.0000 | 3/3 | 0 | 1.3686 pp |
| 7d Last Click | 1.0000 | 3/3 | 0 | 0.0000 pp |
| 7d Last Non-direct | 1.0000 | 3/3 | 0 | 0.8975 pp |
| 7d Linear | 0.9762 | 3/3 | 1 | 0.7399 pp |
| 7d Time Decay | 1.0000 | 3/3 | 0 | 0.2748 pp |

Last Click is exactly invariant because the final conversion Session is present
in every window. The only rank change is a small Linear-model tail swap:
Affiliates moves from rank 8 to 7 and Organic Social from 7 to 8. Both Top-3
sets remain intact. Exact Affiliates/Organic Social ties occur under several
rule models; the stored channel-name secondary order is reproducible only and
does not imply substantive superiority.

## Null-inactivity sensitivity

| Measure | 14 days | 30-day baseline |
|---|---:|---:|
| Completed Null candidates | 232,307 | 177,632 |
| Overlap-excluded candidates | 341 | 0 |
| Final included Null journeys | 231,966 | 177,632 |
| Right-censored journeys | 42,017 | 91,594 |
| Journey conversion probability | 1.885180% | 2.447704% |
| Included average path length | 1.279008 | 1.313089 |
| Included multi-touch share | 16.4333% | 17.7402% |

The completed-outcome population is materially sensitive to inactivity horizon:
the 14-day rule adds 54,334 final Null journeys. Channel allocation is much
more stable: Spearman is 1.0, Top-3 overlap is 3/3, maximum rank shift is zero,
and the largest absolute Markov-share change is Referral at 0.2114 percentage
points.

## Consecutive repeated-channel compression

- Journeys affected: 13,237 of 182,089.
- Repeated states removed: 17,914.
- Channel states: 239,099 to 221,185.
- Observed transitions: 421,188 to 403,274.
- Channel self-transitions: 17,914 to 0.
- Average path length: 1.313089 to 1.214708.
- Multi-touch share: 17.7402% to 13.8943%.
- Spearman: 1.0; Top-3 overlap: 3/3; maximum rank shift: 0.
- Every Markov share is unchanged within floating-point precision; maximum
  absolute difference is approximately `3.9e-14` percentage points.

For this first-order model, self-loop compression changes time spent in a state
but not eventual absorption or normalized graph-state removal shares.

## Direct-treatment sensitivity

The approved sensitivity omits Direct only from mixed-channel paths, retains
Direct-only paths, preserves Conversion/Null endpoints, and does not compress
newly adjacent non-Direct states.

| Rank | Channel | Baseline share | Direct sensitivity | Change |
|---:|---|---:|---:|---:|
| 1 | Organic Search | 40.4496% | 44.2115% | +3.7619 pp |
| 2 | Referral | 23.5271% | 25.5564% | +2.0293 pp |
| 3 | Unknown | 20.8467% | 23.5625% | +2.7158 pp |
| 4 | Direct | 12.6985% | 3.9684% | -8.7301 pp |
| 5 | Paid Search | 1.8908% | 2.0835% | +0.1926 pp |
| 6 | Email | 0.3825% | 0.4007% | +0.0182 pp |
| 7 | Affiliates | 0.1552% | 0.1649% | +0.0097 pp |
| 8 | Organic Social | 0.0491% | 0.0517% | +0.0026 pp |
| 9 | Other | 0.0004% | 0.0005% | +0.0001 pp |

All ranks remain unchanged, but Direct loses 68.75% of its baseline share. This
is the largest deterministic share movement in Phase 5 and shows that Direct's
credit magnitude is highly path-definition-sensitive even though the full
rank ordering is stable.

## User-level cluster bootstrap

The executed baseline contains 179,498 user clusters and 182,089 completed
journeys. Each replicate samples 179,498 users with replacement, includes all
journeys for each sampled user with multiplicity, and rebuilds the transition
matrix and nine graph-state removals locally. All 500 replicates succeed; none
is hidden or discarded.

| Channel | Baseline | Bootstrap mean | 95% percentile interval | Rank range | P(Top 1) | P(Top 3) | P(Top 5) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Organic Search | 40.4496% | 40.3834% | 39.1237%–41.6907% | 1–1 | 100% | 100% | 100% |
| Referral | 23.5271% | 23.5380% | 22.3988%–24.6692% | 2–3 | 0% | 100% | 100% |
| Unknown | 20.8467% | 20.8659% | 19.7747%–21.9284% | 2–3 | 0% | 100% | 100% |
| Direct | 12.6985% | 12.7473% | 11.7740%–13.7000% | 4–4 | 0% | 0% | 100% |
| Paid Search | 1.8908% | 1.8831% | 1.6052%–2.1666% | 5–5 | 0% | 0% | 100% |
| Email | 0.3825% | 0.3794% | 0.2455%–0.5409% | 6–6 | 0% | 0% | 0% |
| Affiliates | 0.1552% | 0.1538% | 0.1115%–0.2098% | 7–8 | 0% | 0% | 0% |
| Organic Social | 0.0491% | 0.0487% | 0.0096%–0.1046% | 7–8 | 0% | 0% | 0% |
| Other | 0.0004% | 0.0004% | 0.0000%–0.0013% | 9–9 | 0% | 0% | 0% |

Referral and Unknown exchange ranks 2/3 in a small number of replicates, but
both remain Top 3 in every replicate. Affiliates and Organic Social exchange
ranks 7/8. Other's interval includes zero, reflecting its extremely sparse path
presence. The removal-effect distribution is retained in both replicate and
summary tables even though the compact report focuses on normalized shares.

## Robustness classification

No arbitrary statistical-significance threshold is used. Classification follows
the observed rank behavior, share movements, and bootstrap ranges.

### Robust conclusions

- Organic Search remains rank 1 across every deterministic Markov scenario and
  all 500 bootstrap replicates.
- The full technical Top 3 remains Organic Search, Referral, and Unknown across
  every deterministic scenario and replicate.
- The actionable presentation order, without renormalizing and excluding only
  Unknown and Other, remains Organic Search, Referral, Direct, Paid Search,
  Email, Affiliates, Organic Social.
- Consecutive compression has no substantive effect on Markov attribution.
- Last Click is invariant to the tested conversion lookbacks.

### Moderately sensitive conclusions

- Conversion lookback materially changes path length and multi-touch share and
  moves First Click, Last Non-direct, Linear, and Time Decay shares, while
  preserving every Top-3 set. Linear swaps only two very small tail channels.
- Null inactivity strongly changes population size and the journey conversion
  proportion, while Markov shares and all ranks remain close to baseline.
- Referral versus Unknown ordering is not perfectly stable under user sampling,
  although both are always Top 3.

### Highly assumption-sensitive conclusions

- Direct's attributed share is highly dependent on whether Direct is retained
  in mixed-channel paths: 12.70% at baseline versus 3.97% under the approved
  omission sensitivity.
- Fine-grained ordering and magnitude for rare tail channels should not support
  business decisions: Affiliates and Organic Social exchange ranks, and Other's
  bootstrap interval reaches zero.

These are descriptive robustness findings, not evidence that any channel causes
the attributed conversions or revenue.

## Technical presentation views

The stored model always retains Unknown and Other. Full-state reporting uses all
nine channels. A separate business-presentation rank may exclude Unknown and
Other without changing or renormalizing any stored share. Unknown must not be
merged into Direct.

## Outputs and validation

| BigQuery object | Rows |
|---|---:|
| `phase5_sensitivity_results` | 276 |
| `phase5_rank_stability` | 187 |
| `phase5_bootstrap_replicates` | 4,500 |
| `phase5_bootstrap_summary` | 9 |
| `phase5_scenario_manifest` | 7 |
| `phase5_validation_summary` | 56 |

All 56 Phase 5 checks pass. They cover prior-phase regressions, scenario
isolation, population and revenue reconciliation, transition and absorbing-state
validity, finite/nonnegative removal effects, normalized shares, common-cohort
consistency, deterministic ranks and ties, bootstrap seed/count/probabilities,
failed-replicate visibility, and unchanged prior-phase metadata.

## Query cost and execution controls

The canonical Phase 5 pipeline processed 119,894,747 bytes and billed
320,864,256 bytes. Every SQL query was dry-run first and individually capped at
1,000,000,000 bytes. The pipeline read only persisted Phase 2B/3/4 tables and
did not scan the public GA4 wildcard. The bootstrap issued no per-replicate
BigQuery queries.

The first result table was created about seven minutes after the guarded worker
started; this elapsed interval includes BigQuery extraction, deterministic
scenario calculations, and all 500 local bootstrap replicates. Peak observed
worker memory during execution was approximately 464 MB.

## Limitations

- The public source is obfuscated and observation is bounded.
- The 30-day baseline retains left-boundary-truncated Null journeys; the 14-day
  scenario has its corresponding shorter left-boundary period.
- Right-censored paths are excluded, so results apply to completed outcomes.
- First-order Markov aggregation loses higher-order context.
- Graph-state removal assumes no channel substitution and is not causal.
- Direct omission reconnects observed neighbors and uses an asymmetric
  Direct-only fallback.
- Percentile intervals describe cluster-sampling variation under this observed
  design; they are not causal confidence intervals.

Phase 5 is complete and stops before Phase 6 pending review.
