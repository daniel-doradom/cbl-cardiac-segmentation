"""Strict CT mask mapping and explicit promotion for short-axis MPR review."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to

from vtseg.errors import GeometryError, NormalizationError, SeriesSelectionError
from vtseg.provenance import base_provenance, git_commit, software_versions, utc_now, write_json, write_provenance
from vtseg.qc.masks import run_backend_qc
from vtseg.segmentation.normalize import CANONICAL_MASKS, write_combined_labels


def _selection(case: Path) -> dict[str, Any]:
    path = case / "source" / "selected_series.json"
    if not path.is_file():
        raise SeriesSelectionError(f"prepared case lacks selected-series metadata: {case}")
    selection = json.loads(path.read_text(encoding="utf-8"))
    if selection.get("series_characterization", {}).get("modality") != "CT":
        raise SeriesSelectionError(f"CT MPR mapping requires CT cases: {case}")
    return selection


def _validate_shared_frame(native: dict[str, Any], mpr: dict[str, Any]) -> None:
    native_for = native.get("frame_of_reference_uid")
    mpr_for = mpr.get("frame_of_reference_uid")
    if not native_for or not mpr_for:
        raise GeometryError("native CT and MPR must both declare FrameOfReferenceUID; refusing to register")
    if native_for != mpr_for:
        raise GeometryError("native CT and MPR FrameOfReferenceUID values differ; refusing to register")
    if native.get("study_uid") != mpr.get("study_uid"):
        raise GeometryError("native CT and MPR StudyInstanceUID values differ; refusing to register")


def map_native_ct_masks_to_mpr(
    native_case_directory: str | Path,
    mpr_case_directory: str | Path,
    *,
    repo_root: str | Path | None = None,
) -> dict[str, Any]:
    """Resample canonical native-CT masks onto an approved CT MPR grid.

    This is deliberately a resample-only operation: the native volume/masks are
    untouched, no registration is estimated, and masks use nearest-neighbor
    interpolation to retain categorical labels.
    """
    native_case = Path(native_case_directory).expanduser().resolve()
    mpr_case = Path(mpr_case_directory).expanduser().resolve()
    native_selection, mpr_selection = _selection(native_case), _selection(mpr_case)
    _validate_shared_frame(native_selection, mpr_selection)

    native_image_path = native_case / "volume" / "image.nii.gz"
    target_image_path = mpr_case / "volume" / "image.nii.gz"
    source_masks = native_case / "segmentation" / "totalsegmentator" / "normalized"
    destination_root = mpr_case / "segmentation" / "native_ct_mapped"
    destination = destination_root / "normalized"
    if destination_root.exists():
        raise NormalizationError(f"refusing to overwrite native CT mapped output: {destination_root}")
    if not native_image_path.is_file() or not target_image_path.is_file():
        raise SeriesSelectionError("native CT and MPR cases must both have a prepared volume")

    native_image = nib.load(str(native_image_path))
    target_image = nib.load(str(target_image_path))
    destination.mkdir(parents=True)
    for name in CANONICAL_MASKS:
        source_path = source_masks / f"{name}.nii.gz"
        if not source_path.is_file():
            raise NormalizationError(f"native CT result lacks canonical mask: {source_path}")
        source = nib.load(str(source_path))
        if source.shape != native_image.shape or not np.allclose(source.affine, native_image.affine, atol=1e-4):
            raise GeometryError(f"native canonical mask does not share native CT geometry: {name}")
        mapped = resample_from_to(source, (target_image.shape, target_image.affine), order=0)
        values = np.asarray(mapped.dataobj) > 0
        output = nib.Nifti1Image(values.astype(np.uint8), target_image.affine, target_image.header.copy())
        output.set_data_dtype(np.uint8)
        output.set_qform(target_image.affine, code=1)
        output.set_sform(target_image.affine, code=1)
        nib.save(output, destination / f"{name}.nii.gz")
    combined = write_combined_labels(target_image_path, destination)
    qc_path = destination_root / "qc" / "mask_qc.json"
    qc = run_backend_qc(mpr_case, normalized_directory=destination, report_path=qc_path)
    provenance = base_provenance(
        git_commit=git_commit(repo_root) if repo_root else None,
        input_study_uid=mpr_selection["study_uid"], selected_series_uid=mpr_selection["series_uid"],
        selected_temporal_frame=mpr_selection.get("selected_temporal_frame"), modality="CT",
        source_dicom_count=mpr_selection["selected_instance_count"],
        prepared_volume_dimensions=list(target_image.shape), voxel_spacing=list(target_image.header.get_zooms()[:3]),
        affine=target_image.affine.tolist(), segmentation_backend="native_ct_to_mpr_mapping",
        model_task="nearest_neighbor_canonical_mask_resample", model_options={
            "native_case": str(native_case), "native_series_uid": native_selection["series_uid"],
            "frame_of_reference_uid": mpr_selection["frame_of_reference_uid"], "interpolation": "nearest_neighbor",
        }, device="cpu", output_files=[str(path.relative_to(mpr_case)) for path in [
            *(destination / f"{name}.nii.gz" for name in CANONICAL_MASKS), combined, qc_path
        ]], software_versions=software_versions(), warnings=qc.get("warnings", []),
    )
    write_provenance(destination_root / "provenance.json", provenance)
    write_json(destination_root / "segmentation_metadata.json", {
        "status": "complete", "backend": "native_ct_to_mpr_mapping", "interpolation": "nearest_neighbor",
        "source_case": str(native_case), "normalized_outputs": [f"{name}.nii.gz" for name in (*CANONICAL_MASKS, "combined_labels")],
        "timestamp": utc_now(),
    })
    return provenance


def promote_ct_candidate(
    mpr_case_directory: str | Path,
    candidate: str,
    output_directory: str | Path,
    *,
    repo_root: str | Path | None = None,
) -> dict[str, Any]:
    """Create an immutable MATLAB-ready best CT case after Slicer selection."""
    mpr_case = Path(mpr_case_directory).expanduser().resolve()
    output = Path(output_directory).expanduser().resolve()
    selection = _selection(mpr_case)
    if output.exists():
        raise NormalizationError(f"refusing to overwrite promoted CT result: {output}")
    choices = {
        "direct-mpr": mpr_case / "segmentation" / "totalsegmentator" / "normalized",
        "native-mapped": mpr_case / "segmentation" / "native_ct_mapped" / "normalized",
    }
    if candidate not in choices:
        raise NormalizationError("candidate must be 'direct-mpr' or 'native-mapped'")
    source = choices[candidate]
    required = [source / f"{name}.nii.gz" for name in (*CANONICAL_MASKS, "combined_labels")]
    if not all(path.is_file() for path in required):
        raise NormalizationError(f"selected CT candidate is incomplete: {source}")
    output.mkdir(parents=True)
    shutil.copytree(mpr_case / "source", output / "source")
    shutil.copytree(mpr_case / "volume", output / "volume")
    selected = output / "segmentation" / "selected" / "normalized"
    selected.mkdir(parents=True)
    for path in required:
        shutil.copy2(path, selected / path.name)
    qc_path = output / "segmentation" / "selected" / "qc" / "mask_qc.json"
    qc = run_backend_qc(output, normalized_directory=selected, report_path=qc_path)
    promoted_image = nib.load(str(output / "volume" / "image.nii.gz"))
    promoted_outputs = [selected / path.name for path in required]
    provenance = base_provenance(
        git_commit=git_commit(repo_root) if repo_root else None,
        input_study_uid=selection["study_uid"], selected_series_uid=selection["series_uid"],
        selected_temporal_frame=selection.get("selected_temporal_frame"), modality="CT",
        source_dicom_count=selection["selected_instance_count"],
        prepared_volume_dimensions=list(promoted_image.shape),
        voxel_spacing=list(promoted_image.header.get_zooms()[:3]), affine=promoted_image.affine.tolist(),
        segmentation_backend="manual_ct_candidate_selection", model_task="slicer_review_promotion",
        model_options={"candidate": candidate, "source_mpr_case": str(mpr_case), "source_masks": str(source)}, device="cpu",
        output_files=[str(path.relative_to(output)) for path in [*promoted_outputs, qc_path]],
        software_versions=software_versions(), warnings=qc.get("warnings", []) + ["candidate selected manually after 3D Slicer review"],
    )
    write_provenance(output / "segmentation" / "selected" / "provenance.json", provenance)
    write_json(output / "segmentation" / "selected" / "selection.json", {
        "schema_version": 1, "candidate": candidate, "source_mpr_case": str(mpr_case),
        "source_masks": str(source), "selected_at": utc_now(), "review_required": True,
    })
    return provenance
