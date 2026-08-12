from __future__ import annotations

import pytest

from src.attribution.markov import build_transition_model
from src.attribution.sensitivity import (
    ClusterJourney,
    compress_consecutive_channels,
    deterministic_ranks,
    omit_direct_from_mixed_path,
    run_user_cluster_bootstrap,
    spearman_rank_correlation,
    tied_channels,
)


def test_compression_removes_only_consecutive_repeats() -> None:
    path = (
        "Start",
        "Email",
        "Email",
        "Paid Search",
        "Email",
        "Conversion",
    )
    assert compress_consecutive_channels(path) == (
        "Start",
        "Email",
        "Paid Search",
        "Email",
        "Conversion",
    )


def test_direct_omission_retains_direct_only_fallback() -> None:
    assert omit_direct_from_mixed_path(
        ("Start", "Direct", "Direct", "Conversion")
    ) == ("Start", "Direct", "Direct", "Conversion")


def test_direct_omission_removes_all_direct_from_mixed_path_without_compressing() -> None:
    assert omit_direct_from_mixed_path(
        ("Start", "Email", "Direct", "Email", "Null")
    ) == ("Start", "Email", "Email", "Null")


def test_deterministic_ranks_use_channel_name_for_ties() -> None:
    values = {"Unknown": 0.2, "Email": 0.2, "Direct": 0.6}
    assert deterministic_ranks(values) == {"Direct": 1, "Email": 2, "Unknown": 3}
    assert tied_channels(values) == {"Email", "Unknown"}


def test_spearman_requires_same_channel_set() -> None:
    with pytest.raises(ValueError, match="same channels"):
        spearman_rank_correlation({"Email": 1}, {"Direct": 1})


def test_user_cluster_bootstrap_is_deterministic_and_preserves_user_draw_count() -> None:
    journeys = [
        ClusterJourney("u1", ("Start", "Email", "Conversion")),
        ClusterJourney("u1", ("Start", "Direct", "Null")),
        ClusterJourney("u2", ("Start", "Email", "Null")),
        ClusterJourney("u3", ("Start", "Direct", "Conversion")),
    ]
    model = build_transition_model([journey.path for journey in journeys])
    baseline_effects = {"Direct": 0.5, "Email": 0.5}
    baseline_shares = {"Direct": 0.5, "Email": 0.5}
    first = run_user_cluster_bootstrap(
        journeys,
        model,
        baseline_effects,
        baseline_shares,
        replicate_count=20,
        seed=20260812,
    )
    second = run_user_cluster_bootstrap(
        journeys,
        model,
        baseline_effects,
        baseline_shares,
        replicate_count=20,
        seed=20260812,
    )
    assert first == second
    assert first.attempted_replicates == 20
    assert first.successful_replicates + first.failed_replicates == 20
    for row in first.replicate_rows:
        assert row["sampled_user_draws"] == 3


def test_bootstrap_absent_channel_is_zero_not_a_failure() -> None:
    journeys = [
        ClusterJourney("u1", ("Start", "Other", "Null")),
        ClusterJourney("u2", ("Start", "Email", "Conversion")),
        ClusterJourney("u3", ("Start", "Email", "Null")),
        ClusterJourney("u4", ("Start", "Email", "Conversion")),
    ]
    model = build_transition_model([journey.path for journey in journeys])
    result = run_user_cluster_bootstrap(
        journeys,
        model,
        {"Email": 0.9, "Other": 0.1},
        {"Email": 0.9, "Other": 0.1},
        replicate_count=25,
        seed=7,
    )
    successful_other = [
        row
        for row in result.replicate_rows
        if row["replicate_status"] == "SUCCESS" and row["channel"] == "Other"
    ]
    assert successful_other
    assert any(row["removal_effect"] == 0.0 for row in successful_other)
