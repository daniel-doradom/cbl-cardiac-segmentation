import json

import pytest

from vtseg.provenance import base_provenance, validate_provenance, write_provenance


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
