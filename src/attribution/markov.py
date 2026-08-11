"""First-order Markov attribution primitives for Phase 4.

Paths passed to this module must already include ``Start`` and exactly one
terminal absorbing state, either ``Conversion`` or ``Null``. Channel removal
uses the owner-approved graph-state rule: remove the channel's row and column,
then redirect every remaining state's incoming probability for that channel to
``Null``.
"""

from __future__ import annotations

from collections import Counter, deque
from dataclasses import dataclass
from math import isfinite
from typing import Callable, Iterable, Mapping, Sequence

import numpy as np

START_STATE = "Start"
CONVERSION_STATE = "Conversion"
NULL_STATE = "Null"
ABSORBING_STATES = (CONVERSION_STATE, NULL_STATE)
RESERVED_STATES = frozenset((START_STATE, *ABSORBING_STATES))
FLOATING_POINT_TOLERANCE = 1e-12


@dataclass(frozen=True)
class MarkovModel:
    """Dense transition representation for one first-order Markov chain."""

    states: tuple[str, ...]
    transition_counts: np.ndarray
    transition_probabilities: np.ndarray
    can_reach_absorbing: tuple[bool, ...]

    def state_index(self, state: str) -> int:
        try:
            return self.states.index(state)
        except ValueError as exc:
            raise ValueError(f"Unknown Markov state: {state}") from exc


@dataclass(frozen=True)
class RemovalResult:
    """Conversion probability and removal effect for one channel."""

    channel: str
    conversion_probability_without_channel: float
    raw_removal_effect: float
    removal_effect: float
    floating_point_adjusted: bool
    materially_negative: bool


def _normalize_paths(paths: Iterable[Sequence[str]]) -> tuple[tuple[str, ...], ...]:
    if isinstance(paths, tuple) and all(isinstance(path, tuple) for path in paths):
        normalized = paths
    else:
        normalized = tuple(tuple(path) for path in paths)
    if not normalized:
        raise ValueError("At least one Markov path is required")
    for path in normalized:
        if len(path) < 2:
            raise ValueError("Every path must contain Start and an outcome")
        if path[0] != START_STATE:
            raise ValueError("Every path must begin with Start")
        if path[-1] not in ABSORBING_STATES:
            raise ValueError("Every path must end in Conversion or Null")
        if any(state in ABSORBING_STATES for state in path[1:-1]):
            raise ValueError("An absorbing state may appear only at the end of a path")
        if any(not state for state in path):
            raise ValueError("Markov states must be non-empty strings")
    return normalized


def channel_states(paths: Iterable[Sequence[str]]) -> tuple[str, ...]:
    """Return sorted observed channel states, excluding reserved states."""

    normalized = _normalize_paths(paths)
    return tuple(
        sorted({state for path in normalized for state in path if state not in RESERVED_STATES})
    )


def _ordered_states(paths: tuple[tuple[str, ...], ...]) -> tuple[str, ...]:
    channels = sorted(
        {state for path in paths for state in path if state not in RESERVED_STATES}
    )
    return (START_STATE, *channels, CONVERSION_STATE, NULL_STATE)


def _reachability(probabilities: np.ndarray, states: tuple[str, ...]) -> tuple[bool, ...]:
    reverse_edges: dict[int, list[int]] = {index: [] for index in range(len(states))}
    for source in range(len(states)):
        for target in range(len(states)):
            if probabilities[source, target] > 0:
                reverse_edges[target].append(source)

    reachable: set[int] = {
        states.index(CONVERSION_STATE),
        states.index(NULL_STATE),
    }
    queue: deque[int] = deque(reachable)
    while queue:
        target = queue.popleft()
        for source in reverse_edges[target]:
            if source not in reachable:
                reachable.add(source)
                queue.append(source)
    return tuple(index in reachable for index in range(len(states)))


def build_transition_model(paths: Iterable[Sequence[str]]) -> MarkovModel:
    """Count transitions and build a validated dense transition matrix."""

    normalized = _normalize_paths(paths)
    states = _ordered_states(normalized)
    state_to_index = {state: index for index, state in enumerate(states)}
    counts = np.zeros((len(states), len(states)), dtype=np.int64)

    for path in normalized:
        for source, target in zip(path, path[1:]):
            counts[state_to_index[source], state_to_index[target]] += 1

    probabilities = np.zeros_like(counts, dtype=np.float64)
    for state in states:
        index = state_to_index[state]
        if state in ABSORBING_STATES:
            probabilities[index, index] = 1.0
            continue
        outgoing = int(counts[index].sum())
        if outgoing <= 0:
            raise ValueError(f"Transient state has no outgoing transitions: {state}")
        probabilities[index] = counts[index] / outgoing

    if not np.allclose(probabilities.sum(axis=1), 1.0, atol=FLOATING_POINT_TOLERANCE):
        raise ValueError("Transition-matrix rows do not sum to one")

    reachable = _reachability(probabilities, states)
    unreachable = [
        state
        for state, can_reach in zip(states, reachable, strict=True)
        if state not in ABSORBING_STATES and not can_reach
    ]
    if unreachable:
        raise ValueError(
            "Transient states cannot reach an absorbing state: " + ", ".join(unreachable)
        )

    return MarkovModel(states, counts, probabilities, reachable)


def build_transition_model_streaming(
    paths: Iterable[Sequence[str]],
) -> MarkovModel:
    """Build a model in one pass without retaining the full path population."""

    edge_counts: Counter[tuple[str, str]] = Counter()
    observed_states: set[str] = set(RESERVED_STATES)
    path_count = 0
    for source_path in paths:
        path = tuple(source_path)
        if len(path) < 2 or path[0] != START_STATE or path[-1] not in ABSORBING_STATES:
            raise ValueError("Every path must begin at Start and end at an absorber")
        if any(state in ABSORBING_STATES for state in path[1:-1]):
            raise ValueError("An absorbing state may appear only at the end of a path")
        observed_states.update(path)
        edge_counts.update(zip(path, path[1:]))
        path_count += 1
    if path_count == 0:
        raise ValueError("At least one Markov path is required")

    channels = sorted(observed_states.difference(RESERVED_STATES))
    states = (START_STATE, *channels, CONVERSION_STATE, NULL_STATE)
    state_to_index = {state: index for index, state in enumerate(states)}
    counts = np.zeros((len(states), len(states)), dtype=np.int64)
    for (source, target), count in edge_counts.items():
        counts[state_to_index[source], state_to_index[target]] = count

    probabilities = np.zeros_like(counts, dtype=np.float64)
    for state in states:
        index = state_to_index[state]
        if state in ABSORBING_STATES:
            probabilities[index, index] = 1.0
            continue
        outgoing = int(counts[index].sum())
        if outgoing <= 0:
            raise ValueError(f"Transient state has no outgoing transitions: {state}")
        probabilities[index] = counts[index] / outgoing
    if not np.allclose(probabilities.sum(axis=1), 1.0, atol=FLOATING_POINT_TOLERANCE):
        raise ValueError("Transition-matrix rows do not sum to one")
    reachable = _reachability(probabilities, states)
    unreachable = [
        state
        for state, can_reach in zip(states, reachable, strict=True)
        if state not in ABSORBING_STATES and not can_reach
    ]
    if unreachable:
        raise ValueError(
            "Transient states cannot reach an absorbing state: " + ", ".join(unreachable)
        )
    return MarkovModel(states, counts, probabilities, reachable)


def conversion_probability(model: MarkovModel) -> float:
    """Return eventual Conversion absorption probability starting from Start."""

    transient_indices = [
        index for index, state in enumerate(model.states) if state not in ABSORBING_STATES
    ]
    conversion_index = model.state_index(CONVERSION_STATE)
    start_position = transient_indices.index(model.state_index(START_STATE))
    q_matrix = model.transition_probabilities[np.ix_(transient_indices, transient_indices)]
    conversion_vector = model.transition_probabilities[transient_indices, conversion_index]
    try:
        absorption = np.linalg.solve(
            np.eye(len(transient_indices), dtype=np.float64) - q_matrix,
            conversion_vector,
        )
    except np.linalg.LinAlgError as exc:
        raise ValueError("Transient transition system is not absorbable") from exc
    probability = float(absorption[start_position])
    if not isfinite(probability) or probability < -FLOATING_POINT_TOLERANCE or probability > 1 + FLOATING_POINT_TOLERANCE:
        raise ValueError(f"Invalid baseline Conversion probability: {probability}")
    return min(1.0, max(0.0, probability))


def remove_channel(
    model: MarkovModel,
    channel: str,
) -> MarkovModel:
    """Remove one graph state and redirect all incoming mass to ``Null``."""

    if channel in RESERVED_STATES:
        raise ValueError(f"Reserved state cannot be removed: {channel}")
    removed_index = model.state_index(channel)
    retained_indices = [
        index for index, state in enumerate(model.states) if state != channel
    ]
    states = tuple(model.states[index] for index in retained_indices)
    null_index = states.index(NULL_STATE)

    probabilities = model.transition_probabilities[
        np.ix_(retained_indices, retained_indices)
    ].copy()
    counts = model.transition_counts[np.ix_(retained_indices, retained_indices)].copy()
    for reduced_source, baseline_source in enumerate(retained_indices):
        probabilities[reduced_source, null_index] += model.transition_probabilities[
            baseline_source, removed_index
        ]
        counts[reduced_source, null_index] += model.transition_counts[
            baseline_source, removed_index
        ]

    if not np.all(np.isfinite(probabilities)):
        raise ValueError("Removed transition matrix contains non-finite probabilities")
    if np.any(probabilities < -FLOATING_POINT_TOLERANCE):
        raise ValueError("Removed transition matrix contains negative probabilities")
    if not np.allclose(
        probabilities.sum(axis=1), 1.0, atol=FLOATING_POINT_TOLERANCE
    ):
        raise ValueError("Removed transition-matrix rows do not sum to one")

    for absorber in ABSORBING_STATES:
        absorber_index = states.index(absorber)
        expected_row = np.zeros(len(states), dtype=np.float64)
        expected_row[absorber_index] = 1.0
        if not np.allclose(
            probabilities[absorber_index],
            expected_row,
            atol=FLOATING_POINT_TOLERANCE,
        ):
            raise ValueError(f"Removed matrix changed absorbing state: {absorber}")

    reachable = _reachability(probabilities, states)
    unreachable = [
        state
        for state, can_reach in zip(states, reachable, strict=True)
        if state not in ABSORBING_STATES and not can_reach
    ]
    if unreachable:
        raise ValueError(
            "Transient states cannot reach an absorbing state after removal: "
            + ", ".join(unreachable)
        )
    return MarkovModel(states, counts, probabilities, reachable)


def calculate_removal_effects(
    paths: Iterable[Sequence[str]],
    *,
    tolerance: float = FLOATING_POINT_TOLERANCE,
) -> tuple[float, tuple[RemovalResult, ...]]:
    """Calculate graph-state removal effects from one baseline matrix."""

    normalized = _normalize_paths(paths)
    baseline_model = build_transition_model(normalized)
    baseline = conversion_probability(baseline_model)
    if baseline <= tolerance:
        raise ValueError("Baseline Conversion probability is zero")

    results: list[RemovalResult] = []
    for channel in channel_states(normalized):
        removed_model = remove_channel(baseline_model, channel)
        without_probability = conversion_probability(removed_model)
        raw_effect = 1.0 - without_probability / baseline
        adjusted = -tolerance <= raw_effect < 0.0
        effect = 0.0 if adjusted else raw_effect
        results.append(
            RemovalResult(
                channel=channel,
                conversion_probability_without_channel=without_probability,
                raw_removal_effect=raw_effect,
                removal_effect=effect,
                floating_point_adjusted=adjusted,
                materially_negative=effect < -tolerance,
            )
        )
    return baseline, tuple(results)


def calculate_streaming_removal_effects(
    path_factory: Callable[[], Iterable[Sequence[str]]],
    *,
    tolerance: float = FLOATING_POINT_TOLERANCE,
) -> tuple[MarkovModel, float, tuple[RemovalResult, ...]]:
    """Build one streamed baseline, then remove each graph state independently."""

    baseline_model = build_transition_model_streaming(path_factory())
    baseline = conversion_probability(baseline_model)
    if baseline <= tolerance:
        raise ValueError("Baseline Conversion probability is zero")
    channels = tuple(
        state for state in baseline_model.states if state not in RESERVED_STATES
    )
    results: list[RemovalResult] = []
    for channel in channels:
        removed_model = remove_channel(baseline_model, channel)
        without_probability = conversion_probability(removed_model)
        raw_effect = 1.0 - without_probability / baseline
        adjusted = -tolerance <= raw_effect < 0.0
        effect = 0.0 if adjusted else raw_effect
        results.append(
            RemovalResult(
                channel=channel,
                conversion_probability_without_channel=without_probability,
                raw_removal_effect=raw_effect,
                removal_effect=effect,
                floating_point_adjusted=adjusted,
                materially_negative=effect < -tolerance,
            )
        )
    return baseline_model, baseline, tuple(results)


def normalize_removal_effects(
    effects: Mapping[str, float],
    *,
    tolerance: float = FLOATING_POINT_TOLERANCE,
) -> dict[str, float]:
    """Normalize valid effects, failing on negative or zero-total inputs."""

    if not effects:
        raise ValueError("At least one removal effect is required")
    prepared: dict[str, float] = {}
    for channel, value in effects.items():
        numeric = float(value)
        if not isfinite(numeric):
            raise ValueError(f"Removal effect is not finite for {channel}")
        if numeric < -tolerance:
            raise ValueError(f"Materially negative removal effect for {channel}: {numeric}")
        prepared[channel] = 0.0 if numeric < 0.0 else numeric
    total = float(sum(prepared.values()))
    if not isfinite(total) or total <= tolerance:
        raise ValueError("Total removal effect is zero or non-finite")
    shares = {channel: value / total for channel, value in prepared.items()}
    if abs(sum(shares.values()) - 1.0) > tolerance:
        raise ValueError("Normalized Markov shares do not sum to one")
    return shares


def transition_records(model: MarkovModel) -> list[dict[str, object]]:
    """Serialize the full dense transition matrix for BigQuery."""

    rows: list[dict[str, object]] = []
    for source_index, source in enumerate(model.states):
        for target_index, target in enumerate(model.states):
            rows.append(
                {
                    "from_state": source,
                    "to_state": target,
                    "transition_count": int(model.transition_counts[source_index, target_index]),
                    "transition_probability": float(
                        model.transition_probabilities[source_index, target_index]
                    ),
                    "is_absorbing_from_state": source in ABSORBING_STATES,
                    "can_reach_absorbing": model.can_reach_absorbing[source_index],
                    "from_state_order": source_index,
                    "to_state_order": target_index,
                }
            )
    return rows


def observed_transition_counts(paths: Iterable[Sequence[str]]) -> Counter[tuple[str, str]]:
    """Expose sparse observed counts for focused unit tests and diagnostics."""

    normalized = _normalize_paths(paths)
    return Counter(
        (source, target)
        for path in normalized
        for source, target in zip(path, path[1:])
    )
