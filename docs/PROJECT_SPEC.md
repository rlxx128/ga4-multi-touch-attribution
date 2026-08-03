这个项目适合按 **BigQuery 数据建模 → 规则归因 → Markov 归因 → 模型比较 → 预算情景分析 → BI 看板** 的顺序推进。

你的前期资料已经把项目目标定位为：基于 Google Analytics 电商公开数据，构建用户—会话—触点—转化周期数据模型，再比较规则归因、Markov、Shapley 和预算方案。这个方向是正确的。

不过，不能原样照搬 `ra_attribution_for_ga4`。原仓库主要实现规则归因，而且对流量来源字段的处理有一个值得改进的关键点。我们应把它作为 baseline，再进行优化。

---

# 一、最终要做成什么项目

## 项目名称

**Google Merchandise Store 多触点营销归因与渠道预算优化**

## 核心业务问题

你最终需要回答四个问题：

1. 用户购买前通常经历哪些营销渠道？
2. First Click、Last Click、Linear 等规则模型会怎样改变渠道排名？
3. Markov 模型识别出的渠道贡献，和 Last Click 有什么区别？
4. 在缺少真实广告成本的情况下，如何通过透明的情景分析提出预算建议？

最终项目流程：

```text
GA4事件数据
    ↓
事件级数据清洗
    ↓
用户Session构建
    ↓
Session渠道识别
    ↓
购买事件与订单去重
    ↓
Conversion Cycle构建
    ↓
规则归因模型
    ↓
Markov Chain归因
    ↓
敏感性与稳定性分析
    ↓
模拟成本与预算优化
    ↓
Looker Studio / Power BI看板
```

---

# 二、数据与项目基线

Google 提供的公开数据集是：

```text
bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
```

数据来自 Google Merchandise Store，覆盖：

```text
2020-11-01 至 2021-01-31
```

它是经过脱敏的三个月 GA4 电商事件数据。Google 明确说明部分字段可能是 `<Other>`、空字符串或 `NULL`，而且脱敏后内部一致性有限，因此分析结果不能被解释为 Google 商店真实经营结论。BigQuery Sandbox 或免费额度足以完成初步探索。([Google for Developers][1])

参考仓库：

```text
rittmananalytics/ra_attribution_for_ga4
```

该仓库实现了：

* First Click
* Last Click
* Linear
* Time Decay
* First Paid Click
* Last Paid Click
* Last Non-direct Click

并输出每个转化周期、每种归因模型的归因结果。仓库默认使用 30 天回溯窗口和 7 天时间衰减参数。([GitHub][2])

## 我们的技术栈

第一版不要强行使用 Looker、dbt、Docker 等全部工具。

使用：

```text
BigQuery SQL：清洗和构建用户旅程
Python：Markov归因、分析和可视化
Looker Studio / Power BI：最终看板
GitHub：项目管理和展示
```

第二版再加入：

```text
dbt：数据模型分层与测试
GitHub Actions：代码质量检查
Streamlit：归因模型交互页面
```

---

# 三、项目仓库结构

先在本地建立：

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

# 四 阶段一：数据审计

先不要马上建归因模型。第一天只完成数据审计。

## 第2步：确认数据规模

运行：

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

检查：

* 事件数
* 用户数
* 日期数
* 最早日期
* 最晚日期

这也是 Google 官方提供的基础探索方式。([Google for Developers][1])

---

## 第3步：检查事件类型

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

重点找：

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

输出保存为：

```text
reports/event_distribution.csv
```

---

## 第4步：检查购买数据质量

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

这里要判断：

* 一个订单是否出现多个 purchase 事件
* 订单号是否为空
* 收入是否为空或非正数
* `COUNT(*)` 是否明显大于唯一订单数

GA4 的 `ecommerce.purchase_revenue` 只在购买事件中填充，`ecommerce.transaction_id` 表示电商交易编号。([谷歌帮助][4])

---

## 第5步：检查 Session ID

GA4 中的 `ga_session_id` 位于重复字段 `event_params` 中。

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

唯一 Session 不能只使用 `ga_session_id`，应使用：

```text
user_pseudo_id + ga_session_id
```

因为 `ga_session_id` 本质上不能保证跨用户唯一。相关公开实现也通过拼接这两个字段构造唯一 Session。([Stacktonic][5])

---

# 五、阶段二：构建事件基础表

建立：

```text
ga4_attribution.event_base
```

## 第6步：提取嵌套字段

```sql
CREATE OR REPLACE TABLE
  `你的项目ID.ga4_attribution.event_base`
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

## 为什么分区和聚类

后续几乎所有查询都会按日期、用户、Session 和事件类型过滤，所以：

```text
PARTITION BY event_date
CLUSTER BY user_pseudo_id, session_key, event_name
```

可以减少重复扫描。

---

# 六、最重要的第一个优化点：流量来源字段

这是整个项目最值得写入 README 的技术发现。

原始 `ra_attribution_for_ga4` 在 Session 和事件处理中使用：

```sql
traffic_source.source
traffic_source.medium
traffic_source.name
```

作为渠道信息。([GitHub][6])

但是 Google 官方定义指出：

> `traffic_source` 记录的是第一次获取该用户的来源，用户后续参与其他营销活动时，这些值不会改变。([谷歌帮助][4])

因此：

```text
traffic_source ≠ 每次Session的流量来源
```

假设某个用户：

```text
第一次：Organic Search
第二次：Email
第三次：Paid Search并购买
```

如果所有 Session 都使用 `traffic_source.source`，三个 Session 可能都会被标为：

```text
Organic Search
```

这会直接破坏多触点归因。

## 你的优化方案

定义三级来源优先级：

```text
1. 事件级source / medium / campaign
2. page_referrer推断
3. traffic_source作为兜底
```

在较新的自有 GA4 数据中，还可以优先使用：

```text
collected_traffic_source
session_traffic_source_last_click
```

官方当前 schema 把 `collected_traffic_source` 定义为事件采集时的流量来源，把 `session_traffic_source_last_click` 定义为 Session 的末次点击来源。([谷歌帮助][4])

但这个公开样本来自 2020 年，部分新字段可能不存在，所以先检查 schema，再决定是否使用。

## 检查字段是否存在

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

# 七、阶段四：构建 Session 触点表

建立：

```text
ga4_attribution.session_touchpoints
```

每一行代表一个用户 Session。

## 第7步：确定 Session 首个有效渠道

```sql
CREATE OR REPLACE TABLE
  `你的项目ID.ga4_attribution.session_touchpoints`
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
    `你的项目ID.ga4_attribution.event_base`
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

## 为什么取 Session 内第一个有效来源

公开实现指出，一个 GA4 Session 内可能包含不同流量来源，因此不能简单使用 `MIN(source)` 或 `MAX(source)`，常见方案是选择 Session 中时间最早的有效来源。([Stacktonic][5])

但这里也要记录为一个业务假设：

```text
Session attribution assumption:
每个Session使用第一个有效营销来源作为该Session触点。
```

---

# 八、阶段四：建立订单表

## 第8步：购买事件去重

```sql
CREATE OR REPLACE TABLE
  `你的项目ID.ga4_attribution.orders`
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
  `你的项目ID.ga4_attribution.event_base`
WHERE
  event_name = 'purchase'
  AND transaction_id IS NOT NULL
GROUP BY
  user_pseudo_id,
  transaction_id;
```

这里不能直接使用：

```sql
SUM(purchase_revenue)
```

如果同一 transaction 被重复采集，直接求和可能重复计算订单收入。第一版用 `MAX`，然后在数据审计中报告重复情况。

## 第二个优化点

原始项目更多关注归因计算，你应额外补充：

* transaction 去重
* NULL transaction 检查
* 重复 purchase 检查
* 退款事件检查
* 收入币种说明
* 异常高订单识别

这部分更像企业数据分析项目，而不是算法练习。

---

# 九、阶段五：构建 Conversion Cycle

这是项目里最重要的数据建模环节。

## Conversion Cycle 是什么

假设用户产生两笔订单：

```text
Email → Organic Search → Purchase A
Paid Search → Direct → Purchase B
```

不能把全部历史压成：

```text
Email → Organic Search → Paid Search → Direct
```

然后同时归给两笔订单。

应该拆成：

```text
Cycle A:
Email → Organic Search → Purchase A

Cycle B:
Paid Search → Direct → Purchase B
```

原仓库明确支持多触点、多转化周期，并为每次购买建立自己的转换周期。([GitHub][2])

---

## 第9步：为订单匹配历史 Session

先采用 30 天回溯窗口：

```sql
CREATE OR REPLACE TABLE
  `你的项目ID.ga4_attribution.conversion_touchpoints`
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
    `你的项目ID.ga4_attribution.orders`
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
    `你的项目ID.ga4_attribution.session_touchpoints` s

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

这个版本采用：

```text
每次订单发生后重置用户路径
```

这是比简单“每笔订单都回看完整 30 天”更清晰的商业定义。

---

# 十、阶段六：路径数据审计

## 第10步：检查路径长度

```sql
SELECT
  path_length,
  COUNT(DISTINCT transaction_id) AS orders,
  AVG(order_revenue) AS avg_order_revenue
FROM
  `你的项目ID.ga4_attribution.conversion_touchpoints`
GROUP BY
  path_length
ORDER BY
  path_length;
```

重点指标：

* 单触点订单比例
* 多触点订单比例
* 平均路径长度
* 最大路径长度
* 不同路径长度对应的平均订单金额

## 查看最常见路径

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
    `你的项目ID.ga4_attribution.conversion_touchpoints`
  GROUP BY transaction_id
)
GROUP BY path
ORDER BY conversions DESC
LIMIT 30;
```

---

# 十一阶段七：规则归因模型

先实现五种即可：

1. First Click
2. Last Click
3. Last Non-direct Click
4. Linear
5. Time Decay

Position Based 可以放到第二版。

---

## 第11步：First Click

```sql
SELECT
  transaction_id,
  channel,
  order_revenue AS attributed_revenue
FROM
  `你的项目ID.ga4_attribution.conversion_touchpoints`
WHERE
  touchpoint_order = 1;
```

---

## 第12步：Last Click

```sql
SELECT
  transaction_id,
  channel,
  order_revenue AS attributed_revenue
FROM
  `你的项目ID.ga4_attribution.conversion_touchpoints`
QUALIFY
  touchpoint_order = MAX(touchpoint_order) OVER (
    PARTITION BY transaction_id
  );
```

---

## 第13步：Linear

```sql
SELECT
  transaction_id,
  channel,
  1.0 / path_length AS attribution_weight,
  order_revenue / path_length AS attributed_revenue
FROM
  `你的项目ID.ga4_attribution.conversion_touchpoints`;
```

---

## 第14步：Time Decay

先使用半衰期 7 天：

[
w_i = 2^{-\frac{d_i}{7}}
]

再对每条路径归一化：

[
\widetilde{w_i} =
\frac{w_i}{\sum_j w_j}
]

SQL：

```sql
WITH raw_weights AS (
  SELECT
    *,
    POW(
      2,
      -SAFE_DIVIDE(hours_before_conversion, 24 * 7)
    ) AS raw_weight
  FROM
    `你的项目ID.ga4_attribution.conversion_touchpoints`
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

---

## 第15步：统一结果表

结果表设计为：

| transaction_id | model | channel | weight | attributed_revenue |
| -------------- | ----- | ------- | -----: | -----------------: |

必须进行守恒校验：

```sql
SELECT
  model,
  SUM(attributed_revenue) AS attributed_revenue
FROM
  `你的项目ID.ga4_attribution.rule_attribution`
GROUP BY model;
```

各模型总归因收入应基本等于总订单收入：

[
\sum_c Revenue_{c,m}
====================

Total\ Order\ Revenue
]

如果不相等，通常说明：

* 路径为空
* 订单被重复关联
* Direct 排除逻辑有问题
* 权重没有归一化
* 同一订单收入重复展开

---

# 十二、阶段八：Markov Chain 归因

规则模型跑通后再做 Markov，不要一开始就写 Markov。

## 第16步：构建 Markov 输入

转换为：

```text
Start > Organic Search > Email > Paid Search > Conversion
```

还需要非转化路径：

```text
Start > Organic Search > Email > Null
```

这里是第三个重要优化点。

很多公开教程只使用购买路径，但 Markov 模型如果完全没有非转化路径，无法很好地区分：

* 常见但不促进购买的渠道
* 真正提高转化概率的渠道

公开教程也明确指出是否纳入 non-converting paths 是一个建模选择，有些示例并没有使用非转化路径。([Stacktonic][5])

你的版本应纳入两类路径：

```text
转化路径 → Conversion
未转化路径 → Null
```

---

## 第17步：准备 Python 数据

输出表：

| journey_id           | path                   | conversion | conversion_value |
| -------------------- | ---------------------- | ---------: | ---------------: |
| order_1              | Organic Search > Email |          1 |              120 |
| user_session_group_2 | Paid Search > Direct   |          0 |                0 |

Python 读取：

```python
from google.cloud import bigquery
import pandas as pd

client = bigquery.Client(project="你的项目ID")

query = """
SELECT
  journey_id,
  path,
  conversion,
  conversion_value
FROM `你的项目ID.ga4_attribution.markov_paths`
"""

paths = client.query(query).to_dataframe()

print(paths.head())
print(paths["conversion"].value_counts(dropna=False))
```

---

## 第18步：构建转移概率

状态包括：

```text
Start
Organic Search
Paid Search
Email
Referral
Direct
Display
Conversion
Null
```

路径：

```text
Start → Email → Paid Search → Conversion
```

拆成转移：

```text
Start → Email
Email → Paid Search
Paid Search → Conversion
```

代码骨架：

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

---

## 第19步：Removal Effect

核心思想：

1. 计算完整渠道网络的转化概率。
2. 移除某渠道。
3. 重新计算转化概率。
4. 观察概率下降多少。

[
RemovalEffect_c =
1-
\frac{P(Conversion\mid remove\ c)}
{P(Conversion)}
]

归一化渠道贡献：

[
Attribution_c =
\frac{RemovalEffect_c}
{\sum_j RemovalEffect_j}
]

收入归因：

[
AttributedRevenue_c =
Attribution_c
\times TotalRevenue
]

README 需要清楚说明：

> Markov attribution 反映的是渠道在已观察用户路径中的结构性贡献，并不等于渠道的因果增量效果。

---

# 十三、阶段九：模型比较

建立表：

| channel | first_click | last_click | linear | time_decay | markov |
| ------- | ----------: | ---------: | -----: | ---------: | -----: |

需要分析三种差异。

## 1. 渠道排名差异

例如：

```text
Last Click排名高，但Markov较低
```

可能表示：

* 渠道经常位于购买前最后一步
* 但移除后用户仍可通过其他渠道完成转化
* 可能是“收割型渠道”

```text
First Click和Markov高，但Last Click低
```

可能表示：

* 渠道主要负责拉新或需求激发
* 经常不处于购买前最后一步
* 可能被 Last Click 低估

注意这些都是路径结构解释，不是因果结论。

---

## 2. 收入变化率

[
ModelDifference_{c}
===================

\frac{MarkovRevenue_c-LastClickRevenue_c}
{LastClickRevenue_c}
]

计算：

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
  `你的项目ID.ga4_attribution.model_comparison`;
```

---

## 3. 渠道排序稳定性

计算：

* Spearman Rank Correlation
* Top-3 渠道一致率
* 不同窗口下排名变化
* Bootstrap 置信区间

这会比单纯输出一张渠道柱状图更有深度。

---

# 十四、最值得做的优化点

## 优化1：修正 Session 来源

**基础仓库问题：**

使用 first-user `traffic_source` 近似 Session 渠道。

**你的优化：**

事件级 UTM → referrer → first-user source 三级降级逻辑。

这是最重要的差异化点。

---

## 优化2：Conversion Cycle 重置

比较两种路径定义：

### 方法A：订单后重置

```text
上一订单后 → 当前订单
```

### 方法B：每笔订单都向前回看30天

```text
当前订单前30天所有Session
```

对比两种定义下：

* 平均路径长度
* 渠道贡献
* Direct 占比
* 渠道排名

---

## 优化3：Lookback Window 敏感性分析

至少比较：

```text
7天
14天
30天
```

输出：

| channel | 7-day | 14-day | 30-day |
| ------- | ----: | -----: | -----: |

如果某渠道只有在 30 天窗口下贡献很高，说明它可能是早期触点。

---

## 优化4：Direct 的处理

比较：

1. Direct 保留为普通触点
2. Last Non-direct 逻辑
3. 中间 Direct 删除
4. 连续 Direct 合并

例如：

```text
Email > Direct > Direct > Purchase
```

可压缩为：

```text
Email > Direct > Purchase
```

避免用户刷新、重复访问导致 Direct 权重膨胀。

---

## 优化5：重复渠道压缩

路径：

```text
Paid Search > Paid Search > Paid Search > Email
```

可以比较：

### 原始路径

保留每次 Session。

### 压缩路径

```text
Paid Search > Email
```

分析重复曝光是否导致 Markov 模型过度强调高频渠道。

---

## 优化6：纳入未转化路径

这是 Markov 模型的重要升级。

比较：

```text
Model A：只有转化路径
Model B：转化 + 非转化路径
```

然后分析 Removal Effect 和渠道排名变化。

---

## 优化7：按用户群体分层

可以分：

* 新用户 / 回访用户
* Mobile / Desktop
* 高客单价 / 低客单价
* 单触点 / 多触点用户
* 美国 / 非美国
* 首购 / 复购

但公开数据只有三个月，而且脱敏后一致性有限，分层不能太细。([Google for Developers][1])

---

## 优化8：Bootstrap 稳定性

对用户或 Journey 进行重复抽样：

```text
Bootstrap 500次
```

每次重新计算：

* Markov contribution
* 渠道排名
* Removal Effect

输出：

```text
渠道贡献均值
95%置信区间
排名进入Top-3的概率
```

这样可以避免把一次样本中的小差异解释得过度确定。

---

## 优化9：收入与订单分别归因

同时输出：

```text
Attributed Conversions
Attributed Revenue
```

某渠道可能：

* 带来订单很多
* 但客单价较低

另一个渠道可能：

* 订单较少
* 但高价值订单多

只看订单数会遗漏价值差异。

---

## 优化10：加入漏斗分析

归因项目不能只有算法。

增加渠道级漏斗：

```text
Session
→ View Item
→ Add to Cart
→ Begin Checkout
→ Purchase
```

分析：

* 哪些渠道带来大量访问但购买率低
* 哪些渠道量小但转化率高
* 哪些渠道的购物车流失严重
* Markov 贡献高的渠道是否也拥有高转化率

---

# 十五、预算优化应该怎样处理

公共 GA4 数据没有完整可靠的广告 Spend 表，因此不能声称计算了真实 ROAS。

正确做法是明确写：

> 由于公开数据不包含完整渠道成本，本项目使用参数化情景成本进行决策模拟，而非估计 Google Merchandise Store 的真实 ROAS。

构造情景表：

| channel     | simulated_spend | min_budget | max_budget |
| ----------- | --------------: | ---------: | ---------: |
| Paid Search |          100000 |      70000 |     130000 |
| Display     |           50000 |      20000 |      70000 |
| Email       |           10000 |       5000 |      20000 |

然后计算：

[
ScenarioROAS_c =
\frac{AttributedRevenue_c}
{SimulatedSpend_c}
]

比较：

* Last Click ROAS
* Linear ROAS
* Markov ROAS

不要直接把全部预算分给 ROAS 最高渠道，因为：

* 历史归因不是因果效果
* 存在边际收益递减
* 渠道之间可能有协同
* 小渠道可能因预算太少而呈现虚高 ROAS

因此第一版只做：

```text
预算情景分析
```

不做“最优真实预算”的强结论。

---

# 十六、Dashboard 页面

最终看板建议四页。

## 页面1：业务概览

* Users
* Sessions
* Orders
* Revenue
* Conversion Rate
* Average Order Value
* Multi-touch Conversion Rate

## 页面2：用户旅程

* 平均路径长度
* 路径长度分布
* Top Conversion Paths
* 首触点渠道
* 末触点渠道
* Sankey Diagram

## 页面3：模型比较

* 模型选择器
* 渠道归因收入
* 渠道排名变化
* Markov vs Last Click
* 渠道贡献差异率

## 页面4：稳定性与预算情景

* 7/14/30天窗口比较
* Bootstrap 区间
* 模拟 Spend
* 情景 ROAS
* 建议验证的渠道

---

# 十七、项目验收标准

## 基础复现合格

完成：

* BigQuery 访问
* event_base
* session_touchpoints
* orders
* conversion_touchpoints
* 五种规则模型
* 模型收入守恒检查
* 基础 Dashboard

## 简历项目合格

再完成：

* Session 来源修正
* 多转化周期
* Markov Chain
* 非转化路径
* 7/14/30 天敏感性分析
* Direct 处理比较
* Bootstrap 稳定性
* 漏斗分析
* 预算情景分析

## 高质量项目

再加入：

* dbt 分层建模
* dbt tests
* 增量更新
* Shapley Value
* Streamlit 模型比较工具
* Holdout Experiment 方案