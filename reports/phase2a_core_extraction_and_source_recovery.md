# Phase 2A Core Extraction and Source Recovery

Last updated: 2026-08-05

## Status and scope

Phase 2A is executed and validated. Work is stopped at the required internal-
domain and ordered channel-mapping approval gate. No final channel mapping,
`session_touchpoints`, conversion path, attribution model, ROAS, budget, or
dashboard output has been created.

The public obfuscated GA4 ecommerce sample is used for portfolio analysis. The
results do not represent actual Google Merchandise Store performance.

## Created BigQuery tables

| Table | Rows | Status |
|---|---:|---|
| `event_base` | 4,295,584 | Validated |
| `orders` | 4,466 | Validated against the hard acceptance count |
| `internal_referrer_domain_audit` | 5 | Proposed internal flags, not approved |
| `session_source_candidates` | 360,129 | Provisional pending gate approval |
| `channel_source_coverage_audit` | 5 | Provisional pending gate approval |
| `source_medium_campaign_frequency` | 251 | Review table |
| `channel_mapping_proposal` | 11 | `PROPOSED_NOT_APPROVED` |
| `phase2a_validation_summary` | 17 | All checks passed |

The existing dataset applies a 60-day default table expiration. The final tables
expire between 2026-10-04 14:02:48 UTC and 14:05:57 UTC unless their metadata is
changed with owner approval.

## Order and core reconciliation

- Event rows: 4,295,584.
- Distinct event dates: 92, from 2020-11-01 through 2021-01-31.
- Eligible deduplicated orders: exactly 4,466.
- Duplicate order keys after deduplication: 0.
- Invalid transaction identifiers retained in `orders`: 0.
- Null or non-positive deduplicated USD order revenue: 0.
- Composite source-candidate Sessions: 360,129.
- Duplicate composite Session keys: 0.
- Sessions ending before they start: 0.

## Source-resolution coverage

These tiers are mutually exclusive. They are provisional because an approved
internal-domain rule can change candidate validity.

| Priority result | Sessions | Percentage |
|---|---:|---:|
| Event-level source tuple | 203,880 | 56.613047% |
| External referrer | 15 | 0.004165% |
| First-user fallback | 53,368 | 14.819134% |
| Direct | 59,966 | 16.651256% |
| Unknown | 42,900 | 11.912398% |
| **Total** | **360,129** | **100.000000%** |

Direct requires explicit `(direct)` source or `(none)` medium. Missing reliable
evidence is Unknown. First-user values remain explicitly labelled fallbacks and
are not represented as Session-native acquisition evidence.

## Internal-referrer candidates

| Referrer host | Registered domain | Referrer Sessions | Observed as page-location registered domain? | Proposal |
|---|---|---:|---|---|
| `shop.googlemerchandisestore.com` | `googlemerchandisestore.com` | 89,846 | Yes | Internal |
| `www.googlemerchandisestore.com` | `googlemerchandisestore.com` | 122 | Yes | Internal |
| `googlemerchandisestore.com` | `googlemerchandisestore.com` | 16 | Yes | Internal |
| `admin.googlemerchandisestore.com` | `googlemerchandisestore.com` | 5 | Yes, at registered-domain level | Internal |
| `www.google.com` | `google.com` | 41 | No | External |

After applying the provisional priority, only 15 Sessions use `www.google.com`
as their external-referrer winner. Higher-priority evidence resolves the other
26 Sessions in which that referrer appears.

## Source / medium / campaign frequency

The complete 251-row review table is available in BigQuery as
`source_medium_campaign_frequency` and locally as
`reports/tables/phase2a_source_medium_campaign_frequency.csv`. The 20 largest
combinations are:

| Tier | Source | Medium | Campaign | Sessions | Percentage |
|---|---|---|---|---:|---:|
| Event | `google` | `organic` | `(organic)` | 93,556 | 25.978469% |
| Direct | `(direct)` | `(none)` | null | 59,966 | 16.651256% |
| Event | `shop.googlemerchandisestore.com` | `referral` | `(referral)` | 57,821 | 16.055636% |
| Unknown | null | null | null | 42,900 | 11.912398% |
| First-user fallback | `google` | `organic` | `(organic)` | 30,415 | 8.445585% |
| Event | null | `referral` | `(referral)` | 20,457 | 5.680465% |
| First-user fallback | null | `referral` | `(referral)` | 8,943 | 2.483277% |
| Event | null | `organic` | `(organic)` | 8,888 | 2.468005% |
| Event | `google` | `cpc` | null | 7,672 | 2.130348% |
| First-user fallback | `shop.googlemerchandisestore.com` | `referral` | `(referral)` | 7,001 | 1.944026% |
| Event | `googlemerchandisestore.com` | `referral` | `(referral)` | 5,992 | 1.663848% |
| First-user fallback | `google` | `cpc` | null | 4,272 | 1.186242% |
| Event | `analytics.google.com` | `referral` | `(referral)` | 3,455 | 0.959378% |
| First-user fallback | null | `organic` | `(organic)` | 2,737 | 0.760005% |
| Event | `Partners` | `affiliate` | `Data Share Promo` | 1,332 | 0.369867% |
| Event | `creatoracademy.youtube.com` | `referral` | `(referral)` | 889 | 0.246856% |
| Event | `baidu` | `organic` | `(organic)` | 696 | 0.193264% |
| Event | `sites.google.com` | `referral` | `(referral)` | 418 | 0.116070% |
| Event | `support.google.com` | `referral` | `(referral)` | 365 | 0.101353% |
| Event | `perksatwork.com` | `referral` | `(referral)` | 226 | 0.062755% |

No observed resolved medium is an explicit paid-social medium. The only resolved
paid-search-style medium is `cpc`, and all 11,944 such Sessions use source
`google`. Paid Social can remain an allowed channel label, but this Phase 2A
evidence does not identify a paid-social Session.

## Exact ordered channel-mapping proposal

The predicates below are review artifacts only and have not been executed to
assign a channel. First match wins.

1. **Direct**: `source_resolution_tier = 'Direct' OR LOWER(resolved_source) = '(direct)' OR LOWER(resolved_medium) = '(none)'`.
2. **Paid Social**: `REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(paid[_ -]?social|social[_ -]?paid)$') OR (REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(cpc|ppc|paidsearch|paid search|sem)$') AND REGEXP_CONTAINS(LOWER(COALESCE(resolved_source, '')), r'(^|\.)(facebook\.com|instagram\.com|twitter\.com|t\.co|linkedin\.com|pinterest\.[a-z.]+|tiktok\.com|youtube\.com)$'))`.
3. **Paid Search**: `REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(cpc|ppc|paidsearch|paid search|sem)$')`.
4. **Display**: `REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(display|banner|cpm|programmatic)$')`.
5. **Email**: `REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(email|e-mail|e_mail)$')`.
6. **Affiliates**: `REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^affiliate(s)?$')`.
7. **Organic Search**: `REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^organic$')`.
8. **Organic Social**: `REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(social|social-network|social-media|sm)$') OR REGEXP_CONTAINS(LOWER(COALESCE(resolved_source, '')), r'(^|\.)(facebook\.com|instagram\.com|twitter\.com|t\.co|linkedin\.com|pinterest\.[a-z.]+|tiktok\.com|youtube\.com)$')`.
9. **Referral**: `source_resolution_tier = 'external_referrer' OR LOWER(COALESCE(resolved_medium, '')) = 'referral'`.
10. **Unknown**: `source_resolution_tier = 'Unknown' OR (resolved_source IS NULL AND resolved_medium IS NULL)`.
11. **Other**: `TRUE`.

The literal SQL predicates are stored in `channel_mapping_proposal` and
`reports/tables/phase2a_channel_mapping_proposal.csv`.

## Unresolved values and expected impact

| Decision | Affected provisional Sessions | Expected impact |
|---|---:|---|
| Exclude storefront-domain `referral` source tuples and re-resolve, or retain them | 70,820 (19.665176%) | Retention would send likely self-referrals to Referral; exclusion redistributes them to lower-priority evidence, Direct, or Unknown and requires rebuilding the provisional source tables. |
| Keep null-source `referral` medium as Referral, or demote to Unknown | 29,400 (8.163741%) | Material movement between Referral and Unknown. |
| Treat `analytics.google.com` as Referral, Other, or administrative/internal | 3,455 (0.959378%) | Changes Referral volume and whether administrative traffic remains in paths. |
| Treat `creatoracademy.youtube.com` as Organic Social or Referral | 889 (0.246856%) | Current source-domain predicate assigns Organic Social; a content-referrer exception assigns Referral. |
| Infer external `www.google.com` as Organic Search or retain Referral | 15 (0.004165%) | Small numerical impact, but it determines the documented referrer-inference rule. |
| Keep explicit missing-evidence Sessions as Unknown | 42,900 (11.912398%) | Reassigning these to Direct would materially inflate Direct without explicit evidence; the recommendation is to keep Unknown. |

Recommended gate decision: approve `googlemerchandisestore.com` and all
subdomains as internal; exclude storefront-domain referral tuples and re-run
source resolution; keep explicit medium-only referrals as Referral; use a small
explicit administrative-host exception list; keep Creator Academy as Referral;
map external `www.google.com` inference to Organic Search; approve the remaining
ordered rules as written.

## Validation results

All 17 checks in `phase2a_validation_summary` passed. They cover event count,
date coverage, missing event user/session identifiers, exact order count,
invalid transaction IDs, non-positive revenue, duplicate order/session keys,
Session time ordering, valid source tiers, coverage reconciliation, and mapping-
proposal rule count/priority uniqueness.

## Query safety, bytes, and recovery note

All executable SQL was dry-run first. Every query used
`maximum_bytes_billed = 1,000,000,000`; no estimate exceeded the cap. Every
source wildcard query restricted `_TABLE_SUFFIX` to one of the three approved
monthly ranges.

| Query | Estimated bytes | Actual processed | Actual billed |
|---|---:|---:|---:|
| `event_base` 2020-11 | 699,075,728 | 699,075,728 | 699,400,192 |
| `event_base` 2020-12 | 776,479,370 | 776,479,370 | 776,994,816 |
| `event_base` 2021-01 | 545,895,355 | 545,895,355 | 546,308,096 |
| `orders` | 470,873,306 | 470,873,306 | 471,859,200 |
| Internal-referrer audit | 736,246,845 | 736,246,845 | 737,148,928 |
| Session source candidates | 831,477,973 | 831,477,973 | 831,520,768 |
| Source coverage | 6,064,441 | 6,064,441 | 10,485,760 |
| Source frequency | 15,911,135 | 15,911,135 | 16,777,216 |
| Mapping proposal | 0 | 0 | 0 |
| Validation summary | 442,639,606 | 442,639,606 | 443,547,648 |
| **Successful Phase 2A total** |  | **4,524,663,759** | **4,534,042,624** |

The first build attempt used historical business-date partitions. The existing
dataset's 60-day default partition expiration immediately expired those rows,
leaving confirmed-empty `event_base` and `orders` tables. After owner-approved
deletion of only those two 0-row tables, the build was changed to clustered,
unpartitioned destinations and successfully rerun. That recovery attempt had
already processed 2,021,450,453 bytes and billed 2,022,703,104 bytes. A read-only
Phase 1 date-coverage diagnostic processed 42,955,840 bytes and billed 42,991,616
bytes. Including successful work, recovery overhead, and the diagnostic, this
task processed 6,589,070,052 bytes and billed 6,599,737,344 bytes.

## Approval gate

Do not begin Phase 2B until the owner approves or revises the internal-domain
list, storefront self-referral recovery, ambiguous-value treatment, and exact
ordered mapping. After approval, rebuild the provisional source tables if the
approved decisions differ from the current candidates, then implement only
Phase 2B.
