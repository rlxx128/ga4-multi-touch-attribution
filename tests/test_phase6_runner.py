from __future__ import annotations

from datetime import date
from pathlib import Path

import pytest

from scripts.run_phase4 import Phase4Config
from scripts.run_phase6 import (
    BASELINE_TABLES,
    BUILD_STEPS,
    PHASE6_TABLES,
    REPORTING_VERSION,
    VALIDATION_STEP,
    render_step,
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


def test_phase6_contract_is_pinned() -> None:
    assert REPORTING_VERSION == "phase6_business_reporting_v1_20260814"
    assert PHASE6_TABLES == (
        "channel_funnel_summary",
        "journey_summary",
        "attribution_business_summary",
        "phase6_validation_summary",
    )
    assert all("budget" not in table_name for table_name in PHASE6_TABLES)


@pytest.mark.parametrize("step", (*BUILD_STEPS, VALIDATION_STEP))
def test_phase6_sql_renders_as_safe_read_only_select(
    config: Phase4Config, step: object
) -> None:
    sql = render_step(step, config)  # type: ignore[arg-type]
    validate_query_sql(sql, config)
    assert "bigquery-public-data" not in sql
    assert "{{" not in sql


def test_funnel_uses_validated_sessions_and_incidence_terminology(
    config: Phase4Config,
) -> None:
    sql = render_step(BUILD_STEPS[0], config)
    assert "session_touchpoints" in sql
    assert "event_base" in sql
    assert "is_attribution_eligible" in sql
    assert "channel_level_funnel_stage_incidence_rates" in sql
    assert "view_item_session_rate" in sql


def test_journey_summary_uses_finalized_conversion_paths(
    config: Phase4Config,
) -> None:
    sql = render_step(BUILD_STEPS[1], config)
    assert "conversion_touchpoints" in sql
    assert "conversion_touchpoints_strict" not in sql
    for summary_type in (
        "OVERALL",
        "PATH_LENGTH",
        "CONVERTING_PATH",
        "FIRST_TOUCH_CHANNEL",
        "LAST_TOUCH_CHANNEL",
    ):
        assert summary_type in sql


def test_attribution_summary_reuses_phase4_and_phase5_outputs(
    config: Phase4Config,
) -> None:
    sql = render_step(BUILD_STEPS[2], config)
    assert "rule_markov_comparison" in sql
    assert "phase5_sensitivity_results" in sql
    assert "phase5_bootstrap_summary" in sql
    assert "attribution_results" not in sql


def test_phase6_protects_all_prior_phase_reporting_inputs() -> None:
    for table_name in (
        "session_touchpoints",
        "conversion_touchpoints",
        "attribution_results",
        "markov_attribution",
        "rule_markov_comparison",
        "phase5_sensitivity_results",
        "phase5_bootstrap_summary",
    ):
        assert table_name in BASELINE_TABLES


def test_phase6_required_files_exist_and_budget_assets_do_not() -> None:
    required = (
        ROOT / "scripts" / "run_phase6.py",
        ROOT / "src" / "attribution" / "reporting.py",
        ROOT / "sql" / "marts" / "05_channel_funnel_summary.sql",
        ROOT / "sql" / "marts" / "06_journey_summary.sql",
        ROOT / "sql" / "marts" / "07_attribution_business_summary.sql",
        ROOT / "sql" / "validation" / "06_phase6_validation.sql",
    )
    assert all(path.exists() for path in required)
    assert not (ROOT / "sql" / "marts" / "08_budget_scenario_summary.sql").exists()


def test_agents_current_instruction_names_phase6_without_phase0_command() -> None:
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
    current = agents.split("## 22. Current instruction", maxsplit=1)[1]
    assert "current approved phase is" in current
    assert "Phase 6" in current
    assert "Business Reporting" in current
    assert "Begin with Phase 0 only" not in current
