from datetime import date
from pathlib import Path

import pytest

from scripts.run_phase4 import (
    COMPARISON_STEP,
    JOURNEY_STEP,
    MARKOV_VERSION,
    PHASE4_TABLES,
    ROOT,
    SQL_STEPS,
    VALIDATION_STEP,
    Phase4Config,
    render_step,
    validate_query_sql,
)


@pytest.fixture
def config() -> Phase4Config:
    return Phase4Config(
        gcp_project_id="example-project",
        bq_dataset="ga4_attribution",
        bq_location="US",
        source_table="bigquery-public-data.example.events_*",
        start_date=date(2020, 11, 1),
        end_date=date(2021, 1, 31),
        maximum_bytes_billed=1_000_000_000,
    )


def test_exact_phase4_output_allowlist() -> None:
    assert PHASE4_TABLES == (
        "markov_journeys",
        "markov_transition_matrix",
        "markov_removal_effects",
        "markov_attribution",
        "rule_markov_comparison",
        "phase4_validation_summary",
    )


def test_every_phase4_sql_file_renders_as_safe_select(config: Phase4Config) -> None:
    for step in SQL_STEPS:
        sql = render_step(step, config)
        validate_query_sql(sql, config)
        assert "{{" not in sql
        assert "bigquery-public-data" not in sql


def test_journey_sql_uses_approved_30_day_boundaries(config: Phase4Config) -> None:
    sql = render_step(JOURNEY_STEP, config)
    assert "session_start_ts >= TIMESTAMP_ADD(" in sql
    assert "INTERVAL 30 DAY" in sql
    assert "next_purchase_ts > inactivity_expiry_ts" in sql
    assert "inactivity_expiry_ts < TIMESTAMP('2021-02-01 00:00:00+00')" in sql
    assert "journey_start_ts < TIMESTAMP('2020-12-01 00:00:00+00')" in sql
    assert "FROM `example-project.ga4_attribution.conversion_touchpoints`" in sql
    assert "phase4_markov_30d_v1_20260811" in sql


def test_journey_sql_retains_channels_and_right_censoring(config: Phase4Config) -> None:
    sql = render_step(JOURNEY_STEP, config)
    assert "ARRAY_AGG(channel ORDER BY session_start_ts, session_key)" in sql
    assert "ARRAY_AGG(channel ORDER BY touchpoint_number)" in sql
    assert "'Right Censored'" in sql
    assert "is_markov_included" in sql
    assert "is_left_boundary_truncated" in sql


def test_comparison_is_long_form_and_preserves_phase3(config: Phase4Config) -> None:
    sql = render_step(COMPARISON_STEP, config)
    for model in (
        "First Click",
        "Last Click",
        "Last Non-direct Click",
        "Linear",
        "Time Decay",
        "Markov",
    ):
        assert f"'{model}'" in sql
    assert "conversion_difference_vs_last_click" in sql
    assert "revenue_relative_difference_vs_last_click" in sql
    assert "UPDATE" not in sql.upper()


def test_validation_covers_population_overlap_and_regressions(
    config: Phase4Config,
) -> None:
    sql = render_step(VALIDATION_STEP, config)
    required = (
        "conversion_journeys",
        "null_journeys",
        "right_censored_journeys",
        "left_boundary_null_journeys",
        "conversion_null_overlap_sessions",
        "invalid_transition_row_sums",
        "absorbing_probability_failures",
        "materially_negative_removal_effects",
        "attribution_share_failures",
        "phase3_model_reconciliation_failures",
    )
    for check in required:
        assert check in sql
    assert "journey_status = 'Right Censored'" in sql
    assert "is_markov_included OR outcome_state IS NOT NULL" in sql


def test_phase4_does_not_target_phase2_or_phase3_tables() -> None:
    protected = {
        "orders",
        "session_touchpoints",
        "conversion_touchpoints",
        "conversion_touchpoints_strict",
        "orders_without_touchpoints",
        "attribution_results",
        "model_comparison",
        "phase2b_validation_summary",
        "phase3_validation_summary",
    }
    assert protected.isdisjoint(PHASE4_TABLES)


@pytest.mark.parametrize(
    "sql",
    [
        "CREATE TABLE x AS SELECT 1",
        "DELETE FROM x WHERE TRUE",
        "SELECT * FROM `example-project.ga4_attribution.orders`",
        "SELECT t.* FROM `example-project.ga4_attribution.orders` AS t",
        "SELECT 1 FROM `bigquery-public-data.example.events_*`",
    ],
)
def test_query_validation_rejects_unsafe_sql(
    sql: str,
    config: Phase4Config,
) -> None:
    with pytest.raises(ValueError):
        validate_query_sql(sql, config)


def test_phase4_required_files_exist() -> None:
    required = (
        ROOT / "sql" / "intermediate" / "07_markov_journeys.sql",
        ROOT / "src" / "attribution" / "markov.py",
        ROOT / "sql" / "marts" / "03_rule_markov_comparison.sql",
        ROOT / "sql" / "validation" / "04_phase4_validation.sql",
        ROOT / "scripts" / "run_phase4.py",
        ROOT / "tests" / "test_markov.py",
        ROOT / "tests" / "test_phase4_runner.py",
        ROOT / "reports" / "phase4_markov_attribution.md",
    )
    assert all(Path(path).is_file() for path in required)


def test_markov_version_is_pinned() -> None:
    assert MARKOV_VERSION == "phase4_markov_30d_anderl_v2_20260811"
