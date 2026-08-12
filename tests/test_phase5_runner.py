from __future__ import annotations

from datetime import date
from pathlib import Path

import pytest

from scripts.run_phase4 import Phase4Config
from scripts.run_phase5 import (
    BOOTSTRAP_REPLICATES,
    BOOTSTRAP_SEED,
    PHASE5_TABLES,
    SENSITIVITY_VERSION,
    LOOKBACK_SQL,
    NULL14_SQL,
    BASELINE_PATH_SQL,
    VALIDATION_SQL,
    render_asset,
    validate_query_sql,
)


ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def config() -> Phase4Config:
    return Phase4Config(
        gcp_project_id="portfolio-project",
        bq_dataset="ga4_attribution",
        bq_location="US",
        source_table="bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*",
        start_date=date(2020, 11, 1),
        end_date=date(2021, 1, 31),
        maximum_bytes_billed=1_000_000_000,
    )


def test_phase5_contract_is_pinned() -> None:
    assert BOOTSTRAP_REPLICATES == 500
    assert BOOTSTRAP_SEED == 20260812
    assert SENSITIVITY_VERSION == "phase5_sensitivity_stability_v1_20260812"
    assert PHASE5_TABLES == (
        "phase5_sensitivity_results",
        "phase5_rank_stability",
        "phase5_bootstrap_replicates",
        "phase5_bootstrap_summary",
        "phase5_scenario_manifest",
        "phase5_validation_summary",
    )


@pytest.mark.parametrize(
    "asset",
    (LOOKBACK_SQL, NULL14_SQL, BASELINE_PATH_SQL, VALIDATION_SQL),
)
def test_phase5_sql_renders_as_safe_read_only_select(
    config: Phase4Config, asset: object
) -> None:
    sql = render_asset(asset, config)  # type: ignore[arg-type]
    validate_query_sql(sql, config)
    assert "bigquery-public-data" not in sql
    assert "{{" not in sql


def test_null_sensitivity_uses_approved_boundary_and_overlap_exclusion(
    config: Phase4Config,
) -> None:
    sql = render_asset(NULL14_SQL, config)
    assert "INTERVAL 14 DAY" in sql
    assert "inactivity_expiry_ts < TIMESTAMP('2021-02-01 00:00:00+00')" in sql
    assert "is_overlap_excluded" in sql
    assert "conversion_touchpoints" in sql


def test_lookback_sql_has_population_and_common_cohort_views(
    config: Phase4Config,
) -> None:
    sql = render_asset(LOOKBACK_SQL, config)
    assert "population_impact" in sql
    assert "common_cohort" in sql
    assert "[7" not in sql  # scenarios are explicit, not a hidden array default
    for days in (7, 14, 30):
        assert f"{days} AS lookback_days" in sql or f"'{days}'" in sql or f", {days}" in sql


def test_phase5_does_not_modify_prior_phase_files() -> None:
    runner = (ROOT / "scripts" / "run_phase5.py").read_text(encoding="utf-8")
    for baseline in (
        "orders",
        "conversion_touchpoints",
        "attribution_results",
        "markov_journeys",
        "markov_transition_matrix",
        "markov_attribution",
    ):
        assert f'"{baseline}"' in runner
    assert "WRITE_EMPTY" not in runner  # centralized create-only loader/query helper
    assert "run_phase6" not in runner.lower()


def test_phase5_required_files_exist() -> None:
    required = (
        ROOT / "src" / "attribution" / "sensitivity.py",
        ROOT / "scripts" / "run_phase5.py",
        ROOT / "sql" / "intermediate" / "08_phase5_conversion_lookback_scenarios.sql",
        ROOT / "sql" / "intermediate" / "09_phase5_null_14d_scenario.sql",
        ROOT / "sql" / "intermediate" / "10_phase5_scenario_paths.sql",
        ROOT / "sql" / "marts" / "04_phase5_sensitivity_results.sql",
        ROOT / "sql" / "validation" / "05_phase5_validation.sql",
        ROOT / "tests" / "test_sensitivity.py",
    )
    assert all(path.exists() for path in required)
