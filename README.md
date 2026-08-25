# GA4 Multi-Touch Attribution and Marketing Decision Analysis

This portfolio project reconstructs ecommerce journeys from the public
obfuscated GA4 sample in BigQuery, compares six descriptive attribution models,
tests their stability, and publishes business-ready reporting marts and figures.

It does **not** represent the actual business performance of Google Merchandise
Store. Attribution describes how observed conversion credit changes under a
model; it is not proof of causal incrementality.

## Business questions

1. How does Session-level funnel activity differ by channel?
2. What do converting journeys look like?
3. How do First Click, Last Click, Last Non-direct Click, Linear, Time Decay,
   and Markov attribution redistribute conversions and revenue?
4. Which findings remain stable under path-definition sensitivity and
   user-cluster bootstrap analysis?
5. What should be treated as descriptive evidence, and what requires an
   incrementality experiment before a budget decision?

## Headline results

The executed reporting population contains:

- 356,409 attribution-eligible Sessions;
- 4,457 attributable orders;
- USD 308,208 attributable revenue;
- 9,577 retained conversion touchpoints;
- 2,324 single-touch conversions (52.14%);
- 2,133 multi-touch conversions (47.86%);
- mean path length 2.149 and median path length 1.

Organic Search ranks first by attributed revenue in all six baseline models. It
also ranks first in all validated deterministic Markov scenarios and all 500
user-cluster bootstrap replicates. Its baseline Markov share is 40.45%, and the
bootstrap 95% percentile interval is 39.12%-41.69%.

The stable technical Markov Top 3 is Organic Search, Referral, and Unknown.
Unknown is unresolved source evidence, not an actionable marketing channel.

Markov redistributes attributed revenue versus Last Click toward Direct
(USD +5,415.90), Unknown (USD +4,492.33), and Paid Search (USD +2,049.66), and
away from Referral (USD -7,905.51) and Organic Search (USD -3,986.12). These
differences are model allocation, not incremental revenue.

![Markov versus Last Click](reports/figures/phase6_markov_vs_last_click.png)

## Channel funnel

The funnel output reports **channel-level funnel stage incidence rates**. Each
metric counts distinct validated Sessions containing the event and divides by
all attribution-eligible Sessions for the channel. Event order is not inferred,
so the metrics are not strictly sequential within-Session conversion rates.

Referral combines 37,486 Sessions with 3.39% purchase-event Session incidence.
Organic Search supplies the largest volume at 150,564 Sessions and has 1.34%
purchase incidence. Email's 12.00% purchase incidence is based on only 200
Sessions and should not be generalized without more data.

![Channel funnel stage incidence](reports/figures/phase6_channel_funnel_incidence.png)

## Customer journeys

The most common complete converting path is Organic Search only, with 1,138
conversions (25.53%). Referral only contributes 674, Unknown only 276, and
Direct only 188. The most common multi-touch path is
`Organic Search > Organic Search` with 153 conversions.

![Converting path length](reports/figures/phase6_path_length_distribution.png)

![Top converting paths](reports/figures/phase6_top_converting_paths.png)

## Stability and interpretation

Robust findings are supported across deterministic sensitivity scenarios and
the 500-replicate user-cluster bootstrap. Directional findings describe journey
or model structure but depend on assumptions. Any claim about incremental
conversions, incremental revenue, or changing investment requires an
experiment.

Direct illustrates this boundary: it remains rank 4, but its Markov share falls
from 12.70% to 3.97% when Direct is omitted from mixed paths in the approved
sensitivity. A stable rank does not guarantee a stable magnitude.

![Markov bootstrap uncertainty](reports/figures/phase6_markov_bootstrap_uncertainty.png)

## Reporting outputs

Phase 6 created four create-only BigQuery tables:

| Table | Grain | Rows |
|---|---|---:|
| `channel_funnel_summary` | one observed attribution-eligible channel | 9 |
| `journey_summary` | one tagged journey summary member | 722 |
| `attribution_business_summary` | one channel and attribution model | 54 |
| `phase6_validation_summary` | one Phase 6 acceptance check | 42 |

All 42 Phase 6 checks pass. The pipeline verifies all stored Phase 2B-5 gates,
records a metadata fingerprint before execution, dry-runs every material query,
uses a 1 GB per-query billing cap, and verifies that all upstream table metadata
remains unchanged.

Dashboard-ready CSV exports are written to `reports/tables/`; six
presentation-ready figures are written to `reports/figures/`. No dashboard tool
is embedded, so the marts can be consumed later by Power BI, Looker Studio,
Tableau, or another BI client.

No simulated-spend table, ROAS calculation, or numeric budget recommendation
was created. Reliable future spend may be joined to the attribution mart for an
explicitly model-dependent extension.

## Proposed causal follow-up

The report proposes a matched-geo randomized Paid Search lift test. Treatment
geographies would receive a pre-specified feasible spend increase while matched
controls remain at business as usual. Valid order revenue per geo would be the
primary outcome, analyzed with a pre-specified difference-in-differences or
covariate-adjusted geo lift estimator. Incremental ROAS would be reported only
from verified incremental revenue and spend.

No experimental result is fabricated or implied.

## Architecture

```text
Public GA4 events_*
        |
        v
event_base -> session_touchpoints -> orders / conversion_touchpoints
                                      |
                                      +-> five rule-based models
                                      +-> Markov journeys and removal effects
                                      +-> Phase 5 sensitivity and bootstrap
                                      +-> Phase 6 business reporting marts
```

BigQuery SQL performs event cleaning, Session/path construction, rule-based
attribution, and validation. Python implements Markov calculations, sensitivity
analysis, bootstrap procedures, report exports, and matplotlib figures. Reusable
logic lives under `src/attribution/`; notebooks are not required for execution.

## Repository layout

```text
config/              Non-sensitive configuration examples
docs/                Decisions, methodology, and data dictionary
reports/              Executed business reports, figures, and local CSV exports
scripts/              Guarded phase runners and environment checks
sql/audit/            Data-quality and business-rule audits
sql/staging/          Event-grain model
sql/intermediate/     Session, conversion-path, and scenario models
sql/marts/            Attribution and business reporting marts
sql/validation/       Executable phase acceptance checks
src/attribution/      Reusable Markov, sensitivity, and reporting logic
tests/                Python and runner contract tests
```

## Reproduce locally

Python 3.11 or a compatible later version is required. Install the declared
dependencies in an approved virtual environment. The project uses Google
Application Default Credentials and never stores cloud credentials.

Set the required environment variables:

```powershell
$env:GCP_PROJECT_ID = "ga4-multi-touch-attribution"
$env:BQ_DATASET = "ga4_attribution"
$env:BQ_LOCATION = "US"
$env:GA4_SOURCE_TABLE = "bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*"
$env:START_DATE = "2020-11-01"
$env:END_DATE = "2021-01-31"
$env:MAXIMUM_BYTES_BILLED = "1000000000"
```

Run the Phase 6 preflight without creating objects:

```powershell
python scripts/run_phase6.py
```

Create the approved outputs only when they do not already exist:

```powershell
python scripts/run_phase6.py --execute
```

If execution stops after an exact create-only prefix, resume without replacing
any table:

```powershell
python scripts/run_phase6.py --execute --resume
```

Run the complete test suite:

```powershell
python -m pytest -q
```

## Documentation

- [Business reporting](reports/phase6_business_reporting.md)
- [Executive analysis](reports/analysis_report.md)
- [Methodology](docs/methodology.md)
- [Decision register](docs/decisions.md)
- [Data dictionary](docs/data_dictionary.md)

## Limitations

- The public sample is obfuscated, time-bounded, and not actual store reporting.
- Session-source recovery uses explicit fallbacks and leaves Unknown separate.
- Funnel stages are independent Session incidences, not ordered conversions.
- Nine valid orders have no attribution-eligible touchpoint after exclusions.
- The Markov model is first order and its removal rule assumes no channel
  substitution.
- Right-censored journeys are excluded; left-boundary-truncated Null journeys
  remain flagged.
- Bootstrap intervals describe sampling stability, not causal uncertainty.
- Reliable channel spend is absent, so no observed ROAS or budget optimum is
  reported.
- Descriptive attribution does not estimate causal incrementality.
