import json

import nibabel as nib
import numpy as np
import pytest

from vtseg.segmentation.matlab_import import import_matlab_case


def test_import_matlab_masks_reconstructs_reference_grid(tmp_path):
    scipy = pytest.importorskip("scipy.io")
    reference = tmp_path / "reference"
    (reference / "volume").mkdir(parents=True)
    (reference / "source").mkdir()
    image = nib.Nifti1Image(np.zeros((5, 6, 4), dtype=np.float32), np.eye(4))
    nib.save(image, reference / "volume" / "image.nii.gz")
    (reference / "source" / "selected_series.json").write_text(
        json.dumps({"study_uid": "synthetic-study", "series_uid": "synthetic-series"}),
        encoding="utf-8",
    )

    matlab_case = tmp_path / "matlab"
    seg = matlab_case / "seg"
    seg.mkdir(parents=True)
    stack_shape = (5, 6, 2)
    lv = np.zeros(stack_shape, dtype=np.uint8); lv[1, 1, :] = 1
    rv = np.zeros(stack_shape, dtype=np.uint8); rv[3, 1, :] = 1
    epi = np.zeros(stack_shape, dtype=np.uint8); epi[0:5, 0:3, :] = 1
    scipy.savemat(seg / "Lendo.mat", {"Lendo": lv})
    scipy.savemat(seg / "Rendo.mat", {"Rendo": rv})
    scipy.savemat(seg / "Epi.mat", {"Epi": epi})
    (seg / "bivme_export_manifest.json").write_text(json.dumps({"slices": [
        {"reference_volume_index": 0}, {"reference_volume_index": 3}
    ]}), encoding="utf-8")

    output = tmp_path / "manual" / "normalized"
    metadata = import_matlab_case(matlab_case, reference, output)
    assert metadata["selected_slice_count"] == 2
    myocardium = np.asanyarray(nib.load(output / "myocardium.nii.gz").dataobj)
    assert np.count_nonzero(myocardium[:, :, 1:3]) == 0
    combined = np.asanyarray(nib.load(output / "combined_labels.nii.gz").dataobj)
    assert combined.dtype == np.uint8
    assert set(np.unique(combined)) == {0, 1, 2, 3}
    assert (output.parent / "qc" / "mask_qc.json").is_file()
    assert (output.parent / "provenance.json").is_file()
