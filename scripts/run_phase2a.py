"""Safely build and validate the approval-gated Phase 2A BigQuery tables."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "reports" / "tables"
COST_LOG_PATH = OUTPUT_DIR / "phase2a_query_costs.csv"
SOURCE_TABLE_PATTERN = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_]+\.events_\*$")
PROJECT_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{4,62}$")
DATASET_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,1023}$")
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

TARGET_TABLES = (
    "event_base",
    "orders",
    "internal_referrer_domain_audit",
    "session_source_candidates",
    "channel_source_coverage_audit",
    "source_medium_campaign_frequency",
    "channel_mapping_proposal",
    "phase2a_validation_summary",
)

MONTH_CHUNKS = (
    ("202011", "20201101", "20201130"),
    ("202012", "20201201", "20201231"),
    ("202101", "20210101", "20210131"),
)


@dataclass(frozen=True)
class Phase2AConfig:
    """Validated settings used by every Phase 2A query."""

    gcp_project_id: str
    bq_dataset: str
    bq_location: str
    source_table: str
    start_date: date
    end_date: date
    start_suffix: str
    end_suffix: str
    maximum_bytes_billed: int

    @property
    def target_dataset_id(self) -> str:
        return f"{self.gcp_project_id}.{self.bq_dataset}"

    def table_id(self, table_name: str) -> str:
        if table_name not in TARGET_TABLES:
            raise ValueError(f"Unknown Phase 2A target table: {table_name}")
        return f"{self.target_dataset_id}.{table_name}"


@dataclass(frozen=True)
class BuildStep:
    """One destination-table query after event_base is available."""

    query_id: str
    sql_path: Path
    destination_table: str
    partition_field: str | None = None
    clustering_fields: tuple[str, ...] = ()


BUILD_STEPS = (
    BuildStep(
        "02_orders",
        ROOT / "sql" / "intermediate" / "01_orders.sql",
        "orders",
        None,
        ("user_pseudo_id", "transaction_id"),
    ),
    BuildStep(
        "03_internal_referrer_domain_audit",
        ROOT / "sql" / "audit" / "09_internal_referrer_domain_audit.sql",
        "internal_referrer_domain_audit",
        None,
        ("proposed_is_internal", "page_referrer_reg_domain"),
    ),
    BuildStep(
        "04_session_source_candidates",
        ROOT / "sql" / "intermediate" / "02_session_source_candidates.sql",
        "session_source_candidates",
        None,
        ("user_pseudo_id", "source_resolution_tier"),
    ),
    BuildStep(
        "05_channel_source_coverage_audit",
        ROOT / "sql" / "audit" / "10_channel_source_coverage.sql",
        "channel_source_coverage_audit",
    ),
    BuildStep(
        "06_source_medium_campaign_frequency",
        ROOT / "sql" / "audit" / "11_source_medium_campaign_frequency.sql",
        "source_medium_campaign_frequency",
        None,
        ("source_resolution_tier", "resolved_source", "resolved_medium"),
    ),
    BuildStep(
        "07_channel_mapping_proposal",
        ROOT / "sql" / "audit" / "12_channel_mapping_proposal.sql",
        "channel_mapping_proposal",
    ),
    BuildStep(
        "08_phase2a_validation_summary",
        ROOT / "sql" / "validation" / "01_phase2a_validation.sql",
        "phase2a_validation_summary",
    ),
)

LOCAL_EXPORTS = {
    "internal_referrer_domain_audit": "phase2a_internal_referrer_domain_audit.csv",
    "channel_source_coverage_audit": "phase2a_channel_source_coverage_audit.csv",
    "source_medium_campaign_frequency": "phase2a_source_medium_campaign_frequency.csv",
    "channel_mapping_proposal": "phase2a_channel_mapping_proposal.csv",
    "phase2a_validation_summary": "phase2a_validation_summary.csv",
}


def load_config() -> Phase2AConfig:
    """Load Phase 2A settings from environment variables."""
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
        raise ValueError(f"Missing required environment variables: {', '.join(missing)}")

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
        raise ValueError("Phase 2A requires 2020-11-01 through 2021-01-31")

    maximum_bytes_billed = int(os.environ["MAXIMUM_BYTES_BILLED"])
    if maximum_bytes_billed != 1_000_000_000:
        raise ValueError("Phase 2A MAXIMUM_BYTES_BILLED must equal 1000000000")

    return Phase2AConfig(
        gcp_project_id=project,
        bq_dataset=dataset,
        bq_location=os.environ["BQ_LOCATION"],
        source_table=source_table,
        start_date=start_date,
        end_date=end_date,
        start_suffix=start_date.strftime("%Y%m%d"),
        end_suffix=end_date.strftime("%Y%m%d"),
        maximum_bytes_billed=maximum_bytes_billed,
    )


def render_sql(
    template: str,
    config: Phase2AConfig,
    extra_replacements: dict[str, str] | None = None,
) -> str:
    """Render the allow-listed Phase 2A SQL placeholders."""
    replacements = {
        "{{SOURCE_TABLE}}": config.source_table,
        "{{TARGET_PROJECT}}": config.gcp_project_id,
        "{{TARGET_DATASET}}": config.bq_dataset,
        "{{START_SUFFIX}}": config.start_suffix,
        "{{END_SUFFIX}}": config.end_suffix,
    }
    if extra_replacements:
        replacements.update(extra_replacements)
    rendered = template
    for placeholder, value in replacements.items():
        rendered = rendered.replace(placeholder, value)
    unresolved = PLACEHOLDER_PATTERN.findall(rendered)
    if unresolved:
        raise ValueError(f"Unresolved SQL placeholders: {', '.join(sorted(set(unresolved)))}")
    return rendered.strip()


def validate_query_sql(sql: str, config: Phase2AConfig) -> None:
    """Reject SQL mutation statements and unbounded source wildcard scans."""
    sql_without_leading_comments = re.sub(
        r"\A(?:\s*--[^\r\n]*(?:\r?\n|\Z))*", "", sql
    )
    normalized = re.sub(r"\s+", " ", sql_without_leading_comments).strip().upper()
    if not normalized.startswith(("SELECT ", "WITH ")):
        raise ValueError("Phase 2A SQL must start with SELECT or WITH")
    for keyword in FORBIDDEN_SQL_KEYWORDS:
        if re.search(rf"\b{keyword}\b", normalized):
            raise ValueError(f"Forbidden SQL keyword: {keyword}")
    if re.search(r"\bSELECT\s+\*", normalized):
        raise ValueError("SELECT * is not allowed in Phase 2A SQL")

    if f"`{config.source_table}`" in sql:
        suffix_ranges = re.findall(
            r"_TABLE_SUFFIX\s+BETWEEN\s+'(\d{8})'\s+AND\s+'(\d{8})'",
            sql,
            flags=re.IGNORECASE,
        )
        if not suffix_ranges:
            raise ValueError("Wildcard query is missing a bounded _TABLE_SUFFIX range")
        for start_suffix, end_suffix in suffix_ranges:
            if not (
                config.start_suffix <= start_suffix <= end_suffix <= config.end_suffix
            ):
                raise ValueError("Wildcard query suffix range is outside Phase 2A")


def serialize_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (date, datetime, time)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, (dict, list, tuple)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
    return str(value)


def write_rows(path: Path, rows: Iterable[Any], field_names: list[str]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    row_count = 0
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(field_names)
        for row in rows:
            writer.writerow([serialize_value(row[name]) for name in field_names])
            row_count += 1
    return row_count


def write_cost_log(records: list[dict[str, Any]]) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    field_names = [
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
        "status",
    ]
    with COST_LOG_PATH.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=field_names)
        writer.writeheader()
        writer.writerows(records)


def read_cost_log() -> list[dict[str, Any]]:
    """Preserve completed-query evidence when resuming a partial build."""
    if not COST_LOG_PATH.is_file():
        return []
    with COST_LOG_PATH.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _dry_run(client: Any, sql: str, config: Phase2AConfig) -> int:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        dry_run=True,
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
    )
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    return int(job.total_bytes_processed or 0)


def _execute_destination_query(
    client: Any,
    sql: str,
    config: Phase2AConfig,
    destination_table: str,
    write_disposition: str,
    partition_field: str | None = None,
    clustering_fields: tuple[str, ...] = (),
) -> Any:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
        destination=config.table_id(destination_table),
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        write_disposition=write_disposition,
    )
    if partition_field:
        job_config.time_partitioning = bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY,
            field=partition_field,
        )
    if clustering_fields:
        job_config.clustering_fields = list(clustering_fields)
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    job.result()
    return job


def _record_query(
    records: list[dict[str, Any]],
    *,
    query_id: str,
    sql_path: Path,
    destination_table: str,
    sql: str,
    estimate: int,
    config: Phase2AConfig,
    job: Any | None = None,
    row_count: int | str = "",
) -> dict[str, Any]:
    within_cap = estimate <= config.maximum_bytes_billed
    record = {
        "query_id": query_id,
        "sql_file": sql_path.relative_to(ROOT).as_posix(),
        "destination_table": config.table_id(destination_table),
        "sql_sha256": hashlib.sha256(sql.encode("utf-8")).hexdigest(),
        "estimated_bytes": estimate,
        "maximum_bytes_billed": config.maximum_bytes_billed,
        "within_cap": within_cap,
        "executed": job is not None,
        "actual_bytes_processed": int(job.total_bytes_processed or 0) if job else "",
        "actual_bytes_billed": int(job.total_bytes_billed or 0) if job else "",
        "destination_row_count": row_count,
        "status": "EXECUTED" if job else "DRY_RUN_PASSED",
    }
    records.append(record)
    return record


def _assert_no_target_tables(client: Any, config: Phase2AConfig) -> None:
    from google.api_core.exceptions import NotFound

    dataset = client.get_dataset(config.target_dataset_id)
    if dataset.location.upper() != config.bq_location.upper():
        raise RuntimeError(
            f"Dataset location {dataset.location} does not match {config.bq_location}"
        )
    print(
        "dataset expiration defaults: "
        f"table_ms={dataset.default_table_expiration_ms}, "
        f"partition_ms={dataset.default_partition_expiration_ms}"
    )
    existing: list[str] = []
    for table_name in TARGET_TABLES:
        try:
            client.get_table(config.table_id(table_name))
        except NotFound:
            continue
        existing.append(config.table_id(table_name))
    if existing:
        raise RuntimeError(
            "Phase 2A will not replace existing target tables: " + ", ".join(existing)
        )


def _validated_resume_tables(client: Any, config: Phase2AConfig) -> set[str]:
    """Allow resumption only from an exact, internally consistent build prefix."""
    from google.api_core.exceptions import NotFound

    completed: list[str] = []
    for table_name in TARGET_TABLES:
        try:
            client.get_table(config.table_id(table_name))
        except NotFound:
            break
        completed.append(table_name)

    unexpected_existing: list[str] = []
    for table_name in TARGET_TABLES[len(completed) :]:
        try:
            client.get_table(config.table_id(table_name))
        except NotFound:
            continue
        unexpected_existing.append(table_name)
    if unexpected_existing:
        raise RuntimeError(
            "Cannot resume because target tables do not form an execution prefix: "
            + ", ".join(unexpected_existing)
        )
    if not completed or len(completed) == len(TARGET_TABLES):
        raise RuntimeError("Resume requires a non-empty, incomplete Phase 2A table prefix")

    exact_row_counts = {
        "event_base": 4_295_584,
        "orders": 4_466,
        "channel_source_coverage_audit": 5,
        "channel_mapping_proposal": 11,
    }
    positive_row_tables = {
        "internal_referrer_domain_audit",
        "session_source_candidates",
        "source_medium_campaign_frequency",
    }
    for table_name in completed:
        table = client.get_table(config.table_id(table_name))
        if table_name in exact_row_counts and table.num_rows != exact_row_counts[table_name]:
            raise RuntimeError(
                f"Cannot resume: {table_name} has {table.num_rows} rows, "
                f"expected {exact_row_counts[table_name]}"
            )
        if table_name in positive_row_tables and table.num_rows <= 0:
            raise RuntimeError(f"Cannot resume: {table_name} is empty")
        if table_name == "event_base" and table.time_partitioning is not None:
            raise RuntimeError("Cannot resume: event_base must not use historical partitioning")
    print("validated resume prefix: " + ", ".join(completed))
    return set(completed)


def _export_review_tables(client: Any, config: Phase2AConfig) -> None:
    for table_name, filename in LOCAL_EXPORTS.items():
        table = client.get_table(config.table_id(table_name))
        field_names = [field.name for field in table.schema]
        rows = client.list_rows(table)
        count = write_rows(OUTPUT_DIR / filename, rows, field_names)
        print(f"export {filename}: rows={count}")


def run_phase2a(config: Phase2AConfig, execute: bool, resume: bool = False) -> None:
    """Preflight, dry-run, and optionally execute Phase 2A in dependency order."""
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
    completed_tables: set[str] = set()
    if resume:
        if not execute:
            raise ValueError("--resume requires --execute")
        completed_tables = _validated_resume_tables(client, config)
    else:
        _assert_no_target_tables(client, config)

    records: list[dict[str, Any]] = read_cost_log() if resume else []
    event_sql_path = ROOT / "sql" / "staging" / "01_event_base.sql"
    event_template = event_sql_path.read_text(encoding="utf-8")
    rendered_chunks: list[tuple[str, str]] = []
    for variant, start_suffix, end_suffix in MONTH_CHUNKS:
        if resume:
            break
        sql = render_sql(
            event_template,
            config,
            {
                "{{CHUNK_START_SUFFIX}}": start_suffix,
                "{{CHUNK_END_SUFFIX}}": end_suffix,
            },
        )
        validate_query_sql(sql, config)
        estimate = _dry_run(client, sql, config)
        if estimate > config.maximum_bytes_billed:
            _record_query(
                records,
                query_id=f"01_event_base_{variant}",
                sql_path=event_sql_path,
                destination_table="event_base",
                sql=sql,
                estimate=estimate,
                config=config,
            )["status"] = "OVER_CAP"
            write_cost_log(records)
            raise RuntimeError(f"event_base {variant} dry run exceeds the billing cap")
        _record_query(
            records,
            query_id=f"01_event_base_{variant}",
            sql_path=event_sql_path,
            destination_table="event_base",
            sql=sql,
            estimate=estimate,
            config=config,
        )
        rendered_chunks.append((variant, sql))
        print(f"01_event_base_{variant}: estimated_bytes={estimate}")

    if not execute:
        write_cost_log(records)
        print("Preflight complete. Downstream dry runs require event_base to exist.")
        return

    for index, (variant, sql) in enumerate(rendered_chunks):
        job = _execute_destination_query(
            client,
            sql,
            config,
            "event_base",
            bigquery.WriteDisposition.WRITE_EMPTY if index == 0 else bigquery.WriteDisposition.WRITE_APPEND,
            None,
            ("user_pseudo_id", "session_key", "event_name"),
        )
        row_count = client.get_table(config.table_id("event_base")).num_rows
        record = next(row for row in records if row["query_id"] == f"01_event_base_{variant}")
        record.update(
            {
                "executed": True,
                "actual_bytes_processed": int(job.total_bytes_processed or 0),
                "actual_bytes_billed": int(job.total_bytes_billed or 0),
                "destination_row_count": row_count,
                "status": "EXECUTED",
            }
        )
        write_cost_log(records)
        print(f"01_event_base_{variant}: cumulative_rows={row_count}")

    for step in BUILD_STEPS:
        if step.destination_table in completed_tables:
            print(f"{step.query_id}: already validated; skipped on resume")
            continue
        template = step.sql_path.read_text(encoding="utf-8")
        sql = render_sql(template, config)
        validate_query_sql(sql, config)
        estimate = _dry_run(client, sql, config)
        if estimate > config.maximum_bytes_billed:
            _record_query(
                records,
                query_id=step.query_id,
                sql_path=step.sql_path,
                destination_table=step.destination_table,
                sql=sql,
                estimate=estimate,
                config=config,
            )["status"] = "OVER_CAP"
            write_cost_log(records)
            raise RuntimeError(f"{step.query_id} dry run exceeds the billing cap")
        print(f"{step.query_id}: estimated_bytes={estimate}")
        job = _execute_destination_query(
            client,
            sql,
            config,
            step.destination_table,
            bigquery.WriteDisposition.WRITE_EMPTY,
            step.partition_field,
            step.clustering_fields,
        )
        row_count = client.get_table(config.table_id(step.destination_table)).num_rows
        _record_query(
            records,
            query_id=step.query_id,
            sql_path=step.sql_path,
            destination_table=step.destination_table,
            sql=sql,
            estimate=estimate,
            config=config,
            job=job,
            row_count=row_count,
        )
        write_cost_log(records)
        print(f"{step.query_id}: rows={row_count}")

        if step.destination_table == "orders" and row_count != 4466:
            raise RuntimeError(
                f"Order reconciliation failed: expected 4466, observed {row_count}. "
                "Stopping before source recovery tables are created."
            )

    validation_rows = list(client.list_rows(config.table_id("phase2a_validation_summary")))
    failed_checks = [row for row in validation_rows if row["validation_status"] != "PASS"]
    if failed_checks:
        failures = ", ".join(
            f"{row['check_id']}={row['observed_value']} (expected {row['expected_value']})"
            for row in failed_checks
        )
        raise RuntimeError(f"Phase 2A validation failed: {failures}")

    _export_review_tables(client, config)
    print("Phase 2A validation passed. Stop at the channel-mapping approval gate.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Create new Phase 2A tables after dry runs; default is preflight only.",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume only after validating an incomplete Phase 2A table prefix.",
    )
    args = parser.parse_args()
    run_phase2a(load_config(), args.execute, args.resume)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
