"""Safely create and validate the approved Phase 3 rule-based attribution tables."""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "reports" / "tables"
COST_LOG_PATH = OUTPUT_DIR / "phase3_query_costs.csv"
PROJECT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{4,62}$")
DATASET_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,1023}$")
SOURCE_TABLE_PATTERN = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_]+\.events_\*$")
PLACEHOLDER_PATTERN = re.compile(r"\{\{[A-Z_]+\}\}")
FORBIDDEN_SQL_KEYWORDS = (
    "ALTER",
    "CREATE",
    "DELETE",
    "DROP",
    "EXPORT",
    "INSERT",
    "MERGE",
    "TRUNCATE",
    "UPDATE",
)

ATTRIBUTION_VERSION = "phase3_rule_attribution_v1_20260809"
EXPECTED_PATH_VERSION = "phase2b_closeout_v1_20260806"
EXPECTED_MAPPING_VERSION = "phase2b_channel_v2_20260806"
PHASE3_TABLES = (
    "attribution_results",
    "model_comparison",
    "phase3_validation_summary",
)


@dataclass(frozen=True)
class Phase3Config:
    gcp_project_id: str
    bq_dataset: str
    bq_location: str
    source_table: str
    start_date: date
    end_date: date
    maximum_bytes_billed: int

    @property
    def target_dataset_id(self) -> str:
        return f"{self.gcp_project_id}.{self.bq_dataset}"

    def table_id(self, table_name: str) -> str:
        if not DATASET_PATTERN.fullmatch(table_name):
            raise ValueError(f"Invalid table name: {table_name}")
        return f"{self.target_dataset_id}.{table_name}"


@dataclass(frozen=True)
class BuildStep:
    query_id: str
    sql_path: Path
    destination_table: str
    clustering_fields: tuple[str, ...] = ()


BUILD_STEPS = (
    BuildStep(
        "01_rule_based_attribution",
        ROOT / "sql" / "marts" / "01_rule_based_attribution.sql",
        "attribution_results",
        ("model", "channel", "order_key"),
    ),
    BuildStep(
        "02_model_comparison",
        ROOT / "sql" / "marts" / "02_model_comparison.sql",
        "model_comparison",
        ("channel",),
    ),
    BuildStep(
        "03_phase3_validation",
        ROOT / "sql" / "validation" / "03_phase3_validation.sql",
        "phase3_validation_summary",
    ),
)

LOCAL_EXPORTS = {
    "model_comparison": "phase3_model_comparison.csv",
    "phase3_validation_summary": "phase3_validation_summary.csv",
}


def load_config() -> Phase3Config:
    required = (
        "GCP_PROJECT_ID",
        "BQ_DATASET",
        "BQ_LOCATION",
        "GA4_SOURCE_TABLE",
        "START_DATE",
        "END_DATE",
        "MAXIMUM_BYTES_BILLED",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise ValueError(
            f"Missing required environment variables: {', '.join(missing)}"
        )

    project = os.environ["GCP_PROJECT_ID"]
    dataset = os.environ["BQ_DATASET"]
    source_table = os.environ["GA4_SOURCE_TABLE"]
    if not PROJECT_PATTERN.fullmatch(project):
        raise ValueError("GCP_PROJECT_ID is not a valid project identifier")
    if not DATASET_PATTERN.fullmatch(dataset):
        raise ValueError("BQ_DATASET is not a valid dataset identifier")
    if not SOURCE_TABLE_PATTERN.fullmatch(source_table):
        raise ValueError("GA4_SOURCE_TABLE must be a fully qualified events_* table")

    start_date = date.fromisoformat(os.environ["START_DATE"])
    end_date = date.fromisoformat(os.environ["END_DATE"])
    if (start_date, end_date) != (date(2020, 11, 1), date(2021, 1, 31)):
        raise ValueError(
            "Phase 3 requires the finalized 2020-11-01 through 2021-01-31 range"
        )
    maximum_bytes_billed = int(os.environ["MAXIMUM_BYTES_BILLED"])
    if maximum_bytes_billed != 1_000_000_000:
        raise ValueError("Phase 3 MAXIMUM_BYTES_BILLED must equal 1000000000")

    return Phase3Config(
        gcp_project_id=project,
        bq_dataset=dataset,
        bq_location=os.environ["BQ_LOCATION"],
        source_table=source_table,
        start_date=start_date,
        end_date=end_date,
        maximum_bytes_billed=maximum_bytes_billed,
    )


def replace_placeholders(template: str, replacements: dict[str, str]) -> str:
    rendered = template
    for placeholder, value in replacements.items():
        rendered = rendered.replace(placeholder, value)
    unresolved = PLACEHOLDER_PATTERN.findall(rendered)
    if unresolved:
        raise ValueError(
            "Unresolved SQL placeholders: "
            + ", ".join(sorted(set(unresolved)))
        )
    return rendered.strip().rstrip(";")


def render_step(step: BuildStep, config: Phase3Config) -> str:
    template = step.sql_path.read_text(encoding="utf-8")
    return replace_placeholders(
        template,
        {
            "{{TARGET_PROJECT}}": config.gcp_project_id,
            "{{TARGET_DATASET}}": config.bq_dataset,
        },
    )


def validate_query_sql(sql: str, config: Phase3Config) -> None:
    sql_without_leading_comments = re.sub(
        r"\A(?:\s*--[^\r\n]*(?:\r?\n|\Z))*", "", sql
    )
    normalized = re.sub(r"\s+", " ", sql_without_leading_comments).strip().upper()
    if not normalized.startswith(("SELECT ", "WITH ")):
        raise ValueError("Phase 3 SQL must start with SELECT or WITH")
    for keyword in FORBIDDEN_SQL_KEYWORDS:
        if re.search(rf"\b{keyword}\b", normalized):
            raise ValueError(f"Forbidden SQL keyword: {keyword}")
    if re.search(r"\bSELECT\s+(?:[A-Z0-9_]+\.)?\*", normalized):
        raise ValueError("SELECT * is not allowed in Phase 3 SQL")
    if f"`{config.source_table}`" in sql:
        raise ValueError(
            "Phase 3 must consume finalized Phase 2B tables, not the public wildcard"
        )


def _table_exists(client: Any, table_id: str) -> bool:
    from google.api_core.exceptions import NotFound

    try:
        client.get_table(table_id)
    except NotFound:
        return False
    return True


def _dry_run(client: Any, sql: str, config: Phase3Config) -> int:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        dry_run=True,
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
    )
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    return int(job.total_bytes_processed or 0)


def _query_without_destination(client: Any, sql: str, config: Phase3Config) -> Any:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
    )
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    rows = list(job.result())
    return job, rows


def _execute_destination_query(
    client: Any,
    sql: str,
    config: Phase3Config,
    step: BuildStep,
) -> Any:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
        destination=config.table_id(step.destination_table),
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        write_disposition=bigquery.WriteDisposition.WRITE_EMPTY,
    )
    if step.clustering_fields:
        job_config.clustering_fields = list(step.clustering_fields)
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    job.result()
    return job


def _cost_record(
    *,
    query_id: str,
    sql_file: str,
    destination_table: str,
    sql: str,
    estimated_bytes: int,
    config: Phase3Config,
    job: Any | None = None,
    row_count: int | str = "",
) -> dict[str, Any]:
    return {
        "query_id": query_id,
        "sql_file": sql_file,
        "destination_table": destination_table,
        "sql_sha256": hashlib.sha256(sql.encode("utf-8")).hexdigest(),
        "estimated_bytes": estimated_bytes,
        "maximum_bytes_billed": config.maximum_bytes_billed,
        "within_cap": estimated_bytes <= config.maximum_bytes_billed,
        "executed": job is not None,
        "actual_bytes_processed": int(job.total_bytes_processed or 0) if job else "",
        "actual_bytes_billed": int(job.total_bytes_billed or 0) if job else "",
        "destination_row_count": row_count,
        "job_id": job.job_id if job else "",
        "status": "EXECUTED" if job else "DRY_RUN_PASSED",
    }


def _write_csv(path: Path, rows: list[Any], field_names: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(field_names)
        for row in rows:
            writer.writerow([row[name] for name in field_names])


def write_cost_log(records: list[dict[str, Any]]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    fields = [
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
    ]
    with COST_LOG_PATH.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)


def _validate_foundations(
    client: Any,
    config: Phase3Config,
) -> tuple[Any, list[Any], str]:
    dataset = client.get_dataset(config.target_dataset_id)
    if dataset.location.upper() != config.bq_location.upper():
        raise RuntimeError("Dataset location does not match BQ_LOCATION")

    expected_rows = {
        "orders": 4_466,
        "conversion_touchpoints": 9_577,
        "orders_without_touchpoints": 9,
        "phase2b_validation_summary": 70,
    }
    for table_name, expected_rows_for_table in expected_rows.items():
        table = client.get_table(config.table_id(table_name))
        if table.num_rows != expected_rows_for_table:
            raise RuntimeError(
                f"Phase 2B foundation {table_name} has {table.num_rows} rows; "
                f"expected {expected_rows_for_table}"
            )

    validation_id = config.table_id("phase2b_validation_summary")
    touchpoints_id = config.table_id("conversion_touchpoints")
    exclusions_id = config.table_id("orders_without_touchpoints")
    orders_id = config.table_id("orders")
    sql = f"""
WITH input_orders AS (
  SELECT order_key, ANY_VALUE(order_revenue_usd) AS order_revenue_usd
  FROM `{touchpoints_id}`
  GROUP BY order_key
)
SELECT
  (SELECT COUNT(*) FROM `{validation_id}`) AS phase2b_check_count,
  (SELECT COUNTIF(validation_status != 'PASS') FROM `{validation_id}`)
    AS phase2b_failed_check_count,
  (SELECT COUNT(*) FROM input_orders) AS attributable_order_count,
  (SELECT SUM(order_revenue_usd) FROM input_orders) AS attributable_revenue_usd,
  (SELECT COUNT(*) FROM `{exclusions_id}`) AS excluded_order_count,
  (SELECT SUM(order_revenue_usd) FROM `{exclusions_id}`)
    AS excluded_revenue_usd,
  (SELECT COUNT(*) FROM `{orders_id}`) AS total_order_count,
  (SELECT SUM(order_revenue_usd) FROM `{orders_id}`) AS total_revenue_usd,
  (SELECT COUNTIF(mapping_version != '{EXPECTED_MAPPING_VERSION}')
   FROM `{touchpoints_id}`) AS invalid_mapping_version_count,
  (SELECT COUNTIF(path_definition_version != '{EXPECTED_PATH_VERSION}')
   FROM `{touchpoints_id}`) AS invalid_path_version_count
""".strip()
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    if estimate > config.maximum_bytes_billed:
        raise RuntimeError("Phase 2B prerequisite query exceeds the billing cap")
    job, rows = _query_without_destination(client, sql, config)
    row = rows[0]
    observed = (
        int(row["phase2b_check_count"]),
        int(row["phase2b_failed_check_count"]),
        int(row["attributable_order_count"]),
        round(float(row["attributable_revenue_usd"]), 2),
        int(row["excluded_order_count"]),
        round(float(row["excluded_revenue_usd"]), 2),
        int(row["total_order_count"]),
        round(float(row["total_revenue_usd"]), 2),
        int(row["invalid_mapping_version_count"]),
        int(row["invalid_path_version_count"]),
    )
    expected = (70, 0, 4_457, 308_208.00, 9, 622.00, 4_466, 308_830.00, 0, 0)
    if observed != expected:
        raise RuntimeError(
            "Phase 2B prerequisite validation failed: "
            f"observed={observed}, expected={expected}"
        )
    print(f"Phase 2B prerequisite validation passed: {observed}")
    return job, rows, sql


def _validate_fresh_targets(client: Any, config: Phase3Config) -> None:
    existing = [
        table_name
        for table_name in PHASE3_TABLES
        if _table_exists(client, config.table_id(table_name))
    ]
    if existing:
        raise RuntimeError(
            "Phase 3 uses create-only outputs and will not replace existing tables: "
            + ", ".join(existing)
        )


def _run_step(
    client: Any,
    config: Phase3Config,
    step: BuildStep,
    records: list[dict[str, Any]],
) -> None:
    sql = render_step(step, config)
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    if estimate > config.maximum_bytes_billed:
        raise RuntimeError(f"{step.query_id} dry run exceeds the billing cap")
    print(f"{step.query_id}: estimated_bytes={estimate}")
    job = _execute_destination_query(client, sql, config, step)
    row_count = client.get_table(config.table_id(step.destination_table)).num_rows
    records.append(
        _cost_record(
            query_id=step.query_id,
            sql_file=step.sql_path.relative_to(ROOT).as_posix(),
            destination_table=config.table_id(step.destination_table),
            sql=sql,
            estimated_bytes=estimate,
            config=config,
            job=job,
            row_count=row_count,
        )
    )
    write_cost_log(records)
    print(f"{step.query_id}: rows={row_count}")


def _export_review_tables(client: Any, config: Phase3Config) -> None:
    for table_name, filename in LOCAL_EXPORTS.items():
        table = client.get_table(config.table_id(table_name))
        rows = list(client.list_rows(table))
        _write_csv(
            OUTPUT_DIR / filename,
            rows,
            [field.name for field in table.schema],
        )
        print(f"export {filename}: rows={len(rows)}")


def run_phase3(config: Phase3Config, execute: bool) -> None:
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

    records: list[dict[str, Any]] = []
    prerequisite_job, _, prerequisite_sql = _validate_foundations(client, config)
    prerequisite_estimate = _dry_run(client, prerequisite_sql, config)
    records.append(
        _cost_record(
            query_id="00_phase2b_prerequisite_validation",
            sql_file="generated:phase2b_prerequisite_validation",
            destination_table="",
            sql=prerequisite_sql,
            estimated_bytes=prerequisite_estimate,
            config=config,
            job=prerequisite_job,
            row_count=1,
        )
    )
    _validate_fresh_targets(client, config)

    for step in BUILD_STEPS:
        rendered_sql = render_step(step, config)
        validate_query_sql(rendered_sql, config)

    first_step = BUILD_STEPS[0]
    first_sql = render_step(first_step, config)
    first_estimate = _dry_run(client, first_sql, config)
    if first_estimate > config.maximum_bytes_billed:
        raise RuntimeError("Phase 3 attribution preflight exceeds the billing cap")
    if not execute:
        records.append(
            _cost_record(
                query_id=first_step.query_id,
                sql_file=first_step.sql_path.relative_to(ROOT).as_posix(),
                destination_table=config.table_id(first_step.destination_table),
                sql=first_sql,
                estimated_bytes=first_estimate,
                config=config,
            )
        )
        write_cost_log(records)
        print(
            "Phase 3 preflight passed for the first create-only query. "
            "Downstream dry runs require the preceding new table."
        )
        return

    for step in BUILD_STEPS:
        _run_step(client, config, step, records)

    validation_rows = list(
        client.list_rows(config.table_id("phase3_validation_summary"))
    )
    failed = [row for row in validation_rows if row["validation_status"] != "PASS"]
    if failed:
        details = ", ".join(
            f"{row['check_id']}={row['observed_value']} "
            f"expected={row['expected_value']}"
            for row in failed
        )
        raise RuntimeError(f"Phase 3 validation failed: {details}")

    _export_review_tables(client, config)
    print("Phase 3 rule-based attribution validation passed. Stop before Phase 4.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Create the three approved Phase 3 outputs after dry runs.",
    )
    args = parser.parse_args()
    run_phase3(load_config(), execute=args.execute)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
