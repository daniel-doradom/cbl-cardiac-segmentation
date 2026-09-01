"""Deliberately explicit MRI boundary for Milestone 1."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from vtseg.errors import BackendUnavailable
from vtseg.segmentation.base import BackendStatus, SegmentationBackend


class UnconfiguredMRIBackend(SegmentationBackend):
    def status(self) -> BackendStatus:
        return BackendStatus(
            name="unconfigured_mri",
            available=False,
            version=None,
            task=None,
            detail="No sequence-validated MRI LV/RV/myocardium backend is configured.",
            capabilities={},
        )

    def run(self, case_dir: Path, **options: Any) -> dict[str, Any]:
        raise BackendUnavailable(
            "MRI acquisition successfully prepared. No validated LV/RV/myocardium "
            "segmentation backend is configured. See docs/mri-backends.md."
        )
