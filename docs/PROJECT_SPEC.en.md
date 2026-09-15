This project is best developed in the following order: **BigQuery data modeling → rule-based attribution → Markov attribution → model comparison → budget scenario analysis → BI dashboard**.

The preliminary material defines the objective well: use public Google Analytics ecommerce data to build a user–Session–touchpoint–conversion-cycle data model, then compare rule-based, Markov, Shapley, and budget approaches.

However, `ra_attribution_for_ga4` should not be copied unchanged. That repository mainly implements rule-based attribution, and its traffic-source handling has an important opportunity for improvement. It should be treated as a baseline and extended.

---

# 1. Target project

## Project name

**Google Merchandise Store Multi-Touch Marketing Attribution and Channel Budget Optimization**

## Core business questions

The finished project should answer four questions:

1. Which marketing channels do users typically encounter before purchase?
2. How do rule-based models such as First Click, Last Click, and Linear change channel rankings?
3. How does channel contribution identified by Markov differ from Last Click?
4. Without real advertising cost data, how can transparent scenario analysis support budget recommendations?

Target workflow:

```text
GA4 event data
    ↓
Event-level data cleaning
    ↓
User Session construction
    ↓
Session channel identification
    ↓
Purchase-event and order deduplication
    ↓
Conversion Cycle construction
    ↓
Rule-based attribution
    ↓
Markov Chain attribution
    ↓
Sensitivity and stability analysis
    ↓
Simulated cost and budget optimization
    ↓
Looker Studio / Power BI dashboard
```

---

# 2. Data and project baseline

Google provides this public dataset:

```text
bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
```

It comes from Google Merchandise Store and covers:

```text
2020-11-01 through 2021-01-31
```

This is three months of obfuscated GA4 ecommerce event data. Google notes that some fields may contain `<Other>`, empty strings, or `NULL`, and that obfuscation can limit internal consistency. Results therefore must not be presented as actual Google store business conclusions. BigQuery Sandbox or the free tier is sufficient for initial exploration. ([Google for Developers][1])

Reference repository:

```text
rittmananalytics/ra_attribution_for_ga4
```

It implements:

* First Click
* Last Click
* Linear
* Time Decay
* First Paid Click
* Last Paid Click
* Last Non-direct Click

It outputs attribution results by conversion cycle and attribution model, using a default 30-day lookback and seven-day time-decay parameter. ([GitHub][2])

## Technology stack

The first version should not force every tool such as Looker, dbt, and Docker into the project.

Use:

```text
BigQuery SQL: clean data and build user journeys
Python: Markov attribution, analysis, and visualization
Looker Studio / Power BI: final dashboard
GitHub: project management and presentation
```

A second version may add:

```text
dbt: layered data models and tests
GitHub Actions: code-quality checks
Streamlit: interactive attribution comparison
```

---

# 3. Repository structure

Create locally:

```text
ga4-multi-touch-attribution/
├── README.md
├── requirements.txt
├── sql/
│   ├── 00_data_audit.sql
│   ├── 01_event_base.sql
│   ├── 02_session_touchpoints.sql
│   ├── 03_orders.sql
│   ├── 04_conversion_cycles.sql
│   ├── 05_rule_based_attribution.sql
│   └── 06_model_validation.sql
├── notebooks/
│   ├── 01_eda.ipynb
│   ├── 02_path_analysis.ipynb
│   ├── 03_markov_attribution.ipynb
│   ├── 04_model_comparison.ipynb
│   └── 05_budget_scenarios.ipynb
├── src/
│   ├── channel_mapping.py
│   ├── rule_models.py
│   ├── markov.py
│   └── validation.py
├── dashboard/
├── reports/
│   ├── figures/
│   └── business_report.md
└── tests/
```

---

# 4. Stage 1: data audit

Do not build attribution immediately. The first day should cover only the data audit.

## Step 2: confirm data volume

Run:

```sql
SELECT
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS user_count,
  COUNT(DISTINCT event_date) AS day_count,
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS min_date,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS max_date
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`;
```

Check event count, user count, day count, earliest date, and latest date. This also follows Google's basic exploration approach. ([Google for Developers][1])

## Step 3: inspect event types

```sql
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
GROUP BY
  event_name
ORDER BY
  event_count DESC;
```

Look especially for:

```text
session_start
page_view
view_item
add_to_cart
begin_checkout
add_shipping_info
add_payment_info
purchase
refund
```

Save the output as `reports/event_distribution.csv`.

## Step 4: inspect purchase quality

```sql
SELECT
  COUNT(*) AS purchase_events,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_orders,
  COUNTIF(ecommerce.transaction_id IS NULL) AS null_transaction_ids,
  COUNTIF(ecommerce.purchase_revenue IS NULL) AS null_revenue_events,
  COUNTIF(ecommerce.purchase_revenue <= 0) AS non_positive_revenue_events,
  SUM(ecommerce.purchase_revenue) AS total_revenue
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE
  event_name = 'purchase';
```

Determine whether an order has multiple purchase events, whether order IDs are missing, whether revenue is null or non-positive, and whether `COUNT(*)` is materially greater than unique order count. GA4 populates `ecommerce.purchase_revenue` only on purchase events, while `ecommerce.transaction_id` is the ecommerce transaction identifier. ([Google Help][4])

## Step 5: inspect Session ID

In GA4, `ga_session_id` is inside the repeated `event_params` field.

```sql
SELECT
  COUNT(*) AS total_events,
  COUNTIF(
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) IS NULL
  ) AS missing_session_id,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    '-',
    CAST((
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS STRING)
  )) AS unique_sessions
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`;
```

A unique Session must use `user_pseudo_id + ga_session_id`, not `ga_session_id` alone, because the latter is not guaranteed unique across users. Public implementations likewise concatenate the two fields. ([Stacktonic][5])

---

# 5. Stage 2: build the event base table

Create `ga4_attribution.event_base`.

## Step 6: extract nested fields

```sql
CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.ga4_attribution.event_base`
PARTITION BY event_date
CLUSTER BY user_pseudo_id, session_key, event_name
AS

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  TIMESTAMP_MICROS(event_timestamp) AS event_ts,

  user_pseudo_id,
  user_id,

  CONCAT(
    user_pseudo_id,
    '-',
    CAST((
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS STRING)
  ) AS session_key,

  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,

  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_number'
  ) AS ga_session_number,

  event_name,

  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'source'
  ) AS event_source,

  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'medium'
  ) AS event_medium,

  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'campaign'
  ) AS event_campaign,

  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,

  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_referrer'
  ) AS page_referrer,

  traffic_source.source AS first_user_source,
  traffic_source.medium AS first_user_medium,
  traffic_source.name AS first_user_campaign,

  device.category AS device_category,
  device.operating_system,
  device.web_info.browser AS browser,

  geo.country,
  geo.region,
  geo.city,

  ecommerce.transaction_id,
  ecommerce.purchase_revenue,
  ecommerce.purchase_revenue_in_usd

FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20201101' AND '20210131';
```

## Why partition and cluster

Most later queries filter by date, user, Session, and event type. Therefore:

```text
PARTITION BY event_date
CLUSTER BY user_pseudo_id, session_key, event_name
```

can reduce repeated scanning.

---

# 6. First major improvement: traffic-source fields

This is the project's most important technical finding to document in the README.

The original `ra_attribution_for_ga4` Session and event processing uses `traffic_source.source`, `traffic_source.medium`, and `traffic_source.name` as channel information. ([GitHub][6])

Google's definition, however, says that `traffic_source` records how the user was first acquired and does not change when the user later engages with other marketing activities. ([Google Help][4])

Therefore:

```text
traffic_source ≠ the traffic source of every Session
```

Suppose a user has:

```text
First visit: Organic Search
Second visit: Email
Third visit: Paid Search and purchase
```

If every Session uses `traffic_source.source`, all three may be labelled `Organic Search`, directly damaging multi-touch attribution.

## Improved approach

Define three source-priority levels:

```text
1. Event-level source / medium / campaign
2. page_referrer inference
3. traffic_source as fallback
```

For newer first-party GA4 data, prefer `collected_traffic_source` and `session_traffic_source_last_click` when available. The current schema defines the former as traffic source collected with the event and the latter as the Session's last-click source. ([Google Help][4])

Because this public sample is from 2020, some newer fields may be absent. Inspect the schema before deciding.

## Check field availability

```sql
SELECT
  column_name,
  data_type
FROM
  `bigquery-public-data.ga4_obfuscated_sample_ecommerce.INFORMATION_SCHEMA.COLUMNS`
WHERE
  column_name IN (
    'collected_traffic_source',
    'session_traffic_source_last_click',
    'traffic_source'
  );
```

---

# 7. Stage 4: build the Session touchpoint table

Create `ga4_attribution.session_touchpoints`, with one row per user Session.

## Step 7: select the first valid Session channel

```sql
CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.ga4_attribution.session_touchpoints`
PARTITION BY session_date
CLUSTER BY user_pseudo_id, channel
AS

WITH session_level AS (
  SELECT
    user_pseudo_id,
    session_key,

    MIN(event_ts) AS session_start_ts,
    MAX(event_ts) AS session_end_ts,
    DATE(MIN(event_ts)) AS session_date,

    ARRAY_AGG(
      STRUCT(
        event_ts,
        NULLIF(LOWER(event_source), '') AS source,
        NULLIF(LOWER(event_medium), '') AS medium,
        NULLIF(LOWER(event_campaign), '') AS campaign,
        page_referrer
      )
      ORDER BY event_ts
    ) AS session_events,

    ANY_VALUE(first_user_source) AS first_user_source,
    ANY_VALUE(first_user_medium) AS first_user_medium,
    ANY_VALUE(first_user_campaign) AS first_user_campaign,

    ANY_VALUE(device_category) AS device_category,
    ANY_VALUE(country) AS country,

    COUNT(*) AS event_count,
    COUNTIF(event_name = 'page_view') AS page_views,
    COUNTIF(event_name = 'view_item') AS product_views,
    COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
    COUNTIF(event_name = 'begin_checkout') AS checkouts,
    COUNTIF(event_name = 'purchase') AS purchase_events,

    SUM(
      IF(event_name = 'purchase', purchase_revenue, 0)
    ) AS session_revenue

  FROM
    `YOUR_PROJECT_ID.ga4_attribution.event_base`
  WHERE
    session_key IS NOT NULL
  GROUP BY
    user_pseudo_id,
    session_key
),

session_source AS (
  SELECT
    *,

    (
      SELECT source
      FROM UNNEST(session_events)
      WHERE source IS NOT NULL
      ORDER BY event_ts
      LIMIT 1
    ) AS session_source,

    (
      SELECT medium
      FROM UNNEST(session_events)
      WHERE medium IS NOT NULL
      ORDER BY event_ts
      LIMIT 1
    ) AS session_medium,

    (
      SELECT campaign
      FROM UNNEST(session_events)
      WHERE campaign IS NOT NULL
      ORDER BY event_ts
      LIMIT 1
    ) AS session_campaign

  FROM session_level
)

SELECT
  *,

  CASE
    WHEN session_source IS NULL
         AND session_medium IS NULL
      THEN 'Direct'

    WHEN REGEXP_CONTAINS(
      COALESCE(session_medium, ''),
      r'cpc|ppc|paidsearch'
    )
      THEN 'Paid Search'

    WHEN REGEXP_CONTAINS(
      COALESCE(session_medium, ''),
      r'organic'
    )
      THEN 'Organic Search'

    WHEN REGEXP_CONTAINS(
      COALESCE(session_medium, ''),
      r'email'
    )
      THEN 'Email'

    WHEN REGEXP_CONTAINS(
      COALESCE(session_medium, ''),
      r'social|social-network|social-media'
    )
      THEN 'Organic Social'

    WHEN REGEXP_CONTAINS(
      COALESCE(session_medium, ''),
      r'display|banner|cpm'
    )
      THEN 'Display'

    WHEN REGEXP_CONTAINS(
      COALESCE(session_medium, ''),
      r'affiliate'
    )
      THEN 'Affiliates'

    WHEN REGEXP_CONTAINS(
      COALESCE(session_medium, ''),
      r'referral'
    )
      THEN 'Referral'

    ELSE 'Other'
  END AS channel

FROM session_source;
```

## Why select the first valid source in a Session

Public implementations note that a GA4 Session can contain multiple traffic sources, so `MIN(source)` or `MAX(source)` is insufficient. A common method selects the earliest valid source by event time. ([Stacktonic][5])

Record this business assumption explicitly:

```text
Session attribution assumption:
Each Session uses its first valid marketing source as the Session touchpoint.
```

---

# 8. Stage 4: build the orders table

## Step 8: deduplicate purchase events

```sql
CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.ga4_attribution.orders`
PARTITION BY order_date
CLUSTER BY user_pseudo_id, transaction_id
AS

SELECT
  user_pseudo_id,
  transaction_id,

  MIN(event_ts) AS order_ts,
  DATE(MIN(event_ts)) AS order_date,

  ANY_VALUE(session_key HAVING MIN event_ts) AS conversion_session_key,

  MAX(purchase_revenue) AS order_revenue,
  MAX(purchase_revenue_in_usd) AS order_revenue_usd,

  COUNT(*) AS duplicate_purchase_events

FROM
  `YOUR_PROJECT_ID.ga4_attribution.event_base`
WHERE
  event_name = 'purchase'
  AND transaction_id IS NOT NULL
GROUP BY
  user_pseudo_id,
  transaction_id;
```

Do not directly use `SUM(purchase_revenue)`. If a transaction is collected more than once, summing can double-count order revenue. The first version should use `MAX` and report duplicates in the audit.

## Second improvement

Add transaction deduplication, null-transaction checks, duplicate-purchase checks, refund checks, currency documentation, and unusually large order detection. This makes the work an enterprise-style analysis project rather than only an algorithm exercise.

---

# 9. Stage 5: build Conversion Cycles

This is the project's most important data-modeling step.

## What is a Conversion Cycle?

Suppose a user has two orders:

```text
Email → Organic Search → Purchase A
Paid Search → Direct → Purchase B
```

Do not collapse all history into `Email → Organic Search → Paid Search → Direct` and assign it to both orders. Split it into:

```text
Cycle A:
Email → Organic Search → Purchase A

Cycle B:
Paid Search → Direct → Purchase B
```

The reference repository supports multiple touchpoints and conversion cycles, creating one cycle for every purchase. ([GitHub][2])

## Step 9: match historical Sessions to orders

Begin with a 30-day lookback:

```sql
CREATE OR REPLACE TABLE
  `YOUR_PROJECT_ID.ga4_attribution.conversion_touchpoints`
PARTITION BY order_date
CLUSTER BY user_pseudo_id, transaction_id
AS

WITH ordered_purchases AS (
  SELECT
    *,
    LAG(order_ts) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY order_ts
    ) AS previous_order_ts
  FROM
    `YOUR_PROJECT_ID.ga4_attribution.orders`
),

matched_sessions AS (
  SELECT
    o.user_pseudo_id,
    o.transaction_id,
    o.order_ts,
    o.order_date,
    o.order_revenue,

    s.session_key,
    s.session_start_ts,
    s.session_source,
    s.session_medium,
    s.session_campaign,
    s.channel,

    TIMESTAMP_DIFF(
      o.order_ts,
      s.session_start_ts,
      HOUR
    ) AS hours_before_conversion

  FROM ordered_purchases o

  JOIN
    `YOUR_PROJECT_ID.ga4_attribution.session_touchpoints` s

  ON
    o.user_pseudo_id = s.user_pseudo_id

    AND s.session_start_ts <= o.order_ts

    AND s.session_start_ts >=
        TIMESTAMP_SUB(o.order_ts, INTERVAL 30 DAY)

    AND (
      o.previous_order_ts IS NULL
      OR s.session_start_ts > o.previous_order_ts
    )
)

SELECT
  *,

  ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id, transaction_id
    ORDER BY session_start_ts
  ) AS touchpoint_order,

  COUNT(*) OVER (
    PARTITION BY user_pseudo_id, transaction_id
  ) AS path_length

FROM matched_sessions;
```

This version resets the user's path after every order, a clearer business definition than looking back a full 30 days for every order.

---

# 10. Stage 6: path-data audit

## Step 10: inspect path length

```sql
SELECT
  path_length,
  COUNT(DISTINCT transaction_id) AS orders,
  AVG(order_revenue) AS avg_order_revenue
FROM
  `YOUR_PROJECT_ID.ga4_attribution.conversion_touchpoints`
GROUP BY
  path_length
ORDER BY
  path_length;
```

Key metrics are single-touch share, multi-touch share, mean path length, maximum path length, and average order value by path length.

## Inspect the most common paths

```sql
SELECT
  path,
  COUNT(*) AS conversions,
  SUM(order_revenue) AS revenue
FROM (
  SELECT
    transaction_id,
    ANY_VALUE(order_revenue) AS order_revenue,
    STRING_AGG(
      channel,
      ' > '
      ORDER BY touchpoint_order
    ) AS path
  FROM
    `YOUR_PROJECT_ID.ga4_attribution.conversion_touchpoints`
  GROUP BY transaction_id
)
GROUP BY path
ORDER BY conversions DESC
LIMIT 30;
```

---

# 11. Stage 7: rule-based attribution

Implement these five first: First Click, Last Click, Last Non-direct Click, Linear, and Time Decay. Position Based can wait for version two.

## Step 11: First Click

```sql
SELECT
  transaction_id,
  channel,
  order_revenue AS attributed_revenue
FROM
  `YOUR_PROJECT_ID.ga4_attribution.conversion_touchpoints`
WHERE
  touchpoint_order = 1;
```

## Step 12: Last Click

```sql
SELECT
  transaction_id,
  channel,
  order_revenue AS attributed_revenue
FROM
  `YOUR_PROJECT_ID.ga4_attribution.conversion_touchpoints`
QUALIFY
  touchpoint_order = MAX(touchpoint_order) OVER (
    PARTITION BY transaction_id
  );
```

## Step 13: Linear

```sql
SELECT
  transaction_id,
  channel,
  1.0 / path_length AS attribution_weight,
  order_revenue / path_length AS attributed_revenue
FROM
  `YOUR_PROJECT_ID.ga4_attribution.conversion_touchpoints`;
```

## Step 14: Time Decay

Start with a seven-day half-life:

```text
w_i = 2^(-d_i / 7)
```

Then normalize within each path:

```text
normalized_w_i = w_i / sum_j(w_j)
```

```sql
WITH raw_weights AS (
  SELECT
    *,
    POW(
      2,
      -SAFE_DIVIDE(hours_before_conversion, 24 * 7)
    ) AS raw_weight
  FROM
    `YOUR_PROJECT_ID.ga4_attribution.conversion_touchpoints`
),

normalized AS (
  SELECT
    *,
    SAFE_DIVIDE(
      raw_weight,
      SUM(raw_weight) OVER (
        PARTITION BY transaction_id
      )
    ) AS attribution_weight
  FROM raw_weights
)

SELECT
  transaction_id,
  channel,
  attribution_weight,
  order_revenue * attribution_weight AS attributed_revenue
FROM normalized;
```

## Step 15: unified result table

Use this design:

| transaction_id | model | channel | weight | attributed_revenue |
|---|---|---|---:|---:|

Validate conservation:

```sql
SELECT
  model,
  SUM(attributed_revenue) AS attributed_revenue
FROM
  `YOUR_PROJECT_ID.ga4_attribution.rule_attribution`
GROUP BY model;
```

Total attributed revenue for every model should approximately equal total order revenue:

```text
sum_c Revenue_(c,m) = Total Order Revenue
```

If it does not, typical causes are empty paths, duplicated order joins, incorrect Direct exclusion, unnormalized weights, or order revenue duplicated across expanded rows.

---

# 12. Stage 8: Markov Chain attribution

Build Markov only after rule-based models work.

## Step 16: build Markov input

Convert journeys to:

```text
Start > Organic Search > Email > Paid Search > Conversion
```

Non-converting paths are also needed:

```text
Start > Organic Search > Email > Null
```

This is the third major improvement. Tutorials that use only purchasing paths cannot distinguish common but non-converting channels from channels that genuinely increase path conversion probability. Public tutorials also note that inclusion of non-converting paths is a modeling choice. ([Stacktonic][5])

Include both `converting path → Conversion` and `non-converting path → Null`.

## Step 17: prepare Python data

Output table:

| journey_id | path | conversion | conversion_value |
|---|---|---:|---:|
| order_1 | Organic Search > Email | 1 | 120 |
| user_session_group_2 | Paid Search > Direct | 0 | 0 |

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project="YOUR_PROJECT_ID")

query = """
SELECT
  journey_id,
  path,
  conversion,
  conversion_value
FROM `YOUR_PROJECT_ID.ga4_attribution.markov_paths`
"""

paths = client.query(query).to_dataframe()

print(paths.head())
print(paths["conversion"].value_counts(dropna=False))
```

## Step 18: build transition probabilities

States include Start, Organic Search, Paid Search, Email, Referral, Direct, Display, Conversion, and Null.

`Start → Email → Paid Search → Conversion` becomes these transitions:

```text
Start → Email
Email → Paid Search
Paid Search → Conversion
```

Code skeleton:

```python
from collections import Counter, defaultdict
from typing import Iterable

ABSORBING_STATES = {"Conversion", "Null"}


def parse_path(path: str, converted: bool) -> list[str]:
    channels = [
        value.strip()
        for value in path.split(">")
        if value.strip()
    ]

    end_state = "Conversion" if converted else "Null"
    return ["Start", *channels, end_state]


def build_transition_counts(
    paths: Iterable[list[str]],
) -> dict[str, Counter]:
    counts: dict[str, Counter] = defaultdict(Counter)

    for states in paths:
        for current_state, next_state in zip(states[:-1], states[1:]):
            counts[current_state][next_state] += 1

    return counts


def normalize_transitions(
    counts: dict[str, Counter],
) -> dict[str, dict[str, float]]:
    probabilities = {}

    for current_state, next_counts in counts.items():
        total = sum(next_counts.values())

        probabilities[current_state] = {
            next_state: count / total
            for next_state, count in next_counts.items()
        }

    return probabilities
```

## Step 19: Removal Effect

The core idea is to calculate the full network's conversion probability, remove one channel, recalculate, and measure the decrease.

```text
RemovalEffect_c = 1 - P(Conversion | remove c) / P(Conversion)

Attribution_c = RemovalEffect_c / sum_j(RemovalEffect_j)

AttributedRevenue_c = Attribution_c × TotalRevenue
```

The README must state clearly:

> Markov attribution reflects a channel's structural contribution within observed user paths; it is not the channel's causal incremental effect.

---

# 13. Stage 9: model comparison

Create:

| channel | first_click | last_click | linear | time_decay | markov |
|---|---:|---:|---:|---:|---:|

Analyze three kinds of differences.

## 1. Channel-ranking differences

High Last Click but lower Markov may mean the channel is frequently the final step before purchase, but users can still convert through other channels after its removal—a possible “harvesting” channel.

High First Click and Markov but low Last Click may mean the channel primarily acquires users or creates demand, seldom appears immediately before purchase, and may be undervalued by Last Click.

These are path-structure interpretations, not causal conclusions.

## 2. Revenue change rate

```text
ModelDifference_c =
  (MarkovRevenue_c - LastClickRevenue_c) / LastClickRevenue_c
```

```sql
SELECT
  channel,
  last_click_revenue,
  markov_revenue,
  SAFE_DIVIDE(
    markov_revenue - last_click_revenue,
    last_click_revenue
  ) AS relative_difference
FROM
  `YOUR_PROJECT_ID.ga4_attribution.model_comparison`;
```

## 3. Channel-ranking stability

Calculate Spearman rank correlation, Top-3 agreement, rank changes under different windows, and bootstrap confidence intervals. This is more informative than only producing a channel bar chart.

---

# 14. Highest-value improvements

## Improvement 1: correct Session source

Baseline repository issue: first-user `traffic_source` approximates Session channel.

Improvement: event-level UTM → referrer → first-user source fallback logic. This is the most important differentiator.

## Improvement 2: reset Conversion Cycles

Compare two path definitions:

- Method A: after previous order → current order.
- Method B: all Sessions in the 30 days before each order.

Compare mean path length, channel contribution, Direct share, and channel ranking.

## Improvement 3: lookback-window sensitivity

Compare at least 7, 14, and 30 days:

| channel | 7-day | 14-day | 30-day |
|---|---:|---:|---:|

A channel that contributes strongly only at 30 days may be an early touchpoint.

## Improvement 4: Direct treatment

Compare Direct as an ordinary touchpoint, Last Non-direct logic, removal of intermediate Direct, and consecutive Direct compression.

For example, compress `Email > Direct > Direct > Purchase` to `Email > Direct > Purchase` to avoid inflated Direct weight from refreshes or repeated visits.

## Improvement 5: repeated-channel compression

Compare the original `Paid Search > Paid Search > Paid Search > Email` path with compressed `Paid Search > Email` to test whether repeated exposure makes Markov overemphasize high-frequency channels.

## Improvement 6: include non-converting paths

Compare Model A with conversion paths only against Model B with conversion plus non-conversion paths, then analyze Removal Effect and ranking changes.

## Improvement 7: user segmentation

Possible segments include new/returning users, Mobile/Desktop, high/low order value, single-/multi-touch, US/non-US, and first/repeat purchase. Because the public data covers only three months and obfuscation limits consistency, do not segment too finely. ([Google for Developers][1])

## Improvement 8: bootstrap stability

Resample users or journeys 500 times. Recalculate Markov contribution, channel rank, and Removal Effect each time. Report mean channel contribution, 95% interval, and probability of reaching the Top 3. This avoids overconfidence in small differences from one sample.

## Improvement 9: attribute orders and revenue separately

Report both Attributed Conversions and Attributed Revenue. A channel may bring many lower-value orders, while another brings fewer but higher-value orders; order count alone misses that distinction.

## Improvement 10: add funnel analysis

An attribution project needs more than algorithms. Add a channel-level funnel:

```text
Session → View Item → Add to Cart → Begin Checkout → Purchase
```

Analyze which channels bring high traffic but low purchase rates, which have low volume but high conversion, where cart abandonment is strongest, and whether channels with high Markov contribution also have high conversion rates.

---

# 15. How to handle budget optimization

The public GA4 data has no complete, reliable advertising spend table, so the project cannot claim to calculate actual ROAS.

State explicitly:

> Because the public data does not contain complete channel cost, this project uses parameterized scenario costs for decision simulation rather than estimating Google Merchandise Store's actual ROAS.

Create a scenario table:

| channel | simulated_spend | min_budget | max_budget |
|---|---:|---:|---:|
| Paid Search | 100000 | 70000 | 130000 |
| Display | 50000 | 20000 | 70000 |
| Email | 10000 | 5000 | 20000 |

Calculate `ScenarioROAS_c = AttributedRevenue_c / SimulatedSpend_c`, comparing Last Click, Linear, and Markov ROAS.

Do not allocate the entire budget to the channel with the highest ROAS because historical attribution is not causal, marginal returns can diminish, channels may have synergies, and small channels may show artificially high ROAS due to tiny budgets. Version one should provide budget scenario analysis, not a strong claim about the “true optimal budget.”

---

# 16. Dashboard pages

Use four pages.

## Page 1: business overview

Users, Sessions, Orders, Revenue, Conversion Rate, Average Order Value, and Multi-touch Conversion Rate.

## Page 2: user journeys

Mean path length, path-length distribution, Top Conversion Paths, first-touch channel, last-touch channel, and Sankey Diagram.

## Page 3: model comparison

Model selector, attributed revenue by channel, channel-ranking changes, Markov versus Last Click, and channel-contribution difference rate.

## Page 4: stability and budget scenarios

7/14/30-day window comparison, bootstrap intervals, simulated Spend, scenario ROAS, and channels recommended for validation.

---

# 17. Project acceptance criteria

## Basic reproducibility

Complete BigQuery access, `event_base`, `session_touchpoints`, `orders`, `conversion_touchpoints`, five rule-based models, model revenue conservation checks, and a basic dashboard.

## Resume-ready portfolio project

Also complete corrected Session source, multiple conversion cycles, Markov Chain, non-converting paths, 7/14/30-day sensitivity, Direct-treatment comparison, bootstrap stability, funnel analysis, and budget scenario analysis.

## High-quality project

Also add layered dbt models, dbt tests, incremental updates, Shapley Value, a Streamlit model-comparison tool, and a Holdout Experiment proposal.
