"""Dry-run and execute bounded, read-only Phase 1 BigQuery audit SQL."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import Decimal
from pathlib import Path
from typing import Any, Iterable

import google.auth
from google.cloud import bigquery


ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql" / "audit"
OUTPUT_DIR = ROOT / "reports" / "tables"
COST_LOG_PATH = OUTPUT_DIR / "phase1_query_costs.csv"
SOURCE_TABLE_PATTERN = re.compile(
    r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_]+\.events_\*$"
)
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
PLACEHOLDER_PATTERN = re.compile(r"\{\{[A-Z_]+\}\}")


@dataclass(frozen=True)
class AuditConfig:
    """Validated settings used by every Phase 1 audit query."""

    gcp_project_id: str
    bq_location: str
    source_table: str
    source_dataset: str
    start_date: date
    end_date: date
    start_suffix: str
    end_suffix: str
    maximum_bytes_billed: int


def load_config() -> AuditConfig:
    """Load Phase 1 settings from environment variables."""
    required = (
        "GCP_PROJECT_ID",
        "BQ_LOCATION",
        "GA4_SOURCE_TABLE",
        "START_DATE",
        "END_DATE",
        "MAXIMUM_BYTES_BILLED",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise ValueError(f"Missing required environment variables: {', '.join(missing)}")

    source_table = os.environ["GA4_SOURCE_TABLE"]
    if not SOURCE_TABLE_PATTERN.fullmatch(source_table):
        raise ValueError("GA4_SOURCE_TABLE must be a valid fully qualified events_* table")
    source_dataset = source_table.rsplit(".", maxsplit=1)[0]

    start_date = date.fromisoformat(os.environ["START_DATE"])
    end_date = date.fromisoformat(os.environ["END_DATE"])
    if (start_date, end_date) != (date(2020, 11, 1), date(2021, 1, 31)):
        raise ValueError("Phase 1 requires the fixed range 2020-11-01 through 2021-01-31")

    maximum_bytes_billed = int(os.environ["MAXIMUM_BYTES_BILLED"])
    if maximum_bytes_billed != 1_000_000_000:
        raise ValueError("Phase 1 MAXIMUM_BYTES_BILLED must equal 1000000000")

    return AuditConfig(
        gcp_project_id=os.environ["GCP_PROJECT_ID"],
        bq_location=os.environ["BQ_LOCATION"],
        source_table=source_table,
        source_dataset=source_dataset,
        start_date=start_date,
        end_date=end_date,
        start_suffix=start_date.strftime("%Y%m%d"),
        end_suffix=end_date.strftime("%Y%m%d"),
        maximum_bytes_billed=maximum_bytes_billed,
    )


def render_sql(
    template: str,
    config: AuditConfig,
    extra_replacements: dict[str, str] | None = None,
) -> str:
    """Render the small, allow-listed set of Phase 1 SQL placeholders."""
    replacements = {
        "{{SOURCE_TABLE}}": config.source_table,
        "{{SOURCE_DATASET}}": config.source_dataset,
        "{{START_DATE}}": config.start_date.isoformat(),
        "{{END_DATE}}": config.end_date.isoformat(),
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


def validate_read_only_sql(sql: str, config: AuditConfig) -> None:
    """Reject mutation statements, SELECT *, or an unbounded source wildcard."""
    sql_without_leading_comments = re.sub(
        r"\A(?:\s*--[^\r\n]*(?:\r?\n|\Z))*",
        "",
        sql,
    )
    normalized = re.sub(r"\s+", " ", sql_without_leading_comments).strip().upper()
    if not (normalized.startswith("SELECT ") or normalized.startswith("WITH ")):
        raise ValueError("Audit SQL must start with SELECT or WITH")
    for keyword in FORBIDDEN_SQL_KEYWORDS:
        if re.search(rf"\b{keyword}\b", normalized):
            raise ValueError(f"Forbidden SQL keyword: {keyword}")
    if re.search(r"\bSELECT\s+\*", normalized):
        raise ValueError("SELECT * is not allowed in Phase 1 audit SQL")

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
                config.start_suffix
                <= start_suffix
                <= end_suffix
                <= config.end_suffix
            ):
                raise ValueError("Wildcard query suffix range is outside Phase 1")


def discover_sql_files(only: set[str] | None = None) -> list[Path]:
    """Return numbered Phase 1 SQL files, optionally restricted by stem."""
    files = sorted(SQL_DIR.glob("[0-9][0-9]_*.sql"))
    if only:
        files = [path for path in files if path.stem in only]
        missing = only - {path.stem for path in files}
        if missing:
            raise ValueError(f"Unknown SQL file stems: {', '.join(sorted(missing))}")
    if not files:
        raise ValueError("No Phase 1 audit SQL files were selected")
    return files


def query_variants(sql_path: Path) -> list[tuple[str | None, dict[str, str]]]:
    """Split wide traffic-field scans into exact, under-cap monthly jobs."""
    if sql_path.stem not in {
        "07_traffic_source_availability",
        "08_traffic_source_value_samples",
    }:
        return [(None, {})]
    return [
        (
            "202011",
            {
                "{{CHUNK_START_SUFFIX}}": "20201101",
                "{{CHUNK_END_SUFFIX}}": "20201130",
            },
        ),
        (
            "202012",
            {
                "{{CHUNK_START_SUFFIX}}": "20201201",
                "{{CHUNK_END_SUFFIX}}": "20201231",
            },
        ),
        (
            "202101",
            {
                "{{CHUNK_START_SUFFIX}}": "20210101",
                "{{CHUNK_END_SUFFIX}}": "20210131",
            },
        ),
    ]


def output_path_for(sql_path: Path, variant: str | None = None) -> Path:
    """Map a numbered SQL file to its local Phase 1 CSV output."""
    logical_name = re.sub(r"^\d{2}_", "", sql_path.stem)
    suffix = f"_{variant}" if variant else ""
    return OUTPUT_DIR / f"phase1_{logical_name}{suffix}.csv"


def serialize_value(value: Any) -> str:
    """Serialize BigQuery scalar and nested values deterministically for CSV."""
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
    """Write query rows to a UTF-8 CSV and return the row count."""
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(field_names)
        for row in rows:
            writer.writerow([serialize_value(row[name]) for name in field_names])
            count += 1
    return count


def write_cost_log(records: list[dict[str, Any]]) -> None:
    """Write dry-run and execution metadata for every selected query."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    field_names = [
        "query_id",
        "sql_file",
        "sql_sha256",
        "estimated_bytes",
        "maximum_bytes_billed",
        "within_cap",
        "executed",
        "actual_bytes_processed",
        "actual_bytes_billed",
        "row_count",
        "status",
    ]
    merged_records: dict[str, dict[str, Any]] = {}
    if COST_LOG_PATH.is_file():
        with COST_LOG_PATH.open(newline="", encoding="utf-8") as handle:
            for existing in csv.DictReader(handle):
                merged_records[existing["query_id"]] = dict(existing)
    for record in records:
        merged_records[str(record["query_id"])] = record

    def sort_key(record: dict[str, Any]) -> tuple[int, str]:
        query_id = str(record["query_id"])
        return int(query_id[:2]), query_id

    with COST_LOG_PATH.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=field_names)
        writer.writeheader()
        writer.writerows(sorted(merged_records.values(), key=sort_key))


def run_audit(config: AuditConfig, sql_files: list[Path], execute: bool) -> None:
    """Dry-run selected SQL and optionally execute queries that fit the cap."""
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    client = bigquery.Client(
        project=config.gcp_project_id,
        location=config.bq_location,
        credentials=credentials,
    )
    records: list[dict[str, Any]] = []

    for sql_path in sql_files:
        template = sql_path.read_text(encoding="utf-8")
        for variant, extra_replacements in query_variants(sql_path):
            sql = render_sql(template, config, extra_replacements)
            validate_read_only_sql(sql, config)
            digest = hashlib.sha256(sql.encode("utf-8")).hexdigest()
            display_name = sql_path.name if variant is None else f"{sql_path.name}:{variant}"

            dry_run_config = bigquery.QueryJobConfig(
                dry_run=True,
                use_legacy_sql=False,
                use_query_cache=False,
                maximum_bytes_billed=config.maximum_bytes_billed,
            )
            dry_run_job = client.query(
                sql,
                job_config=dry_run_config,
                location=config.bq_location,
            )
            estimated_bytes = int(dry_run_job.total_bytes_processed or 0)
            within_cap = estimated_bytes <= config.maximum_bytes_billed
            record: dict[str, Any] = {
                "query_id": sql_path.stem[:2] if variant is None else f"{sql_path.stem[:2]}_{variant}",
                "sql_file": sql_path.relative_to(ROOT).as_posix(),
                "sql_sha256": digest,
                "estimated_bytes": estimated_bytes,
                "maximum_bytes_billed": config.maximum_bytes_billed,
                "within_cap": within_cap,
                "executed": False,
                "actual_bytes_processed": "",
                "actual_bytes_billed": "",
                "row_count": "",
                "status": "DRY_RUN_PASSED" if within_cap else "OVER_CAP",
            }
            records.append(record)
            print(f"{display_name}: estimated_bytes={estimated_bytes}")

            if not within_cap:
                write_cost_log(records)
                raise RuntimeError(
                    f"{display_name} exceeds maximum bytes billed: {estimated_bytes}"
                )
            if not execute:
                continue

            query_config = bigquery.QueryJobConfig(
                use_legacy_sql=False,
                use_query_cache=False,
                maximum_bytes_billed=config.maximum_bytes_billed,
            )
            query_job = client.query(
                sql,
                job_config=query_config,
                location=config.bq_location,
            )
            result = query_job.result()
            field_names = [field.name for field in result.schema]
            row_count = write_rows(output_path_for(sql_path, variant), result, field_names)
            record.update(
                {
                    "executed": True,
                    "actual_bytes_processed": int(query_job.total_bytes_processed or 0),
                    "actual_bytes_billed": int(query_job.total_bytes_billed or 0),
                    "row_count": row_count,
                    "status": "EXECUTED",
                }
            )
            print(f"{display_name}: rows={row_count}")

    write_cost_log(records)


def main() -> int:
    """Parse arguments and run the Phase 1 audit safely."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Execute after a successful dry run; default is dry run only.",
    )
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        metavar="SQL_STEM",
        help="Run only the named SQL stem; may be supplied more than once.",
    )
    args = parser.parse_args()
    run_audit(load_config(), discover_sql_files(set(args.only) or None), args.execute)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
