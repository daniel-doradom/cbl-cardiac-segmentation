import nibabel as nib
import numpy as np
import pytest

from vtseg.errors import NormalizationError
from vtseg.segmentation.normalize import TOTALSEGMENTATOR_CT_MAPPING, normalize_masks


def save(path, shape=(5, 6, 7), affine=None, value=1):
    affine = np.eye(4) if affine is None else affine
    nib.save(nib.Nifti1Image(np.full(shape, value, dtype=np.uint8), affine), path)


def test_backend_names_are_normalized_to_canonical_interface(tmp_path):
    source = tmp_path / "image.nii.gz"
    raw = tmp_path / "raw"
    output = tmp_path / "normalized"
    raw.mkdir()
    save(source, value=0)
    for backend_name in TOTALSEGMENTATOR_CT_MAPPING:
        save(raw / f"{backend_name}.nii.gz")
    normalize_masks(source, raw, output, TOTALSEGMENTATOR_CT_MAPPING)
    assert {item.name for item in output.iterdir()} == {
        "lv_blood_pool.nii.gz", "rv_blood_pool.nii.gz", "myocardium.nii.gz"
    }


def test_missing_backend_label_fails_before_partial_copy(tmp_path):
    source = tmp_path / "image.nii.gz"
    raw = tmp_path / "raw"
    output = tmp_path / "normalized"
    raw.mkdir()
    save(source)
    save(raw / "heart_ventricle_left.nii.gz")
    with pytest.raises(NormalizationError, match="did not produce required labels"):
        normalize_masks(source, raw, output, TOTALSEGMENTATOR_CT_MAPPING)
    assert not output.exists()


def test_geometry_mismatch_fails(tmp_path):
    source = tmp_path / "image.nii.gz"
    raw = tmp_path / "raw"
    raw.mkdir()
    save(source)
    for backend_name in TOTALSEGMENTATOR_CT_MAPPING:
        save(raw / f"{backend_name}.nii.gz")
    shifted = np.eye(4)
    shifted[0, 3] = 10
    save(raw / "heart_myocardium.nii.gz", affine=shifted)
    with pytest.raises(NormalizationError, match="geometry mismatch"):
        normalize_masks(source, raw, tmp_path / "out", TOTALSEGMENTATOR_CT_MAPPING)
