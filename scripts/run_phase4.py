"""Safely build and validate the approved Phase 4 Markov attribution outputs."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from src.attribution.markov import (  # noqa: E402
    ABSORBING_STATES,
    FLOATING_POINT_TOLERANCE,
    START_STATE,
    calculate_streaming_removal_effects,
    normalize_removal_effects,
    transition_records,
)

OUTPUT_DIR = ROOT / "reports" / "tables"
COST_LOG_PATH = OUTPUT_DIR / "phase4_query_costs.csv"
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

MARKOV_VERSION = "phase4_markov_30d_anderl_v2_20260811"
EXPECTED_MAPPING_VERSION = "phase2b_channel_v2_20260806"
EXPECTED_PATH_VERSION = "phase2b_closeout_v1_20260806"
EXPECTED_ATTRIBUTION_VERSION = "phase3_rule_attribution_v1_20260809"
PHASE4_TABLES = (
    "markov_journeys",
    "markov_transition_matrix",
    "markov_removal_effects",
    "markov_attribution",
    "rule_markov_comparison",
    "phase4_validation_summary",
)


@dataclass(frozen=True)
class Phase4Config:
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
class QueryStep:
    query_id: str
    sql_path: Path
    destination_table: str
    clustering_fields: tuple[str, ...] = ()


JOURNEY_STEP = QueryStep(
    "01_markov_journeys",
    ROOT / "sql" / "intermediate" / "07_markov_journeys.sql",
    "markov_journeys",
    ("journey_status", "user_pseudo_id"),
)
COMPARISON_STEP = QueryStep(
    "05_rule_markov_comparison",
    ROOT / "sql" / "marts" / "03_rule_markov_comparison.sql",
    "rule_markov_comparison",
    ("model", "channel"),
)
VALIDATION_STEP = QueryStep(
    "06_phase4_validation",
    ROOT / "sql" / "validation" / "04_phase4_validation.sql",
    "phase4_validation_summary",
)
SQL_STEPS = (JOURNEY_STEP, COMPARISON_STEP, VALIDATION_STEP)


def load_config() -> Phase4Config:
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
            "Phase 4 requires the finalized 2020-11-01 through 2021-01-31 range"
        )
    maximum_bytes_billed = int(os.environ["MAXIMUM_BYTES_BILLED"])
    if maximum_bytes_billed != 1_000_000_000:
        raise ValueError("Phase 4 MAXIMUM_BYTES_BILLED must equal 1000000000")
    return Phase4Config(
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
            "Unresolved SQL placeholders: " + ", ".join(sorted(set(unresolved)))
        )
    return rendered.strip().rstrip(";")


def render_step(step: QueryStep, config: Phase4Config) -> str:
    return replace_placeholders(
        step.sql_path.read_text(encoding="utf-8"),
        {
            "{{TARGET_PROJECT}}": config.gcp_project_id,
            "{{TARGET_DATASET}}": config.bq_dataset,
        },
    )


def validate_query_sql(sql: str, config: Phase4Config) -> None:
    sql_without_leading_comments = re.sub(
        r"\A(?:\s*--[^\r\n]*(?:\r?\n|\Z))*", "", sql
    )
    normalized = re.sub(r"\s+", " ", sql_without_leading_comments).strip().upper()
    if not normalized.startswith(("SELECT ", "WITH ")):
        raise ValueError("Phase 4 SQL must start with SELECT or WITH")
    for keyword in FORBIDDEN_SQL_KEYWORDS:
        if re.search(rf"\b{keyword}\b", normalized):
            raise ValueError(f"Forbidden SQL keyword: {keyword}")
    if re.search(r"\bSELECT\s+(?:[A-Z0-9_]+\.)?\*", normalized):
        raise ValueError("SELECT * is not allowed in Phase 4 SQL")
    if f"`{config.source_table}`" in sql:
        raise ValueError("Phase 4 must not scan the public GA4 wildcard")


def _table_exists(client: Any, table_id: str) -> bool:
    from google.api_core.exceptions import NotFound

    try:
        client.get_table(table_id)
    except NotFound:
        return False
    return True


def _dry_run(client: Any, sql: str, config: Phase4Config) -> int:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        dry_run=True,
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
    )
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    return int(job.total_bytes_processed or 0)


def _query_without_destination(
    client: Any,
    sql: str,
    config: Phase4Config,
) -> tuple[Any, Iterable[Any]]:
    from google.cloud import bigquery

    job_config = bigquery.QueryJobConfig(
        use_legacy_sql=False,
        use_query_cache=False,
        maximum_bytes_billed=config.maximum_bytes_billed,
    )
    job = client.query(sql, job_config=job_config, location=config.bq_location)
    return job, job.result()


def _execute_destination_query(
    client: Any,
    sql: str,
    config: Phase4Config,
    step: QueryStep,
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


def _load_json_create_only(
    client: Any,
    config: Phase4Config,
    table_name: str,
    rows: list[dict[str, object]],
    schema: list[Any],
) -> Any:
    from google.cloud import bigquery

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
        write_disposition=bigquery.WriteDisposition.WRITE_EMPTY,
    )
    job = client.load_table_from_json(
        rows,
        config.table_id(table_name),
        job_config=job_config,
        location=config.bq_location,
    )
    job.result()
    return job


def _query_cost_record(
    query_id: str,
    sql_file: str,
    destination_table: str,
    sql: str,
    estimated_bytes: int,
    config: Phase4Config,
    job: Any | None,
    row_count: int | str,
) -> dict[str, object]:
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


def _write_cost_log(records: list[dict[str, object]]) -> None:
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


def _validate_fresh_targets(client: Any, config: Phase4Config) -> None:
    existing = [
        table_name
        for table_name in PHASE4_TABLES
        if _table_exists(client, config.table_id(table_name))
    ]
    if existing:
        raise RuntimeError(
            "Phase 4 uses create-only outputs and will not replace existing tables: "
            + ", ".join(existing)
        )


def _foundation_sql(config: Phase4Config) -> str:
    return f"""
WITH conversion_orders AS (
  SELECT order_key, ANY_VALUE(order_revenue_usd) AS order_revenue_usd
  FROM `{config.table_id('conversion_touchpoints')}`
  GROUP BY order_key
),
per_model AS (
  SELECT model, COUNT(DISTINCT order_key) AS order_count,
    SUM(attributed_conversion) AS conversions,
    SUM(attributed_revenue) AS revenue
  FROM `{config.table_id('attribution_results')}`
  GROUP BY model
)
SELECT
  (SELECT COUNT(*) FROM `{config.table_id('phase2b_validation_summary')}`)
    AS phase2b_check_count,
  (SELECT COUNTIF(validation_status != 'PASS')
   FROM `{config.table_id('phase2b_validation_summary')}`)
    AS phase2b_failure_count,
  (SELECT COUNT(*) FROM `{config.table_id('phase3_validation_summary')}`)
    AS phase3_check_count,
  (SELECT COUNTIF(validation_status != 'PASS')
   FROM `{config.table_id('phase3_validation_summary')}`)
    AS phase3_failure_count,
  (SELECT COUNT(*) FROM conversion_orders) AS converting_order_count,
  (SELECT COUNT(DISTINCT user_pseudo_id)
   FROM `{config.table_id('conversion_touchpoints')}`) AS converting_user_count,
  (SELECT COUNT(*) FROM `{config.table_id('conversion_touchpoints')}`)
    AS converting_touchpoint_count,
  (SELECT ROUND(SUM(order_revenue_usd), 2) FROM conversion_orders)
    AS converting_revenue,
  (SELECT COUNT(*) FROM `{config.table_id('attribution_results')}`)
    AS phase3_result_rows,
  (SELECT COUNT(*) FROM per_model) AS phase3_model_count,
  (SELECT COUNTIF(order_count != 4457 OR ABS(conversions - 4457.0) > 1e-9
    OR ABS(revenue - 308208.0) > 1e-6) FROM per_model)
    AS phase3_model_reconciliation_failures,
  (SELECT COUNTIF(attribution_version != '{EXPECTED_ATTRIBUTION_VERSION}')
   FROM `{config.table_id('attribution_results')}`)
    AS invalid_phase3_version_count,
  (SELECT COUNTIF(mapping_version != '{EXPECTED_MAPPING_VERSION}'
    OR path_definition_version != '{EXPECTED_PATH_VERSION}')
   FROM `{config.table_id('conversion_touchpoints')}`)
    AS invalid_input_version_count
""".strip()


def _validate_foundations(
    client: Any,
    config: Phase4Config,
) -> tuple[Any, str, int]:
    dataset = client.get_dataset(config.target_dataset_id)
    if dataset.location.upper() != config.bq_location.upper():
        raise RuntimeError("Dataset location does not match BQ_LOCATION")
    sql = _foundation_sql(config)
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    job, row_iterator = _query_without_destination(client, sql, config)
    row = next(iter(row_iterator))
    observed = (
        int(row["phase2b_check_count"]),
        int(row["phase2b_failure_count"]),
        int(row["phase3_check_count"]),
        int(row["phase3_failure_count"]),
        int(row["converting_order_count"]),
        int(row["converting_user_count"]),
        int(row["converting_touchpoint_count"]),
        round(float(row["converting_revenue"]), 2),
        int(row["phase3_result_rows"]),
        int(row["phase3_model_count"]),
        int(row["phase3_model_reconciliation_failures"]),
        int(row["invalid_phase3_version_count"]),
        int(row["invalid_input_version_count"]),
    )
    expected = (70, 0, 46, 0, 4457, 3705, 9577, 308208.0, 27409, 5, 0, 0, 0)
    if observed != expected:
        raise RuntimeError(
            f"Phase 4 prerequisite validation failed: observed={observed}, "
            f"expected={expected}"
        )
    print(f"Phase 4 prerequisite validation passed: {observed}")
    return job, sql, estimate


def _population_preflight_sql(journey_sql: str) -> str:
    return f"""
WITH journeys AS (
  {journey_sql}
),
conversion_sessions AS (
  SELECT DISTINCT session_key
  FROM journeys
  CROSS JOIN UNNEST(session_key_path) AS session_key
  WHERE journey_status = 'Conversion'
),
null_sessions AS (
  SELECT DISTINCT session_key
  FROM journeys
  CROSS JOIN UNNEST(session_key_path) AS session_key
  WHERE journey_status = 'Null'
)
SELECT
  COUNTIF(journey_status = 'Conversion') AS conversion_journeys,
  COUNT(DISTINCT IF(journey_status = 'Conversion', user_pseudo_id, NULL))
    AS converting_users,
  SUM(IF(journey_status = 'Conversion', session_count, 0))
    AS conversion_touchpoints,
  ROUND(SUM(IF(journey_status = 'Conversion', attributable_revenue_usd, 0)), 2)
    AS conversion_revenue,
  COUNTIF(journey_status = 'Null') AS null_journeys,
  COUNT(DISTINCT IF(journey_status = 'Null', user_pseudo_id, NULL))
    AS null_users,
  SUM(IF(journey_status = 'Null', session_count, 0)) AS null_session_rows,
  COUNTIF(journey_status = 'Right Censored') AS right_censored_journeys,
  COUNT(DISTINCT IF(journey_status = 'Right Censored', user_pseudo_id, NULL))
    AS right_censored_users,
  SUM(IF(journey_status = 'Right Censored', session_count, 0))
    AS right_censored_session_rows,
  COUNTIF(journey_status = 'Null' AND is_left_boundary_truncated)
    AS left_boundary_null_journeys,
  COUNTIF(
    EXISTS (
      SELECT 1 FROM UNNEST(channel_path) AS channel
      WHERE channel = 'Internal/Admin'
    )
  ) AS internal_admin_states,
  (SELECT COUNT(*) FROM conversion_sessions
   INNER JOIN null_sessions USING (session_key))
    AS conversion_null_overlap_sessions
FROM journeys
""".strip()


def _validate_population_row(row: Any) -> dict[str, object]:
    counters = {
        "conversion_journeys": int(row["conversion_journeys"]),
        "converting_users": int(row["converting_users"]),
        "conversion_touchpoints": int(row["conversion_touchpoints"]),
        "conversion_revenue": round(float(row["conversion_revenue"]), 2),
        "null_journeys": int(row["null_journeys"]),
        "null_users": int(row["null_users"]),
        "null_session_rows": int(row["null_session_rows"]),
        "right_censored_journeys": int(row["right_censored_journeys"]),
        "right_censored_users": int(row["right_censored_users"]),
        "right_censored_session_rows": int(row["right_censored_session_rows"]),
        "left_boundary_null_journeys": int(row["left_boundary_null_journeys"]),
        "conversion_null_overlap_sessions": int(
            row["conversion_null_overlap_sessions"]
        ),
        "internal_admin_states": int(row["internal_admin_states"]),
    }
    expected = {
        "conversion_journeys": 4457,
        "converting_users": 3705,
        "conversion_touchpoints": 9577,
        "conversion_revenue": 308208.0,
        "null_journeys": 177632,
        "null_users": 177156,
        "null_session_rows": 229522,
        "right_censored_journeys": 91594,
        "right_censored_users": 91594,
        "right_censored_session_rows": 117470,
        "left_boundary_null_journeys": 77918,
        "conversion_null_overlap_sessions": 0,
        "internal_admin_states": 0,
    }
    if counters != expected:
        raise RuntimeError(
            "Phase 4 journey population failed: "
            f"observed={json.dumps(counters, sort_keys=True)}, "
            f"expected={json.dumps(expected, sort_keys=True)}"
        )
    print(f"Phase 4 journey population passed: {json.dumps(counters, sort_keys=True)}")
    return counters


def _included_paths_sql(journey_sql: str) -> str:
    return f"""
SELECT
  channel_path,
  outcome_state
FROM (
  {journey_sql}
)
WHERE is_markov_included
""".strip()


def _write_included_paths(rows: Iterable[Any], path: Path) -> int:
    path_count = 0
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            channels = [str(channel) for channel in row["channel_path"]]
            outcome = str(row["outcome_state"])
            if outcome not in ABSORBING_STATES:
                raise RuntimeError(f"Unexpected included outcome: {outcome}")
            handle.write(json.dumps([START_STATE, *channels, outcome]) + "\n")
            path_count += 1
    if path_count != 4457 + 177632:
        raise RuntimeError(f"Unexpected included Markov path count: {path_count}")
    return path_count


def _iter_path_file(path: Path) -> Iterable[tuple[str, ...]]:
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            yield tuple(json.loads(line))


def _collect_included_paths(rows: Iterable[Any]) -> list[tuple[str, ...]]:
    """Small-population helper retained for unit-level callers."""

    paths: list[tuple[str, ...]] = []
    for row in rows:
        channels = tuple(str(channel) for channel in row["channel_path"])
        outcome = str(row["outcome_state"])
        if outcome not in ABSORBING_STATES:
            raise RuntimeError(f"Unexpected included outcome: {outcome}")
        paths.append((START_STATE, *channels, outcome))
    return paths


def _transition_schema() -> list[Any]:
    from google.cloud import bigquery

    return [
        bigquery.SchemaField("from_state", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("to_state", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("transition_count", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("transition_probability", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("is_absorbing_from_state", "BOOLEAN", mode="REQUIRED"),
        bigquery.SchemaField("can_reach_absorbing", "BOOLEAN", mode="REQUIRED"),
        bigquery.SchemaField("from_state_order", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("to_state_order", "INTEGER", mode="REQUIRED"),
        bigquery.SchemaField("baseline_conversion_probability", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("markov_version", "STRING", mode="REQUIRED"),
    ]


def _removal_schema() -> list[Any]:
    from google.cloud import bigquery

    return [
        bigquery.SchemaField("channel", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("baseline_conversion_probability", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField(
            "conversion_probability_without_channel", "FLOAT", mode="REQUIRED"
        ),
        bigquery.SchemaField("raw_removal_effect", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("removal_effect", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("floating_point_adjusted", "BOOLEAN", mode="REQUIRED"),
        bigquery.SchemaField("materially_negative", "BOOLEAN", mode="REQUIRED"),
        bigquery.SchemaField("markov_version", "STRING", mode="REQUIRED"),
    ]


def _attribution_schema() -> list[Any]:
    from google.cloud import bigquery

    return [
        bigquery.SchemaField("channel", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("markov_share", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("attributed_conversions", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("attributed_revenue", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("conversion_share", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("revenue_share", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("baseline_conversion_probability", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("total_removal_effect", "FLOAT", mode="REQUIRED"),
        bigquery.SchemaField("markov_version", "STRING", mode="REQUIRED"),
    ]


def _run_sql_step(
    client: Any,
    config: Phase4Config,
    step: QueryStep,
    records: list[dict[str, object]],
) -> None:
    sql = render_step(step, config)
    validate_query_sql(sql, config)
    estimate = _dry_run(client, sql, config)
    if estimate > config.maximum_bytes_billed:
        raise RuntimeError(f"{step.query_id} dry run exceeds the billing cap")
    job = _execute_destination_query(client, sql, config, step)
    row_count = client.get_table(config.table_id(step.destination_table)).num_rows
    records.append(
        _query_cost_record(
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
    print(f"{step.query_id}: estimated_bytes={estimate}, rows={row_count}")


def run_phase4(config: Phase4Config, execute: bool) -> None:
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
    records: list[dict[str, object]] = []
    prerequisite_job, prerequisite_sql, prerequisite_estimate = _validate_foundations(
        client, config
    )
    records.append(
        _query_cost_record(
            "00_phase4_prerequisites",
            "generated:phase4_prerequisites",
            "",
            prerequisite_sql,
            prerequisite_estimate,
            config,
            prerequisite_job,
            1,
        )
    )
    _validate_fresh_targets(client, config)
    for step in SQL_STEPS:
        validate_query_sql(render_step(step, config), config)

    journey_sql = render_step(JOURNEY_STEP, config)
    journey_estimate = _dry_run(client, journey_sql, config)
    if journey_estimate > config.maximum_bytes_billed:
        raise RuntimeError("Phase 4 journey query exceeds the billing cap")
    if not execute:
        records.append(
            _query_cost_record(
                JOURNEY_STEP.query_id,
                JOURNEY_STEP.sql_path.relative_to(ROOT).as_posix(),
                config.table_id(JOURNEY_STEP.destination_table),
                journey_sql,
                journey_estimate,
                config,
                None,
                "",
            )
        )
        _write_cost_log(records)
        print(
            "Phase 4 preflight passed. Execute only after reviewing the "
            "approved graph-state removal normalization behavior."
        )
        return

    population_sql = _population_preflight_sql(journey_sql)
    validate_query_sql(population_sql, config)
    population_estimate = _dry_run(client, population_sql, config)
    population_job, population_rows = _query_without_destination(
        client, population_sql, config
    )
    population = _validate_population_row(next(iter(population_rows)))
    records.append(
        _query_cost_record(
            "01a_markov_journey_population_preflight",
            JOURNEY_STEP.sql_path.relative_to(ROOT).as_posix(),
            "",
            population_sql,
            population_estimate,
            config,
            population_job,
            sum(
                int(population[key])
                for key in (
                    "conversion_journeys",
                    "null_journeys",
                    "right_censored_journeys",
                )
            ),
        )
    )
    _write_cost_log(records)

    included_paths_sql = _included_paths_sql(journey_sql)
    validate_query_sql(included_paths_sql, config)
    included_paths_estimate = _dry_run(client, included_paths_sql, config)
    included_paths_job, included_path_rows = _query_without_destination(
        client, included_paths_sql, config
    )
    with TemporaryDirectory(prefix="phase4_markov_") as temporary_directory:
        path_file = Path(temporary_directory) / "included_paths.jsonl"
        path_count = _write_included_paths(included_path_rows, path_file)
        records.append(
            _query_cost_record(
                "01b_markov_included_path_extract",
                JOURNEY_STEP.sql_path.relative_to(ROOT).as_posix(),
                "",
                included_paths_sql,
                included_paths_estimate,
                config,
                included_paths_job,
                path_count,
            )
        )
        _write_cost_log(records)
        baseline_model, baseline_probability, removal_results = (
            calculate_streaming_removal_effects(
                lambda: _iter_path_file(path_file)
            )
        )
    expected_population_probability = 4457 / (4457 + 177632)
    if abs(baseline_probability - expected_population_probability) > 1e-12:
        raise RuntimeError(
            "Baseline Markov journey conversion probability does not reconcile: "
            f"observed={baseline_probability}, expected={expected_population_probability}"
        )
    print(f"Markov states: {baseline_model.states}")
    print(f"Markov journey conversion probability: {baseline_probability:.15f}")
    print(
        "Removal diagnostics: "
        + json.dumps(
            {
                result.channel: {
                    "without_probability": result.conversion_probability_without_channel,
                    "raw_effect": result.raw_removal_effect,
                    "effect": result.removal_effect,
                    "materially_negative": result.materially_negative,
                }
                for result in removal_results
            },
            sort_keys=True,
        )
    )
    if any(result.materially_negative for result in removal_results):
        raise RuntimeError("Materially negative removal effect detected; stop normalization")
    try:
        shares = normalize_removal_effects(
            {result.channel: result.removal_effect for result in removal_results}
        )
    except ValueError as exc:
        raise RuntimeError(
            "Approved graph-state removal effects cannot be normalized; no persistent "
            f"Phase 4 objects were created: {exc}"
        ) from exc

    _run_sql_step(client, config, JOURNEY_STEP, records)

    transition_rows = transition_records(baseline_model)
    for row in transition_rows:
        row["baseline_conversion_probability"] = baseline_probability
        row["markov_version"] = MARKOV_VERSION
    _load_json_create_only(
        client,
        config,
        "markov_transition_matrix",
        transition_rows,
        _transition_schema(),
    )

    removal_rows = [
        {
            "channel": result.channel,
            "baseline_conversion_probability": baseline_probability,
            "conversion_probability_without_channel": (
                result.conversion_probability_without_channel
            ),
            "raw_removal_effect": result.raw_removal_effect,
            "removal_effect": result.removal_effect,
            "floating_point_adjusted": result.floating_point_adjusted,
            "materially_negative": result.materially_negative,
            "markov_version": MARKOV_VERSION,
        }
        for result in removal_results
    ]
    _load_json_create_only(
        client,
        config,
        "markov_removal_effects",
        removal_rows,
        _removal_schema(),
    )

    total_effect = sum(result.removal_effect for result in removal_results)
    attribution_rows = [
        {
            "channel": channel,
            "markov_share": share,
            "attributed_conversions": 4457.0 * share,
            "attributed_revenue": 308208.0 * share,
            "conversion_share": share,
            "revenue_share": share,
            "baseline_conversion_probability": baseline_probability,
            "total_removal_effect": total_effect,
            "markov_version": MARKOV_VERSION,
        }
        for channel, share in sorted(shares.items())
    ]
    _load_json_create_only(
        client,
        config,
        "markov_attribution",
        attribution_rows,
        _attribution_schema(),
    )
    _run_sql_step(client, config, COMPARISON_STEP, records)
    _run_sql_step(client, config, VALIDATION_STEP, records)

    validation_rows = list(
        client.list_rows(config.table_id("phase4_validation_summary"))
    )
    failed = [row for row in validation_rows if row["validation_status"] != "PASS"]
    if failed:
        details = ", ".join(
            f"{row['check_id']}={row['observed_value']} expected={row['expected_value']}"
            for row in failed
        )
        raise RuntimeError(f"Phase 4 validation failed: {details}")
    print("Phase 4 Markov attribution validation passed. Stop before Phase 5.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Create the six approved Phase 4 outputs after all preflight checks.",
    )
    args = parser.parse_args()
    run_phase4(load_config(), execute=args.execute)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
