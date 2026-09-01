"""Confine model-specific names to adapters and enforce source geometry."""

from __future__ import annotations

import shutil
from pathlib import Path

import nibabel as nib
import numpy as np

from vtseg.dicom.geometry import geometry_compatible
from vtseg.errors import NormalizationError

CANONICAL_MASKS = ("lv_blood_pool", "rv_blood_pool", "myocardium")

TOTALSEGMENTATOR_CT_MAPPING = {
    "heart_ventricle_left": "lv_blood_pool",
    "heart_ventricle_right": "rv_blood_pool",
    "heart_myocardium": "myocardium",
}


def normalize_masks(
    source_image: str | Path,
    raw_directory: str | Path,
    output_directory: str | Path,
    mapping: dict[str, str],
) -> dict[str, str]:
    source = nib.load(str(source_image))
    raw = Path(raw_directory)
    output = Path(output_directory)
    missing = [name for name in mapping if not (raw / f"{name}.nii.gz").is_file()]
    if missing:
        raise NormalizationError(
            "segmentation backend did not produce required labels: " + ", ".join(sorted(missing))
        )
    if set(mapping.values()) != set(CANONICAL_MASKS):
        raise NormalizationError("mapping must produce exactly the three canonical masks")

    checked: list[tuple[Path, Path]] = []
    for backend_name, canonical_name in mapping.items():
        source_mask_path = raw / f"{backend_name}.nii.gz"
        mask = nib.load(str(source_mask_path))
        if not geometry_compatible(source.shape, source.affine, mask.shape, mask.affine):
            raise NormalizationError(
                f"geometry mismatch for {backend_name}: source shape/affine differ from mask"
            )
        values = np.asanyarray(mask.dataobj)
        if not np.all(np.isfinite(values)):
            raise NormalizationError(f"mask {backend_name} contains non-finite values")
        checked.append((source_mask_path, output / f"{canonical_name}.nii.gz"))

    output.mkdir(parents=True, exist_ok=True)
    result = {}
    for source_mask_path, destination in checked:
        shutil.copy2(source_mask_path, destination)
        result[source_mask_path.stem.removesuffix(".nii")] = str(destination)
    return result
