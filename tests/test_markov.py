import math
from collections.abc import Iterator

import numpy as np
import pytest

from src.attribution.markov import (
    CONVERSION_STATE,
    FLOATING_POINT_TOLERANCE,
    NULL_STATE,
    START_STATE,
    build_transition_model,
    build_transition_model_from_counts,
    build_transition_model_streaming,
    calculate_removal_effects,
    calculate_streaming_removal_effects,
    channel_states,
    conversion_probability,
    normalize_removal_effects,
    observed_transition_counts,
    remove_channel,
)


def test_single_channel_conversion_path() -> None:
    paths = [(START_STATE, "Email", CONVERSION_STATE)]
    model = build_transition_model(paths)
    assert conversion_probability(model) == pytest.approx(1.0)
    assert observed_transition_counts(paths) == {
        (START_STATE, "Email"): 1,
        ("Email", CONVERSION_STATE): 1,
    }


def test_single_channel_null_path() -> None:
    model = build_transition_model([(START_STATE, "Direct", NULL_STATE)])
    assert conversion_probability(model) == pytest.approx(0.0)


def test_multi_channel_conversion_and_null_paths() -> None:
    paths = [
        (START_STATE, "Email", "Paid Search", CONVERSION_STATE),
        (START_STATE, "Referral", "Unknown", NULL_STATE),
    ]
    assert conversion_probability(build_transition_model(paths)) == pytest.approx(0.5)


def test_repeated_channel_path_preserves_self_transition() -> None:
    paths = [(START_STATE, "Paid Search", "Paid Search", CONVERSION_STATE)]
    counts = observed_transition_counts(paths)
    assert counts[("Paid Search", "Paid Search")] == 1
    model = build_transition_model(paths)
    index = model.state_index("Paid Search")
    assert model.transition_counts[index, index] == 1


def test_direct_and_unknown_remain_distinct_states() -> None:
    paths = [
        (START_STATE, "Direct", CONVERSION_STATE),
        (START_STATE, "Unknown", NULL_STATE),
    ]
    assert channel_states(paths) == ("Direct", "Unknown")


def test_absorbing_states_are_explicit_self_loops() -> None:
    model = build_transition_model(
        [
            (START_STATE, "Email", CONVERSION_STATE),
            (START_STATE, "Direct", NULL_STATE),
        ]
    )
    conversion_index = model.state_index(CONVERSION_STATE)
    null_index = model.state_index(NULL_STATE)
    assert model.transition_probabilities[conversion_index, conversion_index] == 1.0
    assert model.transition_probabilities[null_index, null_index] == 1.0
    assert np.allclose(model.transition_probabilities.sum(axis=1), 1.0)


def test_single_channel_conversion_removal_redirects_start_to_null() -> None:
    model = build_transition_model([(START_STATE, "Email", CONVERSION_STATE)])
    removed = remove_channel(model, "Email")
    assert "Email" not in removed.states
    assert removed.transition_probabilities[
        removed.state_index(START_STATE), removed.state_index(NULL_STATE)
    ] == pytest.approx(1.0)
    assert conversion_probability(removed) == pytest.approx(0.0)


def test_single_channel_null_removal_keeps_null_outcome() -> None:
    model = build_transition_model([(START_STATE, "Email", NULL_STATE)])
    removed = remove_channel(model, "Email")
    assert conversion_probability(removed) == pytest.approx(0.0)
    assert removed.transition_probabilities[
        removed.state_index(START_STATE), removed.state_index(NULL_STATE)
    ] == pytest.approx(1.0)


def test_intermediate_channel_removal_redirects_incoming_mass_to_null() -> None:
    paths = [
        (START_STATE, "Organic", "Email", CONVERSION_STATE),
        (START_STATE, "Organic", NULL_STATE),
    ]
    removed = remove_channel(build_transition_model(paths), "Email")
    organic_index = removed.state_index("Organic")
    assert removed.transition_probabilities[
        organic_index, removed.state_index(NULL_STATE)
    ] == pytest.approx(1.0)
    assert removed.transition_probabilities[
        organic_index, removed.state_index(CONVERSION_STATE)
    ] == pytest.approx(0.0)
    assert conversion_probability(removed) == pytest.approx(0.0)


def test_mixed_outcomes_have_deterministic_removal_probability() -> None:
    paths = [
        (START_STATE, "Email", CONVERSION_STATE),
        (START_STATE, "Email", CONVERSION_STATE),
        (START_STATE, "Direct", NULL_STATE),
    ]
    baseline, results = calculate_removal_effects(paths)
    by_channel = {result.channel: result for result in results}
    assert baseline == pytest.approx(2 / 3)
    assert by_channel["Email"].conversion_probability_without_channel == pytest.approx(
        0.0
    )
    assert by_channel["Email"].removal_effect == pytest.approx(1.0)
    assert by_channel["Direct"].conversion_probability_without_channel == pytest.approx(
        baseline
    )
    assert abs(by_channel["Direct"].removal_effect) <= FLOATING_POINT_TOLERANCE


def test_start_transition_to_removed_channel_is_redirected_to_null() -> None:
    paths = [
        (START_STATE, "Email", CONVERSION_STATE),
        (START_STATE, "Direct", CONVERSION_STATE),
    ]
    baseline = build_transition_model(paths)
    removed = remove_channel(baseline, "Email")
    start_index = removed.state_index(START_STATE)
    assert removed.transition_probabilities[
        start_index, removed.state_index(NULL_STATE)
    ] == pytest.approx(0.5)
    assert removed.transition_probabilities[
        start_index, removed.state_index("Direct")
    ] == pytest.approx(0.5)


def test_self_transition_channel_is_fully_absent_after_removal() -> None:
    paths = [
        (START_STATE, "Email", "Email", CONVERSION_STATE),
        (START_STATE, "Direct", NULL_STATE),
    ]
    removed = remove_channel(build_transition_model(paths), "Email")
    assert "Email" not in removed.states
    assert removed.transition_probabilities.shape == (4, 4)


@pytest.mark.parametrize("channel", ["Email", "Direct", "Unknown"])
def test_removed_matrix_remains_valid(channel: str) -> None:
    paths = [
        (START_STATE, "Email", "Email", CONVERSION_STATE),
        (START_STATE, "Direct", NULL_STATE),
        (START_STATE, "Unknown", "Email", NULL_STATE),
    ]
    removed = remove_channel(build_transition_model(paths), channel)
    assert channel not in removed.states
    assert np.allclose(removed.transition_probabilities.sum(axis=1), 1.0)
    assert np.all(np.isfinite(removed.transition_probabilities))
    for absorber in (CONVERSION_STATE, NULL_STATE):
        index = removed.state_index(absorber)
        expected = np.zeros(len(removed.states))
        expected[index] = 1.0
        assert np.allclose(removed.transition_probabilities[index], expected)
    assert all(
        can_reach
        for state, can_reach in zip(
            removed.states, removed.can_reach_absorbing, strict=True
        )
        if state not in (CONVERSION_STATE, NULL_STATE)
    )
    assert math.isfinite(conversion_probability(removed))


def test_streaming_model_matches_in_memory_model() -> None:
    paths = (
        (START_STATE, "Email", "Paid Search", CONVERSION_STATE),
        (START_STATE, "Direct", NULL_STATE),
    )
    in_memory = build_transition_model(paths)
    streaming = build_transition_model_streaming(iter(paths))
    assert streaming.states == in_memory.states
    assert np.array_equal(streaming.transition_counts, in_memory.transition_counts)
    assert np.allclose(
        streaming.transition_probabilities,
        in_memory.transition_probabilities,
    )


def test_count_matrix_model_matches_path_model() -> None:
    paths = [
        (START_STATE, "Email", CONVERSION_STATE),
        (START_STATE, "Direct", NULL_STATE),
        (START_STATE, "Email", "Direct", CONVERSION_STATE),
    ]
    expected = build_transition_model(paths)
    observed = build_transition_model_from_counts(
        expected.states,
        expected.transition_counts,
    )
    assert np.array_equal(observed.transition_counts, expected.transition_counts)
    assert np.allclose(
        observed.transition_probabilities,
        expected.transition_probabilities,
    )
    assert conversion_probability(observed) == pytest.approx(
        conversion_probability(expected)
    )


def test_count_matrix_model_rejects_zero_outgoing_transient_state() -> None:
    states = (START_STATE, "Email", CONVERSION_STATE, NULL_STATE)
    counts = np.zeros((4, 4), dtype=np.int64)
    counts[0, 1] = 1
    with pytest.raises(ValueError, match="Email"):
        build_transition_model_from_counts(states, counts)


def test_streaming_removal_effects_use_one_baseline_matrix() -> None:
    paths = (
        (START_STATE, "Email", CONVERSION_STATE),
        (START_STATE, "Unknown", NULL_STATE),
    )
    calls = 0

    def path_factory() -> Iterator[tuple[str, ...]]:
        nonlocal calls
        calls += 1
        return iter(paths)

    model, baseline, results = calculate_streaming_removal_effects(path_factory)
    by_channel = {result.channel: result for result in results}
    assert model.states == (START_STATE, "Email", "Unknown", CONVERSION_STATE, NULL_STATE)
    assert baseline == pytest.approx(0.5)
    assert calls == 1
    assert by_channel["Email"].conversion_probability_without_channel == pytest.approx(
        0.0
    )
    assert by_channel["Email"].removal_effect == pytest.approx(1.0)
    assert abs(by_channel["Unknown"].removal_effect) <= FLOATING_POINT_TOLERANCE


def test_zero_total_removal_effect_fails_normalization() -> None:
    with pytest.raises(ValueError, match="Total removal effect is zero"):
        normalize_removal_effects({"Direct": 0.0, "Email": 0.0})


def test_materially_negative_removal_effect_fails() -> None:
    with pytest.raises(ValueError, match="Materially negative"):
        normalize_removal_effects({"Direct": -1e-4, "Email": 0.2})


def test_tiny_negative_removal_effect_is_treated_as_noise() -> None:
    shares = normalize_removal_effects({"Direct": -5e-13, "Email": 0.2})
    assert shares == {"Direct": 0.0, "Email": 1.0}


def test_non_finite_removal_effect_fails() -> None:
    with pytest.raises(ValueError, match="not finite"):
        normalize_removal_effects({"Direct": math.inf, "Email": 0.2})


@pytest.mark.parametrize(
    "path",
    [
        ("Email", CONVERSION_STATE),
        (START_STATE, "Email", "NotAbsorbing"),
        (START_STATE, CONVERSION_STATE, "Email", NULL_STATE),
    ],
)
def test_invalid_paths_fail(path: tuple[str, ...]) -> None:
    with pytest.raises(ValueError):
        build_transition_model([path])
