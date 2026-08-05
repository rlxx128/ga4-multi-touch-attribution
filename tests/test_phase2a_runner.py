from datetime import date

import pytest

from scripts.run_phase2a import (
    BUILD_STEPS,
    ROOT,
    TARGET_TABLES,
    Phase2AConfig,
    read_cost_log,
    render_sql,
    validate_query_sql,
)


@pytest.fixture
def config() -> Phase2AConfig:
    return Phase2AConfig(
        gcp_project_id="example-project",
        bq_dataset="ga4_attribution",
        bq_location="US",
        source_table="bigquery-public-data.example.events_*",
        start_date=date(2020, 11, 1),
        end_date=date(2021, 1, 31),
        start_suffix="20201101",
        end_suffix="20210131",
        maximum_bytes_billed=1_000_000_000,
    )


def test_event_base_is_bounded_and_renders(config: Phase2AConfig) -> None:
    template = (ROOT / "sql" / "staging" / "01_event_base.sql").read_text()
    sql = render_sql(
        template,
        config,
        {
            "{{CHUNK_START_SUFFIX}}": "20201201",
            "{{CHUNK_END_SUFFIX}}": "20201231",
        },
    )
    validate_query_sql(sql, config)
    assert "_TABLE_SUFFIX BETWEEN '20201201' AND '20201231'" in sql


@pytest.mark.parametrize(
    "sql",
    [
        "SELECT event_name FROM `bigquery-public-data.example.events_*`",
        (
            "SELECT * FROM `bigquery-public-data.example.events_*` "
            "WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20201130'"
        ),
        "CREATE TABLE x AS SELECT 1",
        "DELETE FROM x WHERE TRUE",
    ],
)
def test_validation_rejects_unsafe_sql(sql: str, config: Phase2AConfig) -> None:
    with pytest.raises(ValueError):
        validate_query_sql(sql, config)


def test_all_phase2a_sql_is_select_only(config: Phase2AConfig) -> None:
    sql_files = [
        ROOT / "sql" / "intermediate" / "01_orders.sql",
        ROOT / "sql" / "audit" / "09_internal_referrer_domain_audit.sql",
        ROOT / "sql" / "intermediate" / "02_session_source_candidates.sql",
        ROOT / "sql" / "audit" / "10_channel_source_coverage.sql",
        ROOT / "sql" / "audit" / "11_source_medium_campaign_frequency.sql",
        ROOT / "sql" / "audit" / "12_channel_mapping_proposal.sql",
        ROOT / "sql" / "validation" / "01_phase2a_validation.sql",
    ]
    for path in sql_files:
        validate_query_sql(render_sql(path.read_text(), config), config)


def test_orders_uses_approved_transaction_filter() -> None:
    sql = (ROOT / "sql" / "intermediate" / "01_orders.sql").read_text()
    assert "LOWER(TRIM(transaction_id)) != '(not set)'" in sql
    assert "MIN(event_ts) AS order_ts" in sql
    assert "MAX(purchase_revenue_in_usd) AS order_revenue_usd" in sql


def test_source_candidates_do_not_assign_channel() -> None:
    sql = (ROOT / "sql" / "intermediate" / "02_session_source_candidates.sql").read_text()
    assert "source_resolution_tier" in sql
    assert "assigned_channel" not in sql
    assert sql.index("event_tuple IS NOT NULL") < sql.index("external_referrer IS NOT NULL")
    assert sql.index("external_referrer IS NOT NULL") < sql.index("first_user_tuple IS NOT NULL")


def test_mapping_is_proposal_only() -> None:
    sql = (ROOT / "sql" / "audit" / "12_channel_mapping_proposal.sql").read_text()
    assert "PROPOSED_NOT_APPROVED" in sql
    assert "First Click" not in sql
    assert "Markov" not in sql


def test_target_set_contains_only_phase2a_tables() -> None:
    assert set(TARGET_TABLES) == {
        "event_base",
        "orders",
        "internal_referrer_domain_audit",
        "session_source_candidates",
        "channel_source_coverage_audit",
        "source_medium_campaign_frequency",
        "channel_mapping_proposal",
        "phase2a_validation_summary",
    }
    assert all("attribution" not in table for table in TARGET_TABLES)


def test_historical_tables_do_not_inherit_partition_expiration() -> None:
    assert all(step.partition_field is None for step in BUILD_STEPS)


def test_missing_cost_log_starts_clean(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    monkeypatch.setattr("scripts.run_phase2a.COST_LOG_PATH", tmp_path / "missing.csv")
    assert read_cost_log() == []
