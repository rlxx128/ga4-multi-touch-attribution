"""Safely rebuild approved source tables and create Phase 2B path tables."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
from collections.abc import Iterable
from dataclasses import dataclass, replace
from datetime import date, datetime, time
from decimal import Decimal
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "reports" / "tables"
COST_LOG_PATH = OUTPUT_DIR / "phase2b_query_costs.csv"
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

RESOLUTION_VERSION = "phase2b_source_v1_20260806"
MAPPING_VERSION = "phase2b_channel_v1_20260806"

REPLACED_TABLES = (
    "session_source_candidates",
    "channel_source_coverage_audit",
    "source_medium_campaign_frequency",
)


@dataclass(frozen=True)
class Phase2BConfig:
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
        if not DATASET_PATTERN.fullmatch(table_name):
            raise ValueError(f"Invalid table name: {table_name}")
        return f"{self.target_dataset_id}.{table_name}"


@dataclass(frozen=True)
class BuildStep:
    query_id: str
    sql_path: Path
    destination_table: str
    write_mode: str = "create"
    clustering_fields: tuple[str, ...] = ()
    mapping_alias: str | None = None


SOURCE_AUDIT_STEP = BuildStep(
    "01_source_reprocessing_session_audit",
    ROOT / "sql" / "audit" / "13_source_reprocessing_session_audit.sql",
    "source_reprocessing_session_audit",
    "create",
    ("was_internal_storefront_resolved_referral", "session_key"),
)

SOURCE_AUDIT_RECOVERY_STEP = BuildStep(
    "01c_source_reprocessing_audit_rebuild",
    ROOT / "sql" / "audit" / "13b_source_reprocessing_audit_from_snapshot.sql",
    "source_reprocessing_session_audit",
    "replace",
    ("was_internal_storefront_resolved_referral", "session_key"),
)

REPLACEMENT_STEPS = (
    BuildStep(
        "02_session_source_candidates_rebuild",
        ROOT / "sql" / "intermediate" / "03_session_source_candidates_rebuild.sql",
        "session_source_candidates",
        "replace",
        ("user_pseudo_id", "source_resolution_tier"),
    ),
    BuildStep(
        "03_channel_source_coverage_rebuild",
        ROOT / "sql" / "audit" / "16_channel_source_coverage_rebuild.sql",
        "channel_source_coverage_audit",
        "replace",
    ),
    BuildStep(
        "04_source_frequency_rebuild",
        ROOT / "sql" / "audit" / "17_source_medium_campaign_frequency_rebuild.sql",
        "source_medium_campaign_frequency",
        "replace",
        ("source_resolution_tier", "resolved_source", "resolved_medium"),
    ),
)

CREATION_STEPS = (
    BuildStep(
        "05_internal_domain_rules",
        ROOT / "sql" / "audit" / "14_internal_domain_rules.sql",
        "internal_domain_rules",
    ),
    BuildStep(
        "06_channel_mapping_rules",
        ROOT / "sql" / "audit" / "15_channel_mapping_rules.sql",
        "channel_mapping_rules",
    ),
    BuildStep(
        "07_session_touchpoints",
        ROOT / "sql" / "intermediate" / "04_session_touchpoints.sql",
        "session_touchpoints",
        "create",
        ("user_pseudo_id", "channel", "is_internal_admin_traffic"),
        "prepared_sessions",
    ),
    BuildStep(
        "08_source_reprocessing_summary",
        ROOT / "sql" / "audit" / "18_source_reprocessing_summary.sql",
        "source_reprocessing_summary",
        "create",
        ("was_internal_storefront_resolved_referral", "after_source_resolution_tier"),
        "before_prepared",
    ),
    BuildStep(
        "09_channel_mapping_audit",
        ROOT / "sql" / "audit" / "19_channel_mapping_audit.sql",
        "channel_mapping_audit",
        "create",
        ("channel", "source_resolution_tier", "resolved_source"),
    ),
    BuildStep(
        "10_conversion_touchpoints",
        ROOT / "sql" / "intermediate" / "05_conversion_touchpoints.sql",
        "conversion_touchpoints",
        "create",
        ("order_key", "session_key", "channel"),
    ),
    BuildStep(
        "11_order_path_coverage_audit",
        ROOT / "sql" / "audit" / "20_order_path_coverage_audit.sql",
        "order_path_coverage_audit",
        "create",
        ("user_pseudo_id", "path_covered_after_admin_exclusion"),
    ),
    BuildStep(
        "12_orders_without_touchpoints",
        ROOT / "sql" / "intermediate" / "06_orders_without_touchpoints.sql",
        "orders_without_touchpoints",
        "create",
        ("exclusion_reason", "user_pseudo_id"),
    ),
    BuildStep(
        "13_internal_admin_path_impact",
        ROOT / "sql" / "audit" / "21_internal_admin_path_impact_audit.sql",
        "internal_admin_path_impact_audit",
    ),
    BuildStep(
        "14_admin_domain_candidate_audit",
        ROOT / "sql" / "audit" / "22_admin_domain_candidate_audit.sql",
        "admin_domain_candidate_audit",
    ),
    BuildStep(
        "15_same_session_multiple_order_audit",
        ROOT / "sql" / "audit" / "23_same_session_multiple_order_audit.sql",
        "same_session_multiple_order_audit",
        "create",
        ("session_reuse_violation", "user_pseudo_id"),
    ),
    BuildStep(
        "16_path_length_distribution",
        ROOT / "sql" / "audit" / "24_path_length_distribution_audit.sql",
        "path_length_distribution_audit",
    ),
    BuildStep(
        "17_phase2b_validation_summary",
        ROOT / "sql" / "validation" / "02_phase2b_validation.sql",
        "phase2b_validation_summary",
    ),
)

NEW_TABLES = (SOURCE_AUDIT_STEP.destination_table,) + tuple(
    step.destination_table for step in CREATION_STEPS
)

LOCAL_EXPORTS = {
    "channel_source_coverage_audit": "phase2b_channel_source_coverage_audit.csv",
    "source_medium_campaign_frequency": "phase2b_source_medium_campaign_frequency.csv",
    "internal_domain_rules": "phase2b_internal_domain_rules.csv",
    "channel_mapping_rules": "phase2b_channel_mapping_rules.csv",
    "source_reprocessing_summary": "phase2b_source_reprocessing_summary.csv",
    "channel_mapping_audit": "phase2b_channel_mapping_audit.csv",
    "order_path_coverage_audit": "phase2b_order_path_coverage_audit.csv",
    "orders_without_touchpoints": "phase2b_orders_without_touchpoints.csv",
    "internal_admin_path_impact_audit": "phase2b_internal_admin_path_impact_audit.csv",
    "admin_domain_candidate_audit": "phase2b_admin_domain_candidate_audit.csv",
    "same_session_multiple_order_audit": "phase2b_same_session_multiple_order_audit.csv",
    "path_length_distribution_audit": "phase2b_path_length_distribution_audit.csv",
    "phase2b_validation_summary": "phase2b_validation_summary.csv",
}


def load_config() -> Phase2BConfig:
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
        raise ValueError("Phase 2B requires 2020-11-01 through 2021-01-31")
    maximum_bytes_billed = int(os.environ["MAXIMUM_BYTES_BILLED"])
    if maximum_bytes_billed != 1_000_000_000:
        raise ValueError("Phase 2B MAXIMUM_BYTES_BILLED must equal 1000000000")

    return Phase2BConfig(
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


def base_replacements(config: Phase2BConfig) -> dict[str, str]:
    return {
        "{{SOURCE_TABLE}}": config.source_table,
        "{{TARGET_PROJECT}}": config.gcp_project_id,
        "{{TARGET_DATASET}}": config.bq_dataset,
        "{{START_SUFFIX}}": config.start_suffix,
        "{{END_SUFFIX}}": config.end_suffix,
    }


def replace_placeholders(template: str, replacements: dict[str, str]) -> str:
    rendered = template
    for placeholder, value in replacements.items():
        rendered = rendered.replace(placeholder, value)
    unresolved = PLACEHOLDER_PATTERN.findall(rendered)
    if unresolved:
        raise ValueError(f"Unresolved SQL placeholders: {', '.join(sorted(set(unresolved)))}")
    return rendered.strip().rstrip(";")


def render_source_resolution(config: Phase2BConfig) -> str:
    template = (
        ROOT / "sql" / "intermediate" / "03_session_source_candidates_rebuild.sql"
    ).read_text(encoding="utf-8")
    return replace_placeholders(template, base_replacements(config))


def render_mapping_struct(alias: str) -> str:
    template = (
        ROOT / "sql" / "intermediate" / "channel_mapping_v1.sql"
    ).read_text(encoding="utf-8")
    return replace_placeholders(template, {"{{ROW_ALIAS}}": alias})


def render_order_cycles(config: Phase2BConfig) -> str:
    template = (
        ROOT / "sql" / "intermediate" / "order_cycles_v1.sql"
    ).read_text(encoding="utf-8")
    return replace_placeholders(template, base_replacements(config))


def render_step(step: BuildStep, config: Phase2BConfig) -> str:
    replacements = base_replacements(config)
    template = step.sql_path.read_text(encoding="utf-8")
    if "{{SOURCE_RESOLUTION_QUERY}}" in template:
        replacements["{{SOURCE_RESOLUTION_QUERY}}"] = render_source_resolution(config)
    if "{{CHANNEL_MAPPING_STRUCT}}" in template:
        if not step.mapping_alias:
            raise ValueError(f"{step.query_id} requires a mapping alias")
        replacements["{{CHANNEL_MAPPING_STRUCT}}"] = render_mapping_struct(
            step.mapping_alias
        )
    if "{{ORDER_CYCLES_QUERY}}" in template:
        replacements["{{ORDER_CYCLES_QUERY}}"] = render_order_cycles(config)
    return replace_placeholders(template, replacements)


def validate_query_sql(sql: str, config: Phase2BConfig) -> None:
    sql_without_leading_comments = re.sub(
        r"\A(?:\s*--[^\r\n]*(?:\r?\n|\Z))*", "", sql
    )
    normalized = re.sub(r"\s+", " ", sql_without_leading_comments).strip().upper()
    if not normalized.startswith(("SELECT ", "WITH ")):
        raise ValueError("Phase 2B SQL must start with SELECT or WITH")
    for keyword in FORBIDDEN_SQL_KEYWORDS:
        if re.search(rf"\b{keyword}\b", normalized):
            raise ValueError(f"Forbidden SQL keyword: {keyword}")
    if re.search(r"\bSELECT\s+\*", normalized):
        raise ValueError("SELECT * is not allowed in Phase 2B SQL")
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
                raise ValueError("Wildcard query suffix range is outside Phase 2B")


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


def read_cost_log() -> list[dict[str, Any]]:
    if not COST_LOG_PATH.is_file():
        return []
    with COST_LOG_PATH.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


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


def _dry_run(client: Any, sql: str, config: Phase2BConfig) -> int:
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
    config: Phase2BConfig,
    step: BuildStep,
) -> Any:
    from google.cloud import bigquery

    write_disposition = (
        bigquery.WriteDisposition.WRITE_TRUNCATE
        if step.write_mode == "replace"
        else bigquery.WriteDisposition.WRITE_EMPTY
    )
    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
        destination=config.table_id(step.destination_table),
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        write_disposition=write_disposition,
    )
    if step.clustering_fields:
        job_config.clustering_fields = list(step.clustering_fields)
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    job.result()
    return job


def _record_query(
    records: list[dict[str, Any]],
    *,
    query_id: str,
    sql_file: str,
    destination_table: str,
    sql: str,
    estimate: int,
    config: Phase2BConfig,
    job: Any | None = None,
    row_count: int | str = "",
) -> dict[str, Any]:
    record = {
        "query_id": query_id,
        "sql_file": sql_file,
        "destination_table": destination_table,
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
    records.append(record)
    return record


def _run_step(
    client: Any,
    config: Phase2BConfig,
    step: BuildStep,
    records: list[dict[str, Any]],
) -> None:
    sql = render_step(step, config)
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    if estimate > config.maximum_bytes_billed:
        record = _record_query(
            records,
            query_id=step.query_id,
            sql_file=step.sql_path.relative_to(ROOT).as_posix(),
            destination_table=config.table_id(step.destination_table),
            sql=sql,
            estimate=estimate,
            config=config,
        )
        record["status"] = "OVER_CAP"
        write_cost_log(records)
        raise RuntimeError(f"{step.query_id} dry run exceeds the billing cap")
    print(f"{step.query_id}: estimated_bytes={estimate}")
    job = _execute_destination_query(client, sql, config, step)
    row_count = client.get_table(config.table_id(step.destination_table)).num_rows
    _record_query(
        records,
        query_id=step.query_id,
        sql_file=step.sql_path.relative_to(ROOT).as_posix(),
        destination_table=config.table_id(step.destination_table),
        sql=sql,
        estimate=estimate,
        config=config,
        job=job,
        row_count=row_count,
    )
    write_cost_log(records)
    print(f"{step.query_id}: rows={row_count}")


def _table_exists(client: Any, table_id: str) -> bool:
    from google.api_core.exceptions import NotFound

    try:
        client.get_table(table_id)
    except NotFound:
        return False
    return True


def _has_field(client: Any, table_id: str, field_name: str) -> bool:
    table = client.get_table(table_id)
    return field_name in {field.name for field in table.schema}


def _validate_foundations(client: Any, config: Phase2BConfig) -> None:
    expected_rows = {
        "event_base": 4_295_584,
        "orders": 4_466,
        "session_source_candidates": 360_129,
    }
    dataset = client.get_dataset(config.target_dataset_id)
    if dataset.location.upper() != config.bq_location.upper():
        raise RuntimeError("Dataset location does not match BQ_LOCATION")
    print(
        "dataset expiration defaults: "
        f"table_ms={dataset.default_table_expiration_ms}, "
        f"partition_ms={dataset.default_partition_expiration_ms}"
    )
    for table_name, expected in expected_rows.items():
        table = client.get_table(config.table_id(table_name))
        if table.num_rows != expected:
            raise RuntimeError(
                f"Foundation {table_name} has {table.num_rows} rows; expected {expected}"
            )


def _validate_fresh_targets(client: Any, config: Phase2BConfig) -> None:
    existing = [
        table_name
        for table_name in NEW_TABLES
        if _table_exists(client, config.table_id(table_name))
    ]
    if existing:
        raise RuntimeError(
            "Phase 2B will not replace existing new targets: " + ", ".join(existing)
        )
    if _has_field(
        client, config.table_id("session_source_candidates"), "resolution_version"
    ):
        raise RuntimeError("Source candidates are already rebuilt; use --resume")


def _completed_creation_prefix(client: Any, config: Phase2BConfig) -> set[str]:
    completed: list[str] = []
    for step in CREATION_STEPS:
        if _table_exists(client, config.table_id(step.destination_table)):
            completed.append(step.destination_table)
        else:
            break
    unexpected = [
        step.destination_table
        for step in CREATION_STEPS[len(completed) :]
        if _table_exists(client, config.table_id(step.destination_table))
    ]
    if unexpected:
        raise RuntimeError(
            "Cannot resume because Phase 2B targets do not form a prefix: "
            + ", ".join(unexpected)
        )
    return set(completed)


def _run_reprocessing_precheck(
    client: Any,
    config: Phase2BConfig,
    records: list[dict[str, Any]],
) -> None:
    table_id = config.table_id("source_reprocessing_session_audit")
    sql = f"""
SELECT
  COUNT(*) AS audit_session_count,
  COUNTIF(was_internal_storefront_resolved_referral) AS affected_session_count,
  COUNTIF(before_source_resolution_tier IS NULL OR after_source_resolution_tier IS NULL) AS unmatched_session_count
FROM `{table_id}`
""".strip()
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    if estimate > config.maximum_bytes_billed:
        raise RuntimeError("Source reprocessing precheck exceeds the billing cap")

    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
    )
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    rows = list(job.result())
    row = rows[0]
    _record_query(
        records,
        query_id="01b_source_reprocessing_precheck",
        sql_file="generated:source_reprocessing_precheck",
        destination_table="",
        sql=sql,
        estimate=estimate,
        config=config,
        job=job,
        row_count=1,
    )
    write_cost_log(records)
    observed = (
        int(row["audit_session_count"]),
        int(row["affected_session_count"]),
        int(row["unmatched_session_count"]),
    )
    expected = (360_129, 70_820, 0)
    print(f"source reprocessing precheck: observed={observed}, expected={expected}")
    if observed != expected:
        raise RuntimeError(
            "Source reprocessing precheck failed; stopping before provisional table replacement"
        )


def _replacement_complete(client: Any, config: Phase2BConfig, step: BuildStep) -> bool:
    return _has_field(
        client,
        config.table_id(step.destination_table),
        "resolution_version",
    )


def _export_review_tables(client: Any, config: Phase2BConfig) -> None:
    for table_name, filename in LOCAL_EXPORTS.items():
        table = client.get_table(config.table_id(table_name))
        field_names = [field.name for field in table.schema]
        count = write_rows(
            OUTPUT_DIR / filename,
            client.list_rows(table),
            field_names,
        )
        print(f"export {filename}: rows={count}")


def run_phase2b(
    config: Phase2BConfig,
    execute: bool,
    resume: bool = False,
    rebuild_derived: bool = False,
    rebuild_source: bool = False,
    rebuild_validation: bool = False,
) -> None:
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
    _validate_foundations(client, config)
    if rebuild_derived and not (execute and resume):
        raise ValueError("--rebuild-derived requires --execute --resume")
    if rebuild_source and not (execute and resume):
        raise ValueError("--rebuild-source requires --execute --resume")
    if rebuild_validation and not (execute and resume):
        raise ValueError("--rebuild-validation requires --execute --resume")
    if rebuild_validation and (rebuild_source or rebuild_derived):
        raise ValueError(
            "--rebuild-validation cannot be combined with a broader rebuild option"
        )
    if resume:
        if not execute:
            raise ValueError("--resume requires --execute")
        completed_creation = _completed_creation_prefix(client, config)
        records = read_cost_log()
    else:
        _validate_fresh_targets(client, config)
        completed_creation = set()
        records = []

    audit_exists = _table_exists(
        client, config.table_id(SOURCE_AUDIT_STEP.destination_table)
    )
    if not audit_exists:
        sql = render_step(SOURCE_AUDIT_STEP, config)
        validate_query_sql(sql, config)
        estimate = _dry_run(client, sql, config)
        print(f"{SOURCE_AUDIT_STEP.query_id}: estimated_bytes={estimate}")
        if estimate > config.maximum_bytes_billed:
            raise RuntimeError("Source reprocessing audit exceeds the billing cap")
        if not execute:
            _record_query(
                records,
                query_id=SOURCE_AUDIT_STEP.query_id,
                sql_file=SOURCE_AUDIT_STEP.sql_path.relative_to(ROOT).as_posix(),
                destination_table=config.table_id(SOURCE_AUDIT_STEP.destination_table),
                sql=sql,
                estimate=estimate,
                config=config,
            )
            write_cost_log(records)
            print("Preflight complete. Downstream dry runs require rebuilt dependencies.")
            return
        _run_step(client, config, SOURCE_AUDIT_STEP, records)
    elif not resume:
        raise RuntimeError("Source reprocessing audit already exists; use --resume")

    if rebuild_source:
        _run_step(client, config, SOURCE_AUDIT_RECOVERY_STEP, records)

    _run_reprocessing_precheck(client, config, records)

    for step in REPLACEMENT_STEPS:
        if not rebuild_source and _replacement_complete(client, config, step):
            print(f"{step.query_id}: approved replacement already complete; skipped")
            continue
        _run_step(client, config, step, records)
        expected_rows = 360_129 if step.destination_table == "session_source_candidates" else None
        if expected_rows is not None:
            observed_rows = client.get_table(config.table_id(step.destination_table)).num_rows
            if observed_rows != expected_rows:
                raise RuntimeError(
                    f"Rebuilt Session count is {observed_rows}; expected {expected_rows}"
                )

    rebuilding = False
    for step in CREATION_STEPS:
        if rebuild_validation:
            if step.destination_table != "phase2b_validation_summary":
                print(f"{step.query_id}: validation-only rebuild; skipped")
                continue
            effective_step = replace(step, write_mode="replace")
            _run_step(client, config, effective_step, records)
            continue
        if step.destination_table == "session_touchpoints":
            rebuilding = rebuild_derived or rebuild_source
        if rebuilding:
            effective_step = (
                replace(step, write_mode="replace")
                if _table_exists(client, config.table_id(step.destination_table))
                else step
            )
            _run_step(client, config, effective_step, records)
            continue
        if step.destination_table in completed_creation:
            print(f"{step.query_id}: already present in validated resume prefix; skipped")
            continue
        _run_step(client, config, step, records)

    validation_rows = list(
        client.list_rows(config.table_id("phase2b_validation_summary"))
    )
    failed = [row for row in validation_rows if row["validation_status"] != "PASS"]
    if failed:
        details = ", ".join(
            f"{row['check_id']}={row['observed_value']} expected={row['expected_value']}"
            for row in failed
        )
        raise RuntimeError(f"Phase 2B validation failed: {details}")

    _export_review_tables(client, config)
    print("Phase 2B validation passed. Stop before Phase 3 attribution.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Execute after dry runs; default is a source-reprocessing preflight.",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume only from a validated incomplete Phase 2B prefix.",
    )
    parser.add_argument(
        "--rebuild-derived",
        action="store_true",
        help="Replace partial Phase 2B derived tables after an implementation fix.",
    )
    parser.add_argument(
        "--rebuild-source",
        action="store_true",
        help=(
            "Recompute source resolution from the preserved Phase 2A audit snapshot "
            "and replace all Phase 2B derived tables."
        ),
    )
    parser.add_argument(
        "--rebuild-validation",
        action="store_true",
        help="Replace only the Phase 2B validation summary after adding checks.",
    )
    args = parser.parse_args()
    run_phase2b(
        load_config(),
        args.execute,
        args.resume,
        args.rebuild_derived,
        args.rebuild_source,
        args.rebuild_validation,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
