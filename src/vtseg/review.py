"""Collect the image/mask pairs a reviewer opens in 3D Slicer.

The pipeline stores its outputs by provenance: the fitted cine masks live under
``segmentation/``, the LGE-space masks under ``segmentation/bivme/lge_aligned/``,
and the cine masks at the LGE-matched phase under
``registration/bivme_to_lge/metric_masks/``. That layout is correct for
traceability and awkward for review, so this module copies the reviewable pairs
into ``review/`` under stable names without touching the originals.
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np

from vtseg.errors import VTSegError
from vtseg.provenance import utc_now, write_json

REVIEW_DIRECTORY = "review"
SOURCE_IMAGE_NAME = "image.nii.gz"
SOURCE_LABELS_NAME = "combined_labels.nii.gz"
LABEL_VALUES = {"1": "lv_blood_pool", "2": "rv_blood_pool", "3": "myocardium"}


def _read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _cine_phase_directory(case: Path) -> tuple[Path | None, int | None]:
    """Locate ``references/cine_phase_NNN`` and recover its frame number."""
    candidates = sorted((case / "references").glob("cine_phase_*"))
    for candidate in candidates:
        match = re.fullmatch(r"cine_phase_(\d+)", candidate.name)
        if match and candidate.is_dir():
            return candidate, int(match.group(1))
    return None, None


def _geometry(path: Path) -> tuple[tuple[int, ...], Any]:
    image = nib.load(str(path))
    return tuple(image.shape), image.affine


def _pair_specs(case: Path) -> list[dict[str, Any]]:
    bivme = case / "segmentation" / "bivme"
    aligned = bivme / "lge_aligned"
    metric_cine = case / "registration" / "bivme_to_lge" / "metric_masks" / "cine"
    phase_dir, phase_frame = _cine_phase_directory(case)

    fit_frame = _read_json(bivme / "segmentation_metadata.json").get("frame")
    mesh_frame = _read_json(aligned / "segmentation_metadata.json").get("mesh_frame")

    specs = [
        {
            "id": "1_cine_fit",
            "space": "cine",
            "description": "cine bSSFP at the fitted frame, with the biv-me masks",
            "frame": fit_frame,
            "image": case / "volume" / SOURCE_IMAGE_NAME,
            "labels": bivme / "normalized" / SOURCE_LABELS_NAME,
        },
        {
            "id": "2_cine_lge_phase",
            "space": "cine",
            "description": "cine bSSFP at the LGE-matched phase, with that phase's masks",
            "frame": phase_frame if phase_frame is not None else mesh_frame,
            "image": (phase_dir / "volume" / SOURCE_IMAGE_NAME) if phase_dir else None,
            "labels": metric_cine / SOURCE_LABELS_NAME,
        },
        {
            "id": "3_lge",
            "space": "lge",
            "description": "native LGE/MDE with the biv-me masks rigidly aligned into LGE space",
            "frame": mesh_frame,
            "image": case / "references" / "lge" / "volume" / SOURCE_IMAGE_NAME,
            "labels": aligned / "normalized" / SOURCE_LABELS_NAME,
        },
    ]
    return specs


def _remove_stale_copies(destination: Path, keep: set[str]) -> None:
    """Delete NIfTI copies this pair folder no longer owns.

    Only ``.nii.gz`` files are considered, so anything a reviewer leaves in the
    folder (a Slicer scene, notes) survives a rebuild.
    """
    for existing in destination.glob("*.nii.gz"):
        if existing.name not in keep:
            existing.unlink()


def collect_review(case_directory: str | Path) -> dict[str, Any]:
    """Copy every available image/mask pair into ``<case>/review/``.

    Pairs whose stage has not run are skipped and reported, so the command is
    useful after `segment-mri-bivme` alone and again after `align-bivme-lge`.
    """
    case = Path(case_directory).expanduser().resolve()
    if not case.is_dir():
        raise VTSegError(f"case directory not found: {case}")

    review_root = case / REVIEW_DIRECTORY
    collected: list[dict[str, Any]] = []
    skipped: list[dict[str, str]] = []
    warnings: list[str] = []

    for spec in _pair_specs(case):
        image, labels = spec["image"], spec["labels"]
        missing = [
            str(path.relative_to(case)) if path else "(stage not run)"
            for path in (image, labels)
            if path is None or not path.is_file()
        ]
        if missing:
            skipped.append({"id": spec["id"], "missing": ", ".join(missing)})
            continue

        image_shape, image_affine = _geometry(image)
        labels_shape, labels_affine = _geometry(labels)
        if image_shape != labels_shape or not np.allclose(image_affine, labels_affine, atol=1e-4):
            raise VTSegError(
                f"review pair {spec['id']} is not co-registered: "
                f"image {image_shape} vs labels {labels_shape}; "
                "the pair would not overlay in 3D Slicer"
            )

        destination = review_root / spec["id"]
        destination.mkdir(parents=True, exist_ok=True)
        image_name = f"{spec['id']}_image.nii.gz"
        labels_name = f"{spec['id']}_labels.nii.gz"
        _remove_stale_copies(destination, {image_name, labels_name})
        shutil.copyfile(image, destination / image_name)
        shutil.copyfile(labels, destination / labels_name)
        collected.append({
            "id": spec["id"],
            "space": spec["space"],
            "description": spec["description"],
            "frame": spec["frame"],
            "image": str((destination / image_name).relative_to(case)),
            "labels": str((destination / labels_name).relative_to(case)),
            "source_image": str(image.relative_to(case)),
            "source_labels": str(labels.relative_to(case)),
            "array_dimensions": list(image_shape),
        })

    if not collected:
        raise VTSegError(
            f"no reviewable pairs found in {case}; run segment-mri-bivme first"
        )

    registration = _read_json(
        case / "registration" / "bivme_to_lge" / "registration.json"
    )
    registration_summary: dict[str, Any] | None = None
    if registration:
        displacement = registration.get("center_displacement_mm")
        stop = str(registration.get("optimizer_stop_condition", ""))
        converged = "Maximum number of iterations" not in stop
        registration_summary = {
            "center_displacement_mm": displacement,
            "converged": converged,
            "optimizer_stop_condition": registration.get("optimizer_stop_condition"),
            "method": registration.get("method"),
        }
        if isinstance(displacement, (int, float)) and displacement > 30:
            warnings.append(
                f"cine-to-LGE registration moved the image center by {displacement:.1f} mm; "
                "confirm the LGE pair overlays before using it for scar analysis"
            )
        if not converged:
            warnings.append(
                "cine-to-LGE registration stopped on its iteration limit rather than converging"
            )

    for stage in (
        case / "segmentation" / "bivme" / "provenance.json",
        case / "segmentation" / "bivme" / "lge_aligned" / "provenance.json",
    ):
        warnings.extend(_read_json(stage).get("warnings", []))

    manifest = {
        "schema_version": 1,
        "case": case.name,
        "pairs": collected,
        "skipped_pairs": skipped,
        "label_values": LABEL_VALUES,
        "registration": registration_summary,
        "warnings": sorted(set(warnings)),
        "usage": (
            "In 3D Slicer load <pair>_image.nii.gz as a Volume and <pair>_labels.nii.gz "
            "as a LabelMapVolume from the same folder. Do not mix folders: each "
            "pair has its own geometry."
        ),
        "timestamp": utc_now(),
    }
    write_json(review_root / "review.json", manifest)
    return manifest
