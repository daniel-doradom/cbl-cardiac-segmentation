"""Geometry and topology warnings for canonical masks; not clinical validation."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np
from scipy import ndimage

from vtseg.dicom.geometry import geometry_compatible
from vtseg.provenance import write_json
from vtseg.segmentation.normalize import CANONICAL_MASKS


def mask_statistics(data: np.ndarray, affine: np.ndarray) -> dict[str, Any]:
    binary = np.asarray(data) > 0
    voxel_count = int(np.count_nonzero(binary))
    voxel_volume_mm3 = float(abs(np.linalg.det(np.asarray(affine)[:3, :3])))
    structure = ndimage.generate_binary_structure(binary.ndim, 1)
    labels, component_count = ndimage.label(binary, structure=structure)
    if component_count:
        sizes = np.bincount(labels.ravel())[1:]
        largest = int(sizes.max())
        largest_fraction = float(largest / voxel_count)
        indices = np.argwhere(binary)
        bounding_box = {
            "min": indices.min(axis=0).astype(int).tolist(),
            "max": indices.max(axis=0).astype(int).tolist(),
        }
    else:
        largest = 0
        largest_fraction = 0.0
        bounding_box = None

    touches_border = False
    touched_faces: list[str] = []
    if voxel_count:
        for axis in range(binary.ndim):
            low = np.take(binary, 0, axis=axis)
            high = np.take(binary, binary.shape[axis] - 1, axis=axis)
            if np.any(low):
                touches_border = True
                touched_faces.append(f"axis_{axis}_min")
            if np.any(high):
                touches_border = True
                touched_faces.append(f"axis_{axis}_max")
    return {
        "array_dimensions": list(binary.shape),
        "voxel_spacing_mm": [float(np.linalg.norm(np.asarray(affine)[:3, i])) for i in range(3)],
        "physical_voxel_volume_mm3": voxel_volume_mm3,
        "mask_voxel_count": voxel_count,
        "mask_physical_volume_ml": float(voxel_count * voxel_volume_mm3 / 1000.0),
        "connected_components": int(component_count),
        "largest_component_voxels": largest,
        "largest_component_fraction": largest_fraction,
        "empty": voxel_count == 0,
        "touches_image_border": touches_border,
        "touched_border_faces": touched_faces,
        "bounding_box_voxels_inclusive": bounding_box,
    }


def _overlap(a: np.ndarray, b: np.ndarray) -> dict[str, float | int | bool]:
    a = np.asarray(a) > 0
    b = np.asarray(b) > 0
    count_a = int(a.sum())
    count_b = int(b.sum())
    intersection = int(np.logical_and(a, b).sum())
    denominator = count_a + count_b
    smaller = min(count_a, count_b)
    return {
        "intersection_voxels": intersection,
        "dice": float(2 * intersection / denominator) if denominator else 0.0,
        "fraction_of_smaller_mask_overlapped": float(intersection / smaller) if smaller else 0.0,
        "identical": bool(np.array_equal(a, b)),
    }


def evaluate_masks(source_path: str | Path, masks: dict[str, str | Path]) -> dict[str, Any]:
    source = nib.load(str(source_path))
    report: dict[str, Any] = {
        "schema_version": 1,
        "purpose": "research QC flags; not clinical validation",
        "source_image": str(source_path),
        "masks": {},
        "cross_mask_checks": {},
        "warnings": [],
    }
    arrays: dict[str, np.ndarray] = {}
    for name in CANONICAL_MASKS:
        path = masks.get(name)
        if path is None or not Path(path).is_file():
            report["warnings"].append(f"missing canonical mask: {name}")
            continue
        image = nib.load(str(path))
        data = np.asanyarray(image.dataobj)
        arrays[name] = data > 0
        stats = mask_statistics(data, image.affine)
        stats["file"] = str(path)
        stats["geometry_matches_source"] = geometry_compatible(
            source.shape, source.affine, image.shape, image.affine
        )
        if not stats["geometry_matches_source"]:
            report["warnings"].append(f"{name} geometry/affine does not match source image")
        if stats["empty"]:
            report["warnings"].append(f"{name} is empty")
        if stats["touches_image_border"]:
            report["warnings"].append(f"{name} touches an image border")
        if stats["connected_components"] > 1:
            report["warnings"].append(
                f"{name} has {stats['connected_components']} connected components"
            )
        report["masks"][name] = stats

    if "lv_blood_pool" in arrays and "rv_blood_pool" in arrays:
        overlap = _overlap(arrays["lv_blood_pool"], arrays["rv_blood_pool"])
        report["cross_mask_checks"]["lv_vs_rv"] = overlap
        if overlap["identical"]:
            report["warnings"].append("LV and RV masks are identical")
        # A technical warning threshold, not an anatomical acceptance criterion.
        if overlap["fraction_of_smaller_mask_overlapped"] >= 0.95:
            report["warnings"].append(
                "LV/RV overlap covers at least 95% of the smaller mask; review required"
            )

    present = list(report["masks"].values())
    report["cross_mask_checks"]["all_present_dimensions_identical"] = len(
        {tuple(item["array_dimensions"]) for item in present}
    ) <= 1
    report["cross_mask_checks"]["all_present_voxel_spacings_identical"] = len(
        {tuple(round(v, 6) for v in item["voxel_spacing_mm"]) for item in present}
    ) <= 1
    if not report["cross_mask_checks"]["all_present_dimensions_identical"]:
        report["warnings"].append("canonical mask dimensions differ")
    if not report["cross_mask_checks"]["all_present_voxel_spacings_identical"]:
        report["warnings"].append("canonical mask voxel spacings differ")
    report["warnings"] = sorted(set(report["warnings"]))
    return report


def run_case_qc(case_dir: str | Path) -> dict[str, Any]:
    case = Path(case_dir).resolve()
    normalized = case / "segmentation" / "normalized"
    masks = {name: normalized / f"{name}.nii.gz" for name in CANONICAL_MASKS}
    report = evaluate_masks(case / "volume" / "image.nii.gz", masks)
    report["source_image"] = "volume/image.nii.gz"
    for value in report["masks"].values():
        value["file"] = str(Path(value["file"]).relative_to(case))
    write_json(case / "qc" / "mask_qc.json", report)
    return report
