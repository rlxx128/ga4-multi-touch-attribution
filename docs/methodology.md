# Planned Methodology

Last updated: 2026-08-03

## Current implementation status

No attribution model has been implemented yet. The project is in Phase 0, so
this document describes the proposed workflow and analytical guardrails rather
than completed analysis or findings.

## Planned analytical workflow

The work is intended to proceed through controlled phases:

1. Audit the public GA4 source schema, date coverage, event distribution,
   purchase quality, session identifiers, and traffic-source field availability.
2. Build an event-level base model using only fields confirmed by the audit.
3. Construct user-session touchpoints with an approved session-source priority
   and mutually exclusive channel mapping.
4. Deduplicate purchases into orders using approved transaction and revenue
   rules.
5. Match eligible sessions to each order under an approved lookback window and
   conversion-cycle boundary.
6. Implement and reconcile rule-based attribution models.
7. Implement Markov attribution only after rule-based models pass validation.
8. Compare model results and test sensitivity to path definitions and lookback
   windows.
9. Prepare transparent simulated budget scenarios and a proposed incrementality
   experiment; do not treat attributed revenue as causal lift.

Each phase must pass its validation checks before the next phase begins.

## Rule-based attribution

The planned rule-based models are first click, last click, last non-direct,
linear, and time decay. These models allocate each eligible conversion or its
revenue according to explicit positional or time-based rules. For every approved
model, transaction-level weights must sum to one within numerical tolerance, and
attributed conversions and revenue must reconcile to the eligible totals.

Rule-based models are deterministic descriptions of how credit changes under
chosen rules. They do not estimate what would have happened without a channel.

## Markov attribution

The planned Markov model will represent observed journeys as transitions from
`Start` through channel states to an absorbing `Conversion` state. A `Null`
absorbing state may be added only after the construction of non-converting paths
has been explicitly approved. Channel contribution will be based on normalized
removal effects after validating transition probabilities and baseline
conversion probability.

Unlike rule-based models, Markov attribution uses the structure of observed
path transitions rather than a fixed position rule. It is still descriptive:
removal effects are model-based path contributions, not causal incrementality.
Markov implementation must wait until rule-based attribution and reconciliation
checks pass.

## Proposed lookback and sensitivity settings

The proposed baseline lookback window is 30 days. The proposed sensitivity
windows are 7 and 14 days. These are suggested defaults only and remain pending
human approval; changing the window can alter eligible touchpoints, average path
length, channel contribution, and channel ranking.

## Pending business definitions

The following definitions remain unresolved and require approval at their
documented phase gates:

- conversion and order identity;
- purchase-event deduplication and revenue allocation;
- session traffic-source priority;
- channel mapping;
- lookback window and conversion-cycle boundary;
- Direct-channel treatment;
- repeated-channel compression;
- construction and boundary treatment of non-converting paths;
- simulated channel costs;
- dashboard tool and interpretation of business recommendations.

Suggested defaults are recorded separately in `docs/decisions.md` and must not
be treated as approved business definitions.

## Interpretation boundary

All planned attribution methods are descriptive. Neither rule-based credit nor
Markov removal effects prove that a channel caused incremental conversions or
revenue. A causal budget decision would require an additional incrementality
experiment or another defensible causal design.

