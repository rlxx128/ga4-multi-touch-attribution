# GA4 Multi-Touch Attribution and Marketing Budget Scenario Analysis

This portfolio project uses the public GA4 ecommerce sample in BigQuery to
reconstruct user journeys, compare descriptive attribution methods, and prepare
transparent simulated marketing-budget scenarios.

The project does **not** represent the actual business performance of Google
Merchandise Store. Attribution results will describe observed paths and must not
be interpreted as proof of causal incrementality.

## Current status

Phase 2A created and validated `event_base`, `orders`, provisional Session source
candidates, source-coverage audits, internal-referrer candidates, and an ordered
channel-mapping proposal. The 4,466-order hard reconciliation passed, as did all
17 Phase 2A validation checks. Work is stopped at the required internal-domain
and mapping approval gate; no channel assignment, conversion path, or attribution
model has been created. See
`reports/phase2a_core_extraction_and_source_recovery.md`.

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
sql/audit/           Phase 1 audits and Phase 2A review tables
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
- Session source candidates prioritize event evidence and external referrers;
  first-user acquisition is retained only as an explicitly labelled fallback.
- Internal-domain and ordered channel mapping decisions remain unresolved at the
  Phase 2A approval gate.
- The sample does not provide complete reliable channel spend, so future budget
  work will be a parameterized scenario rather than actual ROAS estimation.
- Descriptive attribution does not estimate causal incrementality.
