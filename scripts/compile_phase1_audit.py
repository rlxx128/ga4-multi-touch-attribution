"""Combine chunked Phase 1 audit outputs and compile validation results."""

from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
TABLE_DIR = ROOT / "reports" / "tables"
MONTHS = ("202011", "202012", "202101")


def read_csv(path: Path) -> list[dict[str, str]]:
    """Read a generated audit CSV."""
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, field_names: list[str], rows: Iterable[dict[str, object]]) -> None:
    """Write dictionaries to a deterministic UTF-8 CSV."""
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=field_names)
        writer.writeheader()
        writer.writerows(rows)


def combine_traffic_availability() -> list[dict[str, object]]:
    """Sum monthly field counts and recalculate full-range rates."""
    count_fields = (
        "denominator_event_count",
        "null_count",
        "blank_count",
        "nonblank_count",
        "placeholder_count",
    )
    totals: dict[tuple[str, str], dict[str, int]] = defaultdict(
        lambda: {field: 0 for field in count_fields}
    )
    for month in MONTHS:
        path = TABLE_DIR / f"phase1_traffic_source_availability_{month}.csv"
        for row in read_csv(path):
            key = (row["audit_scope"], row["field_name"])
            for field in count_fields:
                totals[key][field] += int(row[field])

    output_rows: list[dict[str, object]] = []
    for (audit_scope, field_name), counts in sorted(totals.items()):
        denominator = counts["denominator_event_count"]
        if denominator == 0:
            status = "FAIL_EMPTY_SCOPE"
        elif counts["nonblank_count"] == 0:
            status = "REVIEW_NO_USABLE_VALUES"
        elif counts["null_count"] + counts["blank_count"] > 0:
            status = "REVIEW_PARTIAL_COVERAGE"
        elif counts["placeholder_count"] > 0:
            status = "REVIEW_PLACEHOLDERS"
        else:
            status = "PASS"
        output_rows.append(
            {
                "audit_scope": audit_scope,
                "field_name": field_name,
                "denominator_event_count": denominator,
                "null_count": counts["null_count"],
                "null_rate": counts["null_count"] / denominator if denominator else "",
                "blank_count": counts["blank_count"],
                "blank_rate": counts["blank_count"] / denominator if denominator else "",
                "nonblank_count": counts["nonblank_count"],
                "nonblank_rate": counts["nonblank_count"] / denominator if denominator else "",
                "placeholder_count": counts["placeholder_count"],
                "placeholder_rate": (
                    counts["placeholder_count"] / denominator if denominator else ""
                ),
                "validation_status": status,
            }
        )

    field_names = [
        "audit_scope",
        "field_name",
        "denominator_event_count",
        "null_count",
        "null_rate",
        "blank_count",
        "blank_rate",
        "nonblank_count",
        "nonblank_rate",
        "placeholder_count",
        "placeholder_rate",
        "validation_status",
    ]
    write_csv(TABLE_DIR / "phase1_traffic_source_availability.csv", field_names, output_rows)
    return output_rows


def combine_traffic_value_samples() -> list[dict[str, object]]:
    """Combine monthly counts and retain the global top 25 values per field."""
    counts: dict[tuple[str, str, str], int] = defaultdict(int)
    for month in MONTHS:
        path = TABLE_DIR / f"phase1_traffic_source_value_samples_{month}.csv"
        for row in read_csv(path):
            key = (row["field_name"], row["field_value"], row["referrer_host"])
            counts[key] += int(row["event_count"])

    totals: dict[str, int] = defaultdict(int)
    by_field: dict[str, list[tuple[str, str, int]]] = defaultdict(list)
    for (field_name, field_value, referrer_host), event_count in counts.items():
        totals[field_name] += event_count
        by_field[field_name].append((field_value, referrer_host, event_count))

    output_rows: list[dict[str, object]] = []
    for field_name in sorted(by_field):
        ordered_values = sorted(
            by_field[field_name],
            key=lambda item: (-item[2], item[0], item[1]),
        )
        for rank, (field_value, referrer_host, event_count) in enumerate(
            ordered_values[:25], start=1
        ):
            output_rows.append(
                {
                    "field_name": field_name,
                    "value_rank": rank,
                    "field_value": field_value,
                    "referrer_host": referrer_host,
                    "event_count": event_count,
                    "event_share": event_count / totals[field_name],
                }
            )

    field_names = [
        "field_name",
        "value_rank",
        "field_value",
        "referrer_host",
        "event_count",
        "event_share",
    ]
    write_csv(
        TABLE_DIR / "phase1_traffic_source_value_samples.csv",
        field_names,
        output_rows,
    )
    return output_rows


def normalized_review_status(source_status: str) -> str:
    """Treat quantified source defects as accepted review items, not silent passes."""
    if source_status.startswith("FAIL"):
        return "FAIL"
    if source_status.startswith("REVIEW"):
        return "PASS_WITH_REVIEW"
    return "PASS"


def compile_validation_results(
    traffic_availability: list[dict[str, object]],
) -> list[dict[str, object]]:
    """Create a compact acceptance table from executed audit outputs."""
    validations: list[dict[str, object]] = []

    cost_rows = read_csv(TABLE_DIR / "phase1_query_costs.csv")
    cost_pass = bool(cost_rows) and all(
        row["within_cap"] == "True"
        and row["executed"] == "True"
        and row["status"] == "EXECUTED"
        for row in cost_rows
    )
    validations.append(
        {
            "check_id": "query_safety_and_cost",
            "scope": "all_physical_queries",
            "status": "PASS" if cost_pass else "FAIL",
            "detail": f"{len(cost_rows)} jobs recorded; all must execute within cap",
        }
    )

    schema_rows = read_csv(TABLE_DIR / "phase1_source_schema.csv")
    schema_by_path = {row["field_path"]: row for row in schema_rows}
    required_paths = {
        "event_date",
        "event_timestamp",
        "event_name",
        "user_pseudo_id",
        "event_params",
        "event_params.key",
        "event_params.value.int_value",
        "event_params.value.string_value",
        "ecommerce.transaction_id",
        "ecommerce.purchase_revenue",
        "ecommerce.purchase_revenue_in_usd",
        "traffic_source.source",
        "traffic_source.medium",
        "traffic_source.name",
    }
    missing_paths = sorted(
        path
        for path in required_paths
        if path not in schema_by_path
        or schema_by_path[path]["present_in_all_shards"] != "True"
    )
    validations.append(
        {
            "check_id": "required_source_schema",
            "scope": "92_configured_shards",
            "status": "PASS" if not missing_paths else "FAIL",
            "detail": "all required paths present" if not missing_paths else ", ".join(missing_paths),
        }
    )

    date_rows = read_csv(TABLE_DIR / "phase1_date_coverage.csv")
    date_pass = len(date_rows) == 92 and all(
        row["validation_status"] == "PASS" for row in date_rows
    )
    validations.append(
        {
            "check_id": "date_coverage",
            "scope": "20201101_through_20210131",
            "status": "PASS" if date_pass else "FAIL",
            "detail": f"{len(date_rows)} expected-date rows",
        }
    )

    event_rows = read_csv(TABLE_DIR / "phase1_event_name_distribution.csv")
    null_event_rows = [row for row in event_rows if row["event_name"] == "[NULL_OR_BLANK]"]
    purchase_rows = [row for row in event_rows if row["event_name"] == "purchase"]
    validations.extend(
        [
            {
                "check_id": "event_name_completeness",
                "scope": "all_events",
                "status": "PASS" if not null_event_rows else "FAIL",
                "detail": "no null/blank event name" if not null_event_rows else "null/blank event names found",
            },
            {
                "check_id": "purchase_event_presence",
                "scope": "event_distribution",
                "status": "PASS" if purchase_rows and int(purchase_rows[0]["event_count"]) > 0 else "FAIL",
                "detail": "purchase event observed" if purchase_rows else "purchase event absent",
            },
        ]
    )

    purchase_summary = read_csv(TABLE_DIR / "phase1_purchase_quality_summary.csv")[0]
    validations.append(
        {
            "check_id": "purchase_transaction_revenue_quality",
            "scope": "purchase_events",
            "status": normalized_review_status(purchase_summary["validation_status"]),
            "detail": purchase_summary["validation_status"],
        }
    )

    duplicate_rows = read_csv(TABLE_DIR / "phase1_duplicate_purchase_diagnostics.csv")
    validations.append(
        {
            "check_id": "duplicate_purchase_diagnostics",
            "scope": "candidate_user_transaction_keys",
            "status": "PASS" if not duplicate_rows else "PASS_WITH_REVIEW",
            "detail": f"{len(duplicate_rows)} duplicate candidate keys",
        }
    )

    for row in read_csv(TABLE_DIR / "phase1_identifier_quality.csv"):
        validations.append(
            {
                "check_id": "identifier_quality",
                "scope": row["audit_scope"],
                "status": normalized_review_status(row["validation_status"]),
                "detail": row["validation_status"],
            }
        )

    for row in traffic_availability:
        validations.append(
            {
                "check_id": "traffic_source_availability",
                "scope": f"{row['audit_scope']}:{row['field_name']}",
                "status": normalized_review_status(str(row["validation_status"])),
                "detail": str(row["validation_status"]),
            }
        )

    write_csv(
        TABLE_DIR / "phase1_validation_results.csv",
        ["check_id", "scope", "status", "detail"],
        validations,
    )
    return validations


def main() -> int:
    """Compile the full-range Phase 1 audit outputs."""
    availability = combine_traffic_availability()
    sample_rows = combine_traffic_value_samples()
    validations = compile_validation_results(availability)
    print(f"Combined traffic availability rows: {len(availability)}")
    print(f"Combined traffic sample rows: {len(sample_rows)}")
    print(f"Validation rows: {len(validations)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
