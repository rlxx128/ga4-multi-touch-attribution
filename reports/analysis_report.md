# GA4 Multi-Touch Attribution — Business Analysis

Last updated: 2026-08-14

## Executive summary

The validated analysis covers 356,409 attribution-eligible Sessions and 4,457
attributable orders worth USD 308,208 in the public obfuscated GA4 ecommerce
sample. Organic Search is the most prominent descriptive channel: it ranks
first in all six attribution models, every deterministic Markov sensitivity
scenario, and all 500 user-cluster bootstrap replicates.

This stability does not mean additional Organic Search investment would cause
the largest incremental revenue. The project measures observed journey credit,
not causal lift.

## Customer journeys

- Mean converting path length: 2.149 Sessions; median: 1.
- Single-touch conversions: 2,324 (52.14%).
- Multi-touch conversions: 2,133 (47.86%).
- Most common path: Organic Search only, 1,138 conversions (25.53%).
- Organic Search is the first touch for 47.36% and last touch for 41.62% of
  attributable conversions.

These results show that both single-channel and multi-touch journeys matter.
Last Click is useful as a baseline but should not be the only reporting view.

## Channel Session quality

Funnel metrics are independent Session-level stage incidences, each divided by
all attribution-eligible Sessions for the channel. They are not sequential
conversion rates.

Referral combines scale (37,486 Sessions) with a 3.39% purchase-event Session
incidence. Organic Search provides the largest volume (150,564 Sessions) and a
1.34% purchase incidence. Email records 12.00%, but its base is only 200
Sessions; Other has only 3 Sessions. Sample size must accompany every rate.

## Attribution comparison

Markov reallocates revenue versus Last Click toward Direct (USD +5,415.90),
Unknown (USD +4,492.33), and Paid Search (USD +2,049.66), while reallocating
away from Referral (USD -7,905.51) and Organic Search (USD -3,986.12). These are
model allocations, not incremental gains or losses.

The Markov Top 3 is Organic Search (40.45%), Referral (23.53%), and Unknown
(20.85%). Unknown is a measurement state, not a budget channel. Direct retains
rank 4 but falls from 12.70% to 3.97% when omitted from mixed paths in the
approved Phase 5 sensitivity, so its magnitude is assumption-sensitive.

## Evidence categories

### Robust findings

- Organic Search ranks first across all validated models, deterministic Markov
  scenarios, and 500 bootstrap replicates.
- Organic Search, Referral, and Unknown are Top 3 in every deterministic Markov
  scenario and bootstrap replicate.
- Every model reconciles to 4,457 conversions and USD 308,208.

### Directional findings

- 47.86% of attributable conversions contain multiple Session touchpoints.
- Paid Search receives 54.25% more attributed revenue under Markov than Last
  Click, but the absolute difference is USD 2,049.66.
- Referral has the strongest observed purchase incidence among higher-volume
  identifiable channels.
- Direct's share magnitude depends strongly on path treatment.
- Unknown source volume warrants measurement remediation.

### Requires experimentation

Claims about incremental conversions, incremental revenue, optimal spend, or
the causal effect of changing investment are unsupported by attribution alone.

## Recommendations

1. Use the six-model long-form mart as a scorecard instead of treating Last
   Click as ground truth.
2. Investigate Unknown source recovery before using its large descriptive share
   in channel decisions.
3. Always show Session bases alongside funnel incidence rates.
4. Treat Direct and rare-channel magnitudes as assumption-sensitive.
5. Use an incrementality experiment—not an attribution rank—to evaluate a
   real budget change.

## Incrementality experiment proposal

Run a matched-geo randomized Paid Search lift test. Treatment geographies
receive a pre-specified feasible spend increase; control geographies remain at
business as usual. Use valid order revenue per geo as the primary outcome and a
pre-specified difference-in-differences or covariate-adjusted geo lift estimate.
Monitor order count, margin where available, conversion rate, acquisition cost,
spend delivery, cannibalization, and cross-channel shifts. Address spillover,
auction interference, seasonality, concurrent promotions, non-compliance, and
power before interpreting incremental ROAS.

## Spend extension and limitations

No simulated spend or ROAS was created. Reliable future spend could be joined
to `attribution_business_summary` for explicitly model-dependent evaluation,
but causal budget conclusions would still require experimentation.

The dataset is public, obfuscated, and bounded; funnel stages are not ordered;
small channel samples are unstable; Unknown is not actionable; nine orders are
unattributed; Markov is first order and assumes no substitution; and bootstrap
intervals describe sampling stability rather than causal uncertainty.

Detailed results, figures, methods, and validation are in
`reports/phase6_business_reporting.md`.
