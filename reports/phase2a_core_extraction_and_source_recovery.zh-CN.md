# Phase 2A 核心提取与来源恢复

最后更新：2026-08-05

## 状态与范围

Phase 2A 已执行并验证。工作停在要求的内部域与有序渠道映射审批门。尚未创建最终渠道映射、`session_touchpoints`、转化路径、归因模型、ROAS、预算或仪表板输出。

公开混淆 GA4 电商样本仅用于作品集分析，结果不代表 Google Merchandise Store 的实际表现。

## 已创建 BigQuery 表

| 表 | 行数 | 状态 |
|---|---:|---|
| `event_base` | 4,295,584 | 已验证 |
| `orders` | 4,466 | 已按硬性验收数量验证 |
| `internal_referrer_domain_audit` | 5 | 拟议内部标记，未批准 |
| `session_source_candidates` | 360,129 | 临时结果，等待门审批 |
| `channel_source_coverage_audit` | 5 | 临时结果，等待门审批 |
| `source_medium_campaign_frequency` | 251 | 审查表 |
| `channel_mapping_proposal` | 11 | `PROPOSED_NOT_APPROVED` |
| `phase2a_validation_summary` | 17 | 全部检查通过 |

现有数据集应用 60 天默认表到期时间。除非经所有者批准修改元数据，最终表将在 2026-10-04 14:02:48 UTC 至 14:05:57 UTC 之间到期。

## 订单与核心核对

- 事件行：4,295,584。
- 不同事件日期：92，从 2020-11-01 至 2021-01-31。
- 合格去重订单：恰为 4,466。
- 去重后重复订单键：0。
- `orders` 中保留的无效交易标识：0。
- 去重后为空或非正数的美元订单收入：0。
- 复合来源候选 Session：360,129。
- 重复复合 Session 键：0。
- 结束早于开始的 Session：0。

## 来源解析覆盖

下列层级互斥。由于批准的内部域规则可能改变候选有效性，它们仍为临时结果。

| 优先级结果 | Session | 百分比 |
|---|---:|---:|
| 事件级来源元组 | 203,880 | 56.613047% |
| 外部引荐 | 15 | 0.004165% |
| 首次用户回退 | 53,368 | 14.819134% |
| 直接访问 | 59,966 | 16.651256% |
| 未知 | 42,900 | 11.912398% |
| **总计** | **360,129** | **100.000000%** |

直接访问要求明确的 `(direct)` 来源或 `(none)` 媒介。缺少可靠证据时归为未知。首次用户值继续明确标注为回退，不表示 Session 原生的获客证据。

## 内部引荐候选

| 引荐主机 | 注册域 | 引荐 Session | 是否被观察为页面位置注册域 | 提案 |
|---|---|---:|---|---|
| `shop.googlemerchandisestore.com` | `googlemerchandisestore.com` | 89,846 | 是 | 内部 |
| `www.googlemerchandisestore.com` | `googlemerchandisestore.com` | 122 | 是 | 内部 |
| `googlemerchandisestore.com` | `googlemerchandisestore.com` | 16 | 是 | 内部 |
| `admin.googlemerchandisestore.com` | `googlemerchandisestore.com` | 5 | 是，按注册域层级 | 内部 |
| `www.google.com` | `google.com` | 41 | 否 | 外部 |

应用临时优先级后，只有 15 个 Session 以 `www.google.com` 作为获胜的外部引荐；其他 26 个出现该引荐的 Session 被更高优先级证据解析。

## 来源/媒介/广告系列频率

完整 251 行审查表在 BigQuery 中为 `source_medium_campaign_frequency`，本地为 `reports/tables/phase2a_source_medium_campaign_frequency.csv`。最大的 20 种组合为：

| 层级 | 来源 | 媒介 | 广告系列 | Session | 百分比 |
|---|---|---|---|---:|---:|
| 事件 | `google` | `organic` | `(organic)` | 93,556 | 25.978469% |
| 直接访问 | `(direct)` | `(none)` | null | 59,966 | 16.651256% |
| 事件 | `shop.googlemerchandisestore.com` | `referral` | `(referral)` | 57,821 | 16.055636% |
| 未知 | null | null | null | 42,900 | 11.912398% |
| 首次用户回退 | `google` | `organic` | `(organic)` | 30,415 | 8.445585% |
| 事件 | null | `referral` | `(referral)` | 20,457 | 5.680465% |
| 首次用户回退 | null | `referral` | `(referral)` | 8,943 | 2.483277% |
| 事件 | null | `organic` | `(organic)` | 8,888 | 2.468005% |
| 事件 | `google` | `cpc` | null | 7,672 | 2.130348% |
| 首次用户回退 | `shop.googlemerchandisestore.com` | `referral` | `(referral)` | 7,001 | 1.944026% |
| 事件 | `googlemerchandisestore.com` | `referral` | `(referral)` | 5,992 | 1.663848% |
| 首次用户回退 | `google` | `cpc` | null | 4,272 | 1.186242% |
| 事件 | `analytics.google.com` | `referral` | `(referral)` | 3,455 | 0.959378% |
| 首次用户回退 | null | `organic` | `(organic)` | 2,737 | 0.760005% |
| 事件 | `Partners` | `affiliate` | `Data Share Promo` | 1,332 | 0.369867% |
| 事件 | `creatoracademy.youtube.com` | `referral` | `(referral)` | 889 | 0.246856% |
| 事件 | `baidu` | `organic` | `(organic)` | 696 | 0.193264% |
| 事件 | `sites.google.com` | `referral` | `(referral)` | 418 | 0.116070% |
| 事件 | `support.google.com` | `referral` | `(referral)` | 365 | 0.101353% |
| 事件 | `perksatwork.com` | `referral` | `(referral)` | 226 | 0.062755% |

已观察解析媒介中没有明确的付费社交媒介。唯一付费搜索风格的解析媒介是 `cpc`，全部 11,944 个此类 Session 的来源均为 `google`。Paid Social 可继续作为允许的渠道标签，但 Phase 2A 证据未识别出付费社交 Session。

## 精确有序渠道映射提案

下列谓词仅为审查材料，尚未执行渠道分配。首个匹配获胜。

1. **Direct**：`source_resolution_tier = 'Direct' OR LOWER(resolved_source) = '(direct)' OR LOWER(resolved_medium) = '(none)'`。
2. **Paid Social**：`REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(paid[_ -]?social|social[_ -]?paid)$') OR (REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(cpc|ppc|paidsearch|paid search|sem)$') AND REGEXP_CONTAINS(LOWER(COALESCE(resolved_source, '')), r'(^|\.)(facebook\.com|instagram\.com|twitter\.com|t\.co|linkedin\.com|pinterest\.[a-z.]+|tiktok\.com|youtube\.com)$'))`。
3. **Paid Search**：`REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(cpc|ppc|paidsearch|paid search|sem)$')`。
4. **Display**：`REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(display|banner|cpm|programmatic)$')`。
5. **Email**：`REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(email|e-mail|e_mail)$')`。
6. **Affiliates**：`REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^affiliate(s)?$')`。
7. **Organic Search**：`REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^organic$')`。
8. **Organic Social**：`REGEXP_CONTAINS(LOWER(COALESCE(resolved_medium, '')), r'^(social|social-network|social-media|sm)$') OR REGEXP_CONTAINS(LOWER(COALESCE(resolved_source, '')), r'(^|\.)(facebook\.com|instagram\.com|twitter\.com|t\.co|linkedin\.com|pinterest\.[a-z.]+|tiktok\.com|youtube\.com)$')`。
9. **Referral**：`source_resolution_tier = 'external_referrer' OR LOWER(COALESCE(resolved_medium, '')) = 'referral'`。
10. **Unknown**：`source_resolution_tier = 'Unknown' OR (resolved_source IS NULL AND resolved_medium IS NULL)`。
11. **Other**：`TRUE`。

原样 SQL 谓词存储于 `channel_mapping_proposal` 和 `reports/tables/phase2a_channel_mapping_proposal.csv`。

## 未决值及预期影响

| 决策 | 受影响临时 Session | 预期影响 |
|---|---:|---|
| 排除店铺域 `referral` 来源元组并重新解析，或保留它们 | 70,820（19.665176%） | 保留会把可能的自引荐归入 Referral；排除会将其重新分配给较低优先级证据、Direct 或 Unknown，并要求重建临时来源表。 |
| 保留来源为空的 `referral` 媒介为 Referral，或降为 Unknown | 29,400（8.163741%） | Referral 与 Unknown 之间会有实质移动。 |
| 将 `analytics.google.com` 视为 Referral、Other 或管理/内部 | 3,455（0.959378%） | 改变 Referral 规模及管理流量是否留在路径中。 |
| 将 `creatoracademy.youtube.com` 视为 Organic Social 或 Referral | 889（0.246856%） | 当前来源域谓词分配为 Organic Social；内容引荐例外会分配为 Referral。 |
| 将外部 `www.google.com` 推断为 Organic Search，或保留 Referral | 15（0.004165%） | 数值影响很小，但决定文档化的引荐推断规则。 |
| 保持明确缺失证据的 Session 为 Unknown | 42,900（11.912398%） | 在没有明确证据时改为 Direct 会大幅夸大 Direct；建议保留 Unknown。 |

建议的门决策：批准 `googlemerchandisestore.com` 及所有子域为内部；排除店铺域引荐元组并重新运行来源解析；保留明确的仅媒介引荐为 Referral；使用小型明确的管理主机例外清单；保留 Creator Academy 为 Referral；把外部 `www.google.com` 推断映射至 Organic Search；按原样批准其余有序规则。

## 验证结果

`phase2a_validation_summary` 中全部 17 项检查通过，涵盖事件数、日期覆盖、缺失事件用户/Session 标识、精确订单数、无效交易 ID、非正收入、重复订单/Session 键、Session 时间顺序、有效来源层级、覆盖核对以及映射提案规则数/优先级唯一性。

## 查询安全、字节数与恢复说明

所有可执行 SQL 均先 dry run。每个查询都使用 `maximum_bytes_billed = 1,000,000,000`，没有估算超过上限。每个来源通配查询都将 `_TABLE_SUFFIX` 限制在三个已批准月度范围之一。

| 查询 | 估算字节 | 实际处理 | 实际计费 |
|---|---:|---:|---:|
| `event_base` 2020-11 | 699,075,728 | 699,075,728 | 699,400,192 |
| `event_base` 2020-12 | 776,479,370 | 776,479,370 | 776,994,816 |
| `event_base` 2021-01 | 545,895,355 | 545,895,355 | 546,308,096 |
| `orders` | 470,873,306 | 470,873,306 | 471,859,200 |
| 内部引荐审计 | 736,246,845 | 736,246,845 | 737,148,928 |
| Session 来源候选 | 831,477,973 | 831,477,973 | 831,520,768 |
| 来源覆盖 | 6,064,441 | 6,064,441 | 10,485,760 |
| 来源频率 | 15,911,135 | 15,911,135 | 16,777,216 |
| 映射提案 | 0 | 0 | 0 |
| 验证汇总 | 442,639,606 | 442,639,606 | 443,547,648 |
| **成功 Phase 2A 总计** |  | **4,524,663,759** | **4,534,042,624** |

首次构建使用历史业务日期分区。现有数据集的 60 天默认分区到期规则立即使这些行到期，留下经确认为空的 `event_base` 和 `orders` 表。经所有者批准只删除这两个 0 行表后，构建改为聚类、非分区目标并成功重跑。该恢复尝试已处理 2,021,450,453 字节、计费 2,022,703,104 字节。一次只读 Phase 1 日期覆盖诊断处理 42,955,840 字节、计费 42,991,616 字节。计入成功工作、恢复开销及诊断，本任务共处理 6,589,070,052 字节、计费 6,599,737,344 字节。

## 审批门

所有者批准或修订内部域清单、店铺自引荐恢复、歧义值处理及精确有序映射之前，不得开始 Phase 2B。批准后，如果决策与当前候选不同，应重建临时来源表，然后只实施 Phase 2B。
