"""Patient-space geometry helpers.

DICOM direction cosines and positions are LPS. NIfTI affines are conventionally
stored in RAS, so conversion is an explicit sign flip of the first two world axes.
The voxel array layout used here is ``(rows, columns, slices)``.
"""

from __future__ import annotations

from collections.abc import Iterable

import numpy as np

from vtseg.errors import GeometryError

LPS_TO_RAS = np.diag([-1.0, -1.0, 1.0, 1.0])


def as_float_array(value: object, expected: int, name: str) -> np.ndarray:
    try:
        arr = np.asarray(value, dtype=float)
    except (TypeError, ValueError) as exc:
        raise GeometryError(f"{name} is missing or non-numeric") from exc
    if arr.shape != (expected,):
        raise GeometryError(f"{name} must contain {expected} values, got {arr.shape}")
    return arr


def orientation_vectors(orientation: object) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    values = as_float_array(orientation, 6, "ImageOrientationPatient")
    column_axis = values[:3]
    row_axis = values[3:]
    if not np.isclose(np.linalg.norm(column_axis), 1.0, atol=1e-4):
        raise GeometryError("first ImageOrientationPatient vector is not unit length")
    if not np.isclose(np.linalg.norm(row_axis), 1.0, atol=1e-4):
        raise GeometryError("second ImageOrientationPatient vector is not unit length")
    if not np.isclose(np.dot(column_axis, row_axis), 0.0, atol=1e-4):
        raise GeometryError("ImageOrientationPatient vectors are not orthogonal")
    normal = np.cross(column_axis, row_axis)
    return column_axis, row_axis, normal


def slice_coordinate(position: object, orientation: object) -> float:
    _, _, normal = orientation_vectors(orientation)
    return float(np.dot(as_float_array(position, 3, "ImagePositionPatient"), normal))


def spatial_order(datasets: Iterable[object]) -> list[object]:
    items = list(datasets)
    if not items:
        raise GeometryError("cannot order an empty series")
    reference = getattr(items[0], "ImageOrientationPatient", None)
    orientation_vectors(reference)
    for item in items:
        current = as_float_array(
            getattr(item, "ImageOrientationPatient", None), 6, "ImageOrientationPatient"
        )
        if not np.allclose(current, np.asarray(reference, dtype=float), atol=1e-4):
            raise GeometryError("series contains inconsistent ImageOrientationPatient values")
    try:
        return sorted(
            items,
            key=lambda ds: (
                slice_coordinate(ds.ImagePositionPatient, reference),
                int(getattr(ds, "InstanceNumber", 0)),
            ),
        )
    except AttributeError as exc:
        raise GeometryError("ImagePositionPatient is required for spatial ordering") from exc


def dicom_affine_lps(datasets: Iterable[object]) -> np.ndarray:
    ordered = spatial_order(datasets)
    first = ordered[0]
    column_axis, row_axis, normal = orientation_vectors(first.ImageOrientationPatient)
    spacing = as_float_array(first.PixelSpacing, 2, "PixelSpacing")
    positions = [as_float_array(ds.ImagePositionPatient, 3, "ImagePositionPatient") for ds in ordered]

    if len(positions) > 1:
        deltas = np.diff(np.stack(positions), axis=0)
        slice_step = np.median(deltas, axis=0)
        if np.linalg.norm(slice_step) <= 0:
            raise GeometryError("slice positions do not define a non-zero spacing")
    else:
        raw = getattr(first, "SpacingBetweenSlices", None)
        if raw is None:
            raw = getattr(first, "SliceThickness", None)
        if raw is None:
            raise GeometryError("single-slice series lacks through-plane spacing")
        slice_step = normal * float(raw)

    # Array axis 0 increments rows (second DICOM orientation vector); axis 1
    # increments columns (first DICOM orientation vector).
    affine = np.eye(4, dtype=float)
    affine[:3, 0] = row_axis * spacing[0]
    affine[:3, 1] = column_axis * spacing[1]
    affine[:3, 2] = slice_step
    affine[:3, 3] = positions[0]
    return affine


def dicom_affine_ras(datasets: Iterable[object]) -> np.ndarray:
    return LPS_TO_RAS @ dicom_affine_lps(datasets)


def affine_spacing(affine: np.ndarray) -> tuple[float, float, float]:
    matrix = np.asarray(affine, dtype=float)
    if matrix.shape != (4, 4):
        raise GeometryError("affine must be 4x4")
    return tuple(float(np.linalg.norm(matrix[:3, i])) for i in range(3))


def geometry_compatible(
    shape_a: tuple[int, ...],
    affine_a: np.ndarray,
    shape_b: tuple[int, ...],
    affine_b: np.ndarray,
    *,
    atol: float = 1e-4,
) -> bool:
    return tuple(shape_a) == tuple(shape_b) and bool(
        np.allclose(np.asarray(affine_a), np.asarray(affine_b), atol=atol)
    )
