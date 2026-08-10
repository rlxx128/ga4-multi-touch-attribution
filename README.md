# GA4 Multi-Touch Attribution and Marketing Budget Scenario Analysis

This portfolio project uses the public GA4 ecommerce sample in BigQuery to
reconstruct user journeys, compare descriptive attribution methods, and prepare
transparent simulated marketing-budget scenarios.

The project does **not** represent the actual business performance of Google
Merchandise Store. Attribution results will describe observed paths and must not
be interpreted as proof of causal incrementality.

## Current status

Phase 3 rule-based attribution is implemented and validated on the finalized
Phase 2B revised conversion paths. First Click, Last Click, Last Non-direct
Click, Linear, and seven-day Time Decay each reconcile to 4,457 attributable
orders and USD 308,208.00. Nine orders with USD 622.00 remain explicitly
excluded, reconciling to the complete 4,466-order / USD 308,830.00 population.
All 70 Phase 2B prerequisite checks and all 46 Phase 3 checks pass. Work is
stopped before Phase 4 Markov attribution. See
`reports/phase3_rule_based_attribution.md`.

## Data source

```text
bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
```

Configured analysis range: 2020-11-01 through 2021-01-31. The public sample is
obfuscated and may contain null, blank, or internally inconsistent fields.

## Repository layout

```text
config/              Non-sensitive configuration examples
dashboard/           Future dashboard assets
docs/                Project specification and decision register
notebooks/           Thin analysis notebooks built on reusable source code
reports/figures/     Generated figures for reporting
reports/tables/      Generated result tables for reporting
scripts/             Environment, audit, and guarded build runners
sql/audit/           Data-quality, source, mapping, and path audits
sql/staging/         Staging models
sql/intermediate/    Intermediate models
sql/marts/           Reporting models
sql/validation/      SQL data-quality checks
src/attribution/     Reusable Python business logic
tests/               Python tests
```

## Local setup

Python 3.11 or a compatible later version is required. Create a virtual
environment and install `requirements.txt` only after installation is approved.
This repository never stores cloud credentials; Google Application Default
Credentials (ADC) are used for authentication.

In the user's normal VS Code PowerShell environment, `gcloud` and `bq` are
available on `PATH`. The restricted Codex execution environment did not inherit
that same `PATH`, so the Phase 0 diagnostic used the known Google Cloud SDK
installation path as a fallback. The gcloud logging permission warning observed
during inspection is specific to that restricted environment and is not recorded
as a normal VS Code PowerShell issue.

ADC is available and has quota project `ga4-multi-touch-attribution`. The project
scripts nevertheless require `GCP_PROJECT_ID` to be supplied explicitly; they do
not infer the execution project from ADC or embed it in source code.

Set the required variables in the current shell. The committed `.env.example`
and `config/project.example.yaml` contain non-sensitive examples only. Scripts
read environment variables directly and do not automatically load `.env` files.

```powershell
$env:GCP_PROJECT_ID = "ga4-multi-touch-attribution"
$env:BQ_DATASET = "ga4_attribution"
$env:BQ_LOCATION = "US"
$env:GA4_SOURCE_TABLE = "bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*"
$env:START_DATE = "2020-11-01"
$env:END_DATE = "2021-01-31"
$env:MAXIMUM_BYTES_BILLED = "1000000000"
```

Run the local diagnostic:

```powershell
python scripts/check_environment.py
```

Run the bounded BigQuery connection test:

```powershell
python scripts/test_bigquery_connection.py
```

The connection test uses ADC, reads only the `20201101` source suffix, performs
a dry run first, enforces a 1,000,000,000-byte billing ceiling, and executes only
a `SELECT` query. It does not create or modify cloud resources.

Run Phase 2A preflight only:

```powershell
python scripts/run_phase2a.py
```

Run the new-table build only after approval:

```powershell
python scripts/run_phase2a.py --execute
```

The runner refuses to replace existing target tables. It supports
`--execute --resume` only when existing Phase 2A tables form a validated,
incomplete execution prefix. Every query is dry-run first and uses the configured
maximum-bytes-billed ceiling.

The approved Phase 2B runner is resumable and dry-runs every query before
execution:

```powershell
python scripts/run_phase2b.py --execute
```

Recovery flags such as `--rebuild-source`, `--rebuild-derived`, and
`--rebuild-validation` require both `--execute` and `--resume`; they exist for
auditable rebuilds after an implementation correction and should not be used as
ordinary first-run options.

Run the create-only Phase 3 preflight:

```powershell
python scripts/run_phase3.py
```

After approval, create and validate the three Phase 3 outputs:

```powershell
python scripts/run_phase3.py --execute
```

The Phase 3 runner consumes `conversion_touchpoints`, dry-runs every query,
enforces the 1,000,000,000-byte ceiling, and refuses to replace an existing
Phase 3 output.

## Analytical phases

1. Repository and environment
2. Data audit
3. Core data model
4. Rule-based attribution
5. Markov attribution
6. Sensitivity and stability
7. Business reporting

Each phase must pass its validation checks before the next phase begins. See
`docs/decisions.md` for confirmed configuration, suggested defaults, and choices
that still require human approval. Planned schemas and analytical methods are
documented in `docs/data_dictionary.md` and `docs/methodology.md`.

## Limitations

- The public data covers a short, obfuscated observation window.
- Session sources prioritize non-internal event evidence and external referrers;
  first-user acquisition is retained only as an explicitly labelled fallback.
- Missing-source referral media are retained as Referral with a quality flag;
  they do not identify a specific referring website.
- Exact hosts `analytics.google.com` and `moma.corp.google.com` are retained as
  Internal/Admin Sessions but excluded from attribution paths.
- The current order's own conversion Session can cross the previous-order
  boundary only through an explicit, validated exception flag.
- Nine eligible orders have no remaining attribution-eligible touchpoint after
  Internal/Admin exclusion.
- Time Decay uses the approved fixed seven-day half-life; alternative half-lives
  are outside Phase 3.
- Last Non-direct excludes only explicit Direct. Unknown remains eligible, and
  an all-Direct path falls back to its final Direct touchpoint.
- The sample does not provide complete reliable channel spend, so future budget
  work will be a parameterized scenario rather than actual ROAS estimation.
- Descriptive attribution does not estimate causal incrementality.
