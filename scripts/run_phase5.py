"""Build and validate approved Phase 5 sensitivity and stability outputs."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import statistics
import sys
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.run_phase4 import (  # noqa: E402
    Phase4Config,
    _dry_run,
    _execute_destination_query,
    _load_json_create_only,
    _query_without_destination,
    _table_exists,
    load_config,
    replace_placeholders,
    validate_query_sql,
)
from src.attribution.markov import (  # noqa: E402
    ABSORBING_STATES,
    START_STATE,
    build_transition_model_streaming,
    calculate_model_removal_effects,
    normalize_removal_effects,
)
from src.attribution.sensitivity import (  # noqa: E402
    ClusterJourney,
    compress_consecutive_channels,
    deterministic_ranks,
    omit_direct_from_mixed_path,
    run_user_cluster_bootstrap,
    spearman_rank_correlation,
    tied_channels,
)

OUTPUT_DIR = ROOT / "reports" / "tables"
COST_LOG_PATH = OUTPUT_DIR / "phase5_query_costs.csv"
SENSITIVITY_VERSION = "phase5_sensitivity_stability_v1_20260812"
BOOTSTRAP_SEED = 20260812
BOOTSTRAP_REPLICATES = 500
PHASE5_TABLES = (
    "phase5_sensitivity_results",
    "phase5_rank_stability",
    "phase5_bootstrap_replicates",
    "phase5_bootstrap_summary",
    "phase5_scenario_manifest",
    "phase5_validation_summary",
)
BASELINE_TABLES = (
    "orders",
    "conversion_touchpoints",
    "attribution_results",
    "model_comparison",
    "markov_journeys",
    "markov_transition_matrix",
    "markov_removal_effects",
    "markov_attribution",
    "rule_markov_comparison",
    "phase2b_validation_summary",
    "phase3_validation_summary",
    "phase4_validation_summary",
)


@dataclass(frozen=True)
class SqlAsset:
    query_id: str
    path: Path


LOOKBACK_SQL = SqlAsset(
    "01_conversion_lookback_scenarios",
    ROOT / "sql" / "intermediate" / "08_phase5_conversion_lookback_scenarios.sql",
)
NULL14_SQL = SqlAsset(
    "02_null_14d_scenario",
    ROOT / "sql" / "intermediate" / "09_phase5_null_14d_scenario.sql",
)
BASELINE_PATH_SQL = SqlAsset(
    "03_baseline_path_extract",
    ROOT / "sql" / "intermediate" / "10_phase5_scenario_paths.sql",
)
VALIDATION_SQL = SqlAsset(
    "09_phase5_validation",
    ROOT / "sql" / "validation" / "05_phase5_validation.sql",
)


def render_asset(asset: SqlAsset, config: Phase4Config) -> str:
    return replace_placeholders(
        asset.path.read_text(encoding="utf-8"),
        {
            "{{TARGET_PROJECT}}": config.gcp_project_id,
            "{{TARGET_DATASET}}": config.bq_dataset,
        },
    )


def _schema(fields: Sequence[tuple[str, str, str]]) -> list[Any]:
    from google.cloud import bigquery

    return [
        bigquery.SchemaField(name, field_type, mode=mode)
        for name, field_type, mode in fields
    ]


def sensitivity_schema() -> list[Any]:
    return _schema(
        (
            ("scenario_id", "STRING", "REQUIRED"),
            ("scenario_version", "STRING", "REQUIRED"),
            ("cohort_view", "STRING", "REQUIRED"),
            ("model", "STRING", "REQUIRED"),
            ("channel", "STRING", "REQUIRED"),
            ("attributable_order_count", "INTEGER", "REQUIRED"),
            ("attributable_revenue", "FLOAT", "REQUIRED"),
            ("conversion_journey_count", "INTEGER", "REQUIRED"),
            ("null_journey_count", "INTEGER", "REQUIRED"),
            ("right_censored_journey_count", "INTEGER", "REQUIRED"),
            ("average_path_length", "FLOAT", "REQUIRED"),
            ("median_path_length", "FLOAT", "REQUIRED"),
            ("multi_touch_share", "FLOAT", "REQUIRED"),
            ("channel_touchpoint_count", "INTEGER", "REQUIRED"),
            ("channel_touchpoint_share", "FLOAT", "REQUIRED"),
            ("removal_effect", "FLOAT", "NULLABLE"),
            ("attributed_conversions", "FLOAT", "REQUIRED"),
            ("attributed_revenue", "FLOAT", "REQUIRED"),
            ("conversion_share", "FLOAT", "REQUIRED"),
            ("revenue_share", "FLOAT", "REQUIRED"),
            ("conversion_rank", "INTEGER", "REQUIRED"),
            ("revenue_rank", "INTEGER", "REQUIRED"),
            ("is_conversion_share_tied", "BOOLEAN", "REQUIRED"),
            ("is_revenue_share_tied", "BOOLEAN", "REQUIRED"),
            ("baseline_conversion_probability", "FLOAT", "NULLABLE"),
            ("sensitivity_version", "STRING", "REQUIRED"),
        )
    )


def rank_schema() -> list[Any]:
    return _schema(
        (
            ("scenario_id", "STRING", "REQUIRED"),
            ("cohort_view", "STRING", "REQUIRED"),
            ("model", "STRING", "REQUIRED"),
            ("channel", "STRING", "REQUIRED"),
            ("baseline_share", "FLOAT", "REQUIRED"),
            ("scenario_share", "FLOAT", "REQUIRED"),
            ("baseline_rank", "INTEGER", "REQUIRED"),
            ("scenario_rank", "INTEGER", "REQUIRED"),
            ("absolute_rank_shift", "INTEGER", "REQUIRED"),
            ("absolute_percentage_point_change", "FLOAT", "REQUIRED"),
            ("relative_share_change", "FLOAT", "NULLABLE"),
            ("spearman_rank_correlation", "FLOAT", "REQUIRED"),
            ("top_3_overlap", "INTEGER", "REQUIRED"),
            ("maximum_absolute_rank_shift", "INTEGER", "REQUIRED"),
            ("baseline_is_tied", "BOOLEAN", "REQUIRED"),
            ("scenario_is_tied", "BOOLEAN", "REQUIRED"),
            ("sensitivity_version", "STRING", "REQUIRED"),
        )
    )


def manifest_schema() -> list[Any]:
    return _schema(
        (
            ("scenario_id", "STRING", "REQUIRED"),
            ("scenario_version", "STRING", "REQUIRED"),
            ("scenario_label", "STRING", "REQUIRED"),
            ("changed_assumption", "STRING", "REQUIRED"),
            ("changed_assumption_count", "INTEGER", "REQUIRED"),
            ("is_baseline", "BOOLEAN", "REQUIRED"),
            ("is_owner_approved", "BOOLEAN", "REQUIRED"),
            ("lookback_days", "INTEGER", "REQUIRED"),
            ("null_inactivity_days", "INTEGER", "REQUIRED"),
            ("repeated_channel_treatment", "STRING", "REQUIRED"),
            ("direct_treatment", "STRING", "REQUIRED"),
            ("bootstrap_replicates", "INTEGER", "REQUIRED"),
            ("bootstrap_seed", "INTEGER", "REQUIRED"),
            ("conversion_journey_count", "INTEGER", "REQUIRED"),
            ("null_journey_count", "INTEGER", "REQUIRED"),
            ("right_censored_journey_count", "INTEGER", "REQUIRED"),
            ("right_censored_in_model_count", "INTEGER", "REQUIRED"),
            ("internal_admin_state_count", "INTEGER", "REQUIRED"),
            ("invalid_transition_row_count", "INTEGER", "REQUIRED"),
            ("invalid_absorbing_state_count", "INTEGER", "REQUIRED"),
            ("materially_negative_effect_count", "INTEGER", "REQUIRED"),
            ("rank_tie_break_rule", "STRING", "REQUIRED"),
            ("baseline_fingerprint_sha256", "STRING", "REQUIRED"),
            ("sensitivity_version", "STRING", "REQUIRED"),
        )
    )


def bootstrap_replicate_schema() -> list[Any]:
    return _schema(
        (
            ("replicate_id", "INTEGER", "REQUIRED"),
            ("seed", "INTEGER", "REQUIRED"),
            ("sampled_user_draws", "INTEGER", "REQUIRED"),
            ("unique_user_clusters_selected", "INTEGER", "REQUIRED"),
            ("channel", "STRING", "NULLABLE"),
            ("removal_effect", "FLOAT", "NULLABLE"),
            ("markov_share", "FLOAT", "NULLABLE"),
            ("channel_rank", "INTEGER", "NULLABLE"),
            ("baseline_conversion_probability", "FLOAT", "NULLABLE"),
            ("active_state_count", "INTEGER", "NULLABLE"),
            ("replicate_status", "STRING", "REQUIRED"),
            ("failure_reason", "STRING", "NULLABLE"),
            ("bootstrap_version", "STRING", "REQUIRED"),
        )
    )


def bootstrap_summary_schema() -> list[Any]:
    numeric_fields = (
        "baseline_markov_share",
        "bootstrap_mean_share",
        "bootstrap_median_share",
        "bootstrap_share_stddev",
        "share_percentile_2_5",
        "share_percentile_97_5",
        "baseline_removal_effect",
        "bootstrap_mean_removal_effect",
        "bootstrap_median_removal_effect",
        "removal_effect_stddev",
        "removal_effect_percentile_2_5",
        "removal_effect_percentile_97_5",
        "mean_bootstrap_rank",
        "median_bootstrap_rank",
        "probability_top_1",
        "probability_top_3",
        "probability_top_5",
    )
    fields: list[tuple[str, str, str]] = [
        ("channel", "STRING", "REQUIRED"),
        ("seed", "INTEGER", "REQUIRED"),
        ("attempted_replicates", "INTEGER", "REQUIRED"),
        ("successful_replicates", "INTEGER", "REQUIRED"),
        ("failed_replicates", "INTEGER", "REQUIRED"),
    ]
    fields.extend((name, "FLOAT", "REQUIRED") for name in numeric_fields[:12])
    fields.append(("baseline_rank", "INTEGER", "REQUIRED"))
    fields.extend((name, "FLOAT", "REQUIRED") for name in numeric_fields[12:14])
    fields.extend(
        (
            ("minimum_observed_rank", "INTEGER", "REQUIRED"),
            ("maximum_observed_rank", "INTEGER", "REQUIRED"),
        )
    )
    fields.extend((name, "FLOAT", "REQUIRED") for name in numeric_fields[14:])
    fields.append(("bootstrap_version", "STRING", "REQUIRED"))
    return _schema(fields)


def _metadata_snapshot(client: Any, config: Phase4Config) -> dict[str, dict[str, object]]:
    snapshot: dict[str, dict[str, object]] = {}
    for name in BASELINE_TABLES:
        table = client.get_table(config.table_id(name))
        snapshot[name] = {
            "num_rows": int(table.num_rows),
            "modified": table.modified.isoformat() if table.modified else None,
            "etag": table.etag,
            "schema": [(field.name, field.field_type, field.mode) for field in table.schema],
        }
    return snapshot


def _fingerprint(snapshot: Mapping[str, object]) -> str:
    payload = json.dumps(snapshot, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _validate_prerequisites(client: Any, config: Phase4Config) -> tuple[Any, int]:
    sql = f"""
WITH phase3 AS (
  SELECT model, COUNT(DISTINCT order_key) AS orders,
    SUM(attributed_conversion) AS conversions, SUM(attributed_revenue) AS revenue
  FROM `{config.table_id('attribution_results')}` GROUP BY model
)
SELECT
  (SELECT COUNT(*) FROM `{config.table_id('orders')}`) AS orders,
  (SELECT COUNT(DISTINCT order_key) FROM `{config.table_id('conversion_touchpoints')}`)
    AS attributable_orders,
  (SELECT ROUND(SUM(revenue), 2) FROM (
    SELECT ANY_VALUE(order_revenue_usd) AS revenue
    FROM `{config.table_id('conversion_touchpoints')}` GROUP BY order_key
  )) AS attributable_revenue,
  (SELECT COUNT(*) FROM phase3) AS phase3_models,
  (SELECT COUNTIF(orders != 4457 OR ABS(conversions - 4457) > 1e-9
    OR ABS(revenue - 308208) > 1e-6) FROM phase3) AS phase3_failures,
  (SELECT COUNT(*) FROM `{config.table_id('markov_journeys')}`) AS markov_journeys,
  (SELECT COUNTIF(is_markov_included AND outcome_state = 'Conversion')
    FROM `{config.table_id('markov_journeys')}`) AS conversions,
  (SELECT COUNTIF(is_markov_included AND outcome_state = 'Null')
    FROM `{config.table_id('markov_journeys')}`) AS null_journey_count,
  (SELECT SUM(transition_count) FROM `{config.table_id('markov_transition_matrix')}`)
    AS transitions,
  (SELECT COUNTIF(validation_status != 'PASS')
    FROM `{config.table_id('phase4_validation_summary')}`) AS phase4_failures
""".strip()
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    job, rows = _query_without_destination(client, sql, config)
    row = next(iter(rows))
    observed = tuple(int(row[name]) if name != "attributable_revenue" else float(row[name]) for name in (
        "orders", "attributable_orders", "attributable_revenue", "phase3_models",
        "phase3_failures", "markov_journeys", "conversions", "null_journey_count",
        "transitions", "phase4_failures",
    ))
    expected = (4466, 4457, 308208.0, 5, 0, 273683, 4457, 177632, 421188, 0)
    if observed != expected:
        raise RuntimeError(f"Phase 5 prerequisites failed: {observed} != {expected}")
    return job, estimate


def _query_asset(
    client: Any,
    config: Phase4Config,
    asset: SqlAsset,
) -> tuple[Any, Iterable[Any], int, str]:
    sql = render_asset(asset, config)
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    if estimate > config.maximum_bytes_billed:
        raise RuntimeError(f"{asset.query_id} exceeds the billing cap")
    job, rows = _query_without_destination(client, sql, config)
    return job, rows, estimate, sql


def _cost_record(
    query_id: str,
    source: str,
    destination: str,
    sql: str,
    estimate: int,
    job: Any | None,
    rows: int | str,
) -> dict[str, object]:
    return {
        "query_id": query_id,
        "source": source,
        "destination": destination,
        "sql_sha256": hashlib.sha256(sql.encode("utf-8")).hexdigest(),
        "estimated_bytes": estimate,
        "maximum_bytes_billed": 1_000_000_000,
        "actual_bytes_processed": int(job.total_bytes_processed or 0) if job else "",
        "actual_bytes_billed": int(job.total_bytes_billed or 0) if job else "",
        "destination_row_count": rows,
        "job_id": job.job_id if job else "",
        "status": "EXECUTED" if job else "DRY_RUN_PASSED",
    }


def _write_costs(records: Sequence[Mapping[str, object]]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    fields = list(records[0])
    with COST_LOG_PATH.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)


def _load_rows(
    client: Any,
    config: Phase4Config,
    table_name: str,
    rows: list[dict[str, object]],
    schema: list[Any],
) -> None:
    if not rows:
        raise RuntimeError(f"Refusing to create empty Phase 5 table: {table_name}")
    _load_json_create_only(client, config, table_name, rows, schema)
    observed = int(client.get_table(config.table_id(table_name)).num_rows)
    if observed != len(rows):
        raise RuntimeError(f"{table_name} row count {observed} != {len(rows)}")


def _rank_result_groups(rows: list[dict[str, object]]) -> None:
    grouped: dict[tuple[str, str, str], list[dict[str, object]]] = {}
    for row in rows:
        key = (str(row["scenario_id"]), str(row["cohort_view"]), str(row["model"]))
        grouped.setdefault(key, []).append(row)
    for group in grouped.values():
        conversion_values = {
            str(row["channel"]): float(row["conversion_share"]) for row in group
        }
        revenue_values = {
            str(row["channel"]): float(row["revenue_share"]) for row in group
        }
        conversion_ranks = deterministic_ranks(conversion_values)
        revenue_ranks = deterministic_ranks(revenue_values)
        conversion_ties = tied_channels(conversion_values)
        revenue_ties = tied_channels(revenue_values)
        for row in group:
            channel = str(row["channel"])
            row["conversion_rank"] = conversion_ranks[channel]
            row["revenue_rank"] = revenue_ranks[channel]
            row["is_conversion_share_tied"] = channel in conversion_ties
            row["is_revenue_share_tied"] = channel in revenue_ties


def _lookback_rows(source_rows: Iterable[Any]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for source in source_rows:
        row = dict(source.items())
        row.pop("lookback_days")
        row.update(
            {
                "scenario_version": str(row["scenario_id"]).lower(),
                "conversion_journey_count": int(row["attributable_order_count"]),
                "null_journey_count": 0,
                "right_censored_journey_count": 0,
                "removal_effect": None,
                "baseline_conversion_probability": None,
                "sensitivity_version": SENSITIVITY_VERSION,
            }
        )
        rows.append(row)
    _rank_result_groups(rows)
    return rows


def _path_tuple(channels: Sequence[str], outcome: str) -> tuple[str, ...]:
    if outcome not in ABSORBING_STATES:
        raise RuntimeError(f"Unexpected outcome state: {outcome}")
    return (START_STATE, *(str(channel) for channel in channels), outcome)


def _scenario_metrics(
    journeys: Sequence[ClusterJourney],
) -> dict[str, object]:
    lengths = [len(journey.path) - 2 for journey in journeys]
    touchpoints: Counter[str] = Counter(
        state
        for journey in journeys
        for state in journey.path[1:-1]
    )
    total = sum(touchpoints.values())
    return {
        "average_path_length": sum(lengths) / len(lengths),
        "median_path_length": float(statistics.median(lengths)),
        "multi_touch_share": sum(length > 1 for length in lengths) / len(lengths),
        "touchpoints": touchpoints,
        "touchpoint_total": total,
    }


def _calculate_markov(
    journeys: Sequence[ClusterJourney],
) -> tuple[Any, float, dict[str, float], dict[str, float], int]:
    model = build_transition_model_streaming(journey.path for journey in journeys)
    probability, removals = calculate_model_removal_effects(model)
    negative_count = sum(result.materially_negative for result in removals)
    if negative_count:
        raise RuntimeError("Materially negative deterministic removal effect detected")
    effects = {result.channel: result.removal_effect for result in removals}
    shares = normalize_removal_effects(effects)
    return model, probability, effects, shares, negative_count


def _markov_rows(
    scenario_id: str,
    journeys: Sequence[ClusterJourney],
    *,
    null_journeys: int,
    right_censored_journeys: int,
) -> tuple[list[dict[str, object]], Any, dict[str, float], dict[str, float], int]:
    model, probability, effects, shares, negative_count = _calculate_markov(journeys)
    metrics = _scenario_metrics(journeys)
    ranks = deterministic_ranks(shares)
    ties = tied_channels(shares)
    conversions = sum(journey.path[-1] == "Conversion" for journey in journeys)
    rows: list[dict[str, object]] = []
    for channel in sorted(shares):
        share = shares[channel]
        rows.append(
            {
                "scenario_id": scenario_id,
                "scenario_version": scenario_id.lower(),
                "cohort_view": "completed_outcomes",
                "model": "Markov",
                "channel": channel,
                "attributable_order_count": conversions,
                "attributable_revenue": 308208.0,
                "conversion_journey_count": conversions,
                "null_journey_count": null_journeys,
                "right_censored_journey_count": right_censored_journeys,
                "average_path_length": metrics["average_path_length"],
                "median_path_length": metrics["median_path_length"],
                "multi_touch_share": metrics["multi_touch_share"],
                "channel_touchpoint_count": int(metrics["touchpoints"].get(channel, 0)),
                "channel_touchpoint_share": float(
                    metrics["touchpoints"].get(channel, 0) / metrics["touchpoint_total"]
                ),
                "removal_effect": effects[channel],
                "attributed_conversions": conversions * share,
                "attributed_revenue": 308208.0 * share,
                "conversion_share": share,
                "revenue_share": share,
                "conversion_rank": ranks[channel],
                "revenue_rank": ranks[channel],
                "is_conversion_share_tied": channel in ties,
                "is_revenue_share_tied": channel in ties,
                "baseline_conversion_probability": probability,
                "sensitivity_version": SENSITIVITY_VERSION,
            }
        )
    return rows, model, effects, shares, negative_count


def _rank_rows(
    scenario_rows: Sequence[dict[str, object]],
    baseline_rows: Sequence[dict[str, object]],
) -> list[dict[str, object]]:
    scenario_values = {str(row["channel"]): float(row["conversion_share"]) for row in scenario_rows}
    baseline_values = {str(row["channel"]): float(row["conversion_share"]) for row in baseline_rows}
    if set(scenario_values) != set(baseline_values):
        raise RuntimeError("Scenario and baseline rankings have different channels")
    scenario_ranks = deterministic_ranks(scenario_values)
    baseline_ranks = deterministic_ranks(baseline_values)
    correlation = spearman_rank_correlation(baseline_ranks, scenario_ranks)
    baseline_top3 = {channel for channel, rank in baseline_ranks.items() if rank <= 3}
    scenario_top3 = {channel for channel, rank in scenario_ranks.items() if rank <= 3}
    maximum_shift = max(
        abs(scenario_ranks[channel] - baseline_ranks[channel])
        for channel in baseline_values
    )
    baseline_ties = tied_channels(baseline_values)
    scenario_ties = tied_channels(scenario_values)
    sample = scenario_rows[0]
    return [
        {
            "scenario_id": sample["scenario_id"],
            "cohort_view": sample["cohort_view"],
            "model": sample["model"],
            "channel": channel,
            "baseline_share": baseline_values[channel],
            "scenario_share": scenario_values[channel],
            "baseline_rank": baseline_ranks[channel],
            "scenario_rank": scenario_ranks[channel],
            "absolute_rank_shift": abs(
                scenario_ranks[channel] - baseline_ranks[channel]
            ),
            "absolute_percentage_point_change": abs(
                scenario_values[channel] - baseline_values[channel]
            ) * 100.0,
            "relative_share_change": (
                (scenario_values[channel] - baseline_values[channel])
                / baseline_values[channel]
                if baseline_values[channel] != 0
                else None
            ),
            "spearman_rank_correlation": correlation,
            "top_3_overlap": len(baseline_top3 & scenario_top3),
            "maximum_absolute_rank_shift": maximum_shift,
            "baseline_is_tied": channel in baseline_ties,
            "scenario_is_tied": channel in scenario_ties,
            "sensitivity_version": SENSITIVITY_VERSION,
        }
        for channel in sorted(baseline_values)
    ]


def _model_groups(
    rows: Sequence[dict[str, object]],
) -> dict[tuple[str, str, str], list[dict[str, object]]]:
    groups: dict[tuple[str, str, str], list[dict[str, object]]] = {}
    for row in rows:
        key = (str(row["scenario_id"]), str(row["cohort_view"]), str(row["model"]))
        groups.setdefault(key, []).append(row)
    return groups


def _model_diagnostics(model: Any) -> tuple[int, int, int]:
    invalid_rows = sum(
        abs(float(model.transition_probabilities[index].sum()) - 1.0) > 1e-12
        for index in range(len(model.states))
    )
    invalid_absorbers = 0
    for absorber in ABSORBING_STATES:
        index = model.states.index(absorber)
        expected = [0.0] * len(model.states)
        expected[index] = 1.0
        if any(
            abs(float(observed) - target) > 1e-12
            for observed, target in zip(
                model.transition_probabilities[index], expected, strict=True
            )
        ):
            invalid_absorbers += 1
    internal_admin = int("Internal/Admin" in model.states)
    return invalid_rows, invalid_absorbers, internal_admin


def _manifest_rows(
    fingerprint: str,
    model_details: Mapping[str, tuple[Any, int]],
) -> list[dict[str, object]]:
    definitions = (
        ("P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1", "Approved Phase 4 baseline", "none", 0, True, 30, 30, "retained", "retained", 0, 0, 4457, 177632, 91594),
        ("P5_A_LB14_V1", "14-day conversion lookback", "conversion_lookback", 1, False, 14, 30, "retained", "retained", 0, 0, 4457, 177632, 91594),
        ("P5_B_LB7_V1", "7-day conversion lookback", "conversion_lookback", 1, False, 7, 30, "retained", "retained", 0, 0, 4457, 177632, 91594),
        ("P5_C_NULL14_V1", "14-day Null inactivity", "null_inactivity", 1, False, 30, 14, "retained", "retained", 0, 0, 4457, 231966, 42017),
        ("P5_D_COMPRESS_CONSECUTIVE_V1", "Consecutive channel compression", "repeated_channel_treatment", 1, False, 30, 30, "consecutive_compressed", "retained", 0, 0, 4457, 177632, 91594),
        ("P5_E_DIRECT_MIXED_OMIT_V1", "Mixed-path Direct omission", "direct_treatment", 1, False, 30, 30, "retained", "mixed_path_omit_direct_only_fallback", 0, 0, 4457, 177632, 91594),
        ("P5_F_BOOTSTRAP_USER_500_V1", "User cluster bootstrap", "sampling_variation", 1, False, 30, 30, "retained", "retained", 500, BOOTSTRAP_SEED, 4457, 177632, 91594),
    )
    rows: list[dict[str, object]] = []
    for definition in definitions:
        (
            scenario_id, label, changed, count, baseline, lookback, null_days,
            repeated, direct, replicates, seed, conversions, nulls, censored,
        ) = definition
        model, negative_count = model_details.get(
            scenario_id,
            model_details["P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1"],
        )
        invalid_rows, invalid_absorbers, internal_admin = _model_diagnostics(model)
        rows.append(
            {
                "scenario_id": scenario_id,
                "scenario_version": scenario_id.lower(),
                "scenario_label": label,
                "changed_assumption": changed,
                "changed_assumption_count": count,
                "is_baseline": baseline,
                "is_owner_approved": True,
                "lookback_days": lookback,
                "null_inactivity_days": null_days,
                "repeated_channel_treatment": repeated,
                "direct_treatment": direct,
                "bootstrap_replicates": replicates,
                "bootstrap_seed": seed,
                "conversion_journey_count": conversions,
                "null_journey_count": nulls,
                "right_censored_journey_count": censored,
                "right_censored_in_model_count": 0,
                "internal_admin_state_count": internal_admin,
                "invalid_transition_row_count": invalid_rows,
                "invalid_absorbing_state_count": invalid_absorbers,
                "materially_negative_effect_count": negative_count,
                "rank_tie_break_rule": "share_desc_channel_name_asc",
                "baseline_fingerprint_sha256": fingerprint,
                "sensitivity_version": SENSITIVITY_VERSION,
            }
        )
    return rows


def run_phase5(config: Phase4Config, *, execute: bool) -> None:
    import google.auth
    from google.cloud import bigquery

    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    client = bigquery.Client(
        project=config.gcp_project_id,
        location=config.bq_location,
        credentials=credentials,
    )
    if client.get_dataset(config.target_dataset_id).location.upper() != config.bq_location.upper():
        raise RuntimeError("Dataset location does not match BQ_LOCATION")
    existing = [name for name in PHASE5_TABLES if _table_exists(client, config.table_id(name))]
    if existing:
        raise RuntimeError("Phase 5 outputs are create-only and already exist: " + ", ".join(existing))

    initial_snapshot = _metadata_snapshot(client, config)
    fingerprint = _fingerprint(initial_snapshot)
    print(f"Baseline snapshot verified: {fingerprint}", flush=True)
    costs: list[dict[str, object]] = []
    prerequisite_job, prerequisite_estimate = _validate_prerequisites(client, config)
    costs.append(_cost_record("00_phase5_prerequisites", "generated", "", "phase5 prerequisites", prerequisite_estimate, prerequisite_job, 1))
    # The validation query references Phase 5 outputs and is dry-run only after
    # the five source result tables have been created successfully.
    assets = (LOOKBACK_SQL, NULL14_SQL, BASELINE_PATH_SQL)
    for asset in assets:
        sql = render_asset(asset, config)
        validate_query_sql(sql, config)
        estimate = _dry_run(client, sql, config)
        costs.append(_cost_record(asset.query_id, asset.path.relative_to(ROOT).as_posix(), config.table_id("phase5_validation_summary") if asset is VALIDATION_SQL else "", sql, estimate, None, ""))
    if not execute:
        _write_costs(costs)
        print("Phase 5 dry-run preflight passed; no output tables were created.")
        return

    lookback_job, lookback_source, lookback_estimate, lookback_sql = _query_asset(client, config, LOOKBACK_SQL)
    lookback_rows = _lookback_rows(lookback_source)
    print(f"Lookback scenario rows prepared: {len(lookback_rows)}", flush=True)
    costs.append(_cost_record(LOOKBACK_SQL.query_id, LOOKBACK_SQL.path.relative_to(ROOT).as_posix(), "", lookback_sql, lookback_estimate, lookback_job, len(lookback_rows)))

    baseline_job, baseline_source, baseline_estimate, baseline_sql = _query_asset(client, config, BASELINE_PATH_SQL)
    baseline_journeys = [
        ClusterJourney(str(row["user_pseudo_id"]), _path_tuple(row["channel_path"], str(row["outcome_state"])))
        for row in baseline_source
    ]
    if len(baseline_journeys) != 182089:
        raise RuntimeError(f"Unexpected baseline journey count: {len(baseline_journeys)}")
    print(f"Baseline journeys extracted: {len(baseline_journeys)}", flush=True)
    costs.append(_cost_record(BASELINE_PATH_SQL.query_id, BASELINE_PATH_SQL.path.relative_to(ROOT).as_posix(), "", baseline_sql, baseline_estimate, baseline_job, len(baseline_journeys)))

    null_job, null_source, null_estimate, null_sql = _query_asset(client, config, NULL14_SQL)
    null14_journeys: list[ClusterJourney] = [
        journey for journey in baseline_journeys if journey.path[-1] == "Conversion"
    ]
    null_candidate_count = 0
    null_overlap_excluded = 0
    null_right_censored = 0
    for row in null_source:
        status = str(row["candidate_status"])
        if status == "Right Censored":
            null_right_censored += 1
            continue
        null_candidate_count += 1
        if bool(row["is_overlap_excluded"]):
            null_overlap_excluded += 1
            continue
        if bool(row["is_markov_included"]):
            null14_journeys.append(
                ClusterJourney(
                    str(row["user_pseudo_id"]),
                    _path_tuple(row["channel_path"], "Null"),
                )
            )
    if (null_candidate_count, null_overlap_excluded, null_right_censored) != (232307, 341, 42017):
        raise RuntimeError("14-day Null population does not match readiness evidence")
    print(
        "14-day Null population prepared: "
        f"included={len(null14_journeys) - 4457}, "
        f"overlap_excluded={null_overlap_excluded}, "
        f"right_censored={null_right_censored}",
        flush=True,
    )
    costs.append(_cost_record(NULL14_SQL.query_id, NULL14_SQL.path.relative_to(ROOT).as_posix(), "", null_sql, null_estimate, null_job, null_candidate_count + null_right_censored))

    scenario_results: list[dict[str, object]] = list(lookback_rows)
    model_details: dict[str, tuple[Any, int]] = {}
    markov_scenarios: dict[str, list[dict[str, object]]] = {}

    baseline_rows, baseline_model, baseline_effects, baseline_shares, baseline_negative = _markov_rows(
        "P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1", baseline_journeys,
        null_journeys=177632, right_censored_journeys=91594,
    )
    scenario_results.extend(baseline_rows)
    markov_scenarios["P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1"] = baseline_rows
    model_details["P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1"] = (baseline_model, baseline_negative)

    null_rows, null_model, _, _, null_negative = _markov_rows(
        "P5_C_NULL14_V1", null14_journeys,
        null_journeys=231966, right_censored_journeys=42017,
    )
    scenario_results.extend(null_rows)
    markov_scenarios["P5_C_NULL14_V1"] = null_rows
    model_details["P5_C_NULL14_V1"] = (null_model, null_negative)

    compressed_journeys = [
        ClusterJourney(journey.user_pseudo_id, compress_consecutive_channels(journey.path))
        for journey in baseline_journeys
    ]
    compression_rows, compression_model, _, _, compression_negative = _markov_rows(
        "P5_D_COMPRESS_CONSECUTIVE_V1", compressed_journeys,
        null_journeys=177632, right_censored_journeys=91594,
    )
    scenario_results.extend(compression_rows)
    markov_scenarios["P5_D_COMPRESS_CONSECUTIVE_V1"] = compression_rows
    model_details["P5_D_COMPRESS_CONSECUTIVE_V1"] = (compression_model, compression_negative)

    direct_journeys = [
        ClusterJourney(journey.user_pseudo_id, omit_direct_from_mixed_path(journey.path))
        for journey in baseline_journeys
    ]
    direct_rows, direct_model, _, _, direct_negative = _markov_rows(
        "P5_E_DIRECT_MIXED_OMIT_V1", direct_journeys,
        null_journeys=177632, right_censored_journeys=91594,
    )
    scenario_results.extend(direct_rows)
    markov_scenarios["P5_E_DIRECT_MIXED_OMIT_V1"] = direct_rows
    model_details["P5_E_DIRECT_MIXED_OMIT_V1"] = (direct_model, direct_negative)

    bootstrap_started = time.perf_counter()
    print("Starting 500-replicate user cluster bootstrap", flush=True)
    bootstrap = run_user_cluster_bootstrap(
        baseline_journeys,
        baseline_model,
        baseline_effects,
        baseline_shares,
        replicate_count=BOOTSTRAP_REPLICATES,
        seed=BOOTSTRAP_SEED,
    )
    bootstrap_seconds = time.perf_counter() - bootstrap_started
    print(
        f"Bootstrap completed in {bootstrap_seconds:.2f}s: "
        f"success={bootstrap.successful_replicates}, "
        f"failed={bootstrap.failed_replicates}",
        flush=True,
    )
    replicate_rows = [dict(row) for row in bootstrap.replicate_rows]
    for row in replicate_rows:
        row["bootstrap_version"] = SENSITIVITY_VERSION
    summary_rows = [dict(row) for row in bootstrap.summary_rows]
    for row in summary_rows:
        row["bootstrap_version"] = SENSITIVITY_VERSION

    rank_rows: list[dict[str, object]] = []
    lookback_groups = _model_groups(lookback_rows)
    for scenario_id in ("P5_A_LB14_V1", "P5_B_LB7_V1"):
        for cohort_view in ("population_impact", "common_cohort"):
            for model in ("First Click", "Last Click", "Last Non-direct Click", "Linear", "Time Decay"):
                scenario_group = lookback_groups[(scenario_id, cohort_view, model)]
                baseline_view = "common_cohort" if cohort_view == "common_cohort" else "baseline"
                baseline_group = lookback_groups[("P5_BASE_30LB_30NULL_RETAIN_DIRECT_V1", baseline_view, model)]
                rank_rows.extend(_rank_rows(scenario_group, baseline_group))
    for scenario_id in (
        "P5_C_NULL14_V1",
        "P5_D_COMPRESS_CONSECUTIVE_V1",
        "P5_E_DIRECT_MIXED_OMIT_V1",
    ):
        rank_rows.extend(_rank_rows(markov_scenarios[scenario_id], baseline_rows))

    manifest_rows = _manifest_rows(fingerprint, model_details)
    print("Creating five create-only Phase 5 result tables", flush=True)
    _load_rows(client, config, "phase5_sensitivity_results", scenario_results, sensitivity_schema())
    _load_rows(client, config, "phase5_rank_stability", rank_rows, rank_schema())
    _load_rows(client, config, "phase5_bootstrap_replicates", replicate_rows, bootstrap_replicate_schema())
    _load_rows(client, config, "phase5_bootstrap_summary", summary_rows, bootstrap_summary_schema())
    _load_rows(client, config, "phase5_scenario_manifest", manifest_rows, manifest_schema())

    final_snapshot = _metadata_snapshot(client, config)
    if final_snapshot != initial_snapshot:
        raise RuntimeError("A Phase 2/2B/3/4 baseline table changed during Phase 5")
    print("Prior-phase metadata snapshot is unchanged", flush=True)

    validation_sql = render_asset(VALIDATION_SQL, config)
    validation_estimate = _dry_run(client, validation_sql, config)
    from scripts.run_phase4 import QueryStep
    validation_step = QueryStep(
        VALIDATION_SQL.query_id,
        VALIDATION_SQL.path,
        "phase5_validation_summary",
    )
    validation_job = _execute_destination_query(
        client, validation_sql, config, validation_step
    )
    validation_count = int(client.get_table(config.table_id("phase5_validation_summary")).num_rows)
    costs.append(_cost_record(VALIDATION_SQL.query_id, VALIDATION_SQL.path.relative_to(ROOT).as_posix(), config.table_id("phase5_validation_summary"), validation_sql, validation_estimate, validation_job, validation_count))
    validation_rows = list(client.list_rows(config.table_id("phase5_validation_summary")))
    failed = [row for row in validation_rows if row["validation_status"] != "PASS"]
    if failed:
        raise RuntimeError("Phase 5 validation failed: " + "; ".join(
            f"{row['check_id']}={row['observed_value']} expected={row['expected_value']}"
            for row in failed
        ))
    _write_costs(costs)
    print(json.dumps({
        "phase5_tables": {name: int(client.get_table(config.table_id(name)).num_rows) for name in PHASE5_TABLES},
        "bootstrap_seconds": bootstrap_seconds,
        "bootstrap_attempted": bootstrap.attempted_replicates,
        "bootstrap_successful": bootstrap.successful_replicates,
        "bootstrap_failed": bootstrap.failed_replicates,
        "baseline_fingerprint": fingerprint,
        "validation_checks": validation_count,
    }, indent=2, sort_keys=True))
    print("Phase 5 sensitivity and stability validation passed. Stop before Phase 6.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Create the six approved create-only Phase 5 outputs.",
    )
    args = parser.parse_args()
    run_phase5(load_config(), execute=args.execute)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
