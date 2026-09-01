import nibabel as nib
import numpy as np

from vtseg.dicom.convert import prepare_series
from vtseg.dicom.series import scan_headers


def test_prepare_series_retains_all_spatial_slices_and_geometry(tmp_path, dicom_writer):
    source = tmp_path / "source"
    case = tmp_path / "case"
    study = "1.2.826.0.1.3680043.10.3000.1"
    series = "1.2.826.0.1.3680043.10.3000.2"
    for index, z in enumerate((8.0, 0.0, 4.0), start=1):
        dicom_writer(source / f"image{index}", study_uid=study, series_uid=series, z=z, instance=index)
    provenance = prepare_series(scan_headers(source), series, case)
    image = nib.load(str(case / "volume" / "image.nii.gz"))
    data = np.asanyarray(image.dataobj)
    assert image.shape == (4, 5, 3)
    # Spatial order follows z, while the pixel values identify source instances.
    assert data[0, 0, :].tolist() == [2.0, 3.0, 1.0]
    assert image.header.get_zooms()[:3] == (2.0, 3.0, 4.0)
    assert provenance["source_dicom_count"] == 3
    assert (case / "source" / "selected_series.json").is_file()


def test_prepare_cine_selects_requested_trigger_frame(tmp_path, dicom_writer):
    source = tmp_path / "source"
    case = tmp_path / "case"
    study = "1.2.826.0.1.3680043.10.3100.1"
    series = "1.2.826.0.1.3680043.10.3100.2"
    instance = 1
    for z in (0.0, 4.0):
        for trigger in (10.0, 20.0):
            dicom_writer(
                source / f"image{instance}", study_uid=study, series_uid=series,
                z=z, instance=instance, trigger_time=trigger,
            )
            instance += 1
    provenance = prepare_series(scan_headers(source), series, case, frame=1)
    assert provenance["source_dicom_count"] == 2
    assert provenance["selected_temporal_frame"]["temporal_value"] == 20.0
