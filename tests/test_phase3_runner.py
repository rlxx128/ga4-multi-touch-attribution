from datetime import date

import pytest

from scripts.run_phase3 import (
    ATTRIBUTION_VERSION,
    BUILD_STEPS,
    EXPECTED_MAPPING_VERSION,
    EXPECTED_PATH_VERSION,
    PHASE3_TABLES,
    ROOT,
    Phase3Config,
    render_step,
    validate_query_sql,
)


@pytest.fixture
def config() -> Phase3Config:
    return Phase3Config(
        gcp_project_id="example-project",
        bq_dataset="ga4_attribution",
        bq_location="US",
        source_table="bigquery-public-data.example.events_*",
        start_date=date(2020, 11, 1),
        end_date=date(2021, 1, 31),
        maximum_bytes_billed=1_000_000_000,
    )


def test_exact_phase3_output_allowlist() -> None:
    assert PHASE3_TABLES == (
        "attribution_results",
        "model_comparison",
        "phase3_validation_summary",
    )


def test_every_phase3_query_renders_as_safe_select(config: Phase3Config) -> None:
    for step in BUILD_STEPS:
        sql = render_step(step, config)
        validate_query_sql(sql, config)
        assert "{{" not in sql
        assert "bigquery-public-data" not in sql


def test_rule_based_sql_contains_exact_models_and_canonical_grain(
    config: Phase3Config,
) -> None:
    sql = render_step(BUILD_STEPS[0], config)
    for model in (
        "First Click",
        "Last Click",
        "Last Non-direct Click",
        "Linear",
        "Time Decay",
    ):
        assert f"'{model}' AS model" in sql
    assert "GROUP BY\n  user_pseudo_id,\n  order_key," in sql
    assert "model,\n  channel" in sql


def test_first_last_and_linear_definitions_are_exact(config: Phase3Config) -> None:
    sql = render_step(BUILD_STEPS[0], config)
    assert "touchpoint_number = 1" in sql
    assert "touchpoint_number = path_length" in sql
    assert "SAFE_DIVIDE(1.0, path_length)" in sql


def test_last_non_direct_all_direct_fallback_is_explicit(config: Phase3Config) -> None:
    sql = render_step(BUILD_STEPS[0], config)
    assert "MAX(IF(channel != 'Direct', touchpoint_number, NULL))" in sql
    assert "COALESCE(last_non_direct_touchpoint_number, path_length)" in sql
    validation_sql = render_step(BUILD_STEPS[2], config)
    assert "HAVING COUNTIF(channel != 'Direct') = 0" in validation_sql
    assert "all_direct_last_non_direct_fallback_failures" in validation_sql


def test_time_decay_uses_only_approved_seven_day_half_life(
    config: Phase3Config,
) -> None:
    sql = render_step(BUILD_STEPS[0], config)
    assert "7 * 24 * 60 * 60" in sql
    assert "POW(" in sql
    assert "SUM(time_decay_raw_weight) OVER (PARTITION BY order_key)" in sql
    assert "time_decay_half_life_days" in sql


def test_versions_are_pinned_to_approved_inputs() -> None:
    assert EXPECTED_MAPPING_VERSION == "phase2b_channel_v2_20260806"
    assert EXPECTED_PATH_VERSION == "phase2b_closeout_v1_20260806"
    assert ATTRIBUTION_VERSION == "phase3_rule_attribution_v1_20260809"


def test_validation_covers_required_reconciliations(config: Phase3Config) -> None:
    sql = render_step(BUILD_STEPS[2], config)
    required_checks = (
        "phase2b_prerequisite_failures",
        "excluded_orders_in_attribution_results",
        "order_model_weight_failures",
        "order_model_conversion_failures",
        "order_model_revenue_failures",
        "model_conversion_total_failures",
        "model_revenue_total_failures",
        "model_formula_mismatches",
        "model_comparison_reconciliation_failures",
        "forbidden_later_phase_tables",
    )
    for check in required_checks:
        assert check in sql


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
    config: Phase3Config,
) -> None:
    with pytest.raises(ValueError):
        validate_query_sql(sql, config)


def test_phase2_sql_files_are_not_phase3_destinations() -> None:
    phase2_tokens = {
        "orders",
        "session_touchpoints",
        "conversion_touchpoints",
        "conversion_touchpoints_strict",
        "orders_without_touchpoints",
    }
    assert phase2_tokens.isdisjoint(PHASE3_TABLES)
    assert (ROOT / "sql" / "intermediate" / "05_conversion_touchpoints.sql").is_file()
