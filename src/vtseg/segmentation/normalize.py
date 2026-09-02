"""Canonical cardiac mask validation and backend-label normalization."""

from __future__ import annotations

from pathlib import Path

import nibabel as nib
import numpy as np

from vtseg.dicom.geometry import geometry_compatible
from vtseg.errors import NormalizationError

CANONICAL_MASKS = ("lv_blood_pool", "rv_blood_pool", "myocardium")
COMBINED_LABELS = "combined_labels"
COMBINED_LABEL_VALUES = {"lv_blood_pool": 1, "rv_blood_pool": 2, "myocardium": 3}

TOTALSEGMENTATOR_CT_MAPPING = {
    "heart_ventricle_left": "lv_blood_pool",
    "heart_ventricle_right": "rv_blood_pool",
    "heart_myocardium": "myocardium",
}


def _validated_arrays(source: nib.spatialimages.SpatialImage, directory: Path) -> dict[str, np.ndarray]:
    arrays: dict[str, np.ndarray] = {}
    for name in CANONICAL_MASKS:
        path = directory / f"{name}.nii.gz"
        if not path.is_file():
            raise NormalizationError(f"missing canonical mask: {path.name}")
        image = nib.load(str(path))
        if not geometry_compatible(source.shape, source.affine, image.shape, image.affine):
            raise NormalizationError(f"geometry mismatch for canonical mask {name}")
        data = np.asanyarray(image.dataobj)
        if not np.all(np.isfinite(data)):
            raise NormalizationError(f"canonical mask {name} contains non-finite values")
        arrays[name] = np.asarray(data > 0, dtype=bool)
    for index, first in enumerate(CANONICAL_MASKS):
        for second in CANONICAL_MASKS[index + 1 :]:
            overlap = int(np.count_nonzero(arrays[first] & arrays[second]))
            if overlap:
                raise NormalizationError(f"canonical masks {first} and {second} overlap in {overlap} voxels")
    return arrays


def write_combined_labels(source_image: str | Path, normalized_directory: str | Path) -> Path:
    """Validate canonical masks and write the stable uint8 combined label map."""
    source = nib.load(str(source_image))
    directory = Path(normalized_directory)
    arrays = _validated_arrays(source, directory)
    combined = np.zeros(source.shape, dtype=np.uint8)
    for name, value in COMBINED_LABEL_VALUES.items():
        combined[arrays[name]] = value
    image = nib.Nifti1Image(combined, source.affine, source.header.copy())
    image.set_data_dtype(np.uint8)
    image.set_qform(source.affine, code=1)
    image.set_sform(source.affine, code=1)
    destination = directory / f"{COMBINED_LABELS}.nii.gz"
    nib.save(image, destination)
    return destination


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

    arrays: dict[str, np.ndarray] = {}
    for backend_name, canonical_name in mapping.items():
        mask = nib.load(str(raw / f"{backend_name}.nii.gz"))
        if not geometry_compatible(source.shape, source.affine, mask.shape, mask.affine):
            raise NormalizationError(
                f"geometry mismatch for {backend_name}: source shape/affine differ from mask"
            )
        values = np.asanyarray(mask.dataobj)
        if not np.all(np.isfinite(values)):
            raise NormalizationError(f"mask {backend_name} contains non-finite values")
        arrays[canonical_name] = np.asarray(values > 0, dtype=bool)
    for index, first in enumerate(CANONICAL_MASKS):
        for second in CANONICAL_MASKS[index + 1 :]:
            if np.any(arrays[first] & arrays[second]):
                raise NormalizationError(f"backend masks {first} and {second} overlap")

    output.mkdir(parents=True, exist_ok=True)
    result: dict[str, str] = {}
    for name, data in arrays.items():
        destination = output / f"{name}.nii.gz"
        image = nib.Nifti1Image(data.astype(np.uint8), source.affine, source.header.copy())
        image.set_data_dtype(np.uint8)
        image.set_qform(source.affine, code=1)
        image.set_sform(source.affine, code=1)
        nib.save(image, destination)
        result[name] = str(destination)
    result[COMBINED_LABELS] = str(write_combined_labels(source_image, output))
    return result
