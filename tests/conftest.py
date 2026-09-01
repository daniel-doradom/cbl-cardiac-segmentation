from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pydicom
import pytest
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, MRImageStorage, generate_uid


@pytest.fixture
def header_factory():
    def make(z: float, instance: int, **values):
        defaults = {
            "StudyInstanceUID": "1.2.826.0.1.3680043.10.1000.1",
            "SeriesInstanceUID": "1.2.826.0.1.3680043.10.1000.2",
            "SOPInstanceUID": f"1.2.826.0.1.3680043.10.1000.3.{instance}",
            "Modality": "MR",
            "SeriesNumber": 1,
            "SeriesDescription": "Synthetic cine",
            "ProtocolName": "Synthetic",
            "Rows": 4,
            "Columns": 5,
            "PixelSpacing": [2.0, 3.0],
            "SliceThickness": 4.0,
            "SpacingBetweenSlices": 4.0,
            "ImageOrientationPatient": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0],
            "ImagePositionPatient": [10.0, 20.0, z],
            "InstanceNumber": instance,
            "CardiacNumberOfImages": 1,
        }
        defaults.update(values)
        return SimpleNamespace(**defaults)

    return make


@pytest.fixture
def dicom_writer():
    def write(
        path: Path,
        *,
        study_uid: str,
        series_uid: str,
        sop_uid: str | None = None,
        z: float = 0.0,
        instance: int = 1,
        modality: str = "MR",
        trigger_time: float | None = None,
        pixels: np.ndarray | None = None,
    ) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        meta = FileMetaDataset()
        meta.TransferSyntaxUID = ExplicitVRLittleEndian
        meta.MediaStorageSOPClassUID = MRImageStorage
        meta.MediaStorageSOPInstanceUID = sop_uid or generate_uid()
        ds = FileDataset(str(path), {}, file_meta=meta, preamble=b"\0" * 128)
        ds.SOPClassUID = meta.MediaStorageSOPClassUID
        ds.SOPInstanceUID = meta.MediaStorageSOPInstanceUID
        ds.StudyInstanceUID = study_uid
        ds.SeriesInstanceUID = series_uid
        ds.Modality = modality
        ds.SeriesNumber = 1
        ds.SeriesDescription = "Synthetic non-PHI series"
        ds.ProtocolName = "Synthetic"
        ds.Rows = 4
        ds.Columns = 5
        ds.PixelSpacing = [2.0, 3.0]
        ds.SliceThickness = 4.0
        ds.SpacingBetweenSlices = 4.0
        ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
        ds.ImagePositionPatient = [10, 20, z]
        ds.InstanceNumber = instance
        if trigger_time is not None:
            ds.TriggerTime = trigger_time
        data = np.full((4, 5), instance, dtype=np.uint16) if pixels is None else pixels
        ds.SamplesPerPixel = 1
        ds.PhotometricInterpretation = "MONOCHROME2"
        ds.BitsAllocated = 16
        ds.BitsStored = 16
        ds.HighBit = 15
        ds.PixelRepresentation = 0
        ds.PixelData = data.astype(np.uint16).tobytes()
        ds.save_as(path, enforce_file_format=True)
        return path

    return write
