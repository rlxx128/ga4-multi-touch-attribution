# 方法论

最后更新：2026-08-14

## 当前实施状态

Phase 3 规则型归因、Phase 4 一阶 Markov 归因、Phase 5 敏感性与稳定性分析以及 Phase 6 业务报告均已实施。全部 42 项 Phase 6 检查均在不可变的 Phase 2B–5 基准上通过。

## 核心事件与订单定义

`event_base` 提取后缀 `20201101` 至 `20210131` 的已审计字段。来源扫描拆分为有界月度查询。由于现有数据集有 60 天默认分区到期设置，不使用历史事件日期分区，而采用聚类表。

订单是按 `user_pseudo_id` 与修剪后的有效 `transaction_id` 分组的购买事件。排除空值、空白及不区分大小写的 `(not set)` 标识符。最早合格购买时间戳为订单时间戳，观察到的最大 `purchase_revenue_in_usd` 为去重订单价值。

Session 身份是基于 `user_pseudo_id` 和整数 `ga_session_id` 计算的确定性 SHA-256 键。

## 已批准的 Session 来源恢复

选择来源证据前，将空白值和 `(not set)`、`(not provided)`、`(data deleted)`、`<other>`、`unknown` 占位符标准化为空。类似主机的来源用 `NET.HOST` 标准化，注册域使用 `NET.REG_DOMAIN`。

内部店铺规则要求标准化注册域精确等于 `googlemerchandisestore.com`，因此无需子字符串谓词即可覆盖注册域及其子域。规则分别应用于事件级来源、页面引荐和首次用户来源证据。

每个 Session 按以下顺序解析一次：

1. 最早的非内部有效事件级来源/媒介/广告系列元组，且所有元组组件来自同一事件；
2. 最早的非内部页面引荐；
3. 最早的非内部首次用户元组，明确标记为 `first_user_fallback`；
4. 来自 `(direct)` 来源或 `(none)` 媒介的明确 Direct 证据；
5. 没有可靠证据时为 Unknown。

若来源缺失但媒介可用，则保留并设置 `source_missing_flag = TRUE` 与 `source_quality = 'medium_only'`。特别地，来源为空的 `referral` 媒介仍归为 Referral，但不能识别具体引荐网站。

对于已批准的外部 `www.google.com` 引荐推断，原始页面引荐仍可用，`source_resolution_tier = 'external_referrer'`、`is_inferred_source = TRUE`、`inference_rule = 'google_referrer_to_organic_search'`。它不表示为原生事件级证据。

## 管理流量与渠道映射

`analytics.google.com` 与 `moma.corp.google.com` 仅通过标准化主机精确相等匹配。它们的 Session 保留原始来源字段，并标记 `channel = 'Internal/Admin'`、`is_internal_admin_traffic = TRUE`、`is_attribution_eligible = FALSE` 以及主机特定原因。它们保留在 `session_touchpoints`，但从严格和修订转化路径中排除。不使用宽泛 `google.com` 排除；如果存在其他合格营销触点，订单仍保持覆盖。

映射是版本为 `phase2b_channel_v2_20260806` 的单个有序 CASE 表达式。先拦截 Internal/Admin；对于归因合格 Session，首个匹配营销规则获胜：

1. Direct
2. Paid Social
3. Paid Search
4. Display
5. Email
6. Affiliates
7. Organic Search
8. Organic Social
9. Referral
10. Unknown
11. Other

Creator Academy 例外将 `creatoracademy.youtube.com` 映射为 Referral。普通 YouTube/社交域映射为 Organic Social，除非明确的付费社交证据匹配更早的 Paid Social 规则。Direct 要求明确证据；Unknown 不并入 Direct。管理 Session 在营销映射前被拦截。

## 转化周期构建

用户内订单按 `order_ts` 和 `order_key` 排序。`conversion_touchpoints_strict` 在应用两个已批准 Admin 排除后保留严格规则。严格触点必须：

- 具有相同 `user_pseudo_id`；
- 开始时间不晚于订单时间；
- 开始时间不早于订单前 30 天；
- 有上一订单时，开始时间严格晚于上一订单时间；
- 可归因、非 Internal/Admin，且具有一个已批准营销渠道。

主表 `conversion_touchpoints` 加入一个范围狭窄的替代条件。Session 必须是当前订单自身的 `conversion_session_key`，开始不晚于订单，仍在 30 天内且可归因。其开始时间可以早于或等于上一订单时间。其他 Session 均不得跨越该边界。行标记为 `STANDARD_CONVERSION_CYCLE` 或 `CURRENT_CONVERSION_SESSION_EXCEPTION`；后者还设置 `is_same_session_multi_order_exception = TRUE`。

保留所有不同合格 Session，包括 Direct。触点按 Session 开始时间和 Session 键排序。路径长度为订单保留的 Session 数。严格路径保持互不重叠。一个 Session 只有在每个后续分配都是明确标记的当前转化 Session 例外时，才能出现在多个修订订单中。

没有保留触点的订单保存在 `orders_without_touchpoints`，并具有具体诊断原因。管理流量影响在排除前后均进行衡量。

已接受的收尾前结果在覆盖审计中重建为历史基准：覆盖 4,043 笔、未匹配 423 笔。它不作为主要收尾路径表。

## Phase 3 规则型归因

唯一主要归因输入是版本 `phase2b_closeout_v1_20260806` 的 `conversion_touchpoints`。9,577 个保留 Session 触点代表 4,457 笔可归因订单及 308,208.00 美元。`orders_without_touchpoints` 中 9 笔、622.00 美元从所有模型排除，但保留在核对报告中。

先在触点粒度计算权重。重复 Session 和重复渠道不压缩。最终 `attribution_results` 表将触点功劳聚合至 `order_key x model x channel`：

- 首次点击为 `touchpoint_number = 1` 分配 1。
- 末次点击为 `touchpoint_number = path_length` 分配 1。
- 末次非直接点击为最后一个不精确等于 `Direct` 的渠道分配 1。Unknown 仍合格；全 Direct 路径回退至最后一个 Direct 触点。
- 线性为每个保留 Session 分配 `1 / path_length`。
- 时间衰减计算 `0.5 ^ (seconds_before_conversion / 604800)`，然后用订单原始权重总和归一化每个原始权重。

每种模型中，`attributed_conversion` 等于归一化归因权重，`attributed_revenue` 等于 `order_revenue_usd` 乘该权重。每个订单和模型内，转化功劳和为 1，归因收入在批准数值容差内核对至订单收入。这些分配是描述性的，不是因果增量估计。

## Phase 4 旅程与 Markov 门

最终 `conversion_touchpoints` 是唯一转化路径来源。每笔订单成为 `Start -> channel(s) -> Conversion`；Phase 4 不从 Session 时间线重建转化路径。

非转化 Session 限于可归因、非管理行。旅程在有效购买之后或首次观察到的合格 Session 处开始；当下一 Session 在上一 `session_end_ts` 后满 30 天或更晚开始，或期间发生有效购买时切分。在不活跃期到期时或之前发生的购买，使分段旅程成为转化旅程。只有另行最终确定的转化路径进入 Conversion 总体。

观察边界为排他的 `2021-02-01 00:00:00 UTC`。Null 到期必须严格早于该边界，因此完成 Null 需要完整 30 天未来范围位于观察窗口内；否则候选为右删失，只保留为审计行并从转移估计排除。开始于 `2020-12-01 00:00:00 UTC` 前的旅程仍纳入并带明确左边界标记；该标记表示窗口前历史不完整，而非完全观察到的旅程开始。

执行总体含 4,457 条 Conversion 旅程和 177,632 条 Null 旅程。Markov 状态序列保留重复 Session 与渠道：

```text
Start -> channel(s) -> Conversion
Start -> channel(s) -> Null
```

每个相邻转移计数一次。转移估计基于旅程转移计数，不按收入加权。Conversion 与 Null 有显式概率为一的自环。从 Start 出发的一阶吸收概率为 `0.024477041446765`，核对至 Markov 旅程转化比例 `4457 / (4457 + 177632)`。

原始移除尝试从路径删除渠道出现、重连前驱与后继并重建矩阵。执行后否决，因为每条旅程保留原有 Conversion 或 Null 终点，导致总效应 `2.886579864025407e-15`，属于数值零；规范化门正确地没有创建表。

最终批准的 Anderl 风格移除算法作用于基准图。对每个渠道 `C`，独立从同一原始矩阵开始，移除 `C` 的行列，并把每个剩余状态原本流入 `C` 的概率重定向至 Null：

```text
P_removed(i, Null) = P_baseline(i, Null) + P_baseline(i, C)
```

其他剩余转移概率全部保留且不按比例重新归一化。Conversion 和 Null 继续保持概率为一的自环。每个缩减后行必须和为一，每个瞬态状态必须能到达吸收状态，并从 Start 求解最终 Conversion 概率。

该反事实把下一步原本进入被移除渠道的概率质量视为不转化，不对其他渠道替代建模。执行效应均有限且为正，总和为 `1.2126824577935318`，归一化为一。全局份额应用于 4,457 笔转化及 308,208 美元，因此本基准中的转化和收入份额相同。

`Unknown` 与 Direct 保持分离。它表示 Phase 2B 恢复后仍未解决的来源证据，不是真实营销渠道或可直接行动的预算目标。

## 验证与查询安全

每个可执行 BigQuery 查询都先 dry run，并使用配置的 1,000,000,000 字节 `maximum_bytes_billed` 上限。任何通配来源扫描都受 `_TABLE_SUFFIX` 限制。Phase 2B 验证涵盖 Session/订单数、键唯一性、来源层级核对、内部域排除、Direct/Unknown 证据、仅媒介质量、渠道有效性与唯一性、Admin 路径排除、Creator Academy 与 Google 推断例外、时间路径边界、未匹配订单核对、明确例外复用及不存在归因输出表。Phase 3 先重跑 70 项前置门，再验证输入版本/总体、精确模型公式、规范粒度唯一性、全 Direct 回退、每订单和每模型转化与收入核对、排除、渠道比较及不存在后期输出；全部 46 项通过。Phase 4 在执行旅程诊断前重新验证已存储 70 项 Phase 2B 和 46 项 Phase 3 门及当前模型总体；其 70 项检查验证旅程总体、删失、重叠、基准转移矩阵、吸收、移除效应、归一化归因、比较形状及回归，全部通过。

## Phase 5 敏感性与稳定性

每个确定性情景独立从已批准基准开始，不叠加两项模型变更。

### 转化回溯窗口

已批准的 `conversion_touchpoints` 表保持不变。情景保留 `seconds_before_conversion` 不超过完整 7、14 或 30 天的触点，然后重新计算触点编号和全部五个 Phase 3 公式。主要比较使用所有窗口均可归因的订单交集；并行总体影响视图报告各自然情景总体。两个执行视图均含同样的 4,457 笔订单，但继续明确分开，以防未来比较出现分母漂移。

### Null 不活跃期

14 天敏感性从 `session_end_ts` 起按完整 14 天不活跃期重复 Phase 4 分段。到期仍必须严格早于排他观察边界。最终 Conversion 路径仍为权威来源。与最终 Conversion 路径共享任何 Session 的完成 Null 候选整体排除；右删失候选从不进入模型。

### 重复渠道与 Direct

连续压缩将相邻相同渠道状态替换为一个，不触碰非连续重复。只有存在其他渠道时，Direct 情景才删除所有 Direct 状态；仅 Direct 路径及原始 Conversion/Null 终点保持不变。新形成的相邻相同非 Direct 状态不压缩。这是 Markov 路径敏感性，不是 Phase 3 末次非直接点击规则。

### 用户级聚类自助法

完成的 Phase 4 旅程按 `user_pseudo_id` 分组。500 次重复均使用 NumPy 生成器种子 `20260812`，从全部 179,498 位用户有放回抽样。抽中用户的完整 Conversion 和 Null 旅程集按其抽样次数进入。稀疏用户级边计数在每次重复中重建转移矩阵、已批准图状态移除效应、归一化份额和排名。排除右删失旅程；失败会带原因保留，实际执行失败为零。

排名按份额降序，以渠道名升序仅作确定性次级键。精确并列保留并列标记，因此次级排序不表示实质优劣。

Phase 5 层仍是描述性的，不能证明因果增量、增量收入或最优预算。

## Phase 6 业务报告

Phase 6 只读取经验证的本地 BigQuery 表，不重新扫描公开事件通配表。仅新建 runner 会重跑已存储 Phase 2B–5 验证门，记录每个受保护表的行数、修改时间戳、etag 和架构，对元数据快照进行哈希，在执行前 dry run 每个实质查询，并在执行后验证同一快照。

### 渠道漏斗阶段发生率

漏斗事件从 `event_base` 聚合至现有经验证 `session_key`，并与每 Session 一行的 `session_touchpoints` 关联。分析只包括可归因、非 Admin Session，并复用已批准 Phase 2B 渠道，不重建来源证据。

对于渠道 `c` 和阶段事件 `e`，报告比率为：

```text
阶段 Session 发生率(c, e)
  = c 中包含 e 的不同合格 Session
    / c 中所有归因合格 Session
```

四个事件为 `view_item`、`add_to_cart`、`begin_checkout` 和 `purchase`，它们是独立 Session 发生率。Phase 6 不验证事件是否严格依次发生，也不称其为阶段间转化率。

### 旅程汇总

`conversion_touchpoints` 仍是转化路径唯一来源。Phase 6 按订单对最终行分组一次，保留触点顺序及重复 Session/渠道，并计算：

- 可归因转化与收入总额；
- 单触点和多触点占比；
- 精确平均及中位路径长度；
- 路径长度分布；
- 完整渠道路径频率；
- 首次和末次触点渠道分布。

仪表板 mart 使用带标签长表，使 `PATH_LENGTH`、`CONVERTING_PATH`、`FIRST_TOUCH_CHANNEL` 与 `LAST_TOUCH_CHANNEL` 各自独立核对至同一个 4,457 笔订单、308,208 美元总体。

### 业务归因比较

`attribution_business_summary` 从经验证 `rule_markov_comparison` 输出开始，而非重新计算模型权重；它为每个模型加入收入份额和确定性收入排名。Markov 减末次点击差异直接来自经验证 Phase 4 比较，并为便于 BI 筛选在每个渠道/模型行重复。

确定性 Markov 排名/份额范围从 `phase5_sensitivity_results` 中四个已存储 `completed_outcomes` Markov 行汇总：基准、14 天 Null 不活跃期、连续渠道压缩和混合路径 Direct 移除。自助法均值、百分位区间、排名范围及 Top-k 频率复制自 `phase5_bootstrap_summary`。Phase 6 验证在数值容差内将这些字段与来源值逐一比较。

### 图表与证据分类

`src/attribution/reporting.py` 中的 Python 绘图函数只读取仪表板 mart 导出，并将 matplotlib 图表保存至本地 `reports/figures/`；生成图不得上传远端。漏斗图展示渠道样本量。长路径尾部仅为图表的 `10+` 显示进行合并，mart 保留精确长度。

报告将解释分为：

1. **稳健发现：**由确定性敏感性及自助法证据共同支持。
2. **方向性发现：**在旅程或归因中可见，但依赖假设或小样本。
3. **需要实验：**任何关于增量转化、增量收入或改变投资的陈述。

### 已批准的支出省略

公开样本没有可靠完整的渠道支出。因此 Phase 6 不创建模拟支出输入、ROAS 指标、预算 mart 或数值重分配。这是已批准范围决定，不是验证失败。未来可靠支出可以按渠道与时期关联至业务归因 mart，但依赖模型的 ROAS 仍是描述性的。

### 拟议增量实验

后续设计为配对地域随机化付费搜索提升实验。处理组地域接受所有者选择、预先规定且可行的支出增加，配对对照组维持日常业务。主要结果是每个地域的有效订单收入；使用预先规定的双重差分或协变量调整地域提升估计量衡量增量收入，以订单数、可用时的利润、转化率、获客成本、支出执行、蚕食效应及跨渠道变化作为护栏。

在得出任何因果预算结论前，必须评估地域外溢、竞价干扰、季节性、同期促销、处理不依从、跟踪变更、功效低及异质效应。该设计只是提案；不从归因推断任何实验结果。
