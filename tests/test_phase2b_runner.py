from datetime import date

import pytest

from scripts.run_phase2b import (
    CREATION_STEPS,
    MAPPING_VERSION,
    NEW_TABLES,
    REPLACED_TABLES,
    RESOLUTION_VERSION,
    ROOT,
    Phase2BConfig,
    render_mapping_struct,
    render_source_resolution,
    render_step,
    validate_query_sql,
)


@pytest.fixture
def config() -> Phase2BConfig:
    return Phase2BConfig(
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


def test_source_resolution_uses_exact_internal_registered_domain(
    config: Phase2BConfig,
) -> None:
    sql = render_source_resolution(config)
    validate_query_sql(sql, config)
    assert "event_source_reg_domain, '') != 'googlemerchandisestore.com'" in sql
    assert "page_referrer_reg_domain, '') != 'googlemerchandisestore.com'" in sql
    assert "first_user_source_reg_domain, '') != 'googlemerchandisestore.com'" in sql
    assert "%googlemerchandisestore.com%" not in sql


def test_source_priority_matches_approved_order(config: Phase2BConfig) -> None:
    sql = render_source_resolution(config)
    case_start = sql.index("CASE\n      WHEN event_tuple IS NOT NULL")
    event_position = sql.index("WHEN event_tuple IS NOT NULL", case_start)
    referrer_position = sql.index("WHEN external_referrer IS NOT NULL", case_start)
    fallback_position = sql.index("WHEN first_user_tuple IS NOT NULL", case_start)
    direct_position = sql.index("WHEN direct_evidence IS NOT NULL", case_start)
    assert event_position < referrer_position < fallback_position < direct_position


def test_medium_only_and_google_inference_fields_are_explicit(
    config: Phase2BConfig,
) -> None:
    sql = render_source_resolution(config)
    assert "'medium_only'" in sql
    assert "COALESCE(LOWER(clean_event_source), '') != '(direct)'" in sql
    assert "COALESCE(LOWER(clean_event_medium), '') != '(none)'" in sql
    assert "COALESCE(LOWER(clean_first_user_source), '') != '(direct)'" in sql
    assert "COALESCE(LOWER(clean_first_user_medium), '') != '(none)'" in sql
    assert "'google_referrer_to_organic_search'" in sql
    assert "source_resolution_tier = 'external_referrer'" in sql


def test_mapping_is_ordered_and_admin_is_unmapped() -> None:
    sql = render_mapping_struct("candidate")
    assert sql.index("is_internal_admin_traffic") < sql.index("'Direct'")
    channels = [
        "Direct",
        "Paid Social",
        "Paid Search",
        "Display",
        "Email",
        "Affiliates",
        "Organic Search",
        "Organic Social",
        "Referral",
        "Unknown",
        "Other",
    ]
    positions = [sql.index(f"'{channel}' AS channel") for channel in channels]
    assert positions == sorted(positions)
    assert "creatoracademy.youtube.com" in sql


def test_every_executable_sql_renders_as_select(config: Phase2BConfig) -> None:
    from scripts.run_phase2b import (
        REPLACEMENT_STEPS,
        SOURCE_AUDIT_RECOVERY_STEP,
        SOURCE_AUDIT_STEP,
    )

    for step in (
        SOURCE_AUDIT_STEP,
        SOURCE_AUDIT_RECOVERY_STEP,
        *REPLACEMENT_STEPS,
        *CREATION_STEPS,
    ):
        sql = render_step(step, config)
        validate_query_sql(sql, config)


def test_conversion_paths_enforce_all_boundaries() -> None:
    sql = (
        ROOT / "sql" / "intermediate" / "05_conversion_touchpoints.sql"
    ).read_text()
    assert "sessions.session_start_ts <= orders.order_ts" in sql
    assert "TIMESTAMP_SUB(orders.order_ts, INTERVAL 30 DAY)" in sql
    assert "sessions.session_start_ts > orders.previous_order_ts" in sql
    assert "sessions.is_marketing_eligible" in sql


def test_marketing_eligibility_is_null_safe() -> None:
    sql = (
        ROOT / "sql" / "intermediate" / "04_session_touchpoints.sql"
    ).read_text()
    assert "COALESCE(resolved_source_host, '') != 'analytics.google.com'" in sql


def test_phase2b_targets_exclude_attribution_outputs() -> None:
    all_targets = set(NEW_TABLES) | set(REPLACED_TABLES)
    forbidden_tokens = (
        "first_click",
        "last_click",
        "linear",
        "time_decay",
        "markov",
        "shapley",
        "attribution_results",
    )
    assert all(
        token not in table for table in all_targets for token in forbidden_tokens
    )


def test_versions_are_stable() -> None:
    assert RESOLUTION_VERSION == "phase2b_source_v1_20260806"
    assert MAPPING_VERSION == "phase2b_channel_v1_20260806"


@pytest.mark.parametrize(
    "sql",
    [
        "CREATE TABLE x AS SELECT 1",
        "DELETE FROM x WHERE TRUE",
        "SELECT * FROM `example-project.ga4_attribution.event_base`",
    ],
)
def test_validation_rejects_mutating_or_select_star_sql(
    sql: str, config: Phase2BConfig
) -> None:
    with pytest.raises(ValueError):
        validate_query_sql(sql, config)
