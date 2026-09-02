"""Rasterize closed biv-me LPS surfaces into a prepared NIfTI RAS grid."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np


def canonical_masks(
    lv_enclosure: np.ndarray,
    rv_enclosure: np.ndarray,
    epicardial_enclosure: np.ndarray,
) -> dict[str, np.ndarray]:
    lv = np.asarray(lv_enclosure, dtype=bool)
    rv = np.asarray(rv_enclosure, dtype=bool)
    epicardium = np.asarray(epicardial_enclosure, dtype=bool)
    if lv.shape != rv.shape or lv.shape != epicardium.shape:
        raise ValueError("rasterized biv-me surfaces have different dimensions")
    return {
        "lv_blood_pool": lv,
        "rv_blood_pool": rv,
        "myocardium": epicardium & ~lv & ~rv,
    }


def _mesh_in_ras(mesh_path: Path, pyvista: Any) -> Any:
    mesh = pyvista.read(mesh_path).extract_surface().triangulate().clean()
    if mesh.n_points == 0 or mesh.n_cells == 0:
        raise ValueError(f"empty mesh: {mesh_path.name}")
    points = np.asarray(mesh.points, dtype=float).copy()
    # biv-me fits in DICOM patient coordinates (LPS); NIfTI uses RAS.
    points[:, :2] *= -1.0
    mesh.points = points
    return mesh


def _voxel_bounds(
    mesh: Any,
    shape: tuple[int, ...],
    affine: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    inverse = np.linalg.inv(affine)
    voxel_points = nib.affines.apply_affine(inverse, np.asarray(mesh.points))
    lower = np.maximum(np.floor(voxel_points.min(axis=0)).astype(int) - 1, 0)
    upper = np.minimum(np.ceil(voxel_points.max(axis=0)).astype(int) + 2, np.asarray(shape[:3]))
    return lower, upper


def _enclosed_mask(
    mesh: Any,
    shape: tuple[int, ...],
    affine: np.ndarray,
    pyvista: Any,
    *,
    max_chunk_points: int = 500_000,
) -> np.ndarray:
    result = np.zeros(shape[:3], dtype=bool)
    lower, upper = _voxel_bounds(mesh, shape, affine)
    extent = upper - lower
    if np.any(extent <= 0):
        return result

    plane_points = max(1, int(extent[0] * extent[1]))
    chunk_depth = max(1, max_chunk_points // plane_points)
    for z_start in range(int(lower[2]), int(upper[2]), chunk_depth):
        z_stop = min(z_start + chunk_depth, int(upper[2]))
        grid = np.mgrid[
            int(lower[0]):int(upper[0]),
            int(lower[1]):int(upper[1]),
            z_start:z_stop,
        ]
        indices = grid.reshape(3, -1).T
        world_points = nib.affines.apply_affine(affine, indices)
        selected = pyvista.PolyData(world_points).select_enclosed_points(
            mesh,
            tolerance=0.0,
            check_surface=False,
        )["SelectedPoints"]
        result[tuple(indices.T)] = np.asarray(selected, dtype=bool)
    return result


def rasterize(
    source_path: Path,
    lv_mesh_path: Path,
    rv_mesh_path: Path,
    epicardial_mesh_path: Path,
    output_directory: Path,
) -> dict[str, Any]:
    try:
        import pyvista
    except ImportError as exc:
        raise RuntimeError("pyvista is required in the biv-me environment") from exc

    source = nib.load(str(source_path))
    if len(source.shape) != 3:
        raise ValueError("prepared source image must be three-dimensional")
    meshes = {
        "lv_blood_pool": _mesh_in_ras(lv_mesh_path, pyvista),
        "rv_blood_pool": _mesh_in_ras(rv_mesh_path, pyvista),
        "epicardium": _mesh_in_ras(epicardial_mesh_path, pyvista),
    }
    enclosures = {
        name: _enclosed_mask(mesh, source.shape, source.affine, pyvista)
        for name, mesh in meshes.items()
    }
    masks = canonical_masks(
        enclosures["lv_blood_pool"],
        enclosures["rv_blood_pool"],
        enclosures["epicardium"],
    )

    output_directory.mkdir(parents=True, exist_ok=False)
    for name, data in masks.items():
        image = nib.Nifti1Image(data.astype(np.uint8), source.affine, source.header.copy())
        image.set_data_dtype(np.uint8)
        image.set_qform(source.affine, code=1)
        image.set_sform(source.affine, code=1)
        nib.save(image, output_directory / f"{name}.nii.gz")

    return {
        "coordinate_conversion": "DICOM LPS mesh coordinates to NIfTI RAS",
        "source_dimensions": list(source.shape),
        "mesh_open_edges": {name: int(mesh.n_open_edges) for name, mesh in meshes.items()},
        "enclosure_voxels": {name: int(mask.sum()) for name, mask in enclosures.items()},
        "canonical_voxels": {name: int(mask.sum()) for name, mask in masks.items()},
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--lv-mesh", required=True, type=Path)
    parser.add_argument("--rv-mesh", required=True, type=Path)
    parser.add_argument("--epicardial-mesh", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args(argv)
    report = rasterize(
        args.source,
        args.lv_mesh,
        args.rv_mesh,
        args.epicardial_mesh,
        args.output,
    )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
