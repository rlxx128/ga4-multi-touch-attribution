WITH order_cycles AS (
  {{ORDER_CYCLES_QUERY}}
),
admin_sessions AS (
  SELECT
    resolved_source_host AS admin_host,
    session_key,
    user_pseudo_id,
    session_start_ts
  FROM `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.session_touchpoints`
  WHERE is_internal_admin_traffic
),
session_metrics_by_host AS (
  SELECT
    admin_host,
    COUNT(*) AS affected_session_count,
    COUNT(DISTINCT user_pseudo_id) AS affected_user_count
  FROM admin_sessions
  GROUP BY admin_host
),
session_metrics_total AS (
  SELECT
    'ALL_APPROVED_ADMIN_HOSTS' AS admin_host,
    COUNT(*) AS affected_session_count,
    COUNT(DISTINCT user_pseudo_id) AS affected_user_count
  FROM admin_sessions
),
admin_order_candidates AS (
  SELECT
    admin_sessions.admin_host,
    admin_sessions.session_key,
    orders.order_key,
    orders.order_revenue_usd,
    orders.previous_order_ts IS NULL
      OR admin_sessions.session_start_ts > orders.previous_order_ts
      AS is_strict_candidate,
    orders.previous_order_ts IS NULL
      OR admin_sessions.session_start_ts > orders.previous_order_ts
      OR admin_sessions.session_key = orders.conversion_session_key
      AS is_revised_candidate
  FROM order_cycles AS orders
  INNER JOIN admin_sessions
    ON orders.user_pseudo_id = admin_sessions.user_pseudo_id
    AND admin_sessions.session_start_ts <= orders.order_ts
    AND admin_sessions.session_start_ts >= TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)
),
order_host_metrics AS (
  SELECT
    admin_order_candidates.admin_host,
    admin_order_candidates.order_key,
    admin_order_candidates.order_revenue_usd,
    COUNTIF(is_strict_candidate) AS strict_pre_exclusion_touchpoint_rows,
    COUNTIF(is_revised_candidate) AS revised_pre_exclusion_touchpoint_rows
  FROM admin_order_candidates
  GROUP BY
    admin_order_candidates.admin_host,
    admin_order_candidates.order_key,
    admin_order_candidates.order_revenue_usd
),
order_total_metrics AS (
  SELECT
    'ALL_APPROVED_ADMIN_HOSTS' AS admin_host,
    admin_order_candidates.order_key,
    ANY_VALUE(admin_order_candidates.order_revenue_usd) AS order_revenue_usd,
    COUNTIF(is_strict_candidate) AS strict_pre_exclusion_touchpoint_rows,
    COUNTIF(is_revised_candidate) AS revised_pre_exclusion_touchpoint_rows
  FROM admin_order_candidates
  GROUP BY admin_order_candidates.order_key
),
all_order_metrics AS (
  SELECT
    admin_host,
    order_key,
    order_revenue_usd,
    strict_pre_exclusion_touchpoint_rows,
    revised_pre_exclusion_touchpoint_rows
  FROM order_host_metrics
  UNION ALL
  SELECT
    admin_host,
    order_key,
    order_revenue_usd,
    strict_pre_exclusion_touchpoint_rows,
    revised_pre_exclusion_touchpoint_rows
  FROM order_total_metrics
),
impact_by_host AS (
  SELECT
    all_order_metrics.admin_host,
    SUM(all_order_metrics.strict_pre_exclusion_touchpoint_rows)
      AS strict_touchpoint_rows_before_exclusion,
    COUNTIF(all_order_metrics.strict_pre_exclusion_touchpoint_rows > 0)
      AS strict_orders_before_exclusion,
    SUM(IF(
      all_order_metrics.strict_pre_exclusion_touchpoint_rows > 0,
      all_order_metrics.order_revenue_usd,
      0
    )) AS strict_order_revenue_before_exclusion,
    COUNTIF(
      all_order_metrics.strict_pre_exclusion_touchpoint_rows > 0
      AND coverage.path_covered_strict
    ) AS strict_orders_covered_after_exclusion,
    SUM(IF(
      all_order_metrics.strict_pre_exclusion_touchpoint_rows > 0
        AND coverage.path_covered_strict,
      all_order_metrics.order_revenue_usd,
      0
    )) AS strict_order_revenue_covered_after_exclusion,
    SUM(all_order_metrics.revised_pre_exclusion_touchpoint_rows)
      AS revised_touchpoint_rows_before_exclusion,
    COUNTIF(all_order_metrics.revised_pre_exclusion_touchpoint_rows > 0)
      AS revised_orders_before_exclusion,
    SUM(IF(
      all_order_metrics.revised_pre_exclusion_touchpoint_rows > 0,
      all_order_metrics.order_revenue_usd,
      0
    )) AS revised_order_revenue_before_exclusion,
    COUNTIF(
      all_order_metrics.revised_pre_exclusion_touchpoint_rows > 0
      AND coverage.path_covered_revised
    ) AS revised_orders_covered_after_exclusion,
    SUM(IF(
      all_order_metrics.revised_pre_exclusion_touchpoint_rows > 0
        AND coverage.path_covered_revised,
      all_order_metrics.order_revenue_usd,
      0
    )) AS revised_order_revenue_covered_after_exclusion
  FROM all_order_metrics
  INNER JOIN `{{TARGET_PROJECT}}.{{TARGET_DATASET}}.order_path_coverage_audit`
    AS coverage USING (order_key)
  GROUP BY all_order_metrics.admin_host
),
all_session_metrics AS (
  SELECT admin_host, affected_session_count, affected_user_count
  FROM session_metrics_by_host
  UNION ALL
  SELECT admin_host, affected_session_count, affected_user_count
  FROM session_metrics_total
)
SELECT
  all_session_metrics.admin_host,
  all_session_metrics.affected_session_count,
  all_session_metrics.affected_user_count,
  all_session_metrics.affected_session_count AS retained_session_count_after_exclusion,
  0 AS attribution_eligible_session_count_after_exclusion,
  COALESCE(impact_by_host.strict_touchpoint_rows_before_exclusion, 0)
    AS strict_touchpoint_rows_before_exclusion,
  0 AS strict_admin_touchpoint_rows_after_exclusion,
  COALESCE(impact_by_host.strict_orders_before_exclusion, 0)
    AS strict_orders_before_exclusion,
  COALESCE(impact_by_host.strict_order_revenue_before_exclusion, 0)
    AS strict_order_revenue_before_exclusion,
  COALESCE(impact_by_host.strict_orders_covered_after_exclusion, 0)
    AS strict_orders_covered_after_exclusion,
  COALESCE(impact_by_host.strict_order_revenue_covered_after_exclusion, 0)
    AS strict_order_revenue_covered_after_exclusion,
  COALESCE(impact_by_host.strict_orders_before_exclusion, 0)
    - COALESCE(impact_by_host.strict_orders_covered_after_exclusion, 0)
    AS strict_orders_lost_after_exclusion,
  COALESCE(impact_by_host.strict_order_revenue_before_exclusion, 0)
    - COALESCE(impact_by_host.strict_order_revenue_covered_after_exclusion, 0)
    AS strict_order_revenue_lost_after_exclusion,
  COALESCE(impact_by_host.revised_touchpoint_rows_before_exclusion, 0)
    AS revised_touchpoint_rows_before_exclusion,
  0 AS revised_admin_touchpoint_rows_after_exclusion,
  COALESCE(impact_by_host.revised_orders_before_exclusion, 0)
    AS revised_orders_before_exclusion,
  COALESCE(impact_by_host.revised_order_revenue_before_exclusion, 0)
    AS revised_order_revenue_before_exclusion,
  COALESCE(impact_by_host.revised_orders_covered_after_exclusion, 0)
    AS revised_orders_covered_after_exclusion,
  COALESCE(impact_by_host.revised_order_revenue_covered_after_exclusion, 0)
    AS revised_order_revenue_covered_after_exclusion,
  COALESCE(impact_by_host.revised_orders_before_exclusion, 0)
    - COALESCE(impact_by_host.revised_orders_covered_after_exclusion, 0)
    AS revised_orders_lost_after_exclusion,
  COALESCE(impact_by_host.revised_order_revenue_before_exclusion, 0)
    - COALESCE(impact_by_host.revised_order_revenue_covered_after_exclusion, 0)
    AS revised_order_revenue_lost_after_exclusion,
  'APPROVED_EXACT_HOST_INTERNAL_ADMIN' AS decision_status,
  'phase2b_channel_v2_20260806' AS mapping_version,
  'phase2b_closeout_v1_20260806' AS path_definition_version
FROM all_session_metrics
LEFT JOIN impact_by_host USING (admin_host)
