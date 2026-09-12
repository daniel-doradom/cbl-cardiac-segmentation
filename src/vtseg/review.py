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
    selection = _read_json(case / "source" / "selected_series.json")
    if selection.get("series_characterization", {}).get("modality") == "CT":
        image = case / "volume" / SOURCE_IMAGE_NAME
        selected = case / "segmentation" / "selected"
        if (selected / "selection.json").is_file():
            return [{
                "id": "1_selected_ct", "space": "ct_short_axis_mpr", "frame": None,
                "description": "Slicer-selected CT masks on the promoted short-axis MPR",
                "image": image, "labels": selected / "normalized" / SOURCE_LABELS_NAME,
            }]
        return [
            {
                "id": "1_direct_mpr", "space": "ct_short_axis_mpr", "frame": None,
                "description": "TotalSegmentator run directly on the short-axis CT MPR",
                "image": image,
                "labels": case / "segmentation" / "totalsegmentator" / "normalized" / SOURCE_LABELS_NAME,
            },
            {
                "id": "2_native_ct_mapped", "space": "ct_short_axis_mpr", "frame": None,
                "description": "native full-CT TotalSegmentator masks mapped onto the same short-axis MPR grid",
                "image": image,
                "labels": case / "segmentation" / "native_ct_mapped" / "normalized" / SOURCE_LABELS_NAME,
            },
        ]
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


def _slug(name: str) -> str:
    """Reduce a directory name to characters that are safe in a filename."""
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-._")
    return cleaned or "case"


def _pair_prefix(case: Path, pair_id: str) -> str:
    """Name a pair's files after the run they came from.

    3D Slicer names its nodes after the file, so two folders opened together must
    not produce the same node names. The run directory name is used rather than
    the case identifier because comparing two runs of one case is a normal
    review: ``nsha02-pre-mri-v3`` and ``nsha02-pre-mri-v4`` are both
    ``nsha02-pre`` and would otherwise collide.
    """
    number, _, rest = pair_id.partition("_")
    return f"{number}_{_slug(case.name)}_{rest}"


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
        prefix = _pair_prefix(case, spec["id"])
        image_name = f"{prefix}_image.nii.gz"
        labels_name = f"{prefix}_labels.nii.gz"
        _remove_stale_copies(destination, {image_name, labels_name})
        shutil.copyfile(image, destination / image_name)
        shutil.copyfile(labels, destination / labels_name)
        collected.append({
            "id": spec["id"],
            "prefix": prefix,
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
            f"no reviewable pairs found in {case}; run the relevant segmentation stage first"
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
    for stage in (
        case / "segmentation" / "totalsegmentator" / "provenance.json",
        case / "segmentation" / "native_ct_mapped" / "provenance.json",
    ):
        warnings.extend(_read_json(stage).get("warnings", []))

    manifest = {
        "schema_version": 2,
        "case": case.name,
        "pairs": collected,
        "skipped_pairs": skipped,
        "label_values": LABEL_VALUES,
        "registration": registration_summary,
        "warnings": sorted(set(warnings)),
        "usage": (
            "In 3D Slicer load *_image.nii.gz as a Volume and *_labels.nii.gz as a "
            "LabelMapVolume from the same folder. File names carry the run name, so "
            "two runs can be opened side by side without their node names clashing. "
            "Do not mix folders: each pair has its own geometry."
        ),
        "timestamp": utc_now(),
    }
    write_json(review_root / "review.json", manifest)
    return manifest
