"""Stable JSON provenance helpers for ignored case-level artifacts."""

from __future__ import annotations

import importlib.metadata
import json
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from vtseg import __version__

REQUIRED_FIELDS = {
    "pipeline_version",
    "input_study_uid",
    "selected_series_uid",
    "selected_temporal_frame",
    "modality",
    "source_dicom_count",
    "prepared_volume_dimensions",
    "voxel_spacing",
    "affine",
    "segmentation_backend",
    "execution_timestamp",
    "output_files",
    "software_versions",
    "warnings",
    "errors",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def package_version(name: str) -> str | None:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return None


def git_commit(repo: str | Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() or None


def software_versions() -> dict[str, str | None]:
    return {
        "python": platform.python_version(),
        "numpy": package_version("numpy"),
        "pydicom": package_version("pydicom"),
        "nibabel": package_version("nibabel"),
        "scipy": package_version("scipy"),
        "TotalSegmentator": package_version("TotalSegmentator"),
        "torch": package_version("torch"),
    }


def base_provenance(**overrides: Any) -> dict[str, Any]:
    record: dict[str, Any] = {
        "pipeline_version": __version__,
        "git_commit": None,
        "input_study_uid": None,
        "selected_series_uid": None,
        "selected_temporal_frame": None,
        "modality": None,
        "acquisition_characterization": None,
        "source_dicom_count": 0,
        "prepared_volume_dimensions": None,
        "voxel_spacing": None,
        "affine": None,
        "segmentation_backend": None,
        "backend_version": None,
        "model_task": None,
        "model_options": {},
        "device": None,
        "execution_timestamp": utc_now(),
        "output_files": [],
        "software_versions": software_versions(),
        "warnings": [],
        "errors": [],
    }
    record.update(overrides)
    validate_provenance(record)
    return record


def validate_provenance(record: dict[str, Any]) -> None:
    missing = sorted(REQUIRED_FIELDS - record.keys())
    if missing:
        raise ValueError(f"provenance is missing required fields: {', '.join(missing)}")
    if not isinstance(record["warnings"], list) or not isinstance(record["errors"], list):
        raise ValueError("provenance warnings and errors must be lists")


def _json_default(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    if hasattr(value, "tolist"):
        return value.tolist()
    if hasattr(value, "item"):
        return value.item()
    raise TypeError(f"Object of type {value.__class__.__name__} is not JSON serializable")


def write_json(path: str | Path, value: Any) -> None:
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(value, default=_json_default, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def write_provenance(path: str | Path, record: dict[str, Any]) -> None:
    validate_provenance(record)
    write_json(path, record)
