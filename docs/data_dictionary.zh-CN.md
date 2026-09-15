# 数据字典

最后更新：2026-08-14

## 当前实施状态

Phase 3 至 Phase 6 输出均已在 `ga4-multi-touch-attribution.ga4_attribution` 中批准的 Phase 2B 转化路径层上创建并验证。Phase 6 新增三个面向业务的 mart 和一个验证对象，没有修改任何前期表。现有表沿用数据集的 60 天默认到期时间。

## 核心表

### `event_base`

- 粒度：每个 GA4 事件一行。
- 已验证行数：92 个日期、4,295,584 行。
- 物理设计：按 `user_pseudo_id`、`session_key`、`event_name` 聚类。
- 事件字段：`event_date`、`event_ts`、`event_timestamp`、`event_name`。
- 用户/Session 字段：`user_pseudo_id`、`user_id`、`ga_session_id`、`ga_session_number`、`session_key`。
- 来源/页面字段：事件来源/媒介/广告系列，页面位置与引荐值及其标准化主机和注册域，以及首次用户来源字段。
- 上下文字段：设备、操作系统、浏览器、国家、地区、城市。
- 商务字段：`transaction_id`、`purchase_revenue`、`purchase_revenue_in_usd`。

### `orders`

- 粒度：一个有效 `user_pseudo_id` 加修剪后的 `transaction_id`。
- 已验证行数：4,466。
- 键：`order_key`、`user_pseudo_id`、`transaction_id`。
- 时间：`order_ts`、`order_date`、`conversion_session_key`。
- 价值：`order_revenue_usd`，即观察到的最大美元购买收入。
- 诊断：购买事件数、重复数、观察收入的不同值数/最小值/最大值。

最早合格购买时间戳定义订单时间戳。

### `session_source_candidates`

- 粒度：每个复合用户 Session 一行。
- 已验证行数：360,129；重复 Session 键：0。
- 物理设计：按 `user_pseudo_id`、`source_resolution_tier` 聚类。
- 身份/时间：`user_pseudo_id`、`ga_session_id`、`session_key`、`session_start_ts`、`session_end_ts`、`session_date`。
- 计数：事件、Session 开始、购买及原始事件元组计数。
- 解析：`source_resolution_tier`、`resolved_source`、`resolved_medium`、`resolved_campaign`、`resolved_source_host`、`resolved_source_reg_domain`。
- 质量：`source_missing_flag`、`source_quality`、`is_inferred_source`、`inference_rule`。
- 证据：事件元组、外部引荐、首次用户回退及 Direct 证据时间戳；原始外部页面引荐与注册域。
- 内部证据标记：事件来源、页面引荐、首次用户来源及证据类型总数。
- 版本：`resolution_version = 'phase2b_source_v1_20260806'`。

允许且互斥的层级为 `event_level_source`、`external_referrer`、`first_user_fallback`、`Direct`、`Unknown`。

### `session_touchpoints`

- 粒度：每个复合用户 Session 一行。
- 已验证行数：360,129；重复 Session 键：0。
- 携带路径构建所需的 Session 时间、来源解析、质量、推断、原始引荐及版本字段。
- 管理字段：`is_internal_admin_traffic`、`internal_admin_reason`、`is_internal_admin_candidate`、`is_marketing_eligible`、`is_attribution_eligible`。
- 映射字段：`channel`、`mapping_rule_priority`、`mapping_rule_name`、`mapping_version`。

已批准的精确主机 Admin Session 在此表保留原始来源字段并设 `channel = 'Internal/Admin'`，但不可归因。每个 Session 恰有一个渠道。

### `conversion_touchpoints_strict`

- 粒度：每订单转化周期一个严格合格 Session。
- 已验证行数：应用两个 Admin 排除后，4,035 笔覆盖订单、9,155 行。
- 应用 30 天窗口和严格的上一订单边界。
- `touchpoint_eligibility_rule` 始终为 `STANDARD_CONVERSION_CYCLE`，`is_same_session_multi_order_exception` 始终为 false。
- 版本：`path_definition_version = 'phase2b_strict_v1_20260806'`。

### `conversion_touchpoints`

- 粒度：每订单转化周期一个合格 Session。
- 已验证行数：4,457 笔覆盖订单、9,577 行。
- 订单字段：订单身份、时间戳/日期、收入、上一订单时间戳及同时间戳订单诊断。
- 触点字段：`session_key`、`ga_session_id`、`touchpoint_ts`、`session_end_ts`、`touchpoint_number`、`path_length`、`seconds_before_conversion`。
- 来源/渠道字段：解析层级、来源/媒介/广告系列、来源质量、推断元数据、渠道及映射版本。
- 合格字段：`touchpoint_eligibility_rule`、`is_same_session_multi_order_exception`、`path_definition_version`。

触点不晚于转化、位于 30 天内，并排除批准的 Internal/Admin Session。每行要么位于严格周期内，要么是当前订单自身已标记的转化 Session 边界例外。

### `orders_without_touchpoints`

- 粒度：每笔没有营销触点的合格订单一行。
- 已验证行数：9。
- 包含订单/周期字段，以及所有用户 Session、订单前或订单时 Session、30 天窗口 Session、历史/严格/修订合格项、Internal/Admin Session 和归因合格 Session 的计数。
- `exclusion_reason` 记录首个适用路径失败原因。

当前 9 行全部为 `NO_ELIGIBLE_TOUCHPOINT_AFTER_INTERNAL_EXCLUSION`。

## Phase 3 归因表

### `attribution_results`

- 粒度：一个 `order_key`、模型和渠道；已验证 27,409 行。
- 订单审计字段：`user_pseudo_id`、`order_key`、`transaction_id`、`order_ts`、`order_date`、`order_revenue_usd`、`path_length`。
- 模型字段：`model`、`channel`、`attribution_weight`、`attributed_conversion`、`attributed_revenue`。
- 版本字段：`mapping_version`、`path_definition_version`、`attribution_version = 'phase3_rule_attribution_v1_20260809'`。
- `time_decay_half_life_days` 仅对 Time Decay 为 7，其他四个模型为空。

允许的模型为 First Click、Last Click、Last Non-direct Click、Linear、Time Decay。同一渠道重复实例的触点级权重在存储至规范粒度前求和。

### `model_comparison`

- 粒度：每个已观察归因渠道一行；已验证 8 行。
- 包含五个规则型模型的归因转化、归因收入、转化份额及收入份额。
- 包含 Last Click 相对 First Click、Linear 和 Time Decay 的收入差额。
- 精确核对至 `attribution_results` 的渠道/模型聚合。

### `phase3_validation_summary`

- 粒度：每项 Phase 3 验证检查一行；已验证 46 行。
- 字段：`check_id`、`observed_value`、`expected_value`、`validation_status`。
- 结果：70 项 Phase 2B 前置检查全部通过后，46 项检查全部通过。

## Phase 4 Markov 表

以下定义为当前经验证的 BigQuery 对象。

### `markov_journeys`

- 粒度：每条最终 Conversion 旅程、完成 Null 旅程或排除的右删失旅程一行。
- 身份/状态：`journey_id`、`user_pseudo_id`、可选 `order_key`、`journey_status`、`outcome_state`、`is_markov_included`。
- 时间：旅程开始、最后活动、30 天到期、下一次购买及排他数据集结束边界。
- 路径：有序 `channel_path`、有序 `session_key_path` 和 Session 数。
- 诊断：左边界标记、映射版本、不活跃截止及旅程定义版本。
- 已验证 273,683 行：4,457 条 Conversion、177,632 条 Null、91,594 条右删失旅程。
- 只有 182,089 条完成 Conversion/Null 行的 `is_markov_included = TRUE`；右删失行仅留作审计并从转移估计排除。77,918 条左边界完成 Null 行带截断标记继续纳入。

### `markov_transition_matrix`

- 粒度：稠密 `from_state x to_state` 矩阵每单元一行；已验证 144 行。
- 字段包括计数、概率、吸收/可达标记、状态顺序、基准 Conversion 概率和 Markov 版本。
- 基准含 12 个状态，保留观察到的自转移，并为 Conversion 和 Null 存储显式吸收行。
- 转移概率使用旅程转移计数而非收入权重。

### `markov_removal_effects`

- 粒度：每个已观察渠道一行；已验证 9 行。
- 字段包括基准及移除后 Conversion 概率、原始和容差调整效应、负效应标记及版本。
- 版本化方法移除渠道行/列，并把其所有剩余流入概率重定向至 Null。验证总移除效应：`1.2126824577935318`。

### `markov_attribution`

- 粒度：每个已观察渠道及其归一化 Markov 份额一行；已验证 9 行。
- 字段包括归因转化/收入、相同的转化/收入份额、基准概率、总效应和版本。
- 份额和为一，核对至 4,457 笔转化及 308,208 美元。

### `rule_markov_comparison`

- 粒度：五个 Phase 3 模型加 Markov 中，每渠道和模型一行；已验证 54 行。
- 包含归因总额/份额/排名及相对 Last Click 的绝对/相对差异。

### `phase4_validation_summary`

- 粒度：每项 Phase 4 验证检查一行，涵盖总体、右删失、重叠、状态转移、吸收、移除效应、归因核对、比较及 Phase 2B/3 回归。
- 已验证 70 行；全部通过。

## Phase 5 敏感性与稳定性表

### `phase5_sensitivity_results`

- 粒度：每情景、队列视图、归因模型和渠道一行；276 行。
- 存储情景总体及路径统计、渠道触点构成、适用时的移除效应、归因转化与收入、转化/收入份额、确定性排名、并列标记和情景版本。
- 包含总体影响及共同队列回溯视图。Unknown 和 Other 保持技术模型状态。

### `phase5_rank_stability`

- 粒度：每确定性情景、队列视图、模型和渠道一行；187 行。
- 存储基准/情景份额与排名、绝对排名变化、绝对百分点和相对份额变化、Spearman 相关、前三重合、最大绝对排名变化及并列诊断。

### `phase5_bootstrap_replicates`

- 粒度：每次成功重复和渠道一行，或每次失败重复一行；全部 500 次对 9 个渠道成功，故有 4,500 行。
- 存储种子、用户抽取数、不同选中聚类数、移除效应、Markov 份额、排名、重复转化概率、活跃状态数、状态和失败原因。

### `phase5_bootstrap_summary`

- 粒度：每个 Markov 渠道一行；9 行。
- 存储基准份额/效应/排名、自助法均值/中位数/标准差、第 2.5 与 97.5 百分位数、排名范围、平均/中位排名、前 1/3/5 概率、尝试/成功/失败数及种子。

### `phase5_scenario_manifest`

- 粒度：每个已批准情景一行；7 行。
- 记录单一变更假设、基准/敏感性标记、回溯窗口、Null 长度、重复渠道与 Direct 处理、自助法契约、总体、模型验证计数、并列约定及共同基准元数据指纹。

### `phase5_validation_summary`

- 粒度：每项 Phase 5 验收检查一行；56 行，全部通过。
- 涵盖 Phase 2B/3/4 回归、基准不变、情景隔离、转移及吸收状态有效性、效应/份额核对、共同队列一致性、排名有效性、自助法核算、种子、概率界及失败重复可见性。

## Phase 6 业务报告表

### `channel_funnel_summary`

- 粒度：每个已观察归因合格渠道一行；已验证 9 行。
- 总体：`session_touchpoints` 中 `is_attribution_eligible = TRUE` 的所有行，排除批准的 Internal/Admin 流量。
- 计数：Session 数及包含 `view_item`、`add_to_cart`、`begin_checkout` 或 `purchase` 的不同 Session 数。
- 比率：`view_item_session_rate`、`add_to_cart_session_rate`、`checkout_session_rate`、`purchase_session_rate`；每个分母均为分配至该渠道的所有归因合格 Session。
- 定义字段明确这些指标是渠道级漏斗阶段发生率，不编码 Session 内连续事件进展。
- 版本：已批准 Phase 2B 映射及 `reporting_version = 'phase6_business_reporting_v1_20260814'`。

### `journey_summary`

- 粒度：每个带标签汇总成员一行；已验证 722 行。
- `summary_type` 区分 `OVERALL`、`PATH_LENGTH`、`CONVERTING_PATH`、`FIRST_TOUCH_CHANNEL`、`LAST_TOUCH_CHANNEL` 行。
- 维度字段：`dimension_key`、`dimension_label`、确定性 `sort_order`。
- 指标：可归因转化/收入及其份额。
- `OVERALL` 行还存储平均/中位路径长度及单/多触点计数与份额。
- 每个非 overall 汇总类型都独立核对至 4,457 笔转化及 308,208 美元。
- 来源：最终 `conversion_touchpoints`；不重建转化周期。
- 版本：已批准映射/路径定义及 Phase 6 报告版本。

### `attribution_business_summary`

- 粒度：每渠道和模型一行；9 渠道 × 6 模型，已验证 54 行。
- 模型：First Click、Last Click、Last Non-direct Click、Linear、Time Decay、Markov。
- 核心指标：归因转化/收入、转化/收入份额及独立的模型特定转化和收入排名。
- 比较字段：Markov 减 Last Click 的绝对及相对转化/收入差异；为便于 BI 按渠道重复。
- 确定性稳定性：从 `phase5_sensitivity_results` 复现的已存储 Markov 情景数、排名/份额范围及排名第一/前三频率。
- 自助法稳定性：从 `phase5_bootstrap_summary` 复现的均值/中位数/标准差份额、第 2.5/97.5 百分位数、排名范围、前 1/3/5 频率、种子和重复核算。
- `is_business_presentation_channel` 仅对 Unknown 和 Other 为 false；不移除或重新归一化这两个技术状态。

### `phase6_validation_summary`

- 粒度：每项 Phase 6 验收检查一行；已验证 42 行。
- 结果：全部通过。
- 覆盖：已存储 Phase 2B–5 验证门、漏斗来源核对、比率/定义有效性、旅程总体与收入核对、六模型转化/收入核对、Markov 差异复现、Phase 5 自助法复现、自然搜索稳定性、已批准预算情景省略及报告版本。
- runner 还在执行前后单独验证所有受保护 Phase 2B–5 表的元数据快照和 SHA-256 指纹未变。

### 本地 Phase 6 报告产物

- CSV 导出：`reports/tables/` 中每个 Phase 6 BigQuery 对象一个文件。
- 基准元数据：`phase6_baseline_metadata.json` 记录受保护表快照与指纹。
- 图表：`reports/figures/` 中六个本地 PNG，覆盖渠道漏斗发生率、路径长度、主要路径、模型收入、Markov 对 Last Click 及 Markov 自助法不确定性；不得上传远端。
- 未创建模拟支出、ROAS、预算情景或仪表板对象。

## 规则与审计表

### `internal_domain_rules`

- 粒度：每个已批准域规则一行；3 行。
- 记录精确店铺注册域规则，以及批准的 `analytics.google.com` 和 `moma.corp.google.com` Admin 主机及其状态和原因。

### `channel_mapping_rules`

- 粒度：每个有序渠道规则一行；11 行。
- 字段：优先级、渠道、规则名、谓词描述、决策状态及映射版本。

### `source_reprocessing_session_audit`

- 粒度：每个 Session 一行；360,129 行。
- 存储 Phase 2A 之前值与重建 Phase 2B 之后值、内部证据标记、之后质量/推断字段、`resolution_changed` 和 `was_internal_storefront_resolved_referral`。
- 恰有 70,820 行标记为受影响店铺引荐。

### `source_reprocessing_summary`

- 粒度：每个前后层级、拟议/批准渠道、受影响标记及变更状态组合一行；37 行。
- 用途：核对全部 Session 及 70,820 个受影响子集的重新分配。

### `channel_source_coverage_audit`

- 粒度：每个已批准来源层级一行；5 行。
- 包含计数、份额、百分比、覆盖状态和解析版本。
- 计数核对至 360,129 个 Session 及 100% 覆盖。

### `source_medium_campaign_frequency`

- 粒度：每个层级/来源/媒介/广告系列/质量/推断组合一行；248 行。
- 包含 Session/用户计数及 Session 份额/百分比。

### `channel_mapping_audit`

- 粒度：每个来源元组、质量、Admin 状态、映射结果及版本组合一行；248 行。
- 包含 Session 和用户计数，是映射审查/核对表。

### `order_path_coverage_audit`

- 粒度：每笔合格订单一行；4,466 行。
- 包含历史基准、严格和修订 Session/路径计数，Admin 排除计数，恢复/损失标记及全部覆盖状态。

### `internal_admin_path_impact_audit`

- 粒度：每个已批准 Admin 主机及一个全主机总计一行；3 行。
- 报告保留 Session/用户、严格与修订排除前触点行/订单/收入、排除后覆盖订单/收入及损失订单/收入。

### `admin_domain_candidate_audit`

- 兼容表，含一个已批准 `moma.corp.google.com` 行。
- 报告其排除前后精确指标及 `APPROVED_EXACT_HOST_INTERNAL_ADMIN` 状态。

### `same_session_multiple_order_audit`

- 粒度：修订路径中分配给多笔订单的每个 Session 一行；236 行。
- 包含严格/修订分配数、标准和例外数、不匹配/未批准数及明确批准标记。旧 `session_reuse_violation` 列仅为现有聚类元数据保留，只对未批准或不匹配分配为 true。

### `path_length_distribution_audit`

- 粒度：每种路径变体与已观察路径长度一行；26 行。
- 包含订单数/收入、总数/总收入及订单/收入份额。

### `path_closeout_summary_audit`

- 粒度：一个收尾汇总；1 行。
- 核对已接受历史基准、Admin 后严格路径和修订例外路径的订单/收入覆盖、触点、平均路径长度、多触点率、恢复订单、明确例外复用及内部排除损失。

### `phase2b_validation_summary`

- 粒度：每项 Phase 2B 收尾检查一行；70 行。
- 字段：`check_id`、`observed_value`、`expected_value`、`validation_status`。
- 结果：全部 70 项通过。

## 历史 Phase 2A 审查表

`internal_referrer_domain_audit`、`channel_mapping_proposal` 和 `phase2a_validation_summary` 作为历史审批证据保留。提案已被已批准的版本化 Phase 2B 规则取代；它不是 `session_touchpoints` 使用的映射。

## 未实施

回溯窗口敏感性、重复渠道压缩、自助法稳定性、Shapley、ROAS、预算和仪表板输出未实施，仍在 Phase 4 范围之外。
