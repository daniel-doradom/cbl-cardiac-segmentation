import json

import nibabel as nib
import numpy as np
import pytest

from vtseg.errors import GeometryError
from vtseg.segmentation.ct_mpr import map_native_ct_masks_to_mpr, promote_ct_candidate
from vtseg.segmentation.normalize import CANONICAL_MASKS, write_combined_labels


def _case(root, name, shape=(6, 6, 4), affine=None, frame="for-1"):
    case = root / name
    affine = np.eye(4) if affine is None else affine
    case.joinpath("volume").mkdir(parents=True)
    nib.save(nib.Nifti1Image(np.zeros(shape, dtype=np.int16), affine), str(case / "volume" / "image.nii.gz"))
    case.joinpath("source").mkdir()
    (case / "source" / "selected_series.json").write_text(json.dumps({
        "study_uid": "study-1", "series_uid": name, "selected_temporal_frame": None,
        "selected_instance_count": shape[2], "selected_instance_paths": [f"{index}.dcm" for index in range(shape[2])],
        "frame_of_reference_uid": frame, "series_characterization": {"modality": "CT"},
    }), encoding="utf-8")
    return case


def _native_masks(case):
    directory = case / "segmentation" / "totalsegmentator" / "normalized"
    directory.mkdir(parents=True)
    source = nib.load(str(case / "volume" / "image.nii.gz"))
    for index, name in enumerate(CANONICAL_MASKS):
        data = np.zeros(source.shape, dtype=np.uint8)
        data[index + 1, index + 1, 1] = 1
        nib.save(nib.Nifti1Image(data, source.affine), str(directory / f"{name}.nii.gz"))
    write_combined_labels(case / "volume" / "image.nii.gz", directory)


def test_mapping_uses_target_mpr_geometry_and_categorical_values(tmp_path):
    native = _case(tmp_path, "native")
    _native_masks(native)
    mpr_affine = np.diag([0.5, 0.5, 1.5, 1.0])
    mpr = _case(tmp_path, "mpr", shape=(12, 12, 3), affine=mpr_affine)
    map_native_ct_masks_to_mpr(native, mpr)
    target = nib.load(str(mpr / "segmentation" / "native_ct_mapped" / "normalized" / "combined_labels.nii.gz"))
    assert target.shape == (12, 12, 3)
    assert np.allclose(target.affine, mpr_affine)
    assert set(np.unique(target.get_fdata())).issubset({0, 1, 2, 3})


def test_mapping_rejects_frame_of_reference_mismatch(tmp_path):
    native = _case(tmp_path, "native", frame="native-frame")
    _native_masks(native)
    mpr = _case(tmp_path, "mpr", frame="mpr-frame")
    with pytest.raises(GeometryError, match="FrameOfReferenceUID"):
        map_native_ct_masks_to_mpr(native, mpr)


def test_promotion_copies_only_selected_candidate_masks(tmp_path):
    mpr = _case(tmp_path, "mpr")
    _native_masks(mpr)
    best = tmp_path / "best"
    promote_ct_candidate(mpr, "direct-mpr", best)
    assert (best / "segmentation" / "selected" / "normalized" / "combined_labels.nii.gz").is_file()
    assert not (best / "segmentation" / "totalsegmentator").exists()
    selection = json.loads((best / "segmentation" / "selected" / "selection.json").read_text())
    assert selection["candidate"] == "direct-mpr"
