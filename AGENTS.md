# AGENTS.md

## 1. Project identity

Project name:

`GA4 Multi-Touch Attribution and Marketing Budget Scenario Analysis`

The project uses the public GA4 ecommerce sample dataset in BigQuery:

`bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

The project reconstructs ecommerce user journeys, compares attribution methods, and produces marketing analysis suitable for a data analyst portfolio.

This is an analytical portfolio project. Do not claim that the results represent the actual business performance of Google Merchandise Store.

## 2. Primary business questions

The project must answer:

1. Which channels commonly appear before a purchase?
2. How do attribution results differ across first-click, last-click, last-non-direct, linear, time-decay, and Markov models?
3. Which channels are relatively overvalued or undervalued by last-click attribution?
4. How stable are attribution results under different path definitions and lookback windows?
5. How could attributed revenue be used in a transparent simulated budget scenario?
6. What additional incrementality experiment would be required before making a causal budget decision?

Attribution must never be described as proof of causal incrementality.

## 3. Working principles

* Never invent query results, model outputs, channel rankings, revenue figures, or business conclusions.
* Distinguish confirmed findings from assumptions and proposed methods.
* Use explicit and reproducible analytical definitions.
* Do not silently choose an unresolved business definition.
* When an unresolved definition materially changes the result, stop and produce:

  * the decision required;
  * available options;
  * the recommended option;
  * expected analytical impact.
* Do not broaden the project scope without approval.
* Complete one phase at a time.
* Do not start an advanced phase until the previous phase passes its acceptance checks.

## 4. Human decision boundary

The human owner must approve decisions concerning:

* conversion definition;
* order deduplication;
* session traffic-source logic;
* channel mapping;
* lookback window;
* conversion-cycle boundaries;
* Direct-channel treatment;
* repeated-channel compression;
* construction of non-converting paths;
* revenue allocation;
* simulated channel costs;
* dashboard tool;
* interpretation of business recommendations.

Codex may recommend a decision and implement alternative comparisons, but must not hide the assumption.

## 5. Technology

Use:

* BigQuery SQL for event cleaning, session construction, conversion-cycle construction, rule-based attribution, and validation;
* Python for path analysis, Markov attribution, bootstrap analysis, model comparison, and figures;
* pytest for Python tests;
* SQL validation queries for data-quality tests;
* Git for version control.

Initial Python environment:

* Python 3.11 or another compatible installed version;
* pandas;
* numpy;
* scipy;
* networkx;
* google-cloud-bigquery;
* google-cloud-bigquery-storage;
* db-dtypes;
* pyarrow;
* matplotlib;
* pytest;
* ruff.

Do not introduce dbt, Streamlit, Shapley libraries, orchestration tools, or deployment infrastructure during the MVP unless explicitly approved.

## 6. Security and cloud rules

* Never create, display, copy, or commit cloud credentials.
* Use Google Application Default Credentials.
* Never commit `.env`, credential JSON files, local authentication files, or notebook secrets.
* Never write to `bigquery-public-data`.
* Only create resources inside the configured project and dataset.
* Ask for approval before:

  * creating a new cloud dataset;
  * deleting a cloud table;
  * replacing a final production-style table;
  * running a query expected to scan a large amount of data;
  * installing an additional production dependency.
* Use dry runs or query estimates where possible.
* Use a maximum-bytes-billed setting for Python-triggered BigQuery queries.
* Every wildcard query must restrict `_TABLE_SUFFIX`.
* Never use `SELECT *` against the full public events wildcard in production SQL.

## 7. Configuration

Do not hard-code the user's project ID.

Read configuration from a local file or environment variables:

* `GCP_PROJECT_ID`
* `BQ_DATASET`
* `BQ_LOCATION`
* `GA4_SOURCE_TABLE`
* `START_DATE`
* `END_DATE`
* `MAXIMUM_BYTES_BILLED`

Commit only an example configuration file.

Default source:

`bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

Default BigQuery location:

`US`

## 8. Repository structure

Maintain this structure:

```text
sql/
  audit/
  staging/
  intermediate/
  marts/
  validation/

src/
  attribution/

tests/
reports/
  figures/
  tables/

notebooks/
dashboard/
docs/
config/
```

SQL files must be numbered in execution order within each phase.

Python business logic belongs in `src/`, not only in notebooks.

Notebooks may call reusable functions from `src/`.

## 9. Data model

The intended analytical layers are:

1. `event_base`

   * one row per GA4 event;
   * extracts required nested parameters;
   * retains event timestamp, user identifier, session identifier, event name, traffic-source fields, device fields, transaction ID, and revenue.

2. `session_touchpoints`

   * one row per user session;
   * session key must combine `user_pseudo_id` and `ga_session_id`;
   * includes session start and end;
   * includes channel classification;
   * includes funnel-event counts.

3. `orders`

   * one row per deduplicated transaction;
   * includes order timestamp, conversion session, and revenue.

4. `conversion_touchpoints`

   * one row per touchpoint per conversion cycle;
   * includes touchpoint order, path length, time before conversion, channel, transaction, and revenue.

5. `attribution_results`

   * one row per transaction, model, and channel;
   * includes attribution weight, attributed conversion, and attributed revenue.

6. `model_comparison`

   * one row per channel;
   * compares all implemented models.

## 10. Default analytical decisions

Until the human owner changes them, use these defaults:

* Conversion event: `purchase`.
* User identifier: `user_pseudo_id`.
* Session identifier: `user_pseudo_id` plus `ga_session_id`.
* Order identifier: `user_pseudo_id` plus non-null `transaction_id`.
* Duplicate purchase revenue: use the maximum observed revenue per deduplicated order and report duplicate counts.
* Baseline lookback window: 30 days.
* Sensitivity windows: 7 and 14 days.
* Conversion cycle: begin after the previous purchase and end at the current purchase.
* Baseline Direct treatment: retain Direct as a channel.
* Also calculate last-non-direct as a separate attribution model.
* Baseline repeated-channel treatment: retain all distinct sessions.
* Conversion value: purchase revenue.
* Budget data: simulated scenario only.
* Markov and rule-based attribution are descriptive attribution methods, not causal estimates.

Flag any data limitation that makes these defaults impossible to implement.

## 11. Traffic-source logic

Do not assume that first-user acquisition source is the source of every session.

Build and document a traffic-source priority rule using the fields actually available in the public sample.

The intended priority is:

1. session- or event-level collected traffic-source information when available;
2. event parameters such as source, medium, and campaign;
3. referrer-based inference where defensible;
4. first-user traffic source only as an explicit fallback;
5. Direct or Unknown when no reliable source is available.

Before implementing the final channel logic:

* inspect field availability;
* quantify null rates;
* show sample values;
* document the selected fallback order;
* produce a decision request if the available data cannot support the intended logic.

## 12. Channel mapping

Keep channel mapping in one reusable SQL or Python configuration.

At minimum consider:

* Direct;
* Organic Search;
* Paid Search;
* Email;
* Organic Social;
* Paid Social, if identifiable;
* Display;
* Referral;
* Affiliates;
* Other;
* Unknown.

Channel rules must be mutually exclusive and ordered.

Create a channel-mapping audit table containing source, medium, assigned channel, and session count.

Do not bury mapping logic across several SQL files.

## 13. Attribution models

MVP models:

1. First click.
2. Last click.
3. Last non-direct.
4. Linear.
5. Time decay.
6. Markov removal effect.

Optional later model:

7. Shapley value.

For every model:

* weights for each transaction must sum to 1 within numerical tolerance;
* total attributed conversions must reconcile to eligible conversions;
* total attributed revenue must reconcile to eligible order revenue;
* excluded orders must be reported with reasons.

## 14. Markov model requirements

Do not implement Markov until rule-based attribution and reconciliation checks pass.

Markov implementation must:

* add `Start`;
* use `Conversion` as an absorbing state;
* add `Null` when non-converting paths are included;
* construct and validate transition probabilities;
* calculate baseline conversion probability;
* remove one channel at a time;
* recompute conversion probability;
* calculate normalized removal effects;
* reconcile attributed conversion and revenue totals.

Clearly document how a removed channel is handled in the path.

Test the implementation on small manually constructed paths with known expected behaviour.

## 15. Non-converting paths

Non-converting paths materially affect Markov results.

Do not silently define them.

Before adding them, produce a decision note covering:

* observation-window definition;
* inactivity cutoff;
* path-ending rule;
* whether users can contribute multiple non-converting journeys;
* how journeys near the dataset boundary are handled.

The first MVP may run Markov on conversion paths only, but the limitation must be explicit.

## 16. Sensitivity analysis

After the baseline models pass validation, compare:

* 7-, 14-, and 30-day lookback windows;
* Direct retained versus last-non-direct treatment;
* repeated sessions retained versus consecutive repeated channels compressed;
* conversion-only versus conversion-plus-non-conversion Markov paths, when available;
* order attribution versus revenue attribution.

Report changes in:

* channel contribution;
* channel ranking;
* average path length;
* multi-touch conversion share;
* top-three channel stability.

## 17. Validation requirements

Create validation checks for:

* event date range;
* missing user identifiers;
* missing session identifiers;
* null and duplicate transaction IDs;
* non-positive purchase revenue;
* duplicate purchase events;
* sessions ending before they start;
* touchpoints occurring after conversion;
* touchpoints outside the lookback window;
* orders with no eligible touchpoint;
* attribution weights not summing to 1;
* attributed revenue not reconciling;
* invalid channel labels;
* transition rows not summing to 1.

A phase is not complete if its validation queries fail.

## 18. Coding standards

SQL:

* use BigQuery Standard SQL;
* use descriptive CTE names;
* list selected fields explicitly;
* comment business assumptions, not obvious syntax;
* qualify table names through configuration or clear placeholders;
* filter table suffixes;
* use `SAFE_DIVIDE` where denominators may be zero;
* avoid unnecessary repeated scans of the public source.

Python:

* use type hints for reusable functions;
* keep functions small and testable;
* raise clear errors for invalid inputs;
* use deterministic random seeds for bootstrap procedures;
* avoid hidden notebook state;
* do not use seaborn;
* save generated figures to `reports/figures/`;
* save important result tables to `reports/tables/`.

## 19. Documentation requirements

Maintain:

* `README.md`: business problem, architecture, setup, main results, limitations;
* `docs/decisions.md`: every approved analytical decision;
* `docs/data_dictionary.md`: derived tables and columns;
* `docs/methodology.md`: attribution formulas and assumptions;
* `reports/analysis_report.md`: findings and recommendations.

Never insert placeholder numeric findings into the final README.

All results must be generated from executed code.

## 20. Phase plan

### Phase 0 — Repository and environment

Deliver:

* repository structure;
* `.gitignore`;
* example configuration;
* dependency file;
* environment-check script;
* BigQuery connection test;
* initial README;
* decision register.

Do not create analytical tables yet.

### Phase 1 — Data audit

Deliver:

* source schema inspection;
* date and event distribution;
* purchase quality checks;
* traffic-source field availability;
* session-ID quality checks;
* audit report.

Stop after producing the audit report and unresolved decisions.

### Phase 2 — Core data model

Deliver:

* `event_base`;
* `session_touchpoints`;
* `orders`;
* `conversion_touchpoints`;
* validation queries;
* data dictionary.

### Phase 3 — Rule-based attribution

Deliver:

* first click;
* last click;
* last non-direct;
* linear;
* time decay;
* reconciliation tests;
* model comparison table.

### Phase 4 — Markov attribution

Deliver:

* Markov input paths;
* transition matrix;
* removal effects;
* tests;
* comparison with rule-based methods.

### Phase 5 — Sensitivity and stability

Deliver:

* lookback-window comparison;
* Direct-treatment comparison;
* repeated-channel comparison;
* bootstrap confidence intervals;
* ranking stability analysis.

### Phase 6 — Business reporting

Deliver:

* funnel and path analysis;
* simulated cost scenarios;
* dashboard-ready tables;
* final figures;
* final README;
* analysis report;
* proposed incrementality experiment.

## 21. Task execution protocol

At the start of every task:

1. Read this file.
2. Read `docs/decisions.md`.
3. Inspect existing code and outputs.
4. State the current phase.
5. List files expected to change.
6. Identify unresolved decisions.
7. Do not modify files until the task scope is clear.

At the end of every task:

1. Summarize files changed.
2. List commands executed.
3. Report tests and validation results.
4. Report unresolved issues.
5. Distinguish completed work from proposed work.
6. Suggest the next single phase.
7. Do not claim success when a command or query was not executed.

## 22. Current instruction

Phases 0 through 5 are completed and validated. The current approved phase is
Phase 6 — Business Reporting.

Do not modify validated Phase 2, Phase 2B, Phase 3, Phase 4, or Phase 5
analytical definitions or outputs. The explicit current-phase task brief
governs Phase 6 execution.

Do not begin post-Phase-6 work without human-owner approval.
