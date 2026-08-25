"""Build, validate, export, and visualize approved Phase 6 reporting outputs."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.run_phase4 import (  # noqa: E402
    Phase4Config,
    QueryStep,
    _dry_run,
    _execute_destination_query,
    _query_without_destination,
    _table_exists,
    load_config,
    render_step,
    validate_query_sql,
)
from src.attribution.reporting import (  # noqa: E402
    REPORTING_VERSION,
    generate_phase6_figures,
)

OUTPUT_DIR = ROOT / "reports" / "tables"
FIGURE_DIR = ROOT / "reports" / "figures"
COST_LOG_PATH = OUTPUT_DIR / "phase6_query_costs.csv"
BASELINE_METADATA_PATH = OUTPUT_DIR / "phase6_baseline_metadata.json"

PHASE6_TABLES = (
    "channel_funnel_summary",
    "journey_summary",
    "attribution_business_summary",
    "phase6_validation_summary",
)
BASELINE_TABLES = (
    "event_base",
    "session_source_candidates",
    "session_touchpoints",
    "orders",
    "conversion_touchpoints_strict",
    "conversion_touchpoints",
    "orders_without_touchpoints",
    "attribution_results",
    "model_comparison",
    "markov_journeys",
    "markov_transition_matrix",
    "markov_removal_effects",
    "markov_attribution",
    "rule_markov_comparison",
    "phase5_sensitivity_results",
    "phase5_rank_stability",
    "phase5_bootstrap_replicates",
    "phase5_bootstrap_summary",
    "phase5_scenario_manifest",
    "phase2b_validation_summary",
    "phase3_validation_summary",
    "phase4_validation_summary",
    "phase5_validation_summary",
)


@dataclass(frozen=True)
class ExportSpec:
    table_name: str
    filename: str


BUILD_STEPS = (
    QueryStep(
        "01_channel_funnel_summary",
        ROOT / "sql" / "marts" / "05_channel_funnel_summary.sql",
        "channel_funnel_summary",
        ("channel",),
    ),
    QueryStep(
        "02_journey_summary",
        ROOT / "sql" / "marts" / "06_journey_summary.sql",
        "journey_summary",
        ("summary_type", "sort_order"),
    ),
    QueryStep(
        "03_attribution_business_summary",
        ROOT / "sql" / "marts" / "07_attribution_business_summary.sql",
        "attribution_business_summary",
        ("model", "channel"),
    ),
)
VALIDATION_STEP = QueryStep(
    "04_phase6_validation",
    ROOT / "sql" / "validation" / "06_phase6_validation.sql",
    "phase6_validation_summary",
)
LOCAL_EXPORTS = (
    ExportSpec("channel_funnel_summary", "phase6_channel_funnel_summary.csv"),
    ExportSpec("journey_summary", "phase6_journey_summary.csv"),
    ExportSpec(
        "attribution_business_summary", "phase6_attribution_business_summary.csv"
    ),
    ExportSpec("phase6_validation_summary", "phase6_validation_summary.csv"),
)


def _metadata_snapshot(
    client: Any, config: Phase4Config
) -> dict[str, dict[str, object]]:
    snapshot: dict[str, dict[str, object]] = {}
    for table_name in BASELINE_TABLES:
        table = client.get_table(config.table_id(table_name))
        snapshot[table_name] = {
            "num_rows": int(table.num_rows),
            "modified": table.modified.isoformat() if table.modified else None,
            "etag": table.etag,
            "schema": [
                (field.name, field.field_type, field.mode) for field in table.schema
            ],
        }
    return snapshot


def _fingerprint(snapshot: Mapping[str, object]) -> str:
    payload = json.dumps(snapshot, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _write_baseline_metadata(
    snapshot: Mapping[str, object], fingerprint: str, config: Phase4Config
) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    record = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "dataset": config.target_dataset_id,
        "baseline_tables": snapshot,
        "baseline_fingerprint_sha256": fingerprint,
        "reporting_version": REPORTING_VERSION,
    }
    BASELINE_METADATA_PATH.write_text(
        json.dumps(record, indent=2, sort_keys=True), encoding="utf-8"
    )


def _prerequisite_sql(config: Phase4Config) -> str:
    return f"""
SELECT
  (SELECT COUNT(*) FROM `{config.table_id('event_base')}`) AS event_rows,
  (SELECT COUNT(*) FROM `{config.table_id('session_touchpoints')}`) AS sessions,
  (SELECT COUNT(*) FROM `{config.table_id('orders')}`) AS orders,
  (SELECT COUNT(*) FROM `{config.table_id('conversion_touchpoints')}`)
    AS conversion_touchpoints,
  (SELECT COUNT(DISTINCT order_key)
   FROM `{config.table_id('conversion_touchpoints')}`) AS attributable_orders,
  (SELECT ROUND(SUM(revenue), 2) FROM (
    SELECT ANY_VALUE(order_revenue_usd) AS revenue
    FROM `{config.table_id('conversion_touchpoints')}` GROUP BY order_key
  )) AS attributable_revenue,
  (SELECT COUNT(*) FROM `{config.table_id('attribution_results')}`)
    AS attribution_rows,
  (SELECT COUNT(*) FROM `{config.table_id('model_comparison')}`)
    AS model_comparison_rows,
  (SELECT COUNT(*) FROM `{config.table_id('markov_journeys')}`)
    AS markov_journey_rows,
  (SELECT COUNT(*) FROM `{config.table_id('markov_transition_matrix')}`)
    AS transition_rows,
  (SELECT COUNT(*) FROM `{config.table_id('markov_removal_effects')}`)
    AS removal_rows,
  (SELECT COUNT(*) FROM `{config.table_id('markov_attribution')}`)
    AS markov_attribution_rows,
  (SELECT COUNT(*) FROM `{config.table_id('rule_markov_comparison')}`)
    AS rule_markov_rows,
  (SELECT COUNT(*) FROM `{config.table_id('phase5_sensitivity_results')}`)
    AS phase5_sensitivity_rows,
  (SELECT COUNT(*) FROM `{config.table_id('phase5_rank_stability')}`)
    AS phase5_rank_rows,
  (SELECT COUNT(*) FROM `{config.table_id('phase5_bootstrap_replicates')}`)
    AS phase5_bootstrap_rows,
  (SELECT COUNT(*) FROM `{config.table_id('phase5_bootstrap_summary')}`)
    AS phase5_bootstrap_summary_rows,
  (SELECT COUNT(*) FROM `{config.table_id('phase5_scenario_manifest')}`)
    AS phase5_manifest_rows,
  (SELECT COUNT(*) FROM `{config.table_id('phase2b_validation_summary')}`)
    AS phase2b_checks,
  (SELECT COUNTIF(validation_status != 'PASS')
   FROM `{config.table_id('phase2b_validation_summary')}`) AS phase2b_failures,
  (SELECT COUNT(*) FROM `{config.table_id('phase3_validation_summary')}`)
    AS phase3_checks,
  (SELECT COUNTIF(validation_status != 'PASS')
   FROM `{config.table_id('phase3_validation_summary')}`) AS phase3_failures,
  (SELECT COUNT(*) FROM `{config.table_id('phase4_validation_summary')}`)
    AS phase4_checks,
  (SELECT COUNTIF(validation_status != 'PASS')
   FROM `{config.table_id('phase4_validation_summary')}`) AS phase4_failures,
  (SELECT COUNT(*) FROM `{config.table_id('phase5_validation_summary')}`)
    AS phase5_checks,
  (SELECT COUNTIF(validation_status != 'PASS')
   FROM `{config.table_id('phase5_validation_summary')}`) AS phase5_failures
""".strip()


def _validate_prerequisites(
    client: Any, config: Phase4Config
) -> tuple[Any, str, int]:
    dataset = client.get_dataset(config.target_dataset_id)
    if dataset.location.upper() != config.bq_location.upper():
        raise RuntimeError("Dataset location does not match BQ_LOCATION")
    sql = _prerequisite_sql(config)
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    job, rows = _query_without_destination(client, sql, config)
    row = next(iter(rows))
    field_names = (
        "event_rows",
        "sessions",
        "orders",
        "conversion_touchpoints",
        "attributable_orders",
        "attributable_revenue",
        "attribution_rows",
        "model_comparison_rows",
        "markov_journey_rows",
        "transition_rows",
        "removal_rows",
        "markov_attribution_rows",
        "rule_markov_rows",
        "phase5_sensitivity_rows",
        "phase5_rank_rows",
        "phase5_bootstrap_rows",
        "phase5_bootstrap_summary_rows",
        "phase5_manifest_rows",
        "phase2b_checks",
        "phase2b_failures",
        "phase3_checks",
        "phase3_failures",
        "phase4_checks",
        "phase4_failures",
        "phase5_checks",
        "phase5_failures",
    )
    observed = tuple(
        float(row[name]) if name == "attributable_revenue" else int(row[name])
        for name in field_names
    )
    expected = (
        4_295_584,
        360_129,
        4_466,
        9_577,
        4_457,
        308_208.0,
        27_409,
        8,
        273_683,
        144,
        9,
        9,
        54,
        276,
        187,
        4_500,
        9,
        7,
        70,
        0,
        46,
        0,
        70,
        0,
        56,
        0,
    )
    if observed != expected:
        raise RuntimeError(
            f"Phase 6 prerequisites failed: observed={observed}, expected={expected}"
        )
    print(f"Phase 6 upstream validation gates passed: {observed}", flush=True)
    return job, sql, estimate


def _validate_target_state(
    client: Any, config: Phase4Config, *, resume: bool
) -> set[str]:
    existing = [
        table_name
        for table_name in PHASE6_TABLES
        if _table_exists(client, config.table_id(table_name))
    ]
    if existing and not resume:
        raise RuntimeError(
            "Phase 6 uses create-only outputs and will not replace existing tables: "
            + ", ".join(existing)
        )
    if resume:
        expected_prefix = list(PHASE6_TABLES[: len(existing)])
        if existing != expected_prefix:
            raise RuntimeError(
                "Phase 6 resume requires an exact validated execution prefix: "
                + ", ".join(existing)
            )
        expected_rows = {
            "channel_funnel_summary": 9,
            "journey_summary": 722,
            "attribution_business_summary": 54,
        }
        for table_name in existing:
            expected = expected_rows.get(table_name)
            if expected is None:
                continue
            observed = int(client.get_table(config.table_id(table_name)).num_rows)
            if observed != expected:
                raise RuntimeError(
                    f"Phase 6 resume row-count mismatch for {table_name}: "
                    f"{observed} != {expected}"
                )
    return set(existing)


def _cost_record(
    query_id: str,
    sql_file: str,
    destination: str,
    sql: str,
    estimate: int,
    config: Phase4Config,
    job: Any | None = None,
    row_count: int | str = "",
) -> dict[str, object]:
    return {
        "query_id": query_id,
        "sql_file": sql_file,
        "destination_table": destination,
        "sql_sha256": hashlib.sha256(sql.encode("utf-8")).hexdigest(),
        "estimated_bytes": estimate,
        "maximum_bytes_billed": config.maximum_bytes_billed,
        "within_cap": estimate <= config.maximum_bytes_billed,
        "executed": job is not None,
        "actual_bytes_processed": int(job.total_bytes_processed or 0) if job else "",
        "actual_bytes_billed": int(job.total_bytes_billed or 0) if job else "",
        "destination_row_count": row_count,
        "job_id": job.job_id if job else "",
        "status": "EXECUTED" if job else "DRY_RUN_PASSED",
    }


def _write_cost_log(records: list[dict[str, object]]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    field_names = (
        "query_id",
        "sql_file",
        "destination_table",
        "sql_sha256",
        "estimated_bytes",
        "maximum_bytes_billed",
        "within_cap",
        "executed",
        "actual_bytes_processed",
        "actual_bytes_billed",
        "destination_row_count",
        "job_id",
        "status",
    )
    with COST_LOG_PATH.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=field_names)
        writer.writeheader()
        writer.writerows(records)


def _read_cost_log() -> dict[str, dict[str, object]]:
    if not COST_LOG_PATH.exists():
        return {}
    with COST_LOG_PATH.open(newline="", encoding="utf-8") as handle:
        return {row["query_id"]: dict(row) for row in csv.DictReader(handle)}


def _write_csv(path: Path, rows: list[Any], field_names: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(field_names)
        for row in rows:
            writer.writerow([row[name] for name in field_names])


def _export_tables(client: Any, config: Phase4Config) -> dict[str, pd.DataFrame]:
    frames: dict[str, pd.DataFrame] = {}
    for spec in LOCAL_EXPORTS:
        table = client.get_table(config.table_id(spec.table_name))
        rows = list(client.list_rows(table))
        field_names = [field.name for field in table.schema]
        _write_csv(OUTPUT_DIR / spec.filename, rows, field_names)
        frames[spec.table_name] = pd.DataFrame(
            [{name: row[name] for name in field_names} for row in rows],
            columns=field_names,
        )
        print(f"export {spec.filename}: rows={len(rows)}", flush=True)
    return frames


def run_phase6(config: Phase4Config, execute: bool, resume: bool = False) -> None:
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

    prior_cost_records = _read_cost_log()
    records: list[dict[str, object]] = []
    prerequisite_job, prerequisite_sql, prerequisite_estimate = (
        _validate_prerequisites(client, config)
    )
    records.append(
        _cost_record(
            "00_phase6_prerequisites",
            "generated:phase6_prerequisites",
            "",
            prerequisite_sql,
            prerequisite_estimate,
            config,
            prerequisite_job,
            1,
        )
    )

    initial_snapshot = _metadata_snapshot(client, config)
    baseline_fingerprint = _fingerprint(initial_snapshot)
    _write_baseline_metadata(initial_snapshot, baseline_fingerprint, config)
    print(f"Phase 2B-5 baseline fingerprint: {baseline_fingerprint}", flush=True)
    existing_targets = _validate_target_state(client, config, resume=resume)

    rendered_steps: list[tuple[QueryStep, str, int]] = []
    for step in BUILD_STEPS:
        sql = render_step(step, config)
        validate_query_sql(sql, config)
        estimate = _dry_run(client, sql, config)
        if estimate > config.maximum_bytes_billed:
            raise RuntimeError(f"{step.query_id} exceeds the billing cap")
        rendered_steps.append((step, sql, estimate))
        records.append(
            _cost_record(
                step.query_id,
                step.sql_path.relative_to(ROOT).as_posix(),
                config.table_id(step.destination_table),
                sql,
                estimate,
                config,
            )
        )
        print(f"{step.query_id}: dry-run bytes={estimate}", flush=True)

    if not execute:
        _write_cost_log(records)
        print(
            json.dumps(
                {
                    "baseline_fingerprint": baseline_fingerprint,
                    "material_queries_dry_run": len(rendered_steps),
                    "phase6_targets": list(PHASE6_TABLES),
                    "status": "PREFLIGHT_PASSED_NO_OBJECTS_CREATED",
                },
                indent=2,
                sort_keys=True,
            )
        )
        return

    records = records[:1]
    for step, sql, estimate in rendered_steps:
        if step.destination_table in existing_targets:
            prior = prior_cost_records.get(step.query_id)
            if prior and prior.get("sql_sha256") == hashlib.sha256(
                sql.encode("utf-8")
            ).hexdigest():
                records.append(prior)
            else:
                resumed_record = _cost_record(
                    step.query_id,
                    step.sql_path.relative_to(ROOT).as_posix(),
                    config.table_id(step.destination_table),
                    sql,
                    estimate,
                    config,
                    row_count=int(
                        client.get_table(config.table_id(step.destination_table)).num_rows
                    ),
                )
                resumed_record["status"] = "RESUMED_EXISTING_CREATE_ONLY"
                records.append(resumed_record)
            print(
                f"{step.query_id}: reused existing create-only table",
                flush=True,
            )
            continue
        job = _execute_destination_query(client, sql, config, step)
        row_count = int(client.get_table(config.table_id(step.destination_table)).num_rows)
        records.append(
            _cost_record(
                step.query_id,
                step.sql_path.relative_to(ROOT).as_posix(),
                config.table_id(step.destination_table),
                sql,
                estimate,
                config,
                job,
                row_count,
            )
        )
        _write_cost_log(records)
        print(f"{step.query_id}: rows={row_count}", flush=True)

    if _metadata_snapshot(client, config) != initial_snapshot:
        raise RuntimeError("A Phase 2B-5 baseline table changed during Phase 6")

    validation_sql = render_step(VALIDATION_STEP, config)
    validate_query_sql(validation_sql, config)
    validation_estimate = _dry_run(client, validation_sql, config)
    if validation_estimate > config.maximum_bytes_billed:
        raise RuntimeError("Phase 6 validation exceeds the billing cap")
    validation_job = None
    if VALIDATION_STEP.destination_table not in existing_targets:
        validation_job = _execute_destination_query(
            client, validation_sql, config, VALIDATION_STEP
        )
    validation_table = client.get_table(
        config.table_id(VALIDATION_STEP.destination_table)
    )
    validation_rows = list(client.list_rows(validation_table))
    if validation_job is not None:
        records.append(
            _cost_record(
                VALIDATION_STEP.query_id,
                VALIDATION_STEP.sql_path.relative_to(ROOT).as_posix(),
                config.table_id(VALIDATION_STEP.destination_table),
                validation_sql,
                validation_estimate,
                config,
                validation_job,
                int(validation_table.num_rows),
            )
        )
    else:
        prior = prior_cost_records.get(VALIDATION_STEP.query_id)
        if prior:
            records.append(prior)
    _write_cost_log(records)
    failures = [
        row for row in validation_rows if row["validation_status"] != "PASS"
    ]
    if failures:
        details = "; ".join(
            f"{row['check_id']}={row['observed_value']} "
            f"expected={row['expected_value']}"
            for row in failures
        )
        raise RuntimeError(f"Phase 6 validation failed: {details}")
    if _metadata_snapshot(client, config) != initial_snapshot:
        raise RuntimeError("A Phase 2B-5 baseline table changed during validation")

    frames = _export_tables(client, config)
    figure_paths = generate_phase6_figures(
        frames["channel_funnel_summary"],
        frames["journey_summary"],
        frames["attribution_business_summary"],
        FIGURE_DIR,
    )
    print(
        json.dumps(
            {
                "baseline_fingerprint": baseline_fingerprint,
                "figures": [path.relative_to(ROOT).as_posix() for path in figure_paths],
                "phase6_tables": {
                    name: int(client.get_table(config.table_id(name)).num_rows)
                    for name in PHASE6_TABLES
                },
                "validation_checks": len(validation_rows),
            },
            indent=2,
            sort_keys=True,
        )
    )
    print("Phase 6 business reporting validation passed. Stop for review.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Create the four approved create-only Phase 6 outputs.",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Reuse an exact create-only Phase 6 prefix after an interrupted run.",
    )
    args = parser.parse_args()
    if args.resume and not args.execute:
        parser.error("--resume requires --execute")
    run_phase6(load_config(), execute=args.execute, resume=args.resume)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
