"""Header-only DICOM inventory and standards-aware series characterization."""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import pydicom

from vtseg.dicom.geometry import slice_coordinate
from vtseg.dicom.temporal import analyze_temporal
from vtseg.errors import DicomInspectionError, SeriesSelectionError

HEADER_TAGS = [
    "StudyInstanceUID", "SeriesInstanceUID", "SOPInstanceUID", "SOPClassUID",
    "StudyDescription", "SeriesDescription", "ProtocolName", "SeriesNumber", "Modality",
    "Manufacturer", "ManufacturerModelName", "MagneticFieldStrength", "SequenceName",
    "ScanningSequence", "SequenceVariant", "ImageType", "Rows", "Columns", "PixelSpacing",
    "SliceThickness", "SpacingBetweenSlices", "ImageOrientationPatient", "ImagePositionPatient",
    "FrameOfReferenceUID", "RescaleSlope", "RescaleIntercept", "WindowCenter", "WindowWidth",
    "InstanceNumber", "AcquisitionTime", "SeriesTime", "TriggerTime",
    "TemporalPositionIdentifier", "NumberOfTemporalPositions", "CardiacNumberOfImages",
    "NumberOfFrames",
]


def json_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, (list, tuple)) or value.__class__.__name__ in {"MultiValue"}:
        return [json_value(item) for item in value]
    try:
        return int(value)
    except (TypeError, ValueError):
        try:
            return float(value)
        except (TypeError, ValueError):
            return str(value)


def _constant_or_values(datasets: list[object], name: str) -> Any:
    values = [json_value(getattr(ds, name, None)) for ds in datasets]
    unique = []
    for value in values:
        if value is not None and value not in unique:
            unique.append(value)
    if not unique:
        return None
    return unique[0] if len(unique) == 1 else unique


def _numeric_range(datasets: list[object], name: str) -> list[float] | None:
    values = []
    for dataset in datasets:
        try:
            values.append(float(getattr(dataset, name)))
        except (AttributeError, TypeError, ValueError):
            pass
    return [min(values), max(values)] if values else None


def acquisition_type(modality: str | None, description: str | None, protocol: str | None) -> str:
    if modality == "CT":
        return "ct"
    if modality != "MR":
        return "unknown"
    text = " ".join(filter(None, [description, protocol])).upper()
    if any(token in text for token in ("MDE", "LGE", "DELAYED ENHANC")):
        return "lge_mde"
    if any(token in text for token in ("CINE", "FIESTA", "SSFP", "BSSFP")):
        return "cine_bssfp"
    return "mr_other"


@dataclass
class InstanceRecord:
    path: str
    study_uid: str
    series_uid: str
    sop_uid: str | None
    dataset: object = field(repr=False, compare=False)


@dataclass
class Inventory:
    root: Path
    instances: list[InstanceRecord]
    skipped: list[dict[str, str]]

    def series(self, uid: str) -> list[InstanceRecord]:
        matches = [instance for instance in self.instances if instance.series_uid == uid]
        if not matches:
            raise SeriesSelectionError(f"SeriesInstanceUID not found: {uid}")
        return matches


def scan_headers(root: str | Path) -> Inventory:
    source = Path(root).expanduser().resolve()
    if not source.is_dir():
        raise DicomInspectionError(f"DICOM input is not a directory: {source}")
    instances: list[InstanceRecord] = []
    skipped: list[dict[str, str]] = []
    for path in sorted(item for item in source.rglob("*") if item.is_file()):
        if path.name.upper() == "DICOMDIR":
            continue
        try:
            dataset = pydicom.dcmread(
                str(path), stop_before_pixels=True, specific_tags=HEADER_TAGS, force=False
            )
        except Exception as exc:
            skipped.append({"path": str(path.relative_to(source)), "reason": type(exc).__name__})
            continue
        study_uid = getattr(dataset, "StudyInstanceUID", None)
        series_uid = getattr(dataset, "SeriesInstanceUID", None)
        if not study_uid or not series_uid:
            skipped.append({"path": str(path.relative_to(source)), "reason": "missing study/series UID"})
            continue
        instances.append(
            InstanceRecord(
                path=str(path),
                study_uid=str(study_uid),
                series_uid=str(series_uid),
                sop_uid=str(getattr(dataset, "SOPInstanceUID", "")) or None,
                dataset=dataset,
            )
        )
    if not instances:
        raise DicomInspectionError(f"no readable DICOM instances found below {source}")
    return Inventory(source, instances, skipped)


def summarize_series(records: list[InstanceRecord]) -> dict[str, Any]:
    datasets = [record.dataset for record in records]
    first = datasets[0]
    warnings: list[str] = []
    dimensions = sorted({(getattr(ds, "Rows", None), getattr(ds, "Columns", None)) for ds in datasets})
    pixel_spacings = []
    orientations = []
    coordinates = []
    for dataset in datasets:
        if hasattr(dataset, "PixelSpacing"):
            try:
                pixel_spacings.append(tuple(round(float(v), 6) for v in dataset.PixelSpacing))
            except (TypeError, ValueError):
                warnings.append("non-numeric PixelSpacing")
        if hasattr(dataset, "ImageOrientationPatient"):
            try:
                orientations.append(tuple(round(float(v), 5) for v in dataset.ImageOrientationPatient))
            except (TypeError, ValueError):
                warnings.append("non-numeric ImageOrientationPatient")
        try:
            coordinates.append(
                slice_coordinate(dataset.ImagePositionPatient, dataset.ImageOrientationPatient)
            )
        except Exception:
            pass

    if len(dimensions) != 1 or any(None in item for item in dimensions):
        warnings.append("inconsistent Rows/Columns")
    if len(pixel_spacings) != len(datasets) or len(set(pixel_spacings)) != 1:
        warnings.append("missing or inconsistent PixelSpacing")
    if len(orientations) != len(datasets) or len(set(orientations)) != 1:
        warnings.append("missing or inconsistent ImageOrientationPatient")
    if len(coordinates) != len(datasets):
        warnings.append("missing or invalid ImagePositionPatient")

    temporal = analyze_temporal(datasets)
    if temporal.repeated_spatial_positions and not temporal.defensible:
        warnings.append(f"ambiguous temporal/repeated-position structure: {temporal.reason}")
    if any(int(getattr(ds, "NumberOfFrames", 1) or 1) > 1 for ds in datasets):
        warnings.append("enhanced/multiframe DICOM is not supported by prepare-series")

    rounded = [round(value, 3) for value in coordinates]
    coordinate_counts = Counter(rounded)
    unique_coordinates = sorted(coordinate_counts)
    spacings = np.diff(unique_coordinates) if len(unique_coordinates) > 1 else np.asarray([])
    spacing_regular = bool(
        len(spacings) == 0 or np.allclose(spacings, np.median(spacings), atol=1e-2, rtol=1e-3)
    )
    if not spacing_regular:
        warnings.append("irregular slice spacing")

    sop_counts = Counter(record.sop_uid for record in records if record.sop_uid)
    duplicate_sops = sum(count - 1 for count in sop_counts.values() if count > 1)
    if duplicate_sops:
        warnings.append(f"{duplicate_sops} duplicate SOPInstanceUID instances")

    modality = str(getattr(first, "Modality", "")) or None
    description = json_value(getattr(first, "SeriesDescription", None))
    protocol = json_value(getattr(first, "ProtocolName", None))
    return {
        "study_uid": records[0].study_uid,
        "series_uid": records[0].series_uid,
        "study_description": _constant_or_values(datasets, "StudyDescription"),
        "series_description": _constant_or_values(datasets, "SeriesDescription"),
        "protocol_name": _constant_or_values(datasets, "ProtocolName"),
        "series_number": _constant_or_values(datasets, "SeriesNumber"),
        "modality": modality,
        "acquisition_type": acquisition_type(modality, str(description or ""), str(protocol or "")),
        "manufacturer": _constant_or_values(datasets, "Manufacturer"),
        "manufacturer_model_name": _constant_or_values(datasets, "ManufacturerModelName"),
        "magnetic_field_strength": _constant_or_values(datasets, "MagneticFieldStrength"),
        "sequence_name": _constant_or_values(datasets, "SequenceName"),
        "scanning_sequence": _constant_or_values(datasets, "ScanningSequence"),
        "sequence_variant": _constant_or_values(datasets, "SequenceVariant"),
        "image_type": _constant_or_values(datasets, "ImageType"),
        "sop_class_uid": _constant_or_values(datasets, "SOPClassUID"),
        "number_of_instances": len(datasets),
        "rows_columns": [list(item) for item in dimensions],
        "pixel_spacing": _constant_or_values(datasets, "PixelSpacing"),
        "slice_thickness": _constant_or_values(datasets, "SliceThickness"),
        "spacing_between_slices": _constant_or_values(datasets, "SpacingBetweenSlices"),
        "image_orientation_patient": _constant_or_values(datasets, "ImageOrientationPatient"),
        "image_position_patient_range": [min(coordinates), max(coordinates)] if coordinates else None,
        "instance_number_range": _numeric_range(datasets, "InstanceNumber"),
        "acquisition_time": _constant_or_values(datasets, "AcquisitionTime"),
        "series_time": _constant_or_values(datasets, "SeriesTime"),
        "trigger_time": _constant_or_values(datasets, "TriggerTime"),
        "temporal_position_identifier": _constant_or_values(datasets, "TemporalPositionIdentifier"),
        "number_of_temporal_positions": _constant_or_values(datasets, "NumberOfTemporalPositions"),
        "cardiac_number_of_images": _constant_or_values(datasets, "CardiacNumberOfImages"),
        "number_of_frames": _constant_or_values(datasets, "NumberOfFrames"),
        "unique_spatial_positions": len(coordinate_counts),
        "repeated_spatial_positions": sum(count > 1 for count in coordinate_counts.values()),
        "inferred_temporal_frames": temporal.inferred_frames,
        "temporal_inference_defensible": temporal.defensible,
        "temporal_inference_basis": temporal.temporal_key,
        "temporal_inference_reason": temporal.reason,
        "spatial_coverage_mm": max(coordinates) - min(coordinates) if coordinates else None,
        "slice_spacing_regular": spacing_regular,
        "orientation_consistent": len(orientations) == len(datasets) and len(set(orientations)) == 1,
        "dimension_consistent": len(dimensions) == 1 and not any(None in item for item in dimensions),
        "pixel_spacing_consistent": len(pixel_spacings) == len(datasets) and len(set(pixel_spacings)) == 1,
        "duplicate_sop_instances": duplicate_sops,
        "warnings": sorted(set(warnings)),
    }


def inventory_report(inventory: Inventory) -> dict[str, Any]:
    groups: dict[tuple[str, str], list[InstanceRecord]] = defaultdict(list)
    for record in inventory.instances:
        groups[(record.study_uid, record.series_uid)].append(record)
    studies: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for (study_uid, _), records in groups.items():
        studies[study_uid].append(summarize_series(records))
    return {
        "schema_version": 1,
        "input_root": str(inventory.root),
        "readable_instances": len(inventory.instances),
        "skipped_files": inventory.skipped,
        "studies": [
            {"study_uid": uid, "series": sorted(series, key=lambda x: str(x["series_number"]))}
            for uid, series in sorted(studies.items())
        ],
    }
