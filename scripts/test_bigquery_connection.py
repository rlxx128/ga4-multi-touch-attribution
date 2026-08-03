"""Run a bounded, read-only BigQuery connection test using ADC."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from datetime import date

import google.auth
from google.cloud import bigquery


CONNECTION_TEST_SUFFIX = "20201101"
CONNECTION_TEST_DATE = date(2020, 11, 1)
CONNECTION_TEST_MAXIMUM_BYTES_BILLED = 1_000_000_000
REQUIRED_VARIABLES = (
    "GCP_PROJECT_ID",
    "BQ_DATASET",
    "BQ_LOCATION",
    "GA4_SOURCE_TABLE",
    "START_DATE",
    "END_DATE",
    "MAXIMUM_BYTES_BILLED",
)
TABLE_PATTERN = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_]+\.[A-Za-z0-9_*]+$")
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


@dataclass(frozen=True)
class ProjectConfig:
    """Validated configuration required by the connection test."""

    gcp_project_id: str
    bq_dataset: str
    bq_location: str
    ga4_source_table: str
    start_date: date
    end_date: date
    maximum_bytes_billed: int


def load_config() -> ProjectConfig:
    """Load non-secret project settings from environment variables."""
    missing = [name for name in REQUIRED_VARIABLES if not os.environ.get(name)]
    if missing:
        joined = ", ".join(missing)
        raise ValueError(f"Missing required environment variables: {joined}")

    source_table = os.environ["GA4_SOURCE_TABLE"]
    if not TABLE_PATTERN.fullmatch(source_table) or not source_table.endswith(
        "events_*"
    ):
        raise ValueError("GA4_SOURCE_TABLE must be a valid events_* wildcard table")

    start_date = date.fromisoformat(os.environ["START_DATE"])
    end_date = date.fromisoformat(os.environ["END_DATE"])
    if start_date > end_date:
        raise ValueError("START_DATE must be on or before END_DATE")
    if not start_date <= CONNECTION_TEST_DATE <= end_date:
        raise ValueError("The configured range must include 2020-11-01")

    maximum_bytes_billed = int(os.environ["MAXIMUM_BYTES_BILLED"])
    if maximum_bytes_billed != CONNECTION_TEST_MAXIMUM_BYTES_BILLED:
        raise ValueError(
            "MAXIMUM_BYTES_BILLED must equal 1000000000 for the connection test"
        )

    return ProjectConfig(
        gcp_project_id=os.environ["GCP_PROJECT_ID"],
        bq_dataset=os.environ["BQ_DATASET"],
        bq_location=os.environ["BQ_LOCATION"],
        ga4_source_table=source_table,
        start_date=start_date,
        end_date=end_date,
        maximum_bytes_billed=maximum_bytes_billed,
    )


def build_connection_query(source_table: str) -> str:
    """Build the fixed one-day read-only connection query."""
    return f"""
SELECT
  event_date,
  event_name
FROM `{source_table}`
WHERE _TABLE_SUFFIX = '{CONNECTION_TEST_SUFFIX}'
LIMIT 1
""".strip()


def validate_read_only_query(sql: str) -> None:
    """Reject mutations or a connection query without the fixed suffix filter."""
    normalized = re.sub(r"\s+", " ", sql.strip()).upper()
    if not normalized.startswith("SELECT "):
        raise ValueError("Connection test query must start with SELECT")
    for keyword in FORBIDDEN_SQL_KEYWORDS:
        if re.search(rf"\b{keyword}\b", normalized):
            raise ValueError(f"Forbidden SQL keyword: {keyword}")
    required_filter = f"_TABLE_SUFFIX = '{CONNECTION_TEST_SUFFIX}'"
    if required_filter not in sql:
        raise ValueError("Connection test query must restrict _TABLE_SUFFIX to 20201101")


def run_connection_test(config: ProjectConfig) -> None:
    """Validate dataset metadata, dry run, and execute the bounded SELECT query."""
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    client = bigquery.Client(
        project=config.gcp_project_id,
        location=config.bq_location,
        credentials=credentials,
    )

    dataset_id = f"{config.gcp_project_id}.{config.bq_dataset}"
    dataset = client.get_dataset(dataset_id)
    if (dataset.location or "").upper() != config.bq_location.upper():
        raise RuntimeError(
            f"Dataset location {dataset.location!r} does not match "
            f"configured location {config.bq_location!r}"
        )

    sql = build_connection_query(config.ga4_source_table)
    validate_read_only_query(sql)

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
    if estimated_bytes > config.maximum_bytes_billed:
        raise RuntimeError(
            f"Estimated bytes {estimated_bytes} exceed the configured ceiling"
        )

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
    rows = list(query_job.result())
    if len(rows) != 1:
        raise RuntimeError(f"Expected one connection-test row, received {len(rows)}")

    print("BigQuery connection test passed.")
    print(f"Dataset: {dataset_id}")
    print(f"Dataset location: {dataset.location}")
    print("SQL:")
    print(sql)
    print(f"Estimated bytes processed: {estimated_bytes}")
    print(f"Actual bytes processed: {int(query_job.total_bytes_processed or 0)}")
    print(f"Actual bytes billed: {int(query_job.total_bytes_billed or 0)}")
    print(f"Maximum bytes billed: {config.maximum_bytes_billed}")


def main() -> int:
    """Load configuration and run the connection test."""
    run_connection_test(load_config())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
