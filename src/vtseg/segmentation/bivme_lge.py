"""Align fitted biv-me cine meshes to a native LGE/MDE reference grid."""

from __future__ import annotations

import importlib.util
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np
import pydicom

from vtseg.dicom.convert import prepare_series
from vtseg.dicom.series import Inventory, scan_headers, summarize_series
from vtseg.dicom.temporal import analyze_temporal, select_frame
from vtseg.errors import RegistrationError, SeriesSelectionError
from vtseg.provenance import (
    base_provenance,
    git_commit,
    package_version,
    software_versions,
    utc_now,
    write_json,
    write_provenance,
)
from vtseg.qc.masks import evaluate_masks
from vtseg.segmentation.bivme_rasterize import rasterize
from vtseg.segmentation.normalize import CANONICAL_MASKS

CASE_ALIAS = "case"
MESH_NAMES = {
    "lv": "LV_ENDOCARDIAL",
    "rv": "RV_ENDOCARDIAL",
    "epicardial": "EPICARDIAL",
}


def _series_groups(inventory: Inventory) -> dict[str, list[Any]]:
    groups: dict[str, list[Any]] = defaultdict(list)
    for record in inventory.instances:
        groups[record.series_uid].append(record)
    return dict(groups)


def select_lge_series(
    inventory: Inventory,
    *,
    study_uid: str,
    explicit_series_uid: str | None = None,
) -> tuple[str, dict[str, Any]]:
    groups = _series_groups(inventory)
    if explicit_series_uid is not None:
        records = groups.get(explicit_series_uid)
        if not records:
            raise SeriesSelectionError("selected LGE series is not present in the DICOM input")
        summary = summarize_series(records)
        if records[0].study_uid != study_uid:
            raise SeriesSelectionError("selected LGE series is not in the cine DICOM study")
        if summary["modality"] != "MR" or summary["acquisition_type"] != "lge_mde":
            raise SeriesSelectionError("selected LGE series is not characterized as MR LGE/MDE")
        return explicit_series_uid, summary

    candidates: list[tuple[str, dict[str, Any]]] = []
    for uid, records in groups.items():
        if records[0].study_uid != study_uid:
            continue
        summary = summarize_series(records)
        if summary["modality"] != "MR" or summary["acquisition_type"] != "lge_mde":
            continue
        if not summary["orientation_consistent"] or not summary["slice_spacing_regular"]:
            continue
        if summary["unique_spatial_positions"] < 2:
            continue
        candidates.append((uid, summary))
    if not candidates:
        raise SeriesSelectionError("no regular multi-slice LGE/MDE series was found in the cine study")
    candidates.sort(
        key=lambda item: (
            int(item[1]["unique_spatial_positions"]),
            float(item[1].get("spatial_coverage_mm") or 0.0),
        ),
        reverse=True,
    )
    if len(candidates) > 1:
        first = candidates[0][1]
        second = candidates[1][1]
        first_score = (first["unique_spatial_positions"], first.get("spatial_coverage_mm"))
        second_score = (second["unique_spatial_positions"], second.get("spatial_coverage_mm"))
        if first_score == second_score:
            raise SeriesSelectionError(
                "multiple equally ranked LGE/MDE series were found; select one explicitly"
            )
    return candidates[0]


def _median_trigger(records: list[Any]) -> float | None:
    values = []
    for record in records:
        try:
            values.append(float(record.dataset.TriggerTime))
        except (AttributeError, TypeError, ValueError):
            pass
    return float(np.median(values)) if values else None


def match_cine_frame(
    cine_records: list[Any],
    lge_records: list[Any],
    *,
    explicit_frame: int | None = None,
) -> dict[str, Any]:
    datasets = [record.dataset for record in cine_records]
    temporal = analyze_temporal(datasets)
    if not temporal.defensible or temporal.inferred_frames is None:
        raise SeriesSelectionError("cine temporal phases cannot be inferred defensibly")
    if explicit_frame is not None:
        _, selection = select_frame(datasets, explicit_frame)
        return {
            "frame": explicit_frame,
            "cine_temporal_key": selection.get("temporal_key"),
            "cine_temporal_value": selection.get("temporal_value"),
            "lge_trigger_time_ms": _median_trigger(lge_records),
            "timing_difference_ms": None,
            "selection_method": "explicit",
        }

    lge_trigger = _median_trigger(lge_records)
    selections = [select_frame(datasets, index)[1] for index in range(temporal.inferred_frames)]
    if temporal.temporal_key == "TriggerTime" and lge_trigger is not None:
        frame = min(
            range(len(selections)),
            key=lambda index: abs(float(selections[index]["temporal_value"]) - lge_trigger),
        )
        cine_value = float(selections[frame]["temporal_value"])
        return {
            "frame": frame,
            "cine_temporal_key": temporal.temporal_key,
            "cine_temporal_value": cine_value,
            "lge_trigger_time_ms": lge_trigger,
            "timing_difference_ms": abs(cine_value - lge_trigger),
            "selection_method": "nearest_trigger_time",
        }
    return {
        "frame": 0,
        "cine_temporal_key": temporal.temporal_key,
        "cine_temporal_value": selections[0].get("temporal_value"),
        "lge_trigger_time_ms": lge_trigger,
        "timing_difference_ms": None,
        "selection_method": "fallback_first_phase",
    }


def _frame_of_reference(record: Any) -> str | None:
    dataset = pydicom.dcmread(record.path, stop_before_pixels=True)
    value = getattr(dataset, "FrameOfReferenceUID", None)
    return str(value) if value else None


def _mask_union(mask_directory: Path, sitk: Any) -> Any:
    images = [
        sitk.Cast(sitk.ReadImage(str(mask_directory / f"{name}.nii.gz")) > 0, sitk.sitkUInt8)
        for name in CANONICAL_MASKS
    ]
    union = images[0]
    for image in images[1:]:
        union = sitk.Or(union, image)
    spacing = union.GetSpacing()
    radius = [max(1, int(round(20.0 / value))) for value in spacing]
    dilate = sitk.BinaryDilateImageFilter()
    dilate.SetKernelRadius(radius)
    dilate.SetForegroundValue(1)
    return dilate.Execute(union)


def _identity_rigid(fixed: Any, sitk: Any) -> Any:
    center_index = [(size - 1) / 2.0 for size in fixed.GetSize()]
    center = fixed.TransformContinuousIndexToPhysicalPoint(center_index)
    transform = sitk.Euler3DTransform()
    transform.SetCenter(center)
    return transform


def _registration_method(sitk: Any, initial: Any, *, use_masks: bool, fixed_mask: Any, moving_mask: Any) -> Any:
    method = sitk.ImageRegistrationMethod()
    method.SetMetricAsMattesMutualInformation(numberOfHistogramBins=50)
    method.SetMetricSamplingStrategy(method.RANDOM)
    method.SetMetricSamplingPercentage(0.2, 20260901)
    if use_masks:
        method.SetMetricFixedMask(fixed_mask)
        method.SetMetricMovingMask(moving_mask)
    method.SetInterpolator(sitk.sitkLinear)
    method.SetOptimizerAsRegularStepGradientDescent(
        learningRate=1.0,
        minStep=1e-4,
        numberOfIterations=250,
        relaxationFactor=0.5,
        gradientMagnitudeTolerance=1e-8,
    )
    method.SetOptimizerScalesFromPhysicalShift()
    method.SetShrinkFactorsPerLevel([4, 2, 1])
    method.SetSmoothingSigmasPerLevel([2.0, 1.0, 0.0])
    method.SmoothingSigmasAreSpecifiedInPhysicalUnitsOn()
    method.SetInitialTransform(initial, inPlace=True)
    return method


def register_cine_to_lge(
    fixed_lge_path: Path,
    moving_cine_path: Path,
    *,
    fixed_mask_directory: Path,
    moving_mask_directory: Path,
    output_directory: Path,
) -> tuple[Any, dict[str, Any]]:
    try:
        import SimpleITK as sitk
    except ImportError as exc:
        raise RegistrationError("SimpleITK is required for cine-to-LGE registration") from exc

    fixed = sitk.Cast(sitk.ReadImage(str(fixed_lge_path)), sitk.sitkFloat32)
    moving = sitk.Cast(sitk.ReadImage(str(moving_cine_path)), sitk.sitkFloat32)
    fixed_mask = _mask_union(fixed_mask_directory, sitk)
    moving_mask = _mask_union(moving_mask_directory, sitk)
    used_masks = True
    fallback_reason = None
    initial = _identity_rigid(fixed, sitk)
    method = _registration_method(
        sitk, initial, use_masks=True, fixed_mask=fixed_mask, moving_mask=moving_mask
    )
    try:
        fixed_to_moving = method.Execute(fixed, moving)
    except RuntimeError as exc:
        used_masks = False
        fallback_reason = type(exc).__name__
        initial = _identity_rigid(fixed, sitk)
        method = _registration_method(
            sitk, initial, use_masks=False, fixed_mask=fixed_mask, moving_mask=moving_mask
        )
        try:
            fixed_to_moving = method.Execute(fixed, moving)
        except RuntimeError as fallback_exc:
            raise RegistrationError("rigid cine-to-LGE registration failed") from fallback_exc

    try:
        moving_to_fixed = fixed_to_moving.GetInverse()
    except RuntimeError as exc:
        raise RegistrationError("cine-to-LGE rigid transform is not invertible") from exc

    output_directory.mkdir(parents=True, exist_ok=True)
    sitk.WriteTransform(fixed_to_moving, str(output_directory / "fixed_lge_to_moving_cine.tfm"))
    sitk.WriteTransform(moving_to_fixed, str(output_directory / "moving_cine_to_fixed_lge.tfm"))
    registered = sitk.Resample(
        moving,
        fixed,
        fixed_to_moving,
        sitk.sitkLinear,
        0.0,
        sitk.sitkFloat32,
    )
    sitk.WriteImage(registered, str(output_directory / "cine_in_lge.nii.gz"))

    moving_center_index = [(size - 1) / 2.0 for size in moving.GetSize()]
    moving_center = moving.TransformContinuousIndexToPhysicalPoint(moving_center_index)
    transformed_center = moving_to_fixed.TransformPoint(moving_center)
    center_displacement = float(
        np.linalg.norm(np.asarray(transformed_center) - np.asarray(moving_center))
    )
    report = {
        "schema_version": 1,
        "method": "rigid Euler3D, Mattes mutual information",
        "fixed_image": "native LGE/MDE",
        "moving_image": "phase-matched cine bSSFP",
        "transform_direction_used_for_meshes": "moving cine LPS to fixed LGE LPS",
        "metric_value": float(method.GetMetricValue()),
        "optimizer_iteration": int(method.GetOptimizerIteration()),
        "optimizer_stop_condition": method.GetOptimizerStopConditionDescription(),
        "metric_masks_used": used_masks,
        "metric_mask_fallback_reason": fallback_reason,
        "center_displacement_mm": center_displacement,
        "transform_name": moving_to_fixed.GetName(),
        "transform_parameters": list(moving_to_fixed.GetParameters()),
        "fixed_parameters": list(moving_to_fixed.GetFixedParameters()),
    }
    write_json(output_directory / "registration.json", report)
    return moving_to_fixed, report


def transform_mesh_lps(input_path: Path, output_path: Path, transform: Any) -> None:
    try:
        import pyvista
    except ImportError as exc:
        raise RegistrationError("PyVista is required to transform biv-me meshes") from exc
    mesh = pyvista.read(input_path).extract_surface().triangulate().clean()
    if mesh.n_points == 0 or mesh.n_cells == 0:
        raise RegistrationError(f"cannot transform empty mesh: {input_path.name}")
    mesh.points = np.asarray(
        [transform.TransformPoint(tuple(float(value) for value in point)) for point in mesh.points],
        dtype=float,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mesh.save(output_path)


def _relative_qc_paths(report: dict[str, Any], case: Path, source_path: Path) -> None:
    report["source_image"] = str(source_path.relative_to(case))
    for value in report["masks"].values():
        value["file"] = str(Path(value["file"]).relative_to(case))


def _require_optional_dependencies() -> None:
    """Fail before any output is written; a late ImportError would strand partial results."""
    missing = [
        module
        for module in ("SimpleITK", "pyvista")
        if importlib.util.find_spec(module) is None
    ]
    if missing:
        raise RegistrationError(
            "cine-to-LGE alignment needs " + " and ".join(missing)
            + "; this stage runs the registration and rasterization in-process, so install "
            "the 'registration' extra or run it from the biv-me environment"
        )


def align_bivme_to_lge(
    case_directory: str | Path,
    *,
    dicom_directory: str | Path,
    lge_series_uid: str | None = None,
    mesh_frame: int | None = None,
    repo_root: str | Path | None = None,
) -> dict[str, Any]:
    _require_optional_dependencies()
    case = Path(case_directory).expanduser().resolve()
    dicom_root = Path(dicom_directory).expanduser().resolve()
    cine_selection_path = case / "source" / "selected_series.json"
    bivme_provenance_path = case / "segmentation" / "bivme" / "provenance.json"
    if not cine_selection_path.is_file() or not bivme_provenance_path.is_file():
        raise SeriesSelectionError("case lacks a completed biv-me cine segmentation")
    cine_selection = json.loads(cine_selection_path.read_text(encoding="utf-8"))
    bivme_provenance = json.loads(bivme_provenance_path.read_text(encoding="utf-8"))

    aligned_root = case / "segmentation" / "bivme" / "lge_aligned"
    references_root = case / "references"
    registration_root = case / "registration" / "bivme_to_lge"
    if aligned_root.exists() or registration_root.exists() or (references_root / "lge").exists():
        raise RegistrationError("refusing to overwrite existing biv-me LGE alignment outputs")

    inventory = scan_headers(dicom_root)
    groups = _series_groups(inventory)
    cine_uid = cine_selection["series_uid"]
    cine_records = groups.get(cine_uid)
    if not cine_records:
        raise SeriesSelectionError("prepared cine series is not present in the supplied DICOM study")
    lge_uid, lge_summary = select_lge_series(
        inventory,
        study_uid=cine_selection["study_uid"],
        explicit_series_uid=lge_series_uid,
    )
    lge_records = groups[lge_uid]
    cine_frame = match_cine_frame(cine_records, lge_records, explicit_frame=mesh_frame)

    cine_for = _frame_of_reference(cine_records[0])
    lge_for = _frame_of_reference(lge_records[0])
    if cine_for and lge_for and cine_for != lge_for:
        raise RegistrationError("cine and LGE series have different DICOM frames of reference")

    frame = int(cine_frame["frame"])
    frame_suffix = f"{frame:03}"
    raw_mesh_root = case / "segmentation" / "bivme" / "raw" / "models" / CASE_ALIAS / "vtk-meshes"
    raw_meshes = {
        key: raw_mesh_root / f"{CASE_ALIAS}_{label}_{frame_suffix}.vtk"
        for key, label in MESH_NAMES.items()
    }
    if not all(path.is_file() for path in raw_meshes.values()):
        raise RegistrationError("selected cine phase meshes are missing")

    cine_reference = references_root / f"cine_phase_{frame_suffix}"
    lge_reference = references_root / "lge"
    prepare_series(
        inventory,
        cine_uid,
        cine_reference,
        frame=frame,
        repo_root=repo_root,
    )
    prepare_series(
        inventory,
        lge_uid,
        lge_reference,
        repo_root=repo_root,
    )
    cine_image_path = cine_reference / "volume" / "image.nii.gz"
    lge_image_path = lge_reference / "volume" / "image.nii.gz"

    moving_initial_masks = registration_root / "metric_masks" / "cine"
    fixed_initial_masks = registration_root / "metric_masks" / "lge"
    moving_report = rasterize(
        cine_image_path,
        raw_meshes["lv"],
        raw_meshes["rv"],
        raw_meshes["epicardial"],
        moving_initial_masks,
    )
    fixed_report = rasterize(
        lge_image_path,
        raw_meshes["lv"],
        raw_meshes["rv"],
        raw_meshes["epicardial"],
        fixed_initial_masks,
    )

    moving_to_fixed, registration_report = register_cine_to_lge(
        lge_image_path,
        cine_image_path,
        fixed_mask_directory=fixed_initial_masks,
        moving_mask_directory=moving_initial_masks,
        output_directory=registration_root,
    )

    transformed_mesh_root = aligned_root / "meshes"
    transformed_meshes = {
        key: transformed_mesh_root / f"{key}_{frame_suffix}_lge_lps.vtk"
        for key in MESH_NAMES
    }
    for key, path in raw_meshes.items():
        transform_mesh_lps(path, transformed_meshes[key], moving_to_fixed)

    normalized = aligned_root / "normalized"
    raster_report = rasterize(
        lge_image_path,
        transformed_meshes["lv"],
        transformed_meshes["rv"],
        transformed_meshes["epicardial"],
        normalized,
    )
    write_json(aligned_root / "rasterization_report.json", raster_report)

    mask_paths = {name: normalized / f"{name}.nii.gz" for name in CANONICAL_MASKS}
    qc = evaluate_masks(lge_image_path, mask_paths)
    _relative_qc_paths(qc, case, lge_image_path)
    qc["registration"] = registration_report
    qc["phase_matching"] = cine_frame
    qc["frame_of_reference_matches"] = bool(cine_for and lge_for and cine_for == lge_for)
    qc["initial_rasterization"] = {
        "cine_grid": moving_report,
        "lge_grid": fixed_report,
    }
    warnings = list(qc["warnings"])
    warnings.extend(bivme_provenance.get("warnings", []))
    timing_difference = cine_frame.get("timing_difference_ms")
    if timing_difference is None:
        warnings.append("cine-to-LGE phase matching did not use comparable TriggerTime values")
    elif float(timing_difference) > 25.0:
        warnings.append(
            f"nearest cine phase differs from LGE trigger time by {float(timing_difference):.1f} ms"
        )
    if registration_report["center_displacement_mm"] > 30.0:
        warnings.append("cine-to-LGE rigid registration moved the image center by more than 30 mm")
    warnings.append("manual cine-to-LGE alignment review in 3D Slicer is required before scar analysis")
    warnings = sorted(set(warnings))
    qc["warnings"] = warnings
    qc_path = aligned_root / "qc" / "lge_alignment.json"
    write_json(qc_path, qc)

    lge_image = nib.load(str(lge_image_path))
    output_files = [
        str(lge_image_path.relative_to(case)),
        str(cine_image_path.relative_to(case)),
        str((registration_root / "fixed_lge_to_moving_cine.tfm").relative_to(case)),
        str((registration_root / "moving_cine_to_fixed_lge.tfm").relative_to(case)),
        str((registration_root / "cine_in_lge.nii.gz").relative_to(case)),
        str(qc_path.relative_to(case)),
    ]
    output_files.extend(str(path.relative_to(case)) for path in transformed_meshes.values())
    output_files.extend(str(path.relative_to(case)) for path in mask_paths.values())
    output_files.append(str((normalized / "combined_labels.nii.gz").relative_to(case)))
    provenance = base_provenance(
        git_commit=git_commit(repo_root) if repo_root else None,
        input_study_uid=cine_selection["study_uid"],
        selected_series_uid=lge_uid,
        selected_temporal_frame=cine_frame,
        modality="MR",
        acquisition_characterization={
            "target": "LGE/MDE",
            "acquisition_type": lge_summary["acquisition_type"],
            "series_description": lge_summary.get("series_description"),
            "protocol_name": lge_summary.get("protocol_name"),
        },
        source_dicom_count=len(lge_records),
        prepared_volume_dimensions=list(lge_image.shape),
        voxel_spacing=list(lge_image.header.get_zooms()[:3]),
        affine=lge_image.affine.tolist(),
        segmentation_backend="biv-me-lge-alignment",
        backend_version=bivme_provenance.get("backend_version"),
        model_task="cine_cmr_mesh_to_native_lge",
        model_options={
            "mesh_frame": frame,
            "phase_matching": cine_frame,
            "registration": registration_report,
            "mesh_coordinate_system": "DICOM LPS transformed from cine to LGE physical space",
            "raster_target": "native LGE NIfTI geometry",
        },
        device="cpu",
        output_files=output_files,
        software_versions={
            **software_versions(),
            "SimpleITK": package_version("SimpleITK"),
            "pyvista": package_version("pyvista"),
        },
        warnings=warnings,
    )
    write_provenance(aligned_root / "provenance.json", provenance)
    write_json(aligned_root / "segmentation_metadata.json", {
        "status": "complete",
        "backend": "biv-me-lge-alignment",
        "mesh_frame": frame,
        "registration": "rigid",
        "target_geometry": str(lge_image_path.relative_to(case)),
        "normalized_outputs": {
            name: str(path.relative_to(case)) for name, path in mask_paths.items()
        } | {"combined_labels": str((normalized / "combined_labels.nii.gz").relative_to(case))},
        "timestamp": utc_now(),
    })
    return provenance
