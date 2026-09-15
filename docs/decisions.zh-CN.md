# 决策登记

最后更新：2026-08-14

本登记将所有者已批准的分析定义与未决选择分开。公开 GA4 样本仅用于作品集分析，不代表 Google Merchandise Store 的实际业务表现。

## 已确认决策

| 决策 | 确认值 | 范围 | 确认日期 |
|---|---|---|---|
| 当前阶段 | Phase 6 业务报告已在 `main` 实施 | 已执行三个业务 mart、一个验证表、CSV 导出、六张图和最终报告；Phase 6 后停止审查 | 2026-08-14 |
| GCP 项目 | `ga4-multi-touch-attribution` | 已配置执行项目 | 2026-08-03 |
| BigQuery 数据集 | `ga4_attribution` | 仅现有数据集 | 2026-08-03 |
| BigQuery 位置 | `US` | 查询作业与目标表 | 2026-08-03 |
| GA4 来源 | `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` | 公开只读来源 | 2026-08-03 |
| 日期范围 | 2020-11-01 至 2021-01-31 | `_TABLE_SUFFIX` `20201101` 至 `20210131` | 2026-08-03 |
| 查询护栏 | Dry run 加每查询 `maximum_bytes_billed = 1,000,000,000` | 每个可执行查询 | 2026-08-03 |
| 转化事件 | `purchase` | 核心模型 | 2026-08-05 |
| 用户标识符 | `user_pseudo_id` | 旅程与订单归属 | 2026-08-05 |
| Session 标识符 | 对 `user_pseudo_id` 与 `ga_session_id` 计算 SHA-256 | 一个复合 Session 键 | 2026-08-05 |
| 订单标识符 | 对 `user_pseudo_id` 与非空有效 `transaction_id` 计算 SHA-256 | 排除空值、空白及不区分大小写的 `(not set)` | 2026-08-05 |
| 订单时间戳与收入 | 最早合格购买时间戳；观察到的最大 `purchase_revenue_in_usd` | 去重订单粒度 | 2026-08-05 |
| 内部店铺 | 精确匹配标准化注册域 `googlemerchandisestore.com`，含所有子域 | 从事件、引荐和首次用户来源证据排除；不做子字符串匹配 | 2026-08-06 |
| Session 来源优先级 | 最早非内部同事件元组；最早外部引荐；非内部首次用户回退；明确 Direct；Unknown | 重建来源候选 | 2026-08-06 |
| 仅媒介证据 | 保留来源为空的 `referral` 为 Referral；标记 `source_missing_flag` 与 `source_quality = 'medium_only'` | 不声称具体引荐网站 | 2026-08-06 |
| Google 引荐推断 | 外部 `www.google.com` 引荐变为 Organic Search | 保留原始引荐并标记推断/层级 | 2026-08-06 |
| 内部管理流量 | 精确标准化主机匹配 `analytics.google.com` 或 `moma.corp.google.com` | 保留为 `Internal/Admin`、保留来源字段、设 `is_attribution_eligible = FALSE`；不得排除全部 `google.com` | 2026-08-06 |
| Creator Academy | `creatoracademy.youtube.com` 映射为 Referral | 位于普通 YouTube 社交映射前的明确例外 | 2026-08-06 |
| YouTube 与付费社交 | 普通 YouTube 为 Organic Social；明确付费社交证据为 Paid Social | 即使未观察到，Paid Social 仍是有效标签 | 2026-08-06 |
| Direct 与 Unknown | Direct 要求明确 `(direct)` 来源或 `(none)` 媒介；缺少可靠证据为 Unknown | 不得把 Unknown 并入 Direct | 2026-08-06 |
| 渠道映射 | 先拦截 Internal/Admin，再按首个匹配的营销顺序：Direct、Paid Social、Paid Search、Display、Email、Affiliates、Organic Search、Organic Social、Referral、Unknown、Other | 版本 `phase2b_channel_v2_20260806` | 2026-08-06 |
| 基准回溯 | 30 天 | 转化路径 | 2026-08-05 |
| 严格转化周期 | 严格晚于上一订单并截至当前订单 | 两项 Admin 排除后保留为 `conversion_touchpoints_strict` | 2026-08-06 |
| 当前转化 Session 例外 | 当前订单自身 `conversion_session_key` 可跨越上一订单边界，但须不晚于转化且在 30 天内 | 标记每个例外；其他历史 Session 均不得跨界 | 2026-08-06 |
| Direct 处理 | 保留 Direct | 基准路径 | 2026-08-05 |
| 重复 Session | 保留每个不同 Session；仅明确标记的当前转化 Session 例外可复用 | Phase 2B 收尾路径 | 2026-08-06 |
| 同 Session 多订单 | 单独报告例外复用；不得把批准例外分配无条件称为复用违规 | Phase 2B 例外审计 | 2026-08-06 |
| 归因解释 | 仅描述性，绝非因果增量证明 | 整个项目 | 强制 |
| Phase 3 主要输入 | 修订收尾路径 `conversion_touchpoints` | 不得替换为 `conversion_touchpoints_strict` | 2026-08-09 |
| 时间衰减半衰期 | 7 天，使用 `0.5 ^ (seconds_before_conversion / 604800)` 并在订单内归一化 | 仅 Phase 3 基准；无替代半衰期 | 2026-08-09 |
| 末次非直接点击 | 最后一个不精确等于 Direct 的渠道；Unknown 仍合格；全 Direct 路径回退到最后的 Direct | 不因仅有 Direct 而丢弃合格订单 | 2026-08-09 |
| Phase 3 收入分配 | 同一归一化权重同时应用于一个转化和 `order_revenue_usd` | 两项指标在数值容差内核对 | 2026-08-09 |
| Phase 4 Null 不活跃期 | 从 `session_end_ts` 起完整 30 天；下一 Session 在到期时或之后开始即切分 | 14 天替代推迟至 Phase 5 | 2026-08-11 |
| Phase 4 购买边界 | 在不活跃期到期时或之前的有效购买使分段旅程为转化而非 Null | 所有有效订单仍为时间边界 | 2026-08-11 |
| Phase 4 观察边界 | 排他的 `2021-02-01 00:00:00 UTC`；Null 到期必须严格更早 | 更晚候选右删失并排除出 Markov 输入 | 2026-08-11 |
| Phase 4 左边界 | 保留观察期最初 30 天开始的旅程并明确标记截断 | 不声称完整观察窗口前历史 | 2026-08-11 |
| Phase 4 Markov 顺序与状态 | 一阶；保留 Direct、Unknown、Other、重复 Session、重复渠道及自转移 | Conversion 和 Null 为明确吸收状态 | 2026-08-11 |
| 否决的 Phase 4 移除语义 | 移除全部出现、重连前驱和后继，再重建路径与概率 | 已执行并否决：保留每个原始终点导致概率不变、效应数值为零 | 2026-08-11 |
| 最终 Phase 4 移除语义 | Anderl 风格图状态移除：独立从原始基准图移除每渠道行/列，将剩余 `i -> C` 概率重定向至 `i -> Null`；其他概率不按比例归一化 | 结构依赖假设；无渠道替代、无因果解释；版本 `phase4_markov_30d_anderl_v2_20260811` | 2026-08-11 |
| Phase 5 回溯比较 | 共同队列为主；总体影响视图保持可见 | 防止分母静默变化；执行共同队列含全部 4,457 笔可归因订单 | 2026-08-12 |
| Phase 5 Direct 敏感性 | 从混合渠道路径省略每个 Direct 状态；保留仅 Direct 路径；保持终点；不压缩新相邻状态 | 仅情景 Markov 路径变换；不同于末次非直接点击 | 2026-08-12 |
| Phase 5 重复渠道敏感性 | 只压缩连续相同渠道状态 | 非连续重复及所有旅程终点保持不变 | 2026-08-12 |
| Phase 5 自助法 | 用户级聚类；有放回抽样；保留每条完成旅程和抽中次数；500 次，种子 `20260812` | 本地重建矩阵、移除效应、份额和排名；排除右删失旅程 | 2026-08-12 |
| Phase 5 排名 | 份额降序，随后仅为确定性并列处理按渠道名升序 | 字典序不代表并列渠道实质优劣 | 2026-08-12 |
| Phase 6 漏斗分母 | 每个批准 Phase 2B 渠道的所有归因合格 Session | 独立报告 `view_item`、`add_to_cart`、`begin_checkout`、`purchase` 的 Session 事件发生率；不暗示有序阶段转化 | 2026-08-14 |
| Phase 6 预算范围 | 省略模拟支出、ROAS 和预算重分配 | 缺少可靠支出；仅保留未来扩展说明，不因省略而验证失败 | 2026-08-14 |
| Phase 6 仪表板交付 | 工具无关的 BigQuery mart、CSV 导出和适合演示的图表 | Phase 6 不构建 Power BI、Looker Studio、Tableau 或 Streamlit | 2026-08-14 |
| Phase 6 解释 | 将证据分为稳健、方向性或需要实验 | 归因与自助法稳定性仍为描述性；增量结果需要实验 | 2026-08-14 |
| Phase 6 实验 | 提议配对地域随机化付费搜索提升实验 | 仅提案；不捏造提升、增量收入或增量 ROAS | 2026-08-14 |

## Phase 2B 执行证据

- 重建来源候选和 `session_touchpoints` 均含 360,129 个唯一 Session。
- `orders` 仍恰为 4,466 笔合格去重订单。
- 70,820 个受店铺影响的临时 Session 均逐一重新解析并核对。
- 已接受收尾前历史基准保留在审计证据中：9,172 个触点、4,043 笔覆盖订单、423 笔未匹配订单。
- 两项 Admin 排除后，`conversion_touchpoints_strict` 含 9,155 行、覆盖 4,035 笔订单。
- 修订 `conversion_touchpoints` 含 9,577 行、覆盖 4,457 笔；恢复历史 423 笔未匹配中的 422 笔，明确报告最终 9 笔未匹配。
- 全部 70 项 Phase 2B 收尾验证通过。
- 未创建 First Click、Last Click、Last Non-direct、Linear、Time Decay、Markov、Shapley、ROAS、预算或仪表板输出。

执行覆盖、渠道、路径、例外与查询成本见 `reports/phase2b_core_data_model.zh-CN.md`。

## Phase 3 执行证据

- `attribution_results` 在批准的 `order_key x model x channel` 粒度有 27,409 行。
- `model_comparison` 对 8 个已观察路径渠道各有一行。
- 五个模型均覆盖全部 4,457 笔可归因订单，并分别核对至 4,457 笔归因转化及 308,208.00 美元。
- 9 笔排除订单和 622.00 美元继续位于每个模型外并在核对中可见，总计 4,466 笔订单和 308,830.00 美元。
- 70 项 Phase 2B 前置与 46 项 Phase 3 检查全部通过。
- 未创建 Markov、非转化路径、敏感性、自助法、Shapley、预算或仪表板输出。

详见 `reports/phase3_rule_based_attribution.zh-CN.md`。

## Phase 4 移除门决策历史

- 最终转化路径仍为 4,457 条旅程、3,705 位用户、9,577 个触点及 308,208 美元可归因收入。
- 已批准 30 天分段产生 177,632 条完成 Null 旅程，涉及 177,156 位用户和 229,522 个 Session。
- 右删失排除 91,594 条旅程及 117,470 个 Session；77,918 条完成 Null 带左边界标记。
- Conversion/Null Session 重叠及 Internal/Admin 状态均为零。
- 纳入的 182,089 条旅程产生 12 个状态及 `0.024477041446765` 的 Markov 旅程转化比例。
- 重连移除对九个渠道状态均不改变该概率。效应从零至 `4.440892098500626e-16`，总和 `2.886579864025407e-15`，低于批准的 `1e-12` 容差。
- 因此规范化按要求失败；未创建 Markov 旅程、转移、移除、归因、比较或 Phase 4 验证表。

该结果否决重连规则，并作为分析教训保留，而非隐藏或视为数值缺陷。

## Phase 4 最终执行证据

- 批准的图状态规则每次从原始基准矩阵开始，删除选定渠道行列，并把其流入概率质量重定向至 Null。
- 基准 Markov 旅程转化概率在 4,457 条 Conversion 和 177,632 条 Null 旅程上仍为 `0.02447704144676505`。
- 九个移除效应均有限且为正，无零或实质负效应；总和为 `1.2126824577935318`。
- 归一化 Markov 份额和为一，核对至 4,457 笔转化及 308,208 美元归因收入。
- 六个仅新建 Phase 4 输出全部创建；70 项 Phase 4、已存储 70 项 Phase 2B 和 46 项 Phase 3 检查全部通过。
- Phase 2、2B、3 及最终转化路径表未修改。

详见 `reports/phase4_markov_attribution.zh-CN.md`。

## Phase 5 执行证据

- 七个批准情景各自独立记录；每个确定性敏感性只改变一项假设。
- 7、14、30 天回溯保留相同的 4,457 笔订单、308,208 美元共同队列。平均路径从 1.764 增至 1.946、2.149；多触点占比从 38.16% 增至 43.17%、47.86%。
- 14 天 Null 情景含 231,966 条最终 Null、排除 42,017 条右删失；30 天为 177,632 和 91,594。
- 连续压缩移除 17,914 个状态，但 Markov 排名和份额除浮点精度外均不变。
- 混合路径 Direct 移除使 Direct 的 Markov 份额从 12.70% 降至 3.97%；九个完整状态排名顺序与基准相同。
- 500 次用户聚类自助法均成功。自然搜索每次均第一；自然搜索、引荐、未知每次均前三；联盟营销与自然社交偶尔交换第 7/8 名。
- 56 项 Phase 5 检查全部通过，包括存储的 Phase 2B/3/4 回归门、情景核对、自助法核算和未变基准元数据指纹。

详见 `reports/phase5_sensitivity_stability.zh-CN.md`。

## Phase 6 执行证据

- 归因合格漏斗总体含 9 个已观察渠道、356,409 个 Session；计数核对至 `session_touchpoints`，事件阶段标记核对至 `event_base`。
- 旅程 mart 的每个带标签分布均核对至 4,457 笔可归因转化及 308,208 美元；平均路径 2.149，中位数 1，多触点占比 47.86%。
- 归因业务 mart 含 9 渠道 × 6 个经验证模型，共 54 行。每模型均核对至 4,457 笔转化与 308,208 美元。
- 自然搜索在六个模型、四个已存储确定性 Markov 状态及 500 次自助法重复中均为收入第一。
- 不可变 Phase 2B–5 元数据指纹为 `17237893df65b1f0df9ab2266e3dbed26be6f216aa3098a0498b01b72a51218c`。
- `channel_funnel_summary` 9 行、`journey_summary` 722 行、`attribution_business_summary` 54 行、`phase6_validation_summary` 42 行。
- 42 项 Phase 6 检查全部通过。已生成 CSV 导出和六张适合演示的本地图表，未创建仪表板、模拟支出输入、ROAS 指标、预算表或 Shapley 模型；图片不得上传远端。

执行发现、局限、建议及增量实验提案见 `reports/phase6_business_reporting.zh-CN.md` 与 `reports/analysis_report.zh-CN.md`。

## 仍待决定

| 决策 | 何时需要 | 证据/预期影响 |
|---|---|---|
| BigQuery 表保留 | 数据集 60 天默认到期前或长期交接前 | 更改到期元数据需要另行批准。 |

## Phase 2B 收尾修订——2026-08-06

所有者批准 `moma.corp.google.com` 作为第二个精确主机 Internal/Admin 例外，并批准当前转化 Session 边界例外。执行收尾发现 77 个 moma Session 和 67 位用户。在修订时间合格性下，moma 在排除前贡献 16 笔订单的 18 个触点行及 1,455 美元订单收入；排除后其中 7 笔仍由其他营销触点覆盖，9 笔、622 美元未匹配。

转化 Session 例外在 236 个 Session 上新增 422 个标记触点。这些 Session 只有通过明确例外才能出现在多笔订单中。未批准历史 Session 分配、重复订单/Session 行、转化后行及回溯窗口违规均为零。
