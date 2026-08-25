"""Reusable Phase 6 reporting and figure-generation helpers."""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

import matplotlib
import pandas as pd

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402


REPORTING_VERSION = "phase6_business_reporting_v1_20260814"
MODEL_ORDER = (
    "First Click",
    "Last Click",
    "Last Non-direct Click",
    "Linear",
    "Time Decay",
    "Markov",
)
RATE_COLUMNS = (
    "view_item_session_rate",
    "add_to_cart_session_rate",
    "checkout_session_rate",
    "purchase_session_rate",
)


def validate_funnel_data(frame: pd.DataFrame) -> None:
    """Raise when a funnel export violates the approved incidence-rate contract."""
    missing = {"channel", "sessions", *RATE_COLUMNS}.difference(frame.columns)
    if missing:
        raise ValueError(f"Missing funnel columns: {', '.join(sorted(missing))}")
    if frame.empty:
        raise ValueError("Funnel data must not be empty")
    if frame["channel"].duplicated().any():
        raise ValueError("Funnel data must have one row per channel")
    if (frame["sessions"] <= 0).any():
        raise ValueError("Every reported funnel channel must have at least one Session")
    rates = frame.loc[:, RATE_COLUMNS].astype(float)
    if rates.isna().any().any() or ((rates < 0) | (rates > 1)).any().any():
        raise ValueError("Funnel incidence rates must be finite values between zero and one")


def top_converting_paths(frame: pd.DataFrame, limit: int = 10) -> pd.DataFrame:
    """Return the most common validated converting paths in stored rank order."""
    if limit < 1:
        raise ValueError("limit must be positive")
    required = {
        "summary_type",
        "dimension_label",
        "sort_order",
        "attributable_conversions",
    }
    missing = required.difference(frame.columns)
    if missing:
        raise ValueError(f"Missing journey columns: {', '.join(sorted(missing))}")
    paths = frame.loc[frame["summary_type"] == "CONVERTING_PATH"].copy()
    paths = paths.sort_values(
        ["sort_order", "dimension_label"], kind="stable"
    ).head(limit)
    return paths.reset_index(drop=True)


def path_length_plot_data(frame: pd.DataFrame, cap: int = 10) -> pd.DataFrame:
    """Prepare a readable path-length distribution, combining the long tail."""
    if cap < 2:
        raise ValueError("cap must be at least two")
    required = {
        "summary_type",
        "dimension_key",
        "attributable_conversions",
    }
    missing = required.difference(frame.columns)
    if missing:
        raise ValueError(f"Missing journey columns: {', '.join(sorted(missing))}")
    lengths = frame.loc[frame["summary_type"] == "PATH_LENGTH"].copy()
    if lengths.empty:
        raise ValueError("Journey data has no PATH_LENGTH rows")
    lengths["path_length"] = lengths["dimension_key"].astype(int)
    lengths["plot_label"] = lengths["path_length"].map(
        lambda value: f"{cap}+" if value >= cap else str(value)
    )
    plotted = (
        lengths.groupby("plot_label", as_index=False, sort=False)[
            "attributable_conversions"
        ]
        .sum()
        .rename(columns={"attributable_conversions": "conversions"})
    )
    plotted["sort_order"] = plotted["plot_label"].map(
        lambda value: cap if value == f"{cap}+" else int(value)
    )
    total = float(plotted["conversions"].sum())
    plotted["conversion_share"] = plotted["conversions"] / total
    return plotted.sort_values("sort_order", kind="stable").reset_index(drop=True)


def _save_figure(fig: plt.Figure, output_path: Path) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=180, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return output_path


def _channel_labels(values: Iterable[object]) -> list[str]:
    return [str(value) for value in values]


def plot_channel_funnel(frame: pd.DataFrame, output_path: Path) -> Path:
    validate_funnel_data(frame)
    data = frame.sort_values("purchase_session_rate", ascending=False).reset_index(
        drop=True
    )
    labels = [
        f"{channel} (n={int(sessions):,})"
        for channel, sessions in zip(data["channel"], data["sessions"])
    ]
    y = np.arange(len(labels))
    height = 0.18
    fig, ax = plt.subplots(figsize=(12, max(6, len(labels) * 0.6)))
    colors = ("#31688e", "#35b779", "#fde725", "#e76f51")
    names = ("View item", "Add to cart", "Begin checkout", "Purchase")
    for index, (column, name, color) in enumerate(zip(RATE_COLUMNS, names, colors)):
        ax.barh(y + (index - 1.5) * height, data[column] * 100, height, label=name, color=color)
    ax.set_yticks(y, labels)
    ax.invert_yaxis()
    ax.set_xlabel("Share of attribution-eligible channel Sessions (%)")
    ax.set_title("Channel-level funnel stage incidence rates")
    ax.grid(axis="x", alpha=0.2)
    ax.legend(ncols=2, frameon=False, loc="lower right")
    fig.text(
        0.01,
        0.01,
        "Each stage is an independent Session-level incidence rate; sequential event order is not inferred.",
        fontsize=8,
        color="#555555",
    )
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    return _save_figure(fig, output_path)


def plot_path_length_distribution(frame: pd.DataFrame, output_path: Path) -> Path:
    data = path_length_plot_data(frame)
    fig, ax = plt.subplots(figsize=(10, 6))
    bars = ax.bar(data["plot_label"], data["conversion_share"] * 100, color="#31688e")
    ax.bar_label(bars, fmt="%.1f%%", padding=3, fontsize=8)
    ax.set_xlabel("Retained Session touchpoints per conversion")
    ax.set_ylabel("Share of attributable conversions (%)")
    ax.set_title("Converting journey path-length distribution")
    ax.grid(axis="y", alpha=0.2)
    fig.tight_layout()
    return _save_figure(fig, output_path)


def plot_top_paths(frame: pd.DataFrame, output_path: Path, limit: int = 10) -> Path:
    data = top_converting_paths(frame, limit=limit).sort_values(
        "attributable_conversions", ascending=True
    )
    fig, ax = plt.subplots(figsize=(12, 7))
    bars = ax.barh(
        _channel_labels(data["dimension_label"]),
        data["attributable_conversions"],
        color="#35b779",
    )
    ax.bar_label(bars, fmt="%.0f", padding=3, fontsize=8)
    ax.set_xlabel("Attributable conversions")
    ax.set_title(f"Top {len(data)} converting channel paths")
    ax.grid(axis="x", alpha=0.2)
    fig.tight_layout()
    return _save_figure(fig, output_path)


def plot_attribution_revenue(frame: pd.DataFrame, output_path: Path) -> Path:
    required = {"channel", "model", "attributed_revenue"}
    missing = required.difference(frame.columns)
    if missing:
        raise ValueError(f"Missing attribution columns: {', '.join(sorted(missing))}")
    pivot = frame.pivot(index="channel", columns="model", values="attributed_revenue")
    models = [model for model in MODEL_ORDER if model in pivot.columns]
    pivot = pivot.loc[pivot[models].max(axis=1).sort_values(ascending=False).index, models]
    x = np.arange(len(pivot.index))
    width = 0.82 / len(models)
    fig, ax = plt.subplots(figsize=(15, 8))
    colors = plt.cm.viridis(np.linspace(0.08, 0.92, len(models)))
    for index, (model, color) in enumerate(zip(models, colors)):
        offset = (index - (len(models) - 1) / 2) * width
        ax.bar(x + offset, pivot[model], width, label=model, color=color)
    ax.set_xticks(x, _channel_labels(pivot.index), rotation=35, ha="right")
    ax.set_ylabel("Attributed revenue (USD)")
    ax.set_title("Attributed revenue by channel and model")
    ax.grid(axis="y", alpha=0.2)
    ax.legend(ncols=3, frameon=False)
    fig.text(
        0.01,
        0.01,
        "Descriptive attribution allocation; not an estimate of causal incrementality.",
        fontsize=8,
        color="#555555",
    )
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    return _save_figure(fig, output_path)


def plot_markov_vs_last_click(frame: pd.DataFrame, output_path: Path) -> Path:
    markov = frame.loc[frame["model"] == "Markov"].copy()
    if markov.empty:
        raise ValueError("Attribution data has no Markov rows")
    markov = markov.sort_values("markov_minus_last_click_revenue")
    colors = np.where(
        markov["markov_minus_last_click_revenue"] >= 0, "#35b779", "#e76f51"
    )
    fig, ax = plt.subplots(figsize=(11, 7))
    bars = ax.barh(
        _channel_labels(markov["channel"]),
        markov["markov_minus_last_click_revenue"],
        color=colors,
    )
    ax.axvline(0, color="#333333", linewidth=0.8)
    ax.bar_label(bars, fmt="%+.0f", padding=3, fontsize=8)
    ax.set_xlabel("Markov minus Last Click attributed revenue (USD)")
    ax.set_title("How Markov redistributes revenue versus Last Click")
    ax.grid(axis="x", alpha=0.2)
    fig.text(
        0.01,
        0.01,
        "Differences reflect model allocation, not incremental revenue.",
        fontsize=8,
        color="#555555",
    )
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    return _save_figure(fig, output_path)


def plot_markov_bootstrap(frame: pd.DataFrame, output_path: Path) -> Path:
    data = frame.loc[frame["model"] == "Markov"].copy()
    if data.empty:
        raise ValueError("Attribution data has no Markov rows")
    data = data.sort_values("bootstrap_mean_share", ascending=True)
    means = data["bootstrap_mean_share"].to_numpy(dtype=float) * 100
    lower = data["bootstrap_share_percentile_2_5"].to_numpy(dtype=float) * 100
    upper = data["bootstrap_share_percentile_97_5"].to_numpy(dtype=float) * 100
    errors = np.vstack((means - lower, upper - means))
    fig, ax = plt.subplots(figsize=(11, 7))
    ax.errorbar(
        means,
        np.arange(len(data)),
        xerr=errors,
        fmt="o",
        color="#31688e",
        ecolor="#7f8c8d",
        capsize=4,
    )
    ax.set_yticks(np.arange(len(data)), _channel_labels(data["channel"]))
    ax.set_xlabel("Markov contribution share (%)")
    ax.set_title("User-cluster bootstrap uncertainty (500 replicates)")
    ax.grid(axis="x", alpha=0.2)
    fig.text(
        0.01,
        0.01,
        "95% percentile intervals describe sampling stability, not causal confidence intervals.",
        fontsize=8,
        color="#555555",
    )
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    return _save_figure(fig, output_path)


def generate_phase6_figures(
    funnel: pd.DataFrame,
    journeys: pd.DataFrame,
    attribution: pd.DataFrame,
    output_directory: Path,
) -> list[Path]:
    """Generate the six approved, presentation-ready Phase 6 figures."""
    return [
        plot_channel_funnel(
            funnel, output_directory / "phase6_channel_funnel_incidence.png"
        ),
        plot_path_length_distribution(
            journeys, output_directory / "phase6_path_length_distribution.png"
        ),
        plot_top_paths(
            journeys, output_directory / "phase6_top_converting_paths.png"
        ),
        plot_attribution_revenue(
            attribution, output_directory / "phase6_attribution_revenue_by_model.png"
        ),
        plot_markov_vs_last_click(
            attribution, output_directory / "phase6_markov_vs_last_click.png"
        ),
        plot_markov_bootstrap(
            attribution, output_directory / "phase6_markov_bootstrap_uncertainty.png"
        ),
    ]
