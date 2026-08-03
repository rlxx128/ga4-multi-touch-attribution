"""Unit tests for Phase 0 configuration and query safety."""

from __future__ import annotations

import pytest

from scripts.test_bigquery_connection import (
    CONNECTION_TEST_DATE,
    CONNECTION_TEST_MAXIMUM_BYTES_BILLED,
    build_connection_query,
    load_config,
    validate_read_only_query,
)


VALID_ENVIRONMENT = {
    "GCP_PROJECT_ID": "ga4-multi-touch-attribution",
    "BQ_DATASET": "ga4_attribution",
    "BQ_LOCATION": "US",
    "GA4_SOURCE_TABLE": (
        "bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*"
    ),
    "START_DATE": "2020-11-01",
    "END_DATE": "2021-01-31",
    "MAXIMUM_BYTES_BILLED": "1000000000",
}


def set_valid_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    for name, value in VALID_ENVIRONMENT.items():
        monkeypatch.setenv(name, value)


def test_load_config_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    set_valid_environment(monkeypatch)

    config = load_config()

    assert config.gcp_project_id == "ga4-multi-touch-attribution"
    assert config.bq_dataset == "ga4_attribution"
    assert config.bq_location == "US"
    assert config.start_date <= CONNECTION_TEST_DATE <= config.end_date
    assert config.maximum_bytes_billed == 1_000_000_000
    assert config.maximum_bytes_billed == CONNECTION_TEST_MAXIMUM_BYTES_BILLED


def test_load_config_reports_missing_values(monkeypatch: pytest.MonkeyPatch) -> None:
    set_valid_environment(monkeypatch)
    monkeypatch.delenv("BQ_DATASET")

    with pytest.raises(ValueError, match="BQ_DATASET"):
        load_config()


def test_connection_query_is_fixed_to_one_day() -> None:
    sql = build_connection_query(VALID_ENVIRONMENT["GA4_SOURCE_TABLE"])

    validate_read_only_query(sql)
    assert "_TABLE_SUFFIX = '20201101'" in sql
    assert "LIMIT 1" in sql


@pytest.mark.parametrize(
    "sql",
    [
        "CREATE TABLE example AS SELECT 1",
        "DELETE FROM example WHERE TRUE",
        "SELECT event_name FROM `project.dataset.events_*`",
    ],
)
def test_query_guard_rejects_unsafe_or_unbounded_sql(sql: str) -> None:
    with pytest.raises(ValueError):
        validate_read_only_query(sql)


def test_config_rejects_invalid_source_table(monkeypatch: pytest.MonkeyPatch) -> None:
    set_valid_environment(monkeypatch)
    monkeypatch.setenv("GA4_SOURCE_TABLE", "dataset.events_*")

    with pytest.raises(ValueError, match="GA4_SOURCE_TABLE"):
        load_config()


def test_config_rejects_a_different_billing_ceiling(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    set_valid_environment(monkeypatch)
    monkeypatch.setenv("MAXIMUM_BYTES_BILLED", "2000000000")

    with pytest.raises(ValueError, match="1000000000"):
        load_config()
