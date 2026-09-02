import nibabel as nib
import numpy as np
import pytest

from vtseg.errors import NormalizationError
from vtseg.segmentation.normalize import TOTALSEGMENTATOR_CT_MAPPING, normalize_masks


def save(path, shape=(5, 6, 7), affine=None, value=1, region=None):
    affine = np.eye(4) if affine is None else affine
    data = np.zeros(shape, dtype=np.uint8)
    data[region or np.s_[:, :, :]] = value
    nib.save(nib.Nifti1Image(data, affine), path)


def write_ct_masks(raw):
    for backend_name, region in zip(
        TOTALSEGMENTATOR_CT_MAPPING,
        (np.s_[0:1, :, :], np.s_[1:2, :, :], np.s_[2:3, :, :]),
    ):
        save(raw / f"{backend_name}.nii.gz", region=region)


def test_backend_names_are_normalized_to_canonical_interface(tmp_path):
    source = tmp_path / "image.nii.gz"
    raw = tmp_path / "raw"
    output = tmp_path / "normalized"
    raw.mkdir()
    save(source, value=0)
    write_ct_masks(raw)
    normalize_masks(source, raw, output, TOTALSEGMENTATOR_CT_MAPPING)
    assert {item.name for item in output.iterdir()} == {
        "lv_blood_pool.nii.gz", "rv_blood_pool.nii.gz", "myocardium.nii.gz", "combined_labels.nii.gz"
    }
    combined = np.asanyarray(nib.load(output / "combined_labels.nii.gz").dataobj)
    assert combined.dtype == np.uint8
    assert set(np.unique(combined)) == {0, 1, 2, 3}


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
    write_ct_masks(raw)
    shifted = np.eye(4)
    shifted[0, 3] = 10
    save(raw / "heart_myocardium.nii.gz", affine=shifted)
    with pytest.raises(NormalizationError, match="geometry mismatch"):
        normalize_masks(source, raw, tmp_path / "out", TOTALSEGMENTATOR_CT_MAPPING)


def test_overlapping_backend_masks_fail(tmp_path):
    source = tmp_path / "image.nii.gz"
    raw = tmp_path / "raw"
    raw.mkdir()
    save(source)
    for backend_name in TOTALSEGMENTATOR_CT_MAPPING:
        save(raw / f"{backend_name}.nii.gz", region=np.s_[0:1, :, :])
    with pytest.raises(NormalizationError, match="overlap"):
        normalize_masks(source, raw, tmp_path / "out", TOTALSEGMENTATOR_CT_MAPPING)
