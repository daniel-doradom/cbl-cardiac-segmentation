import json
from pathlib import Path

import numpy as np
import pytest

from vtseg.provenance import base_provenance, validate_provenance, write_json, write_provenance


def test_base_provenance_has_required_reproducibility_fields(tmp_path):
    record = base_provenance(
        input_study_uid="synthetic-study",
        selected_series_uid="synthetic-series",
        modality="CT",
        source_dicom_count=3,
    )
    destination = tmp_path / "provenance.json"
    write_provenance(destination, record)
    loaded = json.loads(destination.read_text())
    assert loaded["pipeline_version"]
    assert loaded["software_versions"]["python"]
    assert loaded["warnings"] == []


def test_required_field_validation():
    with pytest.raises(ValueError, match="missing required fields"):
        validate_provenance({"warnings": [], "errors": []})


def test_serialization_is_stably_sorted(tmp_path):
    record = base_provenance(input_study_uid="x", selected_series_uid="y")
    path = tmp_path / "p.json"
    write_provenance(path, record)
    lines = path.read_text().splitlines()
    assert lines[1].lstrip().startswith('"acquisition_characterization"')


def test_json_serializes_numpy_values_and_paths(tmp_path):
    path = tmp_path / "values.json"
    write_json(
        path,
        {
            "spacing": [np.float32(1.25)],
            "affine": np.array([[1, 0], [0, 1]], dtype=np.float32),
            "output": Path("segmentation/normalized/myocardium.nii.gz"),
        },
    )
    loaded = json.loads(path.read_text())
    assert loaded["spacing"] == [1.25]
    assert loaded["affine"] == [[1.0, 0.0], [0.0, 1.0]]
    assert loaded["output"] == "segmentation/normalized/myocardium.nii.gz"
