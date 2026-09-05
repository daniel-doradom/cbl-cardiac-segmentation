import json
from pathlib import Path
from types import SimpleNamespace

import nibabel as nib
import numpy as np
import pytest

from vtseg.errors import SeriesSelectionError
from vtseg.segmentation.bivme import BivMeMRIBackend, _selected_study_instances, build_config
from vtseg.segmentation.bivme_runner import remove_ambiguous_loc_filter
from vtseg.segmentation.bivme_rasterize import canonical_masks, rasterize


def test_bivme_status_reports_missing_source(tmp_path):
    status = BivMeMRIBackend(root=tmp_path / "missing").status()
    assert not status.available
    assert "source is not installed" in status.detail


def test_bivme_config_requests_closed_biventricular_meshes(tmp_path):
    config = build_config(
        input_root=tmp_path / "input",
        raw_directory=tmp_path / "raw",
        correct_mode="automatic",
        workers=2,
        generate_plots=False,
    )
    assert 'closed_mesh = true' in config
    assert 'output_meshes = ["LV_ENDOCARDIAL", "RV_ENDOCARDIAL", "EPICARDIAL"]' in config
    assert 'correct_mode = "automatic"' in config
    assert "workers = 2" in config


def test_bivme_config_supports_image_only_view_selection(tmp_path):
    config = build_config(
        input_root=tmp_path / "input",
        raw_directory=tmp_path / "raw",
        correct_mode="automatic",
        workers=2,
        generate_plots=False,
        view_selection="image-only",
    )
    assert 'option = "image-only"' in config


def test_bivme_config_defaults_ed_frame_to_zero(tmp_path):
    config = build_config(
        input_root=tmp_path / "input",
        raw_directory=tmp_path / "raw",
        correct_mode="automatic",
        workers=2,
        generate_plots=False,
    )
    assert "ed_frame = 0" in config


def test_bivme_config_accepts_an_explicit_ed_frame(tmp_path):
    config = build_config(
        input_root=tmp_path / "input",
        raw_directory=tmp_path / "raw",
        correct_mode="adaptive",
        workers=2,
        generate_plots=False,
        ed_frame=1,
    )
    assert "ed_frame = 1" in config
    # breath-hold correction stays enabled; only its reference phase moves
    assert 'shifting = "derived_from_ed"' in config


def _prepared_cine_case(tmp_path, **characterization):
    case = tmp_path / "case"
    (case / "volume").mkdir(parents=True)
    (case / "source").mkdir(parents=True)
    (case / "volume" / "image.nii.gz").write_bytes(b"")
    (case / "source" / "selected_series.json").write_text(
        json.dumps({
            "series_characterization": {"modality": "MR", **characterization},
            "selected_temporal_frame": {"frame": 0},
        }),
        encoding="utf-8",
    )
    return case


def test_bivme_rejects_a_negative_ed_frame(tmp_path):
    case = _prepared_cine_case(tmp_path)
    with pytest.raises(SeriesSelectionError, match="ed-frame must be non-negative"):
        BivMeMRIBackend().run(
            case,
            dicom_directory=tmp_path / "dicom",
            frame=0,
            ed_frame=-1,
        )


def test_bivme_rejects_an_ed_frame_past_the_last_phase(tmp_path):
    case = _prepared_cine_case(
        tmp_path,
        inferred_temporal_frames=20,
        temporal_inference_defensible=True,
    )
    with pytest.raises(SeriesSelectionError, match="valid values are 0-19"):
        BivMeMRIBackend().run(
            case,
            dicom_directory=tmp_path / "dicom",
            frame=0,
            ed_frame=20,
        )


def test_bivme_accepts_the_last_phase_as_ed_frame(tmp_path):
    case = _prepared_cine_case(
        tmp_path,
        inferred_temporal_frames=20,
        temporal_inference_defensible=True,
    )
    # the bound must not reject the final valid phase; failure comes later
    with pytest.raises(Exception) as excinfo:
        BivMeMRIBackend().run(
            case,
            dicom_directory=tmp_path / "dicom",
            frame=0,
            ed_frame=19,
        )
    assert "ed-frame" not in str(excinfo.value)


def test_bivme_does_not_bound_ed_frame_without_defensible_frame_count(tmp_path):
    case = _prepared_cine_case(
        tmp_path,
        inferred_temporal_frames=20,
        temporal_inference_defensible=False,
    )
    # an indefensible frame count is not a licence to reject; it warns at run time
    with pytest.raises(Exception) as excinfo:
        BivMeMRIBackend().run(
            case,
            dicom_directory=tmp_path / "dicom",
            frame=0,
            ed_frame=99,
        )
    assert "out of range" not in str(excinfo.value)


def test_bivme_stages_only_the_prepared_study_instances():
    first = SimpleNamespace(study_uid="prepared-study")
    second = SimpleNamespace(study_uid="other-study")
    inventory = SimpleNamespace(instances=[first, second])
    assert _selected_study_instances(inventory, "prepared-study") == [first]
    with pytest.raises(SeriesSelectionError, match="prepared cine study"):
        _selected_study_instances(inventory, "missing-study")


def test_bivme_runner_removes_only_ambiguous_loc_filter():
    terms = ["loc", "scout", "mapping"]
    assert remove_ambiguous_loc_filter(terms) == ["scout", "mapping"]


def test_canonical_masks_include_lv_and_rv_wall():
    epicardium = np.ones((3, 3, 3), dtype=bool)
    lv = np.zeros_like(epicardium)
    lv[0, 0, 0] = True
    rv = np.zeros_like(epicardium)
    rv[2, 2, 2] = True
    masks = canonical_masks(lv, rv, epicardium)
    assert masks["lv_blood_pool"].sum() == 1
    assert masks["rv_blood_pool"].sum() == 1
    assert masks["myocardium"].sum() == 25
    assert not masks["myocardium"][0, 0, 0]
    assert not masks["myocardium"][2, 2, 2]


def test_bivme_refuses_prepared_ct_before_backend_or_input_access(tmp_path):
    case = tmp_path / "case"
    (case / "volume").mkdir(parents=True)
    (case / "source").mkdir()
    nib.save(nib.Nifti1Image(np.zeros((2, 2, 2)), np.eye(4)), case / "volume" / "image.nii.gz")
    (case / "source" / "selected_series.json").write_text(json.dumps({
        "series_characterization": {"modality": "CT"},
    }))
    with pytest.raises(SeriesSelectionError, match="refuses modality 'CT'"):
        BivMeMRIBackend(root=tmp_path / "missing").run(
            case,
            dicom_directory=Path("/does/not/matter"),
        )


def test_rasterizer_converts_lps_meshes_to_exact_source_grid(tmp_path):
    pyvista = pytest.importorskip("pyvista")
    source_path = tmp_path / "source.nii.gz"
    nib.save(nib.Nifti1Image(np.zeros((8, 8, 8)), np.eye(4)), source_path)

    mesh_paths = {}
    bounds = {
        "lv": (1.0, 2.5, 2.0, 4.0, 2.0, 4.0),
        "rv": (3.5, 5.0, 2.0, 4.0, 2.0, 4.0),
        "epicardial": (0.5, 5.5, 1.0, 5.0, 1.0, 5.0),
    }
    for name, ras_bounds in bounds.items():
        mesh = pyvista.Cube(bounds=ras_bounds).triangulate()
        lps_points = np.asarray(mesh.points).copy()
        lps_points[:, :2] *= -1
        mesh.points = lps_points
        mesh_path = tmp_path / f"{name}.vtk"
        mesh.save(mesh_path)
        mesh_paths[name] = mesh_path

    output = tmp_path / "normalized"
    report = rasterize(
        source_path,
        mesh_paths["lv"],
        mesh_paths["rv"],
        mesh_paths["epicardial"],
        output,
    )
    assert report["coordinate_conversion"].endswith("NIfTI RAS")
    loaded = {
        name: nib.load(str(output / f"{name}.nii.gz"))
        for name in ("lv_blood_pool", "rv_blood_pool", "myocardium")
    }
    assert all(image.shape == (8, 8, 8) for image in loaded.values())
    assert all(np.array_equal(image.affine, np.eye(4)) for image in loaded.values())
    assert all(np.asanyarray(image.dataobj).sum() > 0 for image in loaded.values())
