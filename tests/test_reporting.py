from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from src.attribution.reporting import (
    generate_phase6_figures,
    path_length_plot_data,
    top_converting_paths,
    validate_funnel_data,
)


def _funnel_frame() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "channel": "Organic Search",
                "sessions": 100,
                "view_item_session_rate": 0.50,
                "add_to_cart_session_rate": 0.20,
                "checkout_session_rate": 0.10,
                "purchase_session_rate": 0.05,
            },
            {
                "channel": "Referral",
                "sessions": 50,
                "view_item_session_rate": 0.40,
                "add_to_cart_session_rate": 0.15,
                "checkout_session_rate": 0.08,
                "purchase_session_rate": 0.04,
            },
        ]
    )


def _journey_frame() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "summary_type": "PATH_LENGTH",
                "dimension_key": "1",
                "dimension_label": "1 touchpoint(s)",
                "sort_order": 1,
                "attributable_conversions": 70,
            },
            {
                "summary_type": "PATH_LENGTH",
                "dimension_key": "2",
                "dimension_label": "2 touchpoint(s)",
                "sort_order": 2,
                "attributable_conversions": 20,
            },
            {
                "summary_type": "PATH_LENGTH",
                "dimension_key": "12",
                "dimension_label": "12 touchpoint(s)",
                "sort_order": 12,
                "attributable_conversions": 10,
            },
            {
                "summary_type": "CONVERTING_PATH",
                "dimension_key": "Organic Search",
                "dimension_label": "Organic Search",
                "sort_order": 1,
                "attributable_conversions": 40,
            },
            {
                "summary_type": "CONVERTING_PATH",
                "dimension_key": "Referral",
                "dimension_label": "Referral",
                "sort_order": 2,
                "attributable_conversions": 25,
            },
        ]
    )


def _attribution_frame() -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for channel, last_click, markov, mean, low, high in (
        ("Organic Search", 120.0, 110.0, 0.60, 0.55, 0.65),
        ("Referral", 80.0, 90.0, 0.40, 0.35, 0.45),
    ):
        rows.extend(
            (
                {
                    "channel": channel,
                    "model": "Last Click",
                    "attributed_revenue": last_click,
                    "markov_minus_last_click_revenue": markov - last_click,
                    "bootstrap_mean_share": mean,
                    "bootstrap_share_percentile_2_5": low,
                    "bootstrap_share_percentile_97_5": high,
                },
                {
                    "channel": channel,
                    "model": "Markov",
                    "attributed_revenue": markov,
                    "markov_minus_last_click_revenue": markov - last_click,
                    "bootstrap_mean_share": mean,
                    "bootstrap_share_percentile_2_5": low,
                    "bootstrap_share_percentile_97_5": high,
                },
            )
        )
    return pd.DataFrame(rows)


def test_validate_funnel_data_accepts_session_incidence_rates() -> None:
    validate_funnel_data(_funnel_frame())


def test_validate_funnel_data_rejects_rate_outside_unit_interval() -> None:
    frame = _funnel_frame()
    frame.loc[0, "purchase_session_rate"] = 1.01
    with pytest.raises(ValueError, match="between zero and one"):
        validate_funnel_data(frame)


def test_top_paths_follows_stored_rank() -> None:
    result = top_converting_paths(_journey_frame(), limit=1)
    assert result.loc[0, "dimension_label"] == "Organic Search"


def test_path_length_plot_data_combines_long_tail() -> None:
    result = path_length_plot_data(_journey_frame(), cap=10)
    assert result["plot_label"].tolist() == ["1", "2", "10+"]
    assert result["conversions"].sum() == 100
    assert result["conversion_share"].sum() == pytest.approx(1.0)


def test_generate_phase6_figures_creates_six_nonempty_pngs(tmp_path: Path) -> None:
    paths = generate_phase6_figures(
        _funnel_frame(), _journey_frame(), _attribution_frame(), tmp_path
    )
    assert len(paths) == 6
    assert all(path.suffix == ".png" for path in paths)
    assert all(path.exists() and path.stat().st_size > 0 for path in paths)
