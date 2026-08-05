from datetime import date

import pytest

from scripts.run_phase1_audit import AuditConfig, render_sql, validate_read_only_sql


@pytest.fixture
def config() -> AuditConfig:
    return AuditConfig(
        gcp_project_id="example-project",
        bq_location="US",
        source_table="bigquery-public-data.example.events_*",
        source_dataset="bigquery-public-data.example",
        start_date=date(2020, 11, 1),
        end_date=date(2021, 1, 31),
        start_suffix="20201101",
        end_suffix="20210131",
        maximum_bytes_billed=1_000_000_000,
    )


def test_render_and_validate_bounded_select(config: AuditConfig) -> None:
    template = """
-- A business-assumption comment may precede the query.
SELECT event_name
FROM `{{SOURCE_TABLE}}`
WHERE _TABLE_SUFFIX BETWEEN '{{START_SUFFIX}}' AND '{{END_SUFFIX}}'
"""
    sql = render_sql(template, config)
    validate_read_only_sql(sql, config)
    assert "20201101" in sql
    assert "20210131" in sql


@pytest.mark.parametrize(
    "sql",
    [
        "SELECT event_name FROM `bigquery-public-data.example.events_*`",
        "SELECT * FROM `bigquery-public-data.example.events_*` WHERE "
        "_TABLE_SUFFIX BETWEEN '20201101' AND '20210131'",
        "CREATE TABLE x AS SELECT 1",
    ],
)
def test_validate_rejects_unsafe_sql(sql: str, config: AuditConfig) -> None:
    with pytest.raises(ValueError):
        validate_read_only_sql(sql, config)


def test_validate_allows_bounded_month_chunk(config: AuditConfig) -> None:
    sql = """
SELECT event_name
FROM `bigquery-public-data.example.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
"""
    validate_read_only_sql(sql, config)


def test_validate_rejects_suffix_outside_phase(config: AuditConfig) -> None:
    sql = """
SELECT event_name
FROM `bigquery-public-data.example.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201001' AND '20201231'
"""
    with pytest.raises(ValueError):
        validate_read_only_sql(sql, config)
