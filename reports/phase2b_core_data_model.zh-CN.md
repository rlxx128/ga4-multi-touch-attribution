# Phase 2B 核心数据模型与收尾

最后更新：2026-08-06

## 状态与范围

Phase 2B 收尾已执行并验证。带日期的修订加入了已批准的精确主机 `moma.corp.google.com` Internal/Admin 例外，保留严格路径表，并只向主路径加入当前订单自身的转化 Session 边界例外。未创建归因、ROAS、预算或仪表板输出。

这是对公开混淆 GA4 电商样本的作品集分析，结果不代表 Google Merchandise Store 的实际表现。

## 收尾前 Git 检查点

已接受的收尾前 Phase 2B 实施经审查，没有冲突、凭据、被跟踪 CSV 或非预期输出，并在独立 `phase2b-closeout` 分支提交为：

`b7a3644e3ad5757b7e439a92b176b24ee91c2a1d`

独立的 main 工作树当时干净，未被合并、重置或覆盖。

## 收尾文件与 BigQuery 表

收尾新增 `channel_mapping_v2.sql`、`05a_conversion_touchpoints_strict.sql` 和 `25_path_closeout_summary_audit.sql`；更新 Session/路径/审计/验证 SQL、受保护 runner 和测试；并修订 README、决策登记、方法、数据字典和本报告。

新建表：

- `conversion_touchpoints_strict`：9,155 行。
- `path_closeout_summary_audit`：1 行。

重建派生表：

- `internal_domain_rules`：3 行。
- `channel_mapping_rules`：11 行。
- `session_touchpoints`：360,129 行。
- `source_reprocessing_summary`：37 行。
- `channel_mapping_audit`：248 行。
- `conversion_touchpoints`：9,577 行。
- `order_path_coverage_audit`：4,466 行。
- `orders_without_touchpoints`：9 行。
- `internal_admin_path_impact_audit`：3 行。
- `admin_domain_candidate_audit`：1 个兼容行，现为已批准而非候选状态。
- `same_session_multiple_order_audit`：236 行。
- `path_length_distribution_audit`：26 个严格/修订行。
- `phase2b_validation_summary`：70 行。

`event_base`、`orders`、来源解析和 360,129 个 Session 的来源覆盖均未改变。`orders` 仍恰为 4,466 行。

## 带日期的收尾修订——2026-08-06

### 精确主机 Internal/Admin 处理

只有标准化主机 `analytics.google.com` 与 `moma.corp.google.com` 是已批准的 Internal/Admin 例外。不存在针对 `google.com` 注册域或子字符串的排除。

匹配的 Session 在 `session_touchpoints` 中保留原始来源字段，使用 `channel = 'Internal/Admin'`，具有主机特定 `internal_admin_reason`，并设置 `is_attribution_eligible = FALSE`。严格和修订路径都明确排除这些 Session。

| 主机 | Session | 用户 | 修订前排除行 | 排除前受影响订单 | 排除前收入 | 排除后仍覆盖订单 | 排除后覆盖收入 | 损失订单 | 损失收入 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `analytics.google.com` | 3,643 | 2,773 | 0 | 0 | 0 美元 | 0 | 0 美元 | 0 | 0 美元 |
| `moma.corp.google.com` | 77 | 67 | 18 | 16 | 1,455 美元 | 7 | 833 美元 | 9 | 622 美元 |
| **不同项总计** | **3,720** | **2,840** | **18** | **16** | **1,455 美元** | **7** | **833 美元** | **9** | **622 美元** |

Moma 在严格周期排除前影响 15 笔订单的 17 行和 1,430 美元。严格排除后，其中 7 笔、833 美元仍由其他营销触点覆盖；损失 8 笔订单和 597 美元。两种路径变体在排除后均没有 Admin 触点行。

订单不会仅因含有 Admin Session 而被排除：另有合格营销触点的 7 笔受影响订单仍被覆盖。

### 历史、严格与修订路径

重建并强验证已接受的收尾前结果作为历史基准。随后 `conversion_touchpoints_strict` 应用两个已批准 Admin 排除。主路径仅增加明确的当前转化 Session 例外。

| 指标 | 已接受历史基准 | 两项 Admin 排除后的严格路径 | 修订主路径 |
|---|---:|---:|---:|
| 覆盖订单 | 4,043 | 4,035 | 4,457 |
| 未匹配订单 | 423 | 431 | 9 |
| 覆盖订单收入 | 286,611 美元 | 286,014 美元 | 308,208 美元 |
| 订单覆盖率 | 90.528437% | 90.349306% | 99.798477% |
| 收入覆盖率 | 92.805427% | 92.612117% | 99.798595% |
| 触点行 | 9,172 | 9,155 | 9,577 |
| 已覆盖订单平均路径长度 | 2.268612 | 2.268897 | 2.148755 |
| 已覆盖多触点订单 | 2,134 | 2,133 | 2,133 |
| 已覆盖订单多触点率 | 52.782587% | 52.862454% | 47.857303% |

该例外恢复已接受历史中 423 笔未匹配订单的 422 笔。历史上被覆盖的 8 笔订单失去唯一的 moma 触点；另有 1 笔历史未匹配订单也只有 moma 转化 Session。因此最终覆盖 4,457 笔，未匹配 9 笔。

全部 9 笔未匹配订单涉及 8 位用户和 622 美元，原因均为 `NO_ELIGIBLE_TOUCHPOINT_AFTER_INTERNAL_EXCLUSION`。其中 8 笔历史上由 moma 覆盖，另 1 笔属于历史 423 笔未匹配总体。

### 明确例外与复用审计

修订路径新增 422 行，标记为 `CURRENT_CONVERSION_SESSION_EXCEPTION`，涉及 236 个 Session 和 219 位用户。同一批 236 个 Session 有 236 次标准分配及 422 次例外分配，共 658 次订单分配。

该例外要求 `session_key = conversion_session_key`，Session 开始不晚于转化，且开始时间在 30 天内。它只能跨越上一订单边界。结果：

- 重复订单/Session 行：0；
- 转化后触点：0；
- 回溯窗口违规：0；
- 跨越上一订单边界的标准行：0；
- 不匹配当前转化 Session 的例外行：0；
- 未批准历史 Session 分配：0；
- 严格路径跨周期 Session 复用：0。

批准的例外分配明确报告为例外，不称为未限定的 Session 复用违规。

## 来源与渠道核对

来源解析层级保持不变，仍核对至 360,129 个唯一 Session 和 100% 覆盖。Internal/Admin Session 有 3,720 个。最终营销渠道不变，仅 77 个 moma Session 从 Referral 移至 Internal/Admin，因此 Referral 包含 37,486 个 Session。映射版本为 `phase2b_channel_v2_20260806`，路径版本为 `phase2b_closeout_v1_20260806`。

## 验证

全部 70 项 BigQuery 检查通过。除现有来源、订单、渠道和覆盖检查外，收尾验证还确认：

- Admin 主机精确等于批准清单，不存在宽泛 `google.com` 规则；
- 所有 Admin Session 均为 `Internal/Admin` 且不可归因；
- 两个路径表均无 Admin 行；
- 已接受历史 4,043/423/9,172 核对；
- 严格及修订订单/触点核对；
- 重复、转化后、回溯窗口或无效边界行均为零；
- 每个例外均匹配当前订单转化 Session；
- 未批准的历史 Session 复用为零；
- 9 笔未匹配订单核对至要求的内部排除原因；
- 不存在归因输出表。

本地验证通过 38 项 pytest 测试，其中包括 12 项 Phase 2B runner 测试。限定范围 Ruff 检查和 `git diff --check` 均通过。仓库范围 Ruff 仍在本收尾范围外的 Phase 0/1 文件中报告 10 个既有问题。

## 查询安全与成本

每个可执行查询均先 dry run，并使用 `maximum_bytes_billed = 1,000,000,000`。最大收尾查询估算为 118,140,624 字节。未重新扫描公开通配表。

每个最终收尾查询的最近一次成功执行如下：

| 查询 | 估算/处理字节数 | 实际计费字节数 |
|---|---:|---:|
| 来源重处理预检 | 11,865,139 | 12,582,912 |
| 内部域规则 | 0 | 0 |
| 渠道映射规则 | 0 | 0 |
| Session 触点 | 79,959,778 | 80,740,352 |
| 来源重处理汇总 | 75,678,207 | 76,546,048 |
| 渠道映射审计 | 49,599,918 | 50,331,648 |
| 严格转化触点 | 74,427,789 | 74,448,896 |
| 修订转化触点 | 74,427,789 | 74,448,896 |
| 订单路径覆盖 | 41,386,083 | 41,943,040 |
| 无触点订单 | 1,500,193 | 10,485,760 |
| Internal/Admin 影响 | 35,673,879 | 36,700,160 |
| Moma 兼容审计 | 835 | 10,485,760 |
| 明确 Session 复用审计 | 3,652,122 | 20,971,520 |
| 路径长度分布 | 107,184 | 10,485,760 |
| 路径收尾汇总 | 819,609 | 31,457,280 |
| 验证汇总 | 118,140,624 | 136,314,880 |
| **最终规范总计** | **567,239,149** | **667,942,912** |

计入初始部分执行、修正后的完整运行及仅审计的历史基准重建，收尾共记录 33 个成功查询作业：处理 1,146,055,451 字节、计费 1,348,468,736 字节。一个目标聚类元数据作业在处理数据前失败，未报告处理或计费字节统计。随后通过保留兼容聚类列完成修正，没有删除表。

## 重要命令

```powershell
python -m pytest -q
python -m ruff check scripts/run_phase2b.py tests/test_phase2b_runner.py
python scripts/run_phase2b.py --execute --resume --closeout
python scripts/run_phase2b.py --execute --resume --closeout-audits
git diff --check
```

生成的 CSV 审查文件继续被忽略并仅保存在本地；没有 CSV 被 Git 跟踪。

## 剩余决策与停止门

- 本次收尾未批准执行 Phase 3 归因。
- 时间衰减半衰期、非转化路径、后续敏感性定义、模拟成本、仪表板工具和业务建议措辞仍待各自文档门批准。
- 现有 BigQuery 表继续沿用数据集 60 天默认到期设置。

Phase 2B 收尾后停止，不创建归因输出。
