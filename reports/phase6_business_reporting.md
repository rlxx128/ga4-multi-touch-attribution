# Phase 6 Business Reporting

Last updated: 2026-08-14

## 1. Business problem

This report translates the validated GA4 journey and attribution outputs into
business-facing evidence. It asks how channel Session quality differs, what
converting journeys look like, how attribution models redistribute credit, and
which results remain stable under the Phase 5 sensitivity and bootstrap tests.

The source is the public obfuscated GA4 ecommerce sample for 2020-11-01 through
2021-01-31. The results are a portfolio analysis and do not represent actual
Google Merchandise Store performance. Attribution is descriptive and is not
proof of causal incrementality.

## 2. Data and attribution scope

- `event_base`: 4,295,584 events.
- Approved Session population: 360,129 Sessions.
- Attribution-eligible marketing population used for the funnel: 356,409
  Sessions across 9 observed channels.
- Eligible deduplicated orders: 4,466 and USD 308,830.
- Attributable orders: 4,457 and USD 308,208.
- Excluded orders: 9 and USD 622, all retained in the upstream exclusion audit.
- Final conversion paths: 9,577 retained Session touchpoints.
- Models compared: First Click, Last Click, Last Non-direct Click, Linear,
  seven-day Time Decay, and first-order Markov.

Session sourcing, channel mapping, conversion cycles, Direct treatment, and
attribution formulas are unchanged from the validated Phase 2B-5 outputs.

## 3. Customer journey overview

The 4,457 attributable conversions have mean path length 2.149 Sessions and
median path length 1. Single-touch paths account for 2,324 conversions
(52.14%); 2,133 conversions (47.86%) are multi-touch.

| Path length | Conversions | Share |
|---:|---:|---:|
| 1 | 2,324 | 52.14% |
| 2 | 838 | 18.80% |
| 3 | 544 | 12.21% |
| 4 | 319 | 7.16% |
| 5 | 193 | 4.33% |
| 6 or more | 239 | 5.36% |

The four most common complete converting paths are single-channel paths:
Organic Search (1,138 conversions), Referral (674), Unknown (276), and Direct
(188). The most common multi-touch path is
`Organic Search > Organic Search` with 153 conversions. There are 693 distinct
stored converting path strings, and the maximum observed path length is 12.

Organic Search is the first touch for 2,111 conversions (47.36%) and the last
touch for 1,855 (41.62%). Referral is the first touch for 1,148 (25.76%) and the
last touch for 1,163 (26.09%). Unknown rises from 645 first touches (14.47%) to
887 last touches (19.90%), which reinforces the need to treat source recovery
as a measurement priority rather than a marketing recommendation.

![Path-length distribution](figures/phase6_path_length_distribution.png)

![Top converting paths](figures/phase6_top_converting_paths.png)

## 4. Channel funnel performance

The funnel metrics are **channel-level funnel stage incidence rates**. Each
numerator counts distinct validated Sessions containing the event, and each
denominator is all attribution-eligible Sessions assigned to the channel. The
rates do not assert a strictly sequential within-Session funnel.

| Channel | Sessions | View item | Add to cart | Checkout | Purchase |
|---|---:|---:|---:|---:|---:|
| Email | 200 | 65.00% | 24.00% | 16.50% | 12.00% |
| Referral | 37,486 | 27.46% | 7.02% | 5.86% | 3.39% |
| Organic Search | 150,564 | 22.80% | 4.32% | 3.27% | 1.34% |
| Unknown | 84,094 | 19.26% | 3.76% | 2.58% | 1.12% |
| Direct | 69,105 | 18.75% | 3.37% | 2.12% | 0.74% |
| Organic Social | 308 | 23.70% | 3.57% | 2.60% | 0.65% |
| Paid Search | 13,250 | 18.13% | 2.85% | 1.67% | 0.51% |
| Affiliates | 1,399 | 14.01% | 2.43% | 1.72% | 0.14% |
| Other | 3 | 33.33% | 0.00% | 0.00% | 0.00% |

Email has the highest observed incidence rates but only 200 Sessions, so its
rates should not be generalized without uncertainty analysis or a larger
sample. Referral combines a much larger base with the strongest purchase
incidence among the higher-volume channels. Organic Search supplies the
largest Session volume and the largest number of purchase-event Sessions.

The 4,838 purchase-event Sessions are not expected to equal the 4,466 valid
deduplicated orders: the funnel counts any eligible Session with a purchase
event, while the order model applies transaction-ID validity and order
deduplication rules.

![Channel funnel stage incidence](figures/phase6_channel_funnel_incidence.png)

## 5. Attribution model comparison

Organic Search ranks first by attributed revenue in all six models. Its share
ranges from 40.45% under Markov to 45.50% under First Click. Model selection
changes credit magnitudes even when the leading channel does not change.

| Channel | Last Click revenue | Markov revenue | Markov minus Last Click | Relative difference |
|---|---:|---:|---:|---:|
| Organic Search | USD 128,655.00 | USD 124,668.88 | USD -3,986.12 | -3.10% |
| Referral | USD 80,418.00 | USD 72,512.49 | USD -7,905.51 | -9.83% |
| Unknown | USD 59,759.00 | USD 64,251.33 | USD +4,492.33 | +7.52% |
| Direct | USD 33,722.00 | USD 39,137.90 | USD +5,415.90 | +16.06% |
| Paid Search | USD 3,778.00 | USD 5,827.66 | USD +2,049.66 | +54.25% |
| Email | USD 1,659.00 | USD 1,178.92 | USD -480.08 | -28.94% |
| Affiliates | USD 167.00 | USD 478.31 | USD +311.31 | +186.41% |
| Organic Social | USD 50.00 | USD 151.29 | USD +101.29 | +202.58% |
| Other | USD 0.00 | USD 1.22 | USD +1.22 | not defined |

Large relative changes for small channels can reflect tiny denominators; the
absolute amounts and sampling uncertainty must remain visible. These deltas
are redistributions of attributed revenue, not incremental revenue.

![Attributed revenue by model](figures/phase6_attribution_revenue_by_model.png)

![Markov versus Last Click](figures/phase6_markov_vs_last_click.png)

## 6. Markov findings

The baseline Markov result assigns 40.45% to Organic Search, 23.53% to
Referral, 20.85% to Unknown, 12.70% to Direct, and 1.89% to Paid Search. The
remaining four states jointly receive less than 0.59%.

Markov's graph-state removal rule redirects probability entering a removed
channel to Null and does not model channel substitution. Its allocations
therefore describe structural path dependency under the approved model, not
the revenue that would actually be lost if a channel were removed.

## 7. Sensitivity and stability evidence

All 500 user-cluster bootstrap replicates succeed.

| Channel | Baseline share | Bootstrap mean | 95% percentile interval | Rank range | P(Top 1) | P(Top 3) |
|---|---:|---:|---:|---:|---:|---:|
| Organic Search | 40.45% | 40.38% | 39.12%-41.69% | 1-1 | 100% | 100% |
| Referral | 23.53% | 23.54% | 22.40%-24.67% | 2-3 | 0% | 100% |
| Unknown | 20.85% | 20.87% | 19.77%-21.93% | 2-3 | 0% | 100% |
| Direct | 12.70% | 12.75% | 11.77%-13.70% | 4-4 | 0% | 0% |
| Paid Search | 1.89% | 1.88% | 1.61%-2.17% | 5-5 | 0% | 0% |

Organic Search ranks first in all four stored deterministic Markov states
(baseline plus three sensitivity transformations) and all 500 bootstrap
replicates. Organic Search, Referral, and Unknown form the Top 3 in every
deterministic scenario and replicate, although Referral and Unknown sometimes
exchange ranks 2 and 3 under bootstrap sampling.

Direct's rank is stable but its magnitude is not: the Phase 5 mixed-path Direct
omission scenario reduces its Markov share from 12.70% to 3.97%. Direct should
therefore not support a magnitude-sensitive recommendation without an explicit
path-treatment qualification.

![Markov bootstrap uncertainty](figures/phase6_markov_bootstrap_uncertainty.png)

## 8. Budget scenario extension

No simulated-spend table, ROAS metric, budget figure, or numeric reallocation
was created. This is an approved omission and not a validation failure. If
reliable channel spend later becomes available, it can be joined by channel and
period to `attribution_business_summary` to compare explicitly labelled
model-dependent ROAS. Such a scenario would still not establish causal return.

## 9. Evidence classification and recommendations

### Robust findings

- Organic Search is rank 1 in every validated deterministic Markov scenario,
  all 500 bootstrap replicates, and all six baseline attribution models.
- Organic Search, Referral, and Unknown form the technical Top 3 across every
  deterministic Markov scenario and bootstrap replicate.
- The attributable population and revenue reconcile in every model to 4,457
  conversions and USD 308,208.

### Directional findings

- Nearly half of attributable conversions are multi-touch, so a last-touch-only
  view omits material observed journey structure.
- Markov allocates more descriptive credit than Last Click to Direct, Unknown,
  and Paid Search, and less to Referral and Organic Search.
- Referral shows the strongest purchase-event incidence among higher-volume
  identifiable channels; Email's stronger rates come from only 200 Sessions.
- Direct's credit magnitude is highly dependent on the approved path treatment.
- Unknown is too large to ignore analytically, but it is not a marketing
  channel and should not receive a budget recommendation.

Recommended descriptive actions are to preserve a multi-model scorecard,
prioritize source-quality investigation for Unknown, display sample sizes with
funnel rates, and use model deltas to select questions for experimentation.

### Requires experimentation

No executed analysis shows that increasing or decreasing investment in any
channel will cause incremental conversions or revenue. Budget reallocation,
incremental ROAS, and substitution effects all require a controlled experiment.

## 10. Limitations

- The public source is short-window, obfuscated, and not actual store reporting.
- Funnel events are independent Session incidences; event order is not tested.
- Small channel bases make some observed rates unstable.
- Unknown is unresolved source evidence rather than an actionable channel.
- Nine orders remain outside attribution after approved exclusions.
- The Markov model is first order, excludes right-censored journeys, retains
  left-boundary-truncated Null paths, and assumes no channel substitution.
- Bootstrap intervals measure user-cluster sampling stability under the
  observed design; they are not causal confidence intervals.
- No reliable spend is available, so there is no observed ROAS or factual
  budget optimum.

## 11. Proposed incrementality experiment

The most actionable directional question is whether Paid Search's higher
Markov allocation relative to Last Click corresponds to incremental value.

- **Business hypothesis:** A controlled increase in Paid Search investment
  produces incremental order revenue beyond business-as-usual activity.
- **Treatment:** A pre-specified, operationally feasible spend increase in
  treatment geographies, fixed before analysis and supported by a power study.
- **Control:** Matched geographies retaining business-as-usual Paid Search.
- **Randomization unit:** Geographic market, region, or DMA; pairs should be
  matched on pre-period revenue, traffic, seasonality, and channel mix before
  random assignment.
- **Primary outcome:** Valid order revenue per geo over the experiment period.
- **Guardrails:** Valid order count, gross margin where available, site
  conversion rate, spend delivery, customer-acquisition cost, brand-query
  cannibalization, and material shifts in other channels.
- **Analysis metric:** Pre-specified geo-level difference-in-differences or a
  covariate-adjusted geo lift estimate. Incremental ROAS may be calculated only
  as estimated incremental revenue divided by verified incremental spend.
- **Validity risks:** Geo spillover, auction interference, seasonality,
  concurrent promotions, tracking changes, treatment non-compliance, insufficient
  power, and heterogeneous effects across markets.

The experiment is a proposal. No experimental result or causal lift is claimed.

## Validation and delivery

Four create-only BigQuery outputs were created:

| Object | Rows |
|---|---:|
| `channel_funnel_summary` | 9 |
| `journey_summary` | 722 |
| `attribution_business_summary` | 54 |
| `phase6_validation_summary` | 42 |

All 42 Phase 6 checks pass. The stored Phase 2B-5 baseline fingerprint remained
`17237893df65b1f0df9ab2266e3dbed26be6f216aa3098a0498b01b72a51218c`
through execution. CSV exports and six presentation-ready figures are available
under `reports/tables/` and `reports/figures/`.
