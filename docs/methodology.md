# Planned Methodology

Last updated: 2026-08-05

## Current implementation status

No attribution model has been implemented. Phase 2A created and validated the
event, order, internal-referrer, and session-source-candidate layers. Work is
stopped at the required internal-domain and ordered channel-mapping approval
gate. `session_touchpoints` and conversion paths do not exist yet.

## Implemented Phase 2A definitions

`event_base` extracts only audited source fields over suffixes `20201101`
through `20210131`. The build is physically split into three monthly queries;
each query is dry-run before execution and capped at 1,000,000,000 billed bytes.
The destination is clustered but deliberately not partitioned by historical
event date because the existing dataset has a 60-day default partition expiry.

Orders are purchase events grouped by `user_pseudo_id` and a trimmed valid
`transaction_id`. Null, blank, and case-insensitive `(not set)` identifiers are
excluded. The order timestamp is the minimum eligible purchase timestamp and
USD order revenue is the maximum observed `purchase_revenue_in_usd`.

Session identity combines `user_pseudo_id` and integer `ga_session_id` using a
deterministic SHA-256 key. The provisional source evidence is resolved in this
order:

1. earliest event with at least one usable source, medium, or campaign value;
2. earliest external `page_referrer` after proposed internal-domain exclusion;
3. earliest usable first-user source tuple, explicitly labelled as a fallback;
4. explicit Direct when source is `(direct)` or medium is `(none)`; otherwise
   Unknown.

Blank and placeholder values `(not set)`, `(not provided)`, `(data deleted)`,
`<other>`, and `unknown` are not treated as usable source components. The
source, medium, and campaign selected at event level always come from the same
event. No marketing channel is assigned in `session_source_candidates`.

The current coverage remains provisional. Internal storefront source tuples
and observed ambiguous referrers must be resolved before the ordered mapping is
applied in Phase 2B.

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

## Approved lookback and planned sensitivity settings

The approved baseline lookback window is 30 days. The planned sensitivity
windows are 7 and 14 days in a later phase. Changing the window can alter
eligible touchpoints, average path length, channel contribution, and channel
ranking.

## Pending business definitions

The following definitions remain unresolved and require approval at their
documented phase gates:

- channel mapping;
- internal-domain and self-referral handling;
- ambiguous referral and social-source values;
- same-Session multiple-order handling;
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
