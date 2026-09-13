"""Export canonical masks as a MATLAB meshing case (raw/ DICOMs + seg/ mask stacks).

The downstream MATLAB workflow builds its own ``seg/info.mat`` from ``raw/`` via
``readdata``, so this stage deliberately writes only the DICOM subset and the mask
stacks and leaves all geometry derivation to that validated code.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np
import pydicom

from vtseg.errors import NormalizationError
from vtseg.provenance import (
    base_provenance,
    git_commit,
    package_version,
    software_versions,
    utc_now,
    write_json,
    write_provenance,
)
from vtseg.segmentation.normalize import CANONICAL_MASKS

# MATLAB file/variable name -> how it is built from the canonical masks.
MATLAB_MASKS = {
    "Lendo": "lv_blood_pool",
    "Rendo": "rv_blood_pool",
    "myocardium": "myocardium",
    "Epi": None,  # union of the three canonical masks
}
EXPORT_MANIFEST = "vtseg_export_manifest.json"


def _base_to_apex_indices(epicardium: np.ndarray) -> tuple[list[int], str]:
    """Infer which end of a short-axis stack is basal from endpoint area.

    The biv-me-derived epicardial extent is larger at the basal end than at the
    apical end for the expected short-axis acquisition.  When the endpoints are
    indistinguishable, preserve prepared-volume order and require visual review.
    """
    areas = epicardium.sum(axis=(0, 1))
    nonempty = np.flatnonzero(areas)
    if nonempty.size == 0:
        raise NormalizationError("masks are empty; nothing to export")
    first, last = int(nonempty[0]), int(nonempty[-1])
    reference_order = list(range(epicardium.shape[2]))
    if areas[last] > areas[first]:
        return list(reversed(reference_order)), "reference_last_endpoint_larger"
    if areas[first] > areas[last]:
        return reference_order, "reference_first_endpoint_larger"
    return reference_order, "endpoint_areas_indistinguishable_reference_order_used"


def select_slice_indices(
    ordered_indices: list[int],
    *,
    start_slice: int = 1,
    end_slice: int | None = None,
    count: int | None = None,
) -> list[int]:
    """Select a range in the chosen order, always retaining its two endpoints."""
    total = len(ordered_indices)
    end_slice = total if end_slice is None else end_slice
    if start_slice < 1 or end_slice < start_slice or end_slice > total:
        raise NormalizationError(
            f"slice range must be within 1-{total} and start must not exceed end"
        )
    selected = ordered_indices[start_slice - 1 : end_slice]
    if count is None:
        return selected
    if count < 2:
        raise NormalizationError("at least two slices are required when --slices is used")
    if count > len(selected):
        raise NormalizationError("requested slice count exceeds the selected base-to-apex range")
    # Integer rounding distributes any unavoidable one-slice differences over
    # the stack while retaining both selected endpoints exactly.
    positions = np.rint(np.linspace(0, len(selected) - 1, count)).astype(int)
    return [selected[int(position)] for position in positions]


def preview_matlab_slices(
    mask_directory: str | Path,
    reference_directory: str | Path,
    *,
    slice_order: str = "base_to_apex",
) -> dict[str, Any]:
    """Describe the ordered positions without writing a MATLAB case.

    Reference z-indices are zero-based, while the positions accepted by
    ``export-matlab-seg`` are one-based.  DICOM filenames are deliberately not
    included: the preview is for choosing a geometric range before DICOM files
    are copied into an ignored MATLAB review case.
    """
    masks_path = Path(mask_directory).expanduser().resolve()
    reference = Path(reference_directory).expanduser().resolve()
    selection_path = reference / "source" / "selected_series.json"
    image_path = reference / "volume" / "image.nii.gz"
    if not selection_path.is_file() or not image_path.is_file():
        raise NormalizationError(f"reference is not a prepared case: {reference}")

    image = nib.load(str(image_path))
    volumes: dict[str, np.ndarray] = {}
    for name in CANONICAL_MASKS:
        path = masks_path / f"{name}.nii.gz"
        if not path.is_file():
            raise NormalizationError(f"missing canonical mask: {path}")
        mask = nib.load(str(path))
        if mask.shape != image.shape or not np.allclose(mask.affine, image.affine, atol=1e-4):
            raise NormalizationError(f"{name} does not share the reference geometry")
        volumes[name] = np.asanyarray(mask.dataobj) > 0

    epicardium = volumes["lv_blood_pool"] | volumes["rv_blood_pool"] | volumes["myocardium"]
    for first, second in (
        ("lv_blood_pool", "rv_blood_pool"),
        ("lv_blood_pool", "myocardium"),
        ("rv_blood_pool", "myocardium"),
    ):
        overlap = int(np.count_nonzero(volumes[first] & volumes[second]))
        if overlap:
            raise NormalizationError(f"{first} and {second} overlap in {overlap} voxels")

    base_to_apex, reason = _base_to_apex_indices(epicardium)
    if slice_order == "base_to_apex":
        ordered, order_reason = base_to_apex, reason
    elif slice_order == "reference":
        ordered, order_reason = list(range(image.shape[2])), "explicit_reference_order"
    elif slice_order == "reverse_reference":
        ordered, order_reason = list(reversed(range(image.shape[2]))), "explicit_reverse_reference_order"
    else:
        raise NormalizationError("slice order must be 'base_to_apex', 'reference', or 'reverse_reference'")

    slices = [
        {
            "position": position,
            "reference_z_index": index,
            "foreground_voxels": int(epicardium[:, :, index].sum()),
        }
        for position, index in enumerate(ordered, start=1)
    ]
    nonempty = [item["position"] for item in slices if item["foreground_voxels"] > 0]
    if not nonempty:
        raise NormalizationError("masks are empty; nothing to export")
    return {
        "slice_order": slice_order,
        "slice_order_reason": order_reason,
        "total_positions": len(slices),
        "suggested_start_slice": nonempty[0],
        "suggested_end_slice": nonempty[-1],
        "slices": slices,
    }


def export_matlab_case(
    mask_directory: str | Path,
    reference_directory: str | Path,
    output_directory: str | Path,
    *,
    slices: int | None = None,
    start_slice: int = 1,
    end_slice: int | None = None,
    slice_order: str = "base_to_apex",
    slicer_approved: bool = False,
    repo_root: str | Path | None = None,
) -> dict[str, Any]:
    masks_path = Path(mask_directory).expanduser().resolve()
    reference = Path(reference_directory).expanduser().resolve()
    output = Path(output_directory).expanduser().resolve()
    if not slicer_approved:
        raise NormalizationError(
            "MATLAB export requires completed 3D Slicer review; rerun with --slicer-approved"
        )
    if output.exists():
        raise NormalizationError(f"refusing to overwrite existing MATLAB case: {output}")

    selection_path = reference / "source" / "selected_series.json"
    image_path = reference / "volume" / "image.nii.gz"
    if not selection_path.is_file() or not image_path.is_file():
        raise NormalizationError(f"reference is not a prepared case: {reference}")
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    modality = selection.get("series_characterization", {}).get("modality")
    if modality not in {"CT", "MR"}:
        raise NormalizationError(f"MATLAB export requires CT or MR reference data, got {modality!r}")
    instance_paths = [Path(p) for p in selection["selected_instance_paths"]]

    image = nib.load(str(image_path))
    volumes: dict[str, np.ndarray] = {}
    for name in CANONICAL_MASKS:
        path = masks_path / f"{name}.nii.gz"
        if not path.is_file():
            raise NormalizationError(f"missing canonical mask: {path}")
        mask = nib.load(str(path))
        if mask.shape != image.shape or not np.allclose(mask.affine, image.affine, atol=1e-4):
            raise NormalizationError(f"{name} does not share the reference geometry")
        volumes[name] = np.asanyarray(mask.dataobj) > 0
    if len(instance_paths) != image.shape[2]:
        raise NormalizationError("prepared volume and selected instance list disagree")

    epicardium = volumes["lv_blood_pool"] | volumes["rv_blood_pool"] | volumes["myocardium"]
    for first, second in (
        ("lv_blood_pool", "rv_blood_pool"),
        ("lv_blood_pool", "myocardium"),
        ("rv_blood_pool", "myocardium"),
    ):
        overlap = int(np.count_nonzero(volumes[first] & volumes[second]))
        if overlap:
            raise NormalizationError(f"{first} and {second} overlap in {overlap} voxels")

    base_to_apex, base_to_apex_reason = _base_to_apex_indices(epicardium)
    base_to_apex_positions = {index: position + 1 for position, index in enumerate(base_to_apex)}
    if slice_order == "base_to_apex":
        ordered, order_reason = base_to_apex, base_to_apex_reason
    elif slice_order == "reference":
        ordered, order_reason = list(range(image.shape[2])), "explicit_reference_order"
    elif slice_order == "reverse_reference":
        ordered, order_reason = list(reversed(range(image.shape[2]))), "explicit_reverse_reference_order"
        base_to_apex_positions = {index: position + 1 for position, index in enumerate(ordered)}
    else:
        raise NormalizationError("slice order must be 'base_to_apex', 'reference', or 'reverse_reference'")
    indices = select_slice_indices(
        ordered,
        start_slice=start_slice,
        end_slice=end_slice,
        count=slices,
    )
    slice_selection = "all_selected_range_slices" if slices is None else "evenly_spaced_selected_range"
    slicer_approval_time = utc_now()

    # MATLAB reads raw/ in lexical file-name order.  Give each copied source a
    # generated, zero-padded name so that this order is exactly NIfTI's z-index
    # order, independent of the original export's filenames or InstanceNumber.
    ordered = indices

    raw_dir = output / "raw"
    seg_dir = output / "seg"
    for directory in (
        raw_dir, seg_dir, output / "mesh", output / "remesh", output / "global", output / "visualizations"
    ):
        directory.mkdir(parents=True)
    if output.name == "matlab":
        (output.parent / "slicer").mkdir(exist_ok=True)

    # MATLAB's readdata globs strcat(path,'*.dcm') and is case-sensitive on Linux, so the
    # extension is mandatory; appending it to a zero-padded stem preserves dir()'s name sort.
    names = [f"slice_{position + 1:04d}.dcm" for position in range(len(ordered))]
    for index, name in zip(ordered, names):
        shutil.copy2(instance_paths[index], raw_dir / name)

    source_slice_metadata = []
    for index in ordered:
        dataset = pydicom.dcmread(str(instance_paths[index]), stop_before_pixels=True)
        position = getattr(dataset, "ImagePositionPatient", None)
        source_slice_metadata.append({
            "source_dicom_filename": instance_paths[index].name,
            "source_dicom_path": str(instance_paths[index]),
            "image_position_patient": [float(value) for value in position] if position is not None else None,
        })

    try:
        from scipy.io import savemat
    except ImportError as exc:
        raise NormalizationError("SciPy is required for MATLAB mask export") from exc

    stacks = {
        "Lendo": volumes["lv_blood_pool"],
        "Rendo": volumes["rv_blood_pool"],
        "myocardium": volumes["myocardium"],
        "Epi": epicardium,
    }
    written = {}
    for label, volume in stacks.items():
        stack = np.ascontiguousarray(volume[:, :, ordered])
        savemat(str(seg_dir / f"{label}.mat"), {label: stack}, do_compression=True)
        written[label] = [int(stack[:, :, k].sum()) for k in range(stack.shape[2])]

    manifest = {
        "schema_version": 1,
        "mask_source": str(masks_path),
        "reference_case": str(reference),
        "series_uid": selection["series_uid"],
        "slice_count": len(ordered),
        "slice_selection": slice_selection,
        "slice_order": slice_order,
        "slice_order_reason": order_reason,
        "slicer_review": {
            "approved": True,
            "approval_recorded_at": slicer_approval_time,
        },
        "start_slice_base_to_apex": start_slice,
        "end_slice_base_to_apex": end_slice if end_slice is not None else image.shape[2],
        "reference_index_steps": [
            abs(int(ordered[index + 1]) - int(ordered[index]))
            for index in range(len(ordered) - 1)
        ],
        "matlab_variable_names": {name: name for name in stacks},
        "mask_dimensions": [int(image.shape[0]), int(image.shape[1]), len(ordered)],
        "slices": [
            {
                "matlab_index": position + 1,
                "dicom_file": names[position],
                "reference_volume_index": int(index),
                "base_to_apex_reference_slice": base_to_apex_positions[int(index)],
                **source_slice_metadata[position],
                "epi_voxels": written["Epi"][position],
                "lendo_voxels": written["Lendo"][position],
                "rendo_voxels": written["Rendo"][position],
            }
            for position, index in enumerate(ordered)
        ],
    }
    manifest["modality"] = modality
    write_json(seg_dir / EXPORT_MANIFEST, manifest)
    write_json(output / "manifest.json", manifest)

    provenance = base_provenance(
        git_commit=git_commit(repo_root) if repo_root else None,
        input_study_uid=selection["study_uid"],
        selected_series_uid=selection["series_uid"],
        selected_temporal_frame=selection.get("selected_temporal_frame"),
        modality=modality,
        source_dicom_count=len(ordered),
        prepared_volume_dimensions=manifest["mask_dimensions"],
        voxel_spacing=list(image.header.get_zooms()[:3]),
        affine=image.affine.tolist(),
        segmentation_backend="matlab-meshing-export",
        model_task="canonical_masks_to_matlab_seg_case",
        model_options={
            "mask_source": str(masks_path),
            "slice_selection": slice_selection,
            "slice_order": slice_order,
            "slice_order_reason": order_reason,
            "matlab_stack_order": "zero-padded generated raw file names match NIfTI z-index order",
            "matlab_geometry": "per-slice DICOM positions; supports nonuniform selected spacing",
            "info_mat": "not written; generate with readdata(raw_path, seg_path)",
            "slicer_review": {
                "approved": True,
                "approval_recorded_at": slicer_approval_time,
            },
        },
        device="cpu",
        output_files=[str(Path("raw") / name) for name in names]
        + [str(Path("seg") / f"{label}.mat") for label in stacks],
        software_versions={**software_versions(), "scipy": package_version("scipy")},
        warnings=[
            "MATLAB mask stacks assume readdata orders raw/ by file name; verify against "
            f"seg/{EXPORT_MANIFEST} before meshing",
            "selected endpoints are always retained; intermediate selected slices can differ by one "
            "reference slice and MATLAB uses their actual DICOM positions",
            "base-to-apex ordering is inferred from endpoint epicardial area; visually confirm "
            "the first and last exported slices before manual correction",
            "masks are model-derived, not manual contours; review them before meshing",
        ],
    )
    write_provenance(output / "provenance.json", provenance)
    return manifest
