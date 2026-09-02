import nibabel as nib
import numpy as np
import pytest

from vtseg.qc.masks import evaluate_masks, mask_statistics, run_backend_qc, run_case_qc


def test_empty_mask_statistics():
    stats = mask_statistics(np.zeros((4, 5, 6)), np.diag([2, 2, 3, 1]))
    assert stats["empty"]
    assert stats["connected_components"] == 0
    assert stats["mask_physical_volume_ml"] == 0


def test_components_volume_border_and_bbox():
    mask = np.zeros((5, 5, 5), dtype=np.uint8)
    mask[1:3, 1:3, 1:3] = 1
    mask[4, 4, 4] = 1
    stats = mask_statistics(mask, np.diag([2, 2, 2, 1]))
    assert stats["connected_components"] == 2
    assert stats["largest_component_voxels"] == 8
    assert stats["largest_component_fraction"] == pytest.approx(8 / 9)
    assert stats["mask_physical_volume_ml"] == pytest.approx(0.072)
    assert stats["touches_image_border"]
    assert stats["bounding_box_voxels_inclusive"] == {"min": [1, 1, 1], "max": [4, 4, 4]}


def save(path, data, affine=None):
    nib.save(nib.Nifti1Image(data.astype(np.uint8), np.eye(4) if affine is None else affine), path)


def test_cross_mask_identical_and_affine_mismatch_warnings(tmp_path):
    source = tmp_path / "source.nii.gz"
    save(source, np.zeros((5, 5, 5)))
    mask = np.zeros((5, 5, 5)); mask[1:3, 1:3, 1:3] = 1
    lv = tmp_path / "lv.nii.gz"; rv = tmp_path / "rv.nii.gz"; myo = tmp_path / "myo.nii.gz"
    save(lv, mask); save(rv, mask)
    shifted = np.eye(4); shifted[0, 3] = 1
    save(myo, mask, shifted)
    report = evaluate_masks(source, {"lv_blood_pool": lv, "rv_blood_pool": rv, "myocardium": myo})
    assert report["cross_mask_checks"]["lv_vs_rv"]["identical"]
    assert "LV and RV masks are identical" in report["warnings"]
    assert any("myocardium geometry" in warning for warning in report["warnings"])


def test_case_qc_writes_machine_readable_report(tmp_path):
    (tmp_path / "volume").mkdir()
    normalized = tmp_path / "segmentation" / "normalized"
    normalized.mkdir(parents=True)
    source = np.zeros((4, 4, 4))
    save(tmp_path / "volume" / "image.nii.gz", source)
    for index, name in enumerate(("lv_blood_pool", "rv_blood_pool", "myocardium"), start=1):
        mask = np.zeros((4, 4, 4)); mask[index, 1, 1] = 1
        save(normalized / f"{name}.nii.gz", mask)
    report = run_case_qc(tmp_path)
    assert (tmp_path / "qc" / "mask_qc.json").is_file()
    assert len(report["masks"]) == 3


def test_backend_scoped_qc_uses_requested_paths(tmp_path):
    (tmp_path / "volume").mkdir()
    normalized = tmp_path / "segmentation" / "bivme" / "normalized"
    normalized.mkdir(parents=True)
    save(tmp_path / "volume" / "image.nii.gz", np.zeros((4, 4, 4)))
    for index, name in enumerate(("lv_blood_pool", "rv_blood_pool", "myocardium"), start=1):
        mask = np.zeros((4, 4, 4))
        mask[index, 1, 1] = 1
        save(normalized / f"{name}.nii.gz", mask)
    report_path = tmp_path / "qc" / "bivme" / "mask_qc.json"
    report = run_backend_qc(
        tmp_path,
        normalized_directory=normalized,
        report_path=report_path,
    )
    assert report_path.is_file()
    assert report["masks"]["myocardium"]["file"].startswith("segmentation/bivme/")
