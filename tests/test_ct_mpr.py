import json

import nibabel as nib
import numpy as np
import pydicom
import pytest
from pydicom.uid import CTImageStorage

from vtseg.dicom.convert import prepare_series
from vtseg.dicom.series import scan_headers
from vtseg.errors import GeometryError, NormalizationError
from vtseg.review import collect_review
from vtseg.segmentation.ct_mpr import map_native_ct_masks_to_mpr, promote_ct_candidate
from vtseg.segmentation.matlab_export import export_matlab_case
from vtseg.segmentation.matlab_import import import_matlab_case
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


def _native_masks(case, *, full_stack=False):
    directory = case / "segmentation" / "totalsegmentator" / "normalized"
    directory.mkdir(parents=True)
    source = nib.load(str(case / "volume" / "image.nii.gz"))
    for index, name in enumerate(CANONICAL_MASKS):
        data = np.zeros(source.shape, dtype=np.uint8)
        data[index + 1, index + 1, :] = 1 if full_stack else 0
        if not full_stack:
            data[index + 1, index + 1, 1] = 1
        nib.save(nib.Nifti1Image(data, source.affine), str(directory / f"{name}.nii.gz"))
    write_combined_labels(case / "volume" / "image.nii.gz", directory)


def test_mapping_uses_target_mpr_geometry_and_categorical_values(tmp_path):
    native = _case(tmp_path, "native")
    _native_masks(native)
    mpr_affine = np.diag([0.5, 0.5, 1.0, 1.0])
    mpr = _case(tmp_path, "mpr", shape=(12, 12, 4), affine=mpr_affine)
    map_native_ct_masks_to_mpr(native, mpr)
    target = nib.load(str(mpr / "segmentation" / "native_ct_mapped" / "normalized" / "combined_labels.nii.gz"))
    assert target.shape == (12, 12, 4)
    assert np.allclose(target.affine, mpr_affine)
    values = np.asarray(target.dataobj)
    assert set(np.unique(values)) == {0, 1, 2, 3}
    assert [int(values[index, index, 1]) for index in (2, 4, 6)] == [1, 2, 3]


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


def test_promotion_rejects_inconsistent_combined_labels_before_copy(tmp_path):
    mpr = _case(tmp_path, "mpr")
    _native_masks(mpr)
    combined_path = mpr / "segmentation" / "totalsegmentator" / "normalized" / "combined_labels.nii.gz"
    combined = nib.load(str(combined_path))
    invalid = np.asarray(combined.dataobj).copy()
    invalid[1, 1, 1] = 2
    nib.save(nib.Nifti1Image(invalid, combined.affine), str(combined_path))
    best = tmp_path / "best"
    with pytest.raises(NormalizationError, match="disagree"):
        promote_ct_candidate(mpr, "direct-mpr", best)
    assert not best.exists()


def test_mapping_rejects_incomplete_source_before_creating_destination(tmp_path):
    native = _case(tmp_path, "native")
    _native_masks(native)
    (native / "segmentation" / "totalsegmentator" / "normalized" / "rv_blood_pool.nii.gz").unlink()
    mpr = _case(tmp_path, "mpr")
    with pytest.raises(NormalizationError, match="missing canonical"):
        map_native_ct_masks_to_mpr(native, mpr)
    assert not (mpr / "segmentation" / "native_ct_mapped").exists()


def test_ct_dicom_to_mpr_review_promotion_matlab_round_trip(tmp_path, dicom_writer):
    pytest.importorskip("scipy.io")
    study_uid = "1.2.826.0.1.3680043.10.491.1"
    frame_uid = "1.2.826.0.1.3680043.10.491.2"
    cases = []
    for series_index, label in enumerate(("native", "mpr"), start=1):
        dicom_root = tmp_path / f"{label}-dicom"
        series_uid = f"1.2.826.0.1.3680043.10.491.{series_index + 2}"
        for index in range(4):
            path = dicom_writer(
                dicom_root / f"original_{index + 1:02d}.dcm", study_uid=study_uid,
                series_uid=series_uid, z=float(index * 4), instance=index + 1,
                modality="CT", frame_of_reference=frame_uid,
            )
            ds = pydicom.dcmread(str(path))
            ds.SOPClassUID = CTImageStorage
            ds.file_meta.MediaStorageSOPClassUID = CTImageStorage
            ds.RescaleSlope = 2
            ds.RescaleIntercept = -1024
            ds.WindowCenter = 40
            ds.WindowWidth = 400
            ds.save_as(path, enforce_file_format=True)
        case = tmp_path / label
        prepare_series(scan_headers(dicom_root), series_uid, case)
        selection = json.loads((case / "source" / "selected_series.json").read_text())
        assert selection["frame_of_reference_uid"] == frame_uid
        assert nib.load(str(case / "volume" / "image.nii.gz")).get_fdata()[0, 0, 0] == -1022
        _native_masks(case, full_stack=True)
        cases.append(case)

    native, mpr = cases
    mapped_provenance = map_native_ct_masks_to_mpr(native, mpr)
    assert mapped_provenance["modality"] == "CT"
    review = collect_review(mpr)
    assert [pair["id"] for pair in review["pairs"]] == ["1_direct_mpr", "2_native_ct_mapped"]
    best = tmp_path / "best"
    promote_ct_candidate(mpr, "native-mapped", best)
    promoted_review = collect_review(best)
    assert [pair["id"] for pair in promoted_review["pairs"]] == ["1_selected_ct"]
    matlab_case = tmp_path / "matlab"
    manifest = export_matlab_case(
        best / "segmentation" / "selected" / "normalized", best, matlab_case,
        start_slice=1, end_slice=4, slices=3, slicer_approved=True,
    )
    assert manifest["modality"] == "CT"
    assert [entry["reference_volume_index"] for entry in manifest["slices"]] == [0, 2, 3]
    assert manifest["slices"][0]["source_dicom_filename"] == "original_01.dcm"
    assert manifest["slices"][0]["image_position_patient"] == [10.0, 20.0, 0.0]
    assert (matlab_case / "seg" / "vtseg_export_manifest.json").is_file()
    assert (matlab_case / "raw" / "slice_0001.dcm").is_file()
    import_matlab_case(matlab_case, best, best / "manual" / "normalized")
    imported = nib.load(str(best / "manual" / "normalized" / "combined_labels.nii.gz"))
    assert imported.shape == nib.load(str(best / "volume" / "image.nii.gz")).shape
    assert set(np.unique(np.asarray(imported.dataobj))) == {0, 1, 2, 3}
    assert json.loads((best / "manual" / "provenance.json").read_text())["modality"] == "CT"
