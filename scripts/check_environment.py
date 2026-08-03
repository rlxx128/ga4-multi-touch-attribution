"""Report local prerequisites without reading or displaying credentials."""

from __future__ import annotations

import argparse
import importlib.metadata
import os
import platform
import shutil
import sys
from pathlib import Path


MINIMUM_PYTHON = (3, 11)
REQUIRED_ENVIRONMENT_VARIABLES = (
    "GCP_PROJECT_ID",
    "BQ_DATASET",
    "BQ_LOCATION",
    "GA4_SOURCE_TABLE",
    "START_DATE",
    "END_DATE",
    "MAXIMUM_BYTES_BILLED",
)
REQUIRED_DISTRIBUTIONS = (
    "pandas",
    "numpy",
    "scipy",
    "networkx",
    "google-cloud-bigquery",
    "google-cloud-bigquery-storage",
    "db-dtypes",
    "pyarrow",
    "matplotlib",
    "pytest",
    "ruff",
)


def find_google_cloud_cli(command: str) -> str | None:
    """Find a Google Cloud CLI command on PATH or in its common Windows path."""
    discovered = shutil.which(command)
    if discovered:
        return discovered

    local_app_data = os.environ.get("LOCALAPPDATA")
    if platform.system() == "Windows" and local_app_data:
        candidate = (
            Path(local_app_data)
            / "Google"
            / "Cloud SDK"
            / "google-cloud-sdk"
            / "bin"
            / f"{command}.cmd"
        )
        if candidate.is_file():
            return str(candidate)
    return None


def distribution_versions() -> tuple[dict[str, str], list[str]]:
    """Return installed package versions and missing distribution names."""
    installed: dict[str, str] = {}
    missing: list[str] = []
    for name in REQUIRED_DISTRIBUTIONS:
        try:
            installed[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            missing.append(name)
    return installed, missing


def adc_status() -> tuple[bool, str]:
    """Check whether ADC can be discovered without refreshing or printing it."""
    try:
        import google.auth

        _, default_project = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
    except Exception as exc:  # pragma: no cover - depends on host credentials
        return False, f"unavailable ({type(exc).__name__})"
    project_message = default_project or "no default project in ADC"
    return True, f"available ({project_message})"


def main() -> int:
    """Print a safe environment report and optionally fail on missing items."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Return a non-zero exit code if any prerequisite is missing.",
    )
    args = parser.parse_args()

    python_ok = sys.version_info >= MINIMUM_PYTHON
    print(f"Python: {platform.python_version()} ({'OK' if python_ok else 'TOO OLD'})")

    installed, missing_packages = distribution_versions()
    for name in REQUIRED_DISTRIBUTIONS:
        value = installed.get(name, "MISSING")
        print(f"Package {name}: {value}")

    missing_variables: list[str] = []
    for name in REQUIRED_ENVIRONMENT_VARIABLES:
        if os.environ.get(name):
            print(f"Environment {name}: SET")
        else:
            print(f"Environment {name}: MISSING")
            missing_variables.append(name)

    missing_commands: list[str] = []
    for command in ("git", "gcloud", "bq"):
        path = (
            find_google_cloud_cli(command)
            if command in {"gcloud", "bq"}
            else shutil.which(command)
        )
        if path:
            print(f"Command {command}: AVAILABLE ({path})")
        else:
            print(f"Command {command}: MISSING")
            missing_commands.append(command)

    adc_available, adc_message = adc_status()
    print(f"Application Default Credentials: {adc_message}")

    has_missing = bool(
        not python_ok
        or missing_packages
        or missing_variables
        or missing_commands
        or not adc_available
    )
    if has_missing:
        print("Environment check completed with missing prerequisites.")
    else:
        print("Environment check passed.")
    return 1 if args.strict and has_missing else 0


if __name__ == "__main__":
    raise SystemExit(main())

