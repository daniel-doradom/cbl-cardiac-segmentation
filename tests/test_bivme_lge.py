import json
from pathlib import Path

import nibabel as nib
import numpy as np
import pytest

from vtseg.dicom.series import InstanceRecord, Inventory
from vtseg.errors import NormalizationError, RegistrationError
from vtseg.segmentation.bivme_lge import (
    align_bivme_to_lge,
    match_cine_frame,
    register_cine_to_lge,
    select_lge_series,
    transform_mesh_lps,
)


def _records(headers, root: Path):
    return [
        InstanceRecord(
            str(root / f"image-{index}"),
            header.StudyInstanceUID,
            header.SeriesInstanceUID,
            header.SOPInstanceUID,
            header,
        )
        for index, header in enumerate(headers)
    ]


def test_select_lge_series_prefers_denser_regular_stack(tmp_path, header_factory):
    study = "1.2.826.0.1.3680043.10.5000.1"
    sparse_uid = "1.2.826.0.1.3680043.10.5000.2"
    dense_uid = "1.2.826.0.1.3680043.10.5000.3"
    headers = []
    for uid, positions in ((sparse_uid, (0.0, 8.0)), (dense_uid, (0.0, 1.0, 2.0, 3.0))):
        headers.extend([
            header_factory(
                z,
                index + 1,
                StudyInstanceUID=study,
                SeriesInstanceUID=uid,
                SeriesDescription="Synthetic 3D MDE",
                SliceThickness=1.0,
                SpacingBetweenSlices=1.0,
            )
            for index, z in enumerate(positions)
        ])
    inventory = Inventory(tmp_path, _records(headers, tmp_path), [])
    selected_uid, summary = select_lge_series(inventory, study_uid=study)
    assert selected_uid == dense_uid
    assert summary["unique_spatial_positions"] == 4


def test_match_cine_frame_uses_nearest_lge_trigger(tmp_path, header_factory):
    cine_headers = []
    instance = 1
    for z in (0.0, 4.0):
        for trigger in (100.0, 200.0, 300.0):
            cine_headers.append(
                header_factory(
                    z,
                    instance,
                    TriggerTime=trigger,
                    CardiacNumberOfImages=3,
                )
            )
            instance += 1
    lge_headers = [header_factory(z, index + 1, TriggerTime=270.0) for index, z in enumerate((0, 1))]
    result = match_cine_frame(
        _records(cine_headers, tmp_path),
        _records(lge_headers, tmp_path),
    )
    assert result["frame"] == 2
    assert result["cine_temporal_value"] == 300.0
    assert result["timing_difference_ms"] == 30.0


def test_transform_mesh_lps_applies_physical_transform(tmp_path):
    pyvista = pytest.importorskip("pyvista")
    sitk = pytest.importorskip("SimpleITK")
    source = tmp_path / "source.vtk"
    output = tmp_path / "output.vtk"
    mesh = pyvista.Cube().triangulate()
    original = np.asarray(mesh.points).copy()
    mesh.save(source)
    transform_mesh_lps(source, output, sitk.TranslationTransform(3, (1.0, 2.0, 3.0)))
    transformed = pyvista.read(output)
    expected_lower = original.min(axis=0) + np.asarray([1.0, 2.0, 3.0])
    expected_upper = original.max(axis=0) + np.asarray([1.0, 2.0, 3.0])
    assert np.allclose(np.asarray(transformed.bounds)[::2], expected_lower)
    assert np.allclose(np.asarray(transformed.bounds)[1::2], expected_upper)


def test_rigid_registration_writes_invertible_transforms(tmp_path):
    pytest.importorskip("SimpleITK")
    shape = (24, 24, 24)
    grid = np.mgrid[: shape[0], : shape[1], : shape[2]]
    image_data = np.exp(-sum((grid[axis] - 12.0) ** 2 for axis in range(3)) / 30.0)
    mask_data = (image_data > 0.1).astype(np.uint8)
    fixed = tmp_path / "fixed.nii.gz"
    moving = tmp_path / "moving.nii.gz"
    nib.save(nib.Nifti1Image(image_data.astype(np.float32), np.eye(4)), fixed)
    nib.save(nib.Nifti1Image(image_data.astype(np.float32), np.eye(4)), moving)
    fixed_masks = tmp_path / "fixed-masks"
    moving_masks = tmp_path / "moving-masks"
    for directory in (fixed_masks, moving_masks):
        directory.mkdir()
        for name in ("lv_blood_pool", "rv_blood_pool", "myocardium"):
            nib.save(nib.Nifti1Image(mask_data, np.eye(4)), directory / f"{name}.nii.gz")
    _, report = register_cine_to_lge(
        fixed,
        moving,
        fixed_mask_directory=fixed_masks,
        moving_mask_directory=moving_masks,
        output_directory=tmp_path / "registration",
    )
    assert (tmp_path / "registration" / "moving_cine_to_fixed_lge.tfm").is_file()
    assert (tmp_path / "registration" / "cine_in_lge.nii.gz").is_file()
    assert report["center_displacement_mm"] < 1.0
    assert report["registration_rejected"] is False
    assert report["translation_bound_hit"] is False


def _shifted_blob_case(tmp_path, shift_mm):
    """An elongated blob with three sharp markers, and the same blob moved by
    ``shift_mm`` along x, on 1 mm voxels. The body gives the metric a pull over
    tens of millimetres; the markers pin all six rigid degrees of freedom."""
    shape = (64, 64, 64)
    grid = np.mgrid[: shape[0], : shape[1], : shape[2]].astype(float)
    rng = np.random.default_rng(7)
    offsets = rng.uniform(-1, 1, size=(3, 3)) * np.array([14.0, 8.0, 8.0])
    amplitudes = rng.uniform(0.5, 1.0, size=3)

    def pattern(x_center):
        center = np.array([x_center, 32.0, 32.0])
        body = np.exp(
            -((grid[0] - center[0]) ** 2 / (2 * 25.0**2)
              + (grid[1] - center[1]) ** 2 / (2 * 12.0**2)
              + (grid[2] - center[2]) ** 2 / (2 * 12.0**2))
        )
        markers = sum(
            amplitude * np.exp(
                -sum((grid[axis] - (center[axis] + offset[axis])) ** 2 for axis in range(3))
                / (2 * 3.0**2)
            )
            for amplitude, offset in zip(amplitudes, offsets)
        )
        return body + markers

    fixed_data = pattern(18.0)
    moving_data = pattern(18.0 + shift_mm)
    fixed = tmp_path / "fixed.nii.gz"
    moving = tmp_path / "moving.nii.gz"
    nib.save(nib.Nifti1Image(fixed_data.astype(np.float32), np.eye(4)), fixed)
    nib.save(nib.Nifti1Image(moving_data.astype(np.float32), np.eye(4)), moving)
    fixed_masks = tmp_path / "fixed-masks"
    moving_masks = tmp_path / "moving-masks"
    for directory, data in ((fixed_masks, fixed_data), (moving_masks, moving_data)):
        directory.mkdir()
        mask = (data > 0.2).astype(np.uint8)
        for name in ("lv_blood_pool", "rv_blood_pool", "myocardium"):
            nib.save(nib.Nifti1Image(mask, np.eye(4)), directory / f"{name}.nii.gz")
    return fixed, moving, fixed_masks, moving_masks


def test_registration_recovers_a_breath_hold_sized_shift(tmp_path):
    pytest.importorskip("SimpleITK")
    fixed, moving, fixed_masks, moving_masks = _shifted_blob_case(tmp_path, shift_mm=6.0)
    _, report = register_cine_to_lge(
        fixed,
        moving,
        fixed_mask_directory=fixed_masks,
        moving_mask_directory=moving_masks,
        output_directory=tmp_path / "registration",
    )
    assert report["registration_rejected"] is False
    assert report["translation_bound_hit"] is False
    assert 4.0 < report["center_displacement_mm"] < 9.0


def test_registration_stops_at_the_translation_bound(tmp_path):
    sitk = pytest.importorskip("SimpleITK")
    fixed, moving, fixed_masks, moving_masks = _shifted_blob_case(tmp_path, shift_mm=36.0)
    _, report = register_cine_to_lge(
        fixed,
        moving,
        fixed_mask_directory=fixed_masks,
        moving_mask_directory=moving_masks,
        output_directory=tmp_path / "registration",
    )
    assert report["translation_bound_hit"] is True
    assert report["max_translation_mm"] > 25.0
    assert report["registration_rejected"] is True
    assert any("25 mm bound" in reason for reason in report["rejection_reasons"])
    # the DICOM placement is used instead
    assert report["center_displacement_mm"] == 0.0
    used = sitk.ReadTransform(str(tmp_path / "registration" / "moving_cine_to_fixed_lge.tfm"))
    assert all(abs(value) < 1e-9 for value in used.GetParameters())


STUDY = "1.2.826.0.1.3680043.10.6000.1"
CINE_UID = "1.2.826.0.1.3680043.10.6000.2"
LGE_UID = "1.2.826.0.1.3680043.10.6000.3"
FRAME_OF_REFERENCE = "1.2.826.0.1.3680043.10.6000.9"
CINE_Z = (0.0, 4.0, 8.0, 12.0)
LGE_Z = (0.0, 3.0, 6.0, 9.0, 12.0, 15.0)
TRIGGERS = (40.0, 120.0, 200.0)


def _blob(z: float, rows: int = 16, columns: int = 16) -> np.ndarray:
    """Intensity blob positioned in DICOM LPS so both grids see the same object."""
    row_index, column_index = np.mgrid[:rows, :columns]
    x = 10.0 + column_index * 3.0
    y = 20.0 + row_index * 2.0
    squared = (x - 33.0) ** 2 + (y - 35.0) ** 2 + (z - 6.0) ** 2
    return (1000.0 * np.exp(-squared / 200.0)).astype(np.uint16)


def _write_study(root: Path, dicom_writer) -> None:
    instance = 1
    for z in CINE_Z:
        for trigger in TRIGGERS:
            dicom_writer(
                root / f"cine-{instance}.dcm",
                study_uid=STUDY,
                series_uid=CINE_UID,
                z=z,
                instance=instance,
                trigger_time=trigger,
                pixels=_blob(z),
                series_description="Synthetic CINE bSSFP",
                frame_of_reference=FRAME_OF_REFERENCE,
            )
            instance += 1
    for z in LGE_Z:
        dicom_writer(
            root / f"lge-{instance}.dcm",
            study_uid=STUDY,
            series_uid=LGE_UID,
            z=z,
            instance=instance,
            trigger_time=210.0,
            pixels=_blob(z),
            series_description="Synthetic MDE delayed enhancement",
            frame_of_reference=FRAME_OF_REFERENCE,
        )
        instance += 1


def _write_meshes(case: Path, frame: int, pyvista) -> None:
    """Fitted-mesh stand-ins in DICOM LPS, with the epicardium enclosing both cavities."""
    mesh_root = case / "segmentation" / "bivme" / "raw" / "models" / "case" / "vtk-meshes"
    mesh_root.mkdir(parents=True, exist_ok=True)
    surfaces = {
        "LV_ENDOCARDIAL": pyvista.Sphere(radius=4.0, center=(28.0, 35.0, 6.0)),
        "RV_ENDOCARDIAL": pyvista.Sphere(radius=4.0, center=(38.0, 35.0, 6.0)),
        "EPICARDIAL": pyvista.Sphere(radius=9.0, center=(33.0, 35.0, 6.0)),
    }
    for label, surface in surfaces.items():
        surface.triangulate().save(mesh_root / f"case_{label}_{frame:03}.vtk")


def _write_case(case: Path) -> None:
    source = case / "source"
    source.mkdir(parents=True, exist_ok=True)
    (source / "selected_series.json").write_text(
        json.dumps({"schema_version": 1, "study_uid": STUDY, "series_uid": CINE_UID}),
        encoding="utf-8",
    )
    bivme = case / "segmentation" / "bivme"
    bivme.mkdir(parents=True, exist_ok=True)
    (bivme / "provenance.json").write_text(
        json.dumps({"backend_version": "1.2", "warnings": ["upstream biv-me warning"]}),
        encoding="utf-8",
    )


def test_align_bivme_to_lge_end_to_end(tmp_path, dicom_writer):
    pytest.importorskip("SimpleITK")
    pyvista = pytest.importorskip("pyvista")

    dicom_root = tmp_path / "study"
    case = tmp_path / "case"
    _write_study(dicom_root, dicom_writer)
    _write_case(case)
    # LGE TriggerTime 210 ms is nearest the third cine phase (200 ms).
    _write_meshes(case, 2, pyvista)

    provenance = align_bivme_to_lge(case, dicom_directory=dicom_root)

    assert provenance["segmentation_backend"] == "biv-me-lge-alignment"
    assert provenance["selected_series_uid"] == LGE_UID
    assert provenance["selected_temporal_frame"]["frame"] == 2
    assert provenance["selected_temporal_frame"]["selection_method"] == "nearest_trigger_time"

    normalized = case / "segmentation" / "bivme" / "lge_aligned" / "normalized"
    lge_image = nib.load(str(case / "references" / "lge" / "volume" / "image.nii.gz"))
    for name in ("lv_blood_pool", "rv_blood_pool", "myocardium", "combined_labels"):
        mask = nib.load(str(normalized / f"{name}.nii.gz"))
        assert mask.shape == lge_image.shape
        assert np.allclose(mask.affine, lge_image.affine)
        assert int(np.count_nonzero(np.asanyarray(mask.dataobj))) > 0

    registration = case / "registration" / "bivme_to_lge"
    assert (registration / "metric_masks" / "cine" / "lv_blood_pool.nii.gz").is_file()
    assert (registration / "metric_masks" / "lge" / "lv_blood_pool.nii.gz").is_file()
    assert (registration / "moving_cine_to_fixed_lge.tfm").is_file()
    assert (registration / "fixed_lge_to_moving_cine.tfm").is_file()
    assert (registration / "cine_in_lge.nii.gz").is_file()

    qc = json.loads((case / "segmentation" / "bivme" / "lge_aligned" / "qc" / "lge_alignment.json").read_text(encoding="utf-8"))
    assert qc["frame_of_reference_matches"] is True
    assert qc["phase_matching"]["timing_difference_ms"] == 10.0
    assert "upstream biv-me warning" in qc["warnings"]
    assert any("manual cine-to-LGE alignment review" in item for item in qc["warnings"])

    # Provenance must reference files that exist, by case-relative path.
    for relative in provenance["output_files"]:
        assert (case / relative).exists(), relative


def test_export_matlab_seg_case(tmp_path, dicom_writer):
    pytest.importorskip("scipy")
    from scipy.io import loadmat

    from vtseg.segmentation.matlab_export import export_matlab_case, preview_matlab_slices

    # A prepared reference case, built the way prepare_series builds one.
    dicom_root = tmp_path / "study"
    for index, z in enumerate(LGE_Z):
        dicom_writer(
            dicom_root / f"IM{index:06d}",
            study_uid=STUDY, series_uid=LGE_UID, z=z, instance=len(LGE_Z) - index,
            pixels=_blob(z), series_description="Synthetic MDE",
        )
    from vtseg.dicom.convert import prepare_series
    from vtseg.dicom.series import scan_headers

    reference = tmp_path / "reference"
    prepare_series(scan_headers(dicom_root), LGE_UID, reference)

    image = nib.load(str(reference / "volume" / "image.nii.gz"))
    masks = tmp_path / "masks"
    masks.mkdir()
    lv = np.zeros(image.shape, dtype=np.uint8); lv[4:8, 4:8, :] = 1
    rv = np.zeros(image.shape, dtype=np.uint8); rv[9:12, 4:8, :] = 1
    myo = np.zeros(image.shape, dtype=np.uint8); myo[2:14, 2:10, :] = 1
    # The larger final endpoint is inferred as the base, so MATLAB order must reverse.
    myo[:, :, -1] = 1
    myo[lv > 0] = 0; myo[rv > 0] = 0
    for name, data in (("lv_blood_pool", lv), ("rv_blood_pool", rv), ("myocardium", myo)):
        nib.save(nib.Nifti1Image(data, image.affine), masks / f"{name}.nii.gz")

    preview = preview_matlab_slices(masks, reference)
    assert preview["slice_order"] == "base_to_apex"
    assert preview["slice_order_reason"] == "reference_last_endpoint_larger"
    assert preview["total_positions"] == image.shape[2]
    assert preview["suggested_start_slice"] == 1
    assert preview["suggested_end_slice"] == image.shape[2]
    assert [item["reference_z_index"] for item in preview["slices"]] == list(
        reversed(range(image.shape[2]))
    )

    unapproved_out = tmp_path / "matlab-case-unapproved"
    with pytest.raises(NormalizationError, match="3D Slicer review"):
        export_matlab_case(masks, reference, unapproved_out)
    assert not unapproved_out.exists()

    out = tmp_path / "matlab-case"
    manifest = export_matlab_case(
        masks, reference, out, start_slice=1, end_slice=5, slices=3,
        slicer_approved=True,
    )

    assert manifest["slice_count"] == 3
    assert manifest["slice_order"] == "base_to_apex"
    assert manifest["slice_order_reason"] == "reference_last_endpoint_larger"
    assert manifest["slicer_review"]["approved"] is True
    assert manifest["slicer_review"]["approval_recorded_at"]
    assert [item["base_to_apex_reference_slice"] for item in manifest["slices"]] == [1, 3, 5]
    assert [s["dicom_file"] for s in manifest["slices"]] == sorted(
        s["dicom_file"] for s in manifest["slices"]
    ), "MATLAB stack must be ordered by DICOM file name"
    exported = sorted(q.name for q in (out / "raw").iterdir())
    assert len(exported) == 3
    # readdata globs '*.dcm' case-sensitively; without the suffix it finds nothing.
    assert all(name.endswith(".dcm") for name in exported), exported
    assert exported == sorted(s["dicom_file"] for s in manifest["slices"])
    assert [s["reference_volume_index"] for s in manifest["slices"]] == [5, 3, 1]
    for d in ("mesh", "remesh", "global", "visualizations"):
        assert (out / d).is_dir()
    assert (out / "manifest.json").is_file()
    export_provenance = json.loads((out / "provenance.json").read_text(encoding="utf-8"))
    assert export_provenance["model_options"]["slicer_review"]["approved"] is True
    assert export_provenance["model_options"]["slicer_review"]["approval_recorded_at"] == (
        manifest["slicer_review"]["approval_recorded_at"]
    )

    epi = loadmat(str(out / "seg" / "Epi.mat"))["Epi"]
    lendo = loadmat(str(out / "seg" / "Lendo.mat"))["Lendo"]
    rendo = loadmat(str(out / "seg" / "Rendo.mat"))["Rendo"]
    myocardium = loadmat(str(out / "seg" / "myocardium.mat"))["myocardium"]
    assert epi.shape == (image.shape[0], image.shape[1], 3)
    # Epi must enclose both cavities, and myocardium is the wall between them.
    assert np.all(epi[lendo > 0]) and np.all(epi[rendo > 0])
    assert not np.any(myocardium & (lendo > 0)) and not np.any(myocardium & (rendo > 0))
    assert np.array_equal(myocardium > 0, (epi > 0) & ~(lendo > 0) & ~(rendo > 0))

    # info.mat is intentionally left to MATLAB's own readdata.
    assert not (out / "seg" / "info.mat").exists()

    endpoint_out = tmp_path / "matlab-case-endpoints"
    endpoint_manifest = export_matlab_case(
        masks, reference, endpoint_out, start_slice=1, end_slice=6, slices=4,
        slicer_approved=True,
    )
    endpoint_indices = [item["reference_volume_index"] for item in endpoint_manifest["slices"]]
    assert endpoint_indices[0] == image.shape[2] - 1
    assert endpoint_indices[-1] == 0
    assert set(abs(right - left) for left, right in zip(endpoint_indices, endpoint_indices[1:])) <= {1, 2}

    dense_out = tmp_path / "matlab-case-dense"
    dense_manifest = export_matlab_case(masks, reference, dense_out, slicer_approved=True)
    assert dense_manifest["slice_count"] == image.shape[2]
    assert dense_manifest["slice_selection"] == "all_selected_range_slices"
    assert [s["reference_volume_index"] for s in dense_manifest["slices"]] == list(
        reversed(range(image.shape[2]))
    )
    assert [item["base_to_apex_reference_slice"] for item in dense_manifest["slices"]] == list(
        range(1, image.shape[2] + 1)
    )

def test_align_bivme_to_lge_refuses_to_overwrite(tmp_path, dicom_writer):
    pytest.importorskip("SimpleITK")
    pyvista = pytest.importorskip("pyvista")

    dicom_root = tmp_path / "study"
    case = tmp_path / "case"
    _write_study(dicom_root, dicom_writer)
    _write_case(case)
    _write_meshes(case, 2, pyvista)
    (case / "segmentation" / "bivme" / "lge_aligned").mkdir(parents=True)

    with pytest.raises(RegistrationError):
        align_bivme_to_lge(case, dicom_directory=dicom_root)


def test_align_bivme_to_lge_checks_dependencies_before_writing(tmp_path, dicom_writer, monkeypatch):
    import importlib.util

    dicom_root = tmp_path / "study"
    case = tmp_path / "case"
    _write_study(dicom_root, dicom_writer)
    _write_case(case)

    real_find_spec = importlib.util.find_spec
    monkeypatch.setattr(
        importlib.util,
        "find_spec",
        lambda name, *args, **kwargs: None if name == "pyvista" else real_find_spec(name, *args, **kwargs),
    )

    with pytest.raises(RegistrationError, match="pyvista"):
        align_bivme_to_lge(case, dicom_directory=dicom_root)

    # A late ImportError would leave these behind and the overwrite guard would block any retry.
    assert not (case / "references").exists()
    assert not (case / "registration").exists()
    assert not (case / "segmentation" / "bivme" / "lge_aligned").exists()
