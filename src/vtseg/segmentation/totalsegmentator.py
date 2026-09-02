"""CT-only TotalSegmentator ``heartchambers_highres`` adapter."""

from __future__ import annotations

import importlib.metadata
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

import nibabel as nib

from vtseg.errors import BackendUnavailable, SeriesSelectionError
from vtseg.provenance import base_provenance, git_commit, software_versions, utc_now, write_json, write_provenance
from vtseg.qc.masks import run_backend_qc
from vtseg.segmentation.base import BackendStatus, SegmentationBackend
from vtseg.segmentation.normalize import TOTALSEGMENTATOR_CT_MAPPING, normalize_masks

TASK = "heartchambers_highres"
EXPECTED_CLASSES = {
    "heart_myocardium",
    "heart_ventricle_left",
    "heart_ventricle_right",
}


def _version() -> str | None:
    try:
        return importlib.metadata.version("TotalSegmentator")
    except importlib.metadata.PackageNotFoundError:
        return None


class TotalSegmentatorCTBackend(SegmentationBackend):
    def status(self) -> BackendStatus:
        executable = shutil.which("TotalSegmentator")
        info_executable = shutil.which("totalseg_info")
        version = _version()
        if not executable:
            return BackendStatus(
                name="TotalSegmentator",
                available=False,
                version=version,
                task=TASK,
                detail=(
                    "TotalSegmentator CLI is not installed in this environment. Install the pinned "
                    "optional 'ct' dependency in a supported Python environment."
                ),
                capabilities={},
            )

        capabilities: dict[str, Any] = {}
        if info_executable:
            try:
                result = subprocess.run(
                    [info_executable, "--json"], check=True, capture_output=True, text=True, timeout=30
                )
                registry = json.loads(result.stdout)
                capabilities = registry.get("tasks", {}).get(TASK, {})
            except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
                return BackendStatus(
                    "TotalSegmentator", False, version, TASK,
                    f"task registry discovery failed: {type(exc).__name__}", {},
                )
            classes = set(capabilities.get("classes", {}).values())
            if not EXPECTED_CLASSES <= classes:
                return BackendStatus(
                    "TotalSegmentator", False, version, TASK,
                    "installed task registry does not contain required cardiac classes", capabilities,
                )
        return BackendStatus(
            name="TotalSegmentator",
            available=True,
            version=version,
            task=TASK,
            detail=(
                "CLI and task are discoverable. The task requires a separately configured "
                "TotalSegmentator license and model weights."
            ),
            capabilities=capabilities,
        )

    def run(
        self,
        case_dir: Path,
        *,
        device: str = "gpu",
        higher_order_resampling: bool = False,
        force_split: bool = False,
        repo_root: Path | None = None,
    ) -> dict[str, Any]:
        case_dir = case_dir.resolve()
        image_path = case_dir / "volume" / "image.nii.gz"
        selection_path = case_dir / "source" / "selected_series.json"
        if not image_path.is_file() or not selection_path.is_file():
            raise SeriesSelectionError("case is not prepared: missing volume or selected-series metadata")
        selection = json.loads(selection_path.read_text(encoding="utf-8"))
        summary = selection["series_characterization"]
        if summary.get("modality") != "CT":
            raise SeriesSelectionError(
                f"TotalSegmentator CT adapter refuses modality {summary.get('modality')!r}"
            )

        status = self.status()
        backend_dir = case_dir / "segmentation" / "totalsegmentator"
        metadata_path = backend_dir / "segmentation_metadata.json"
        if not status.available:
            payload = {
                "status": "blocked",
                "backend": status.name,
                "backend_version": status.version,
                "task": TASK,
                "message": status.detail,
                "timestamp": utc_now(),
            }
            write_json(metadata_path, payload)
            raise BackendUnavailable(status.detail)

        normalized_dir = backend_dir / "normalized"
        if any(normalized_dir.glob("*.nii.gz")):
            raise BackendUnavailable(f"refusing to overwrite normalized masks in {normalized_dir}")
        raw_dir = backend_dir / "raw"
        raw_dir.mkdir(parents=True, exist_ok=True)
        report_path = raw_dir / "totalsegmentator_report.json"
        command = [
            shutil.which("TotalSegmentator") or "TotalSegmentator",
            "-i", str(image_path),
            "-o", str(raw_dir),
            "-ta", TASK,
            "--device", device,
            "--report", str(report_path),
        ]
        if higher_order_resampling:
            command.append("--higher_order_resampling")
        if force_split:
            command.append("--force_split")

        result = subprocess.run(command, capture_output=True, text=True)
        (raw_dir / "execution.log").write_text(
            result.stdout + "\n--- STDERR ---\n" + result.stderr, encoding="utf-8"
        )
        if result.returncode != 0:
            lower = (result.stdout + result.stderr).lower()
            cause = "TotalSegmentator inference failed"
            if "license" in lower:
                cause = (
                    "heartchambers_highres requires a valid TotalSegmentator license; configure it "
                    "with totalseg_set_license before retrying"
                )
            elif "weight" in lower or "download" in lower:
                cause = "TotalSegmentator model weights are unavailable or could not be downloaded"
            payload = {
                "status": "failed", "backend": status.name, "backend_version": status.version,
                "task": TASK, "device": device, "message": cause, "return_code": result.returncode,
                "timestamp": utc_now(),
            }
            write_json(metadata_path, payload)
            raise BackendUnavailable(cause)

        outputs = normalize_masks(
            image_path, raw_dir, normalized_dir, TOTALSEGMENTATOR_CT_MAPPING
        )
        qc_path = backend_dir / "qc" / "mask_qc.json"
        qc = run_backend_qc(case_dir, normalized_directory=normalized_dir, report_path=qc_path)
        image = nib.load(str(image_path))
        provenance = base_provenance(
            git_commit=git_commit(repo_root) if repo_root else None,
            input_study_uid=selection["study_uid"],
            selected_series_uid=selection["series_uid"],
            selected_temporal_frame=selection["selected_temporal_frame"],
            modality="CT",
            acquisition_characterization={
                "acquisition_type": summary.get("acquisition_type"),
                "series_description": summary.get("series_description"),
                "protocol_name": summary.get("protocol_name"),
            },
            source_dicom_count=selection["selected_instance_count"],
            prepared_volume_dimensions=list(image.shape),
            voxel_spacing=list(image.header.get_zooms()[:3]),
            affine=image.affine.tolist(),
            segmentation_backend="TotalSegmentator",
            backend_version=status.version,
            model_task=TASK,
            model_options={
                "higher_order_resampling": higher_order_resampling,
                "force_split": force_split,
            },
            device=device,
            output_files=[
                str(Path(path).relative_to(case_dir)) for path in outputs.values()
            ] + [str(qc_path.relative_to(case_dir))],
            software_versions=software_versions(),
            warnings=qc.get("warnings", []),
        )
        write_provenance(backend_dir / "provenance.json", provenance)
        metadata = {
            "status": "complete",
            "backend": "TotalSegmentator",
            "backend_version": status.version,
            "task": TASK,
            "device": device,
            "mapping": TOTALSEGMENTATOR_CT_MAPPING,
            "raw_outputs_preserved": True,
            "normalized_outputs": outputs,
            "timestamp": utc_now(),
        }
        write_json(metadata_path, metadata)
        return provenance
