"""Import manually corrected MATLAB mask stacks into canonical NIfTI masks."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import nibabel as nib
import numpy as np

from vtseg.errors import NormalizationError
from vtseg.provenance import base_provenance, git_commit, software_versions, write_json, write_provenance
from vtseg.qc.masks import run_backend_qc
from vtseg.segmentation.normalize import CANONICAL_MASKS, write_combined_labels


def _stack(path: Path, name: str, expected_shape: tuple[int, int, int]) -> np.ndarray:
    try:
        from scipy.io import loadmat
    except ImportError as exc:
        raise NormalizationError("SciPy is required for MATLAB mask import") from exc
    if not path.is_file():
        raise NormalizationError(f"missing MATLAB mask stack: {path.name}")
    values = loadmat(str(path)).get(name)
    if values is None or tuple(values.shape) != expected_shape:
        raise NormalizationError(f"MATLAB mask {name} does not match the exported slice dimensions")
    if not np.all(np.isfinite(values)):
        raise NormalizationError(f"MATLAB mask {name} contains non-finite values")
    return np.asarray(values > 0, dtype=bool)


def import_matlab_case(
    matlab_case_directory: str | Path,
    reference_directory: str | Path,
    output_directory: str | Path,
    *,
    repo_root: str | Path | None = None,
) -> dict[str, Any]:
    """Reconstruct sparse full-grid canonical masks from corrected MATLAB stacks."""
    matlab_case = Path(matlab_case_directory).expanduser().resolve()
    reference = Path(reference_directory).expanduser().resolve()
    output = Path(output_directory).expanduser().resolve()
    if not (matlab_case / "seg").is_dir() and (matlab_case / "work" / "seg").is_dir():
        # An export folder with original/ and work/: the corrected masks are in work/.
        matlab_case = matlab_case / "work"
    seg = matlab_case / "seg"
    manifest_path = seg / "vtseg_export_manifest.json"
    if not manifest_path.is_file():
        # Existing MRI exports predate the modality-neutral manifest name.
        manifest_path = seg / "bivme_export_manifest.json"
    image_path = reference / "volume" / "image.nii.gz"
    selection_path = reference / "source" / "selected_series.json"
    if not manifest_path.is_file() or not image_path.is_file() or not selection_path.is_file():
        raise NormalizationError("MATLAB case or reference is incomplete")
    if output.exists():
        raise NormalizationError(f"refusing to overwrite existing manual normalized masks: {output}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    slices = manifest.get("slices")
    if not isinstance(slices, list) or not slices:
        raise NormalizationError("MATLAB export manifest has no slice mapping")
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    modality = selection.get("series_characterization", {}).get("modality")
    if modality is None and manifest_path.name == "bivme_export_manifest.json":
        modality = "MR"
    if modality not in {"CT", "MR"}:
        raise NormalizationError(f"reference modality is not supported for MATLAB import: {modality!r}")
    if manifest.get("series_uid") is not None and manifest["series_uid"] != selection.get("series_uid"):
        raise NormalizationError("MATLAB export manifest series UID does not match the reference")
    if manifest.get("modality") is not None and manifest["modality"] != modality:
        raise NormalizationError("MATLAB export manifest modality does not match the reference")
    image = nib.load(str(image_path))
    indices = [entry.get("reference_volume_index") for entry in slices]
    if any(not isinstance(index, int) or not 0 <= index < image.shape[2] for index in indices):
        raise NormalizationError("MATLAB export manifest has an invalid reference_volume_index")
    if len(indices) != len(set(indices)):
        raise NormalizationError("MATLAB export manifest repeats a reference_volume_index")
    stack_shape = (int(image.shape[0]), int(image.shape[1]), len(slices))
    lv_stack = _stack(seg / "Lendo.mat", "Lendo", stack_shape)
    rv_stack = _stack(seg / "Rendo.mat", "Rendo", stack_shape)
    epi_stack = _stack(seg / "Epi.mat", "Epi", stack_shape)
    if np.any(lv_stack & rv_stack):
        raise NormalizationError("corrected MATLAB LV and RV masks overlap")
    if np.any((lv_stack | rv_stack) & ~epi_stack):
        raise NormalizationError("corrected MATLAB cavities extend outside Epi")
    myocardium_stack = epi_stack & ~lv_stack & ~rv_stack

    volumes = {name: np.zeros(image.shape, dtype=bool) for name in CANONICAL_MASKS}
    for matlab_index, entry in enumerate(slices):
        reference_index = entry.get("reference_volume_index")
        if not isinstance(reference_index, int) or not 0 <= reference_index < image.shape[2]:
            raise NormalizationError("MATLAB export manifest has an invalid reference_volume_index")
        volumes["lv_blood_pool"][:, :, reference_index] = lv_stack[:, :, matlab_index]
        volumes["rv_blood_pool"][:, :, reference_index] = rv_stack[:, :, matlab_index]
        volumes["myocardium"][:, :, reference_index] = myocardium_stack[:, :, matlab_index]

    output.mkdir(parents=True)
    for name, data in volumes.items():
        mask = nib.Nifti1Image(data.astype(np.uint8), image.affine, image.header.copy())
        mask.set_data_dtype(np.uint8)
        mask.set_qform(image.affine, code=1)
        mask.set_sform(image.affine, code=1)
        nib.save(mask, output / f"{name}.nii.gz")
    combined_path = write_combined_labels(image_path, output)

    manual_root = output.parent
    qc_path = manual_root / "qc" / "mask_qc.json"
    qc = run_backend_qc(reference, normalized_directory=output, report_path=qc_path)
    provenance = base_provenance(
        git_commit=git_commit(repo_root) if repo_root else None,
        input_study_uid=selection["study_uid"],
        selected_series_uid=selection["series_uid"],
        selected_temporal_frame=selection.get("selected_temporal_frame"),
        modality=modality,
        source_dicom_count=len(slices),
        prepared_volume_dimensions=list(image.shape),
        voxel_spacing=list(image.header.get_zooms()[:3]),
        affine=image.affine.tolist(),
        segmentation_backend="matlab-manual-correction",
        model_task="corrected_matlab_masks_to_canonical_nifti",
        model_options={"matlab_case": str(matlab_case), "sparse_selected_slices": len(slices)},
        device="cpu",
        output_files=[str(path.relative_to(manual_root)) for path in [
            *(output / f"{name}.nii.gz" for name in CANONICAL_MASKS), combined_path, qc_path
        ]],
        software_versions=software_versions(),
        warnings=qc.get("warnings", []) + [
            "manual masks are defined only on the MATLAB-selected slice subset; other reference slices are empty"
        ],
    )
    write_provenance(manual_root / "provenance.json", provenance)
    metadata = {
        "status": "complete",
        "backend": "matlab-manual-correction",
        "source_manifest": str(manifest_path.relative_to(matlab_case)),
        "normalized_outputs": [f"{name}.nii.gz" for name in (*CANONICAL_MASKS, "combined_labels")],
        "selected_slice_count": len(slices),
    }
    write_json(manual_root / "manual_import_metadata.json", metadata)
    return metadata
