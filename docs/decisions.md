# Decision Register

Last updated: 2026-08-03

This register separates decisions explicitly confirmed by the project owner
from analytical defaults that are only recommended. A suggested default remains
unapproved until it is moved to the confirmed section with an approval date.

## Confirmed decisions

| Decision | Confirmed value | Scope | Confirmed on |
|---|---|---|---|
| Current phase | Phase 0 only | Repository and environment setup | 2026-08-03 |
| GCP project | `ga4-multi-touch-attribution` | Local configuration and read-only checks | 2026-08-03 |
| BigQuery dataset | `ga4_attribution` | Dataset metadata check; no resource changes | 2026-08-03 |
| BigQuery location | `US` | Client and dataset validation | 2026-08-03 |
| GA4 source | `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` | Public read-only source | 2026-08-03 |
| Configured date range | 2020-11-01 to 2021-01-31 | Project configuration | 2026-08-03 |
| Maximum bytes billed | 1,000,000,000 bytes | Python-triggered BigQuery queries | 2026-08-03 |
| Authentication | Application Default Credentials | Never store or print credentials or tokens | 2026-08-03 |
| Phase 0 connection test | Read-only, suffix `20201101` only | No table or dataset changes | 2026-08-03 |
| Git operation | Initialize locally; do not commit automatically | Phase 0 repository setup | 2026-08-03 |
| Dependency operation | Create `requirements.txt`; do not install packages | Phase 0 only | 2026-08-03 |

## Confirmed local environment notes

- In the user's normal VS Code PowerShell environment, `gcloud` and `bq` are
  available on `PATH`.
- The restricted Codex execution environment did not inherit that same `PATH`;
  its Phase 0 check used the installed Google Cloud SDK path as a fallback.
- The gcloud logging permission warning observed during inspection is specific
  to the restricted Codex environment.
- Application Default Credentials are available and have quota project
  `ga4-multi-touch-attribution`.
- Project scripts still require `GCP_PROJECT_ID` to be provided explicitly and
  do not rely on ADC to select the execution project.

The project-wide constraint that attribution is descriptive and not evidence of
causal incrementality is mandatory, not an optional modeling choice.

## Suggested defaults — not yet approved as business decisions

| Decision | Suggested default | Expected analytical impact |
|---|---|---|
| Conversion event | `purchase` | Defines the eligible conversion population. |
| User identifier | `user_pseudo_id` | Preserves anonymous cross-session journeys within the sample. |
| Session identifier | `user_pseudo_id` plus `ga_session_id` | Prevents collisions between users sharing a session ID value. |
| Order identifier | `user_pseudo_id` plus non-null `transaction_id` | Defines order uniqueness and exclusion rules. |
| Duplicate purchase revenue | Maximum observed revenue per deduplicated order; report duplicate counts | Avoids multiplying revenue when a purchase event is duplicated. |
| Baseline lookback | 30 days; compare 7 and 14 days later | Longer windows can increase path length and early-channel credit. |
| Conversion-cycle boundary | Begin after the previous purchase and end at the current purchase | Prevents old touchpoints from being reused across consecutive orders. |
| Direct treatment | Retain Direct in the baseline; calculate last-non-direct separately | Makes Direct contribution visible while enabling a standard comparison. |
| Repeated channels | Retain all distinct sessions in the baseline | Preserves observed visits but may favor high-frequency channels. |
| Conversion value | Purchase revenue | Supports both conversion-count and revenue attribution. |
| Budget data | Simulated scenario only | Prevents simulated costs from being described as actual spend or ROAS. |
| Markov MVP input | Conversion paths may be used first with the limitation stated | Avoids silently inventing non-converting journey rules. |

## Pending decisions requiring human confirmation

| Decision required | Options | Recommendation | Expected impact / approval gate |
|---|---|---|---|
| Final conversion and order rules | Use the suggested defaults or approve alternatives | Confirm after Phase 1 purchase-quality results | Blocks final order modeling in Phase 2. |
| Session traffic-source priority | Available collected/session fields; event parameters; referrer inference; first-user fallback; Direct/Unknown | Audit field availability and null rates before selecting the ordered fallback | Materially changes every channel path and attribution result. |
| Channel mapping | Approve mutually exclusive ordered rules and supported channel labels | Build a mapping audit from observed source/medium values first | Blocks final `session_touchpoints` channel logic. |
| Lookback window | 7, 14, 30 days, or another approved baseline | Use 30 days as baseline and 7/14 as sensitivity checks | Changes eligible touchpoints, path length, and channel ranking. |
| Conversion-cycle boundary | Reset after purchase or independently look back for every order | Reset after the previous purchase | Changes whether historical sessions are reused across orders. |
| Direct-channel treatment | Retain, exclude/reassign, or compress under approved rules | Retain in baseline and compare last-non-direct | Can materially move credit between Direct and marketing channels. |
| Consecutive repeated-channel handling | Retain sessions or compress consecutive identical channels | Retain in baseline; compare compression in sensitivity analysis | Affects high-frequency channel contribution. |
| Non-converting journeys | Observation window, inactivity cutoff, ending rule, repeat journeys, boundary treatment | Produce a dedicated decision note before adding them | Required before conversion-plus-non-conversion Markov analysis. |
| Revenue allocation | Purchase revenue, revenue in USD, or another validated value | Use purchase revenue subject to Phase 1 quality checks | Affects reconciliation and cross-order value comparisons. |
| Simulated channel costs | Owner-supplied parameters and constraints | Defer until business-reporting phase | Required before any budget scenario; cannot support causal claims. |
| Dashboard tool | Looker Studio or Power BI | Decide in the business-reporting phase | Affects dashboard artifacts and publishing workflow. |
| Business recommendation interpretation | Approve language, confidence, and experiment proposal | Keep attribution descriptive and propose an incrementality experiment | Required before final recommendations are published. |
