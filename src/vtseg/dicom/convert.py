"""Prepare one explicitly selected classic DICOM acquisition as NIfTI."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np
import pydicom

from vtseg.dicom.geometry import affine_spacing, dicom_affine_ras, spatial_order
from vtseg.dicom.series import Inventory, inventory_report, summarize_series
from vtseg.dicom.temporal import select_frame
from vtseg.errors import GeometryError, SeriesSelectionError, UnsupportedModality
from vtseg.provenance import base_provenance, git_commit, write_json, write_provenance


def _validate_headers(datasets: list[object]) -> None:
    if any(int(getattr(ds, "NumberOfFrames", 1) or 1) > 1 for ds in datasets):
        raise SeriesSelectionError(
            "enhanced/multiframe DICOM is not supported in Milestone 1; export a validated "
            "classic single-frame series or add an enhanced-DICOM converter"
        )
    modalities = {str(getattr(ds, "Modality", "")) for ds in datasets}
    if len(modalities) != 1:
        raise SeriesSelectionError(f"selected series contains multiple modalities: {sorted(modalities)}")
    modality = next(iter(modalities))
    if modality not in {"CT", "MR"}:
        raise UnsupportedModality(f"unsupported modality: {modality or 'missing'}")

    shapes = {(int(ds.Rows), int(ds.Columns)) for ds in datasets if hasattr(ds, "Rows")}
    if len(shapes) != 1 or len(shapes) == 0:
        raise GeometryError("selected instances have missing or inconsistent Rows/Columns")
    spacings = {
        tuple(round(float(v), 6) for v in ds.PixelSpacing)
        for ds in datasets
        if hasattr(ds, "PixelSpacing")
    }
    if len(spacings) != 1:
        raise GeometryError("selected instances have missing or inconsistent PixelSpacing")


def _load_pixels(path: str) -> np.ndarray:
    dataset = pydicom.dcmread(path, force=False)
    try:
        pixels = dataset.pixel_array.astype(np.float32)
    except Exception as exc:
        raise SeriesSelectionError(f"unable to decode DICOM pixel data: {Path(path).name}") from exc
    slope = float(getattr(dataset, "RescaleSlope", 1.0) or 1.0)
    intercept = float(getattr(dataset, "RescaleIntercept", 0.0) or 0.0)
    return pixels * slope + intercept


def prepare_series(
    inventory: Inventory,
    series_uid: str,
    output: str | Path,
    *,
    frame: int | None = None,
    repo_root: str | Path | None = None,
) -> dict[str, Any]:
    case_dir = Path(output).expanduser().resolve()
    image_path = case_dir / "volume" / "image.nii.gz"
    if image_path.exists():
        raise SeriesSelectionError(f"refusing to overwrite prepared volume: {image_path}")

    records = inventory.series(series_uid)
    datasets = [record.dataset for record in records]
    _validate_headers(datasets)
    selected_datasets, temporal_selection = select_frame(datasets, frame)
    _validate_headers(selected_datasets)

    path_by_id = {id(record.dataset): record.path for record in records}
    selected_datasets = spatial_order(selected_datasets)
    selected_paths = [path_by_id[id(dataset)] for dataset in selected_datasets]
    coordinates = [
        float(np.dot(np.asarray(ds.ImagePositionPatient, dtype=float), np.cross(
            np.asarray(ds.ImageOrientationPatient[:3], dtype=float),
            np.asarray(ds.ImageOrientationPatient[3:], dtype=float),
        )))
        for ds in selected_datasets
    ]
    if len({round(value, 3) for value in coordinates}) != len(coordinates):
        raise SeriesSelectionError("selected frame still contains repeated spatial positions")
    if len(coordinates) > 2:
        deltas = np.diff(coordinates)
        if not np.allclose(deltas, np.median(deltas), atol=1e-2, rtol=1e-3):
            raise GeometryError("selected frame has irregular slice spacing")

    arrays = [_load_pixels(path) for path in selected_paths]
    volume = np.stack(arrays, axis=2)
    affine = dicom_affine_ras(selected_datasets)
    image_path.parent.mkdir(parents=True, exist_ok=True)
    image = nib.Nifti1Image(volume, affine)
    image.set_qform(affine, code=1)
    image.set_sform(affine, code=1)
    nib.save(image, image_path)

    summary = summarize_series(records)
    source_dir = case_dir / "source"
    source_dir.mkdir(parents=True, exist_ok=True)
    write_json(source_dir / "dicom_inventory.json", inventory_report(inventory))
    selection = {
        "schema_version": 1,
        "input_root": str(inventory.root),
        "study_uid": records[0].study_uid,
        "series_uid": series_uid,
        "selected_temporal_frame": temporal_selection,
        "selected_instance_count": len(selected_paths),
        "selected_instance_paths": selected_paths,
        "series_characterization": summary,
    }
    write_json(source_dir / "selected_series.json", selection)

    modality = str(getattr(selected_datasets[0], "Modality"))
    spacing = affine_spacing(affine)
    provenance = base_provenance(
        git_commit=git_commit(repo_root) if repo_root else None,
        input_study_uid=records[0].study_uid,
        selected_series_uid=series_uid,
        selected_temporal_frame=temporal_selection,
        modality=modality,
        acquisition_characterization={
            "acquisition_type": summary["acquisition_type"],
            "series_description": summary["series_description"],
            "protocol_name": summary["protocol_name"],
            "sequence_name": summary["sequence_name"],
            "scanning_sequence": summary["scanning_sequence"],
            "sequence_variant": summary["sequence_variant"],
        },
        source_dicom_count=len(selected_paths),
        prepared_volume_dimensions=list(volume.shape),
        voxel_spacing=list(spacing),
        affine=affine.tolist(),
        segmentation_backend="not_run",
        output_files=[str(image_path.relative_to(case_dir))],
        warnings=summary["warnings"],
    )
    write_provenance(source_dir / "preparation_provenance.json", provenance)

    if modality == "MR":
        status = {
            "status": "not_configured",
            "modality": "MR",
            "acquisition_type": summary["acquisition_type"],
            "message": (
                "MRI acquisition successfully prepared. No validated LV/RV/myocardium "
                "segmentation backend is configured."
            ),
        }
        write_json(case_dir / "segmentation" / "segmentation_metadata.json", status)
    return provenance
