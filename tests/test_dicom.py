from types import SimpleNamespace

from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, MRImageStorage, generate_uid

from vtseg.dicom.series import (
    InstanceRecord,
    acquisition_type,
    inventory_report,
    scan_headers,
    summarize_series,
)


def test_scan_groups_by_study_and_series(tmp_path, dicom_writer):
    study = "1.2.826.0.1.3680043.10.2000.1"
    series_a = "1.2.826.0.1.3680043.10.2000.2"
    series_b = "1.2.826.0.1.3680043.10.2000.3"
    dicom_writer(tmp_path / "nested" / "a1", study_uid=study, series_uid=series_a, z=0)
    dicom_writer(tmp_path / "nested" / "a2", study_uid=study, series_uid=series_a, z=4, instance=2)
    dicom_writer(tmp_path / "b1", study_uid=study, series_uid=series_b, z=0)
    report = inventory_report(scan_headers(tmp_path))
    assert len(report["studies"]) == 1
    assert {s["series_uid"] for s in report["studies"][0]["series"]} == {series_a, series_b}


def test_missing_uid_metadata_is_reported_not_manufactured(tmp_path):
    meta = FileMetaDataset()
    meta.TransferSyntaxUID = ExplicitVRLittleEndian
    meta.MediaStorageSOPClassUID = MRImageStorage
    meta.MediaStorageSOPInstanceUID = generate_uid()
    dataset = FileDataset(str(tmp_path / "missing"), {}, file_meta=meta, preamble=b"\0" * 128)
    dataset.Modality = "MR"
    dataset.save_as(tmp_path / "missing", enforce_file_format=True)
    # Add one valid file so an inventory exists.
    dataset.StudyInstanceUID = generate_uid()
    dataset.SeriesInstanceUID = generate_uid()
    dataset.SOPInstanceUID = generate_uid()
    dataset.save_as(tmp_path / "valid", enforce_file_format=True)
    inventory = scan_headers(tmp_path)
    assert len(inventory.skipped) == 1
    assert "missing study/series UID" in inventory.skipped[0]["reason"]


def test_summary_flags_inconsistent_dimensions_and_spacing(header_factory):
    a = header_factory(0, 1)
    b = header_factory(4, 2, Rows=8, PixelSpacing=[2.5, 3.0])
    records = [
        InstanceRecord("a", a.StudyInstanceUID, a.SeriesInstanceUID, a.SOPInstanceUID, a),
        InstanceRecord("b", b.StudyInstanceUID, b.SeriesInstanceUID, b.SOPInstanceUID, b),
    ]
    summary = summarize_series(records)
    assert "inconsistent Rows/Columns" in summary["warnings"]
    assert "missing or inconsistent PixelSpacing" in summary["warnings"]


def test_duplicate_sop_is_reported(header_factory):
    a = header_factory(0, 1)
    b = header_factory(4, 2, SOPInstanceUID=a.SOPInstanceUID)
    summary = summarize_series([
        InstanceRecord("a", a.StudyInstanceUID, a.SeriesInstanceUID, a.SOPInstanceUID, a),
        InstanceRecord("b", b.StudyInstanceUID, b.SeriesInstanceUID, b.SOPInstanceUID, b),
    ])
    assert summary["duplicate_sop_instances"] == 1


def test_modality_and_sequence_characterization():
    assert acquisition_type("CT", "anything", None) == "ct"
    assert acquisition_type("MR", "SAO 3D MDE NAV", None) == "lge_mde"
    assert acquisition_type("MR", "SA FIESTA gated", None) == "cine_bssfp"
    assert acquisition_type("US", None, None) == "unknown"
