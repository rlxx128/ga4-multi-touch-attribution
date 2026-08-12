"""Phase 5 path transformations, rank comparisons, and cluster bootstrap."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from math import isfinite
from typing import Iterable, Mapping, Sequence

import numpy as np

from .markov import (
    ABSORBING_STATES,
    CONVERSION_STATE,
    NULL_STATE,
    RESERVED_STATES,
    START_STATE,
    MarkovModel,
    build_transition_model_from_counts,
    calculate_model_removal_effects,
    calculate_streaming_removal_effects,
    normalize_removal_effects,
)

RANK_TOLERANCE = 1e-15


@dataclass(frozen=True)
class ClusterJourney:
    """One completed Markov journey owned by one bootstrap cluster."""

    user_pseudo_id: str
    path: tuple[str, ...]


@dataclass(frozen=True)
class MarkovScenarioResult:
    model: MarkovModel
    baseline_probability: float
    effects: dict[str, float]
    shares: dict[str, float]
    materially_negative_channels: tuple[str, ...]


@dataclass(frozen=True)
class BootstrapResult:
    replicate_rows: tuple[dict[str, object], ...]
    summary_rows: tuple[dict[str, object], ...]
    attempted_replicates: int
    successful_replicates: int
    failed_replicates: int


@dataclass(frozen=True)
class UserTransitionCounts:
    """Sparse coordinate representation of user-level transition counts."""

    users: tuple[str, ...]
    user_indices: np.ndarray
    edge_indices: np.ndarray
    edge_counts: np.ndarray
    edge_dimension: int


def _validate_path(path: Sequence[str]) -> tuple[str, ...]:
    normalized = tuple(str(state) for state in path)
    if len(normalized) < 2 or normalized[0] != START_STATE:
        raise ValueError("Every sensitivity path must begin with Start")
    if normalized[-1] not in ABSORBING_STATES:
        raise ValueError("Every sensitivity path must end in Conversion or Null")
    if any(state in ABSORBING_STATES for state in normalized[1:-1]):
        raise ValueError("An absorbing state may appear only at the path end")
    return normalized


def compress_consecutive_channels(path: Sequence[str]) -> tuple[str, ...]:
    """Remove only adjacent identical channel states, preserving endpoints."""

    normalized = _validate_path(path)
    transformed = [START_STATE]
    for state in normalized[1:-1]:
        if state != transformed[-1]:
            transformed.append(state)
    transformed.append(normalized[-1])
    return tuple(transformed)


def omit_direct_from_mixed_path(path: Sequence[str]) -> tuple[str, ...]:
    """Omit Direct only when another channel exists; retain Direct-only paths."""

    normalized = _validate_path(path)
    channels = normalized[1:-1]
    if not any(channel != "Direct" for channel in channels):
        return normalized
    transformed = [START_STATE]
    transformed.extend(channel for channel in channels if channel != "Direct")
    transformed.append(normalized[-1])
    return tuple(transformed)


def deterministic_ranks(values: Mapping[str, float]) -> dict[str, int]:
    """Return ordinal ranks using descending value then channel name."""

    if not values:
        raise ValueError("At least one value is required for ranking")
    prepared: list[tuple[str, float]] = []
    for channel, value in values.items():
        numeric = float(value)
        if not isfinite(numeric):
            raise ValueError(f"Non-finite rank value for {channel}")
        prepared.append((str(channel), numeric))
    return {
        channel: rank
        for rank, (channel, _) in enumerate(
            sorted(prepared, key=lambda item: (-item[1], item[0])),
            start=1,
        )
    }


def tied_channels(values: Mapping[str, float], *, tolerance: float = RANK_TOLERANCE) -> set[str]:
    """Return channels participating in a numerical tie."""

    channels = sorted(values)
    tied: set[str] = set()
    for index, channel in enumerate(channels):
        for other in channels[index + 1 :]:
            if abs(float(values[channel]) - float(values[other])) <= tolerance:
                tied.update((channel, other))
    return tied


def spearman_rank_correlation(
    baseline_ranks: Mapping[str, int], scenario_ranks: Mapping[str, int]
) -> float:
    """Calculate Spearman correlation for two complete ordinal rank vectors."""

    if set(baseline_ranks) != set(scenario_ranks):
        raise ValueError("Spearman rankings must contain the same channels")
    count = len(baseline_ranks)
    if count < 2:
        return 1.0
    squared_differences = sum(
        (int(baseline_ranks[channel]) - int(scenario_ranks[channel])) ** 2
        for channel in baseline_ranks
    )
    return 1.0 - (6.0 * squared_differences) / (count * (count**2 - 1))


def calculate_markov_scenario(
    paths: Iterable[Sequence[str]],
) -> MarkovScenarioResult:
    """Calculate one deterministic scenario with the approved removal rule."""

    model, baseline_probability, removal_results = calculate_streaming_removal_effects(
        lambda: iter(paths) if isinstance(paths, Sequence) else paths
    )
    materially_negative = tuple(
        result.channel for result in removal_results if result.materially_negative
    )
    effects = {result.channel: result.removal_effect for result in removal_results}
    shares = normalize_removal_effects(effects)
    return MarkovScenarioResult(
        model=model,
        baseline_probability=baseline_probability,
        effects=effects,
        shares=shares,
        materially_negative_channels=materially_negative,
    )


def _user_transition_matrix(
    journeys: Sequence[ClusterJourney],
    states: tuple[str, ...],
) -> UserTransitionCounts:
    users = tuple(sorted({journey.user_pseudo_id for journey in journeys}))
    if not users:
        raise ValueError("At least one bootstrap user is required")
    user_index = {user: index for index, user in enumerate(users)}
    state_index = {state: index for index, state in enumerate(states)}
    edge_counts: Counter[tuple[int, int]] = Counter()
    state_count = len(states)
    for journey in journeys:
        path = _validate_path(journey.path)
        for source, target in zip(path, path[1:]):
            if source not in state_index or target not in state_index:
                raise ValueError(f"Bootstrap path contains unknown state: {source}->{target}")
            flat_edge = state_index[source] * state_count + state_index[target]
            edge_counts[(user_index[journey.user_pseudo_id], flat_edge)] += 1
    rows = np.fromiter((key[0] for key in edge_counts), dtype=np.int64)
    columns = np.fromiter((key[1] for key in edge_counts), dtype=np.int64)
    data = np.fromiter(edge_counts.values(), dtype=np.int64)
    return UserTransitionCounts(
        users=users,
        user_indices=rows,
        edge_indices=columns,
        edge_counts=data,
        edge_dimension=state_count * state_count,
    )


def _active_replicate_model(
    states: tuple[str, ...], full_counts: np.ndarray
) -> tuple[MarkovModel, tuple[str, ...]]:
    channel_indices = [
        index for index, state in enumerate(states) if state not in RESERVED_STATES
    ]
    active_indices = [
        index
        for index in channel_indices
        if int(full_counts[index].sum() + full_counts[:, index].sum()) > 0
    ]
    retained = [states.index(START_STATE), *active_indices]
    retained.extend((states.index(CONVERSION_STATE), states.index(NULL_STATE)))
    active_states = tuple(states[index] for index in retained)
    active_counts = full_counts[np.ix_(retained, retained)]
    return build_transition_model_from_counts(active_states, active_counts), active_states


def run_user_cluster_bootstrap(
    journeys: Sequence[ClusterJourney],
    baseline_model: MarkovModel,
    baseline_effects: Mapping[str, float],
    baseline_shares: Mapping[str, float],
    *,
    replicate_count: int,
    seed: int,
) -> BootstrapResult:
    """Run a deterministic user-level cluster bootstrap locally."""

    if replicate_count <= 0:
        raise ValueError("replicate_count must be positive")
    channels = tuple(
        state for state in baseline_model.states if state not in RESERVED_STATES
    )
    if set(channels) != set(baseline_shares) or set(channels) != set(baseline_effects):
        raise ValueError("Baseline channel vectors do not match the Markov states")
    user_edges = _user_transition_matrix(journeys, baseline_model.states)
    users = user_edges.users
    rng = np.random.default_rng(seed)
    rows: list[dict[str, object]] = []
    successful = 0
    failed = 0

    for replicate_id in range(1, replicate_count + 1):
        sampled = rng.integers(0, len(users), size=len(users), dtype=np.int64)
        multiplicity = np.bincount(sampled, minlength=len(users)).astype(np.int64)
        unique_selected = int(np.count_nonzero(multiplicity))
        sampled_edge_counts = (
            multiplicity[user_edges.user_indices] * user_edges.edge_counts
        )
        flat_counts = np.bincount(
            user_edges.edge_indices,
            weights=sampled_edge_counts,
            minlength=user_edges.edge_dimension,
        ).astype(np.int64)
        full_counts = flat_counts.reshape(
            (len(baseline_model.states), len(baseline_model.states))
        )
        try:
            replicate_model, active_states = _active_replicate_model(
                baseline_model.states, full_counts
            )
            probability, removal_results = calculate_model_removal_effects(
                replicate_model
            )
            effects = {channel: 0.0 for channel in channels}
            for result in removal_results:
                effects[result.channel] = result.removal_effect
            shares = normalize_removal_effects(effects)
            ranks = deterministic_ranks(shares)
        except (ValueError, np.linalg.LinAlgError) as exc:
            failed += 1
            rows.append(
                {
                    "replicate_id": replicate_id,
                    "seed": seed,
                    "sampled_user_draws": len(users),
                    "unique_user_clusters_selected": unique_selected,
                    "channel": None,
                    "removal_effect": None,
                    "markov_share": None,
                    "channel_rank": None,
                    "baseline_conversion_probability": None,
                    "active_state_count": None,
                    "replicate_status": "FAILED",
                    "failure_reason": str(exc),
                }
            )
            continue
        successful += 1
        for channel in channels:
            rows.append(
                {
                    "replicate_id": replicate_id,
                    "seed": seed,
                    "sampled_user_draws": len(users),
                    "unique_user_clusters_selected": unique_selected,
                    "channel": channel,
                    "removal_effect": effects[channel],
                    "markov_share": shares[channel],
                    "channel_rank": ranks[channel],
                    "baseline_conversion_probability": probability,
                    "active_state_count": len(active_states),
                    "replicate_status": "SUCCESS",
                    "failure_reason": None,
                }
            )

    successful_rows = [row for row in rows if row["replicate_status"] == "SUCCESS"]
    summary: list[dict[str, object]] = []
    baseline_ranks = deterministic_ranks(baseline_shares)
    for channel in channels:
        channel_rows = [row for row in successful_rows if row["channel"] == channel]
        if not channel_rows:
            raise ValueError(f"No successful bootstrap observations for {channel}")
        shares_array = np.asarray(
            [float(row["markov_share"]) for row in channel_rows], dtype=np.float64
        )
        effects_array = np.asarray(
            [float(row["removal_effect"]) for row in channel_rows], dtype=np.float64
        )
        ranks_array = np.asarray(
            [int(row["channel_rank"]) for row in channel_rows], dtype=np.int64
        )
        summary.append(
            {
                "channel": channel,
                "seed": seed,
                "attempted_replicates": replicate_count,
                "successful_replicates": successful,
                "failed_replicates": failed,
                "baseline_markov_share": float(baseline_shares[channel]),
                "bootstrap_mean_share": float(np.mean(shares_array)),
                "bootstrap_median_share": float(np.median(shares_array)),
                "bootstrap_share_stddev": float(np.std(shares_array, ddof=1)),
                "share_percentile_2_5": float(np.percentile(shares_array, 2.5)),
                "share_percentile_97_5": float(np.percentile(shares_array, 97.5)),
                "baseline_removal_effect": float(baseline_effects[channel]),
                "bootstrap_mean_removal_effect": float(np.mean(effects_array)),
                "bootstrap_median_removal_effect": float(np.median(effects_array)),
                "removal_effect_stddev": float(np.std(effects_array, ddof=1)),
                "removal_effect_percentile_2_5": float(
                    np.percentile(effects_array, 2.5)
                ),
                "removal_effect_percentile_97_5": float(
                    np.percentile(effects_array, 97.5)
                ),
                "baseline_rank": baseline_ranks[channel],
                "mean_bootstrap_rank": float(np.mean(ranks_array)),
                "median_bootstrap_rank": float(np.median(ranks_array)),
                "minimum_observed_rank": int(np.min(ranks_array)),
                "maximum_observed_rank": int(np.max(ranks_array)),
                "probability_top_1": float(np.mean(ranks_array <= 1)),
                "probability_top_3": float(np.mean(ranks_array <= 3)),
                "probability_top_5": float(np.mean(ranks_array <= 5)),
            }
        )
    return BootstrapResult(
        replicate_rows=tuple(rows),
        summary_rows=tuple(summary),
        attempted_replicates=replicate_count,
        successful_replicates=successful,
        failed_replicates=failed,
    )
