import json
from pathlib import Path

import nibabel as nib
import numpy as np
import pytest

from vtseg.errors import VTSegError
from vtseg.review import collect_review


def _write(path, shape=(4, 4, 3), affine=None, labels=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.zeros(shape, dtype=np.uint8)
    if labels:
        data[1, 1, 1], data[2, 2, 1], data[3, 3, 1] = 1, 2, 3
    affine = np.eye(4) if affine is None else affine
    nib.save(nib.Nifti1Image(data, affine), str(path))


def _cine_case(tmp_path, frame=0):
    case = tmp_path / "case"
    _write(case / "volume" / "image.nii.gz")
    _write(case / "segmentation" / "bivme" / "normalized" / "combined_labels.nii.gz", labels=True)
    (case / "segmentation" / "bivme" / "segmentation_metadata.json").write_text(
        json.dumps({"frame": frame}), encoding="utf-8"
    )
    return case


def _ct_mpr_case(tmp_path):
    case = tmp_path / "ct-mpr"
    _write(case / "volume" / "image.nii.gz")
    (case / "source").mkdir(parents=True)
    (case / "source" / "selected_series.json").write_text(
        json.dumps({"series_characterization": {"modality": "CT"}}), encoding="utf-8"
    )
    _write(case / "segmentation" / "totalsegmentator" / "normalized" / "combined_labels.nii.gz", labels=True)
    _write(case / "segmentation" / "native_ct_mapped" / "normalized" / "combined_labels.nii.gz", labels=True)
    return case


def _add_lge_stage(case, mesh_frame=13):
    _write(case / "references" / f"cine_phase_{mesh_frame:03}" / "volume" / "image.nii.gz")
    _write(case / "registration" / "bivme_to_lge" / "metric_masks" / "cine" / "combined_labels.nii.gz", labels=True)
    lge_affine = np.diag([1.5, 1.5, 1.0, 1.0])
    _write(case / "references" / "lge" / "volume" / "image.nii.gz", shape=(6, 6, 8), affine=lge_affine)
    _write(case / "segmentation" / "bivme" / "lge_aligned" / "normalized" / "combined_labels.nii.gz",
           shape=(6, 6, 8), affine=lge_affine, labels=True)
    aligned = case / "segmentation" / "bivme" / "lge_aligned"
    aligned.mkdir(parents=True, exist_ok=True)
    (aligned / "segmentation_metadata.json").write_text(
        json.dumps({"mesh_frame": mesh_frame}), encoding="utf-8"
    )


def test_collect_review_gathers_the_cine_pair_alone(tmp_path):
    case = _cine_case(tmp_path, frame=3)
    manifest = collect_review(case)
    assert [pair["id"] for pair in manifest["pairs"]] == ["1_cine_fit"]
    assert manifest["pairs"][0]["frame"] == 3
    assert {skipped["id"] for skipped in manifest["skipped_pairs"]} == {"2_cine_lge_phase", "3_lge"}
    assert (case / "review" / "1_cine_fit" / f"1_{case.name}_cine_fit_image.nii.gz").is_file()
    assert (case / "review" / "1_cine_fit" / f"1_{case.name}_cine_fit_labels.nii.gz").is_file()


def test_collect_review_gathers_two_ct_candidates_on_the_same_mpr(tmp_path):
    case = _ct_mpr_case(tmp_path)
    manifest = collect_review(case)
    assert [pair["id"] for pair in manifest["pairs"]] == ["1_direct_mpr", "2_native_ct_mapped"]
    assert manifest["pairs"][0]["source_image"] == manifest["pairs"][1]["source_image"]
    assert manifest["skipped_pairs"] == []


def test_collect_review_gathers_all_three_pairs_with_frames(tmp_path):
    case = _cine_case(tmp_path, frame=0)
    _add_lge_stage(case, mesh_frame=13)
    manifest = collect_review(case)
    assert [pair["id"] for pair in manifest["pairs"]] == ["1_cine_fit", "2_cine_lge_phase", "3_lge"]
    assert [pair["frame"] for pair in manifest["pairs"]] == [0, 13, 13]
    assert manifest["skipped_pairs"] == []


def test_collect_review_copies_bytes_and_leaves_sources_in_place(tmp_path):
    case = _cine_case(tmp_path)
    manifest = collect_review(case)
    pair = manifest["pairs"][0]
    for kind in ("image", "labels"):
        copied = (case / pair[kind]).read_bytes()
        source = (case / pair[f"source_{kind}"]).read_bytes()
        assert copied == source
        assert (case / pair[f"source_{kind}"]).is_file()


def test_collect_review_refuses_a_pair_that_would_not_overlay(tmp_path):
    case = _cine_case(tmp_path)
    # a mask on a different grid than its image cannot be reviewed together
    _write(case / "segmentation" / "bivme" / "normalized" / "combined_labels.nii.gz",
           shape=(8, 8, 5), labels=True)
    with pytest.raises(VTSegError, match="not co-registered"):
        collect_review(case)


def test_collect_review_reports_a_case_with_nothing_to_review(tmp_path):
    bare = tmp_path / "bare"
    bare.mkdir()
    with pytest.raises(VTSegError, match="no reviewable pairs"):
        collect_review(bare)


def test_collect_review_surfaces_a_suspect_registration(tmp_path):
    case = _cine_case(tmp_path)
    _add_lge_stage(case)
    registration = case / "registration" / "bivme_to_lge"
    (registration / "registration.json").write_text(json.dumps({
        "center_displacement_mm": 103.4,
        "optimizer_stop_condition": "RegularStepGradientDescentOptimizerv4: Maximum number of iterations (250) exceeded.",
    }), encoding="utf-8")
    manifest = collect_review(case)
    assert manifest["registration"]["converged"] is False
    assert any("103.4 mm" in warning for warning in manifest["warnings"])
    assert any("iteration limit" in warning for warning in manifest["warnings"])


def test_collect_review_is_idempotent(tmp_path):
    case = _cine_case(tmp_path)
    _add_lge_stage(case)
    first = collect_review(case)
    second = collect_review(case)
    assert [p["id"] for p in first["pairs"]] == [p["id"] for p in second["pairs"]]


def test_collect_review_names_files_after_their_pair(tmp_path):
    case = _cine_case(tmp_path)
    _add_lge_stage(case, mesh_frame=13)
    manifest = collect_review(case)
    # 3D Slicer names nodes from the filename, so every copy must be distinct
    names = [Path(p[kind]).name for p in manifest["pairs"] for kind in ("image", "labels")]
    assert len(names) == len(set(names)) == 6
    for pair in manifest["pairs"]:
        number, _, rest = pair["id"].partition("_")
        assert pair["prefix"] == f"{number}_{case.name}_{rest}"
        assert Path(pair["image"]).name == f"{pair['prefix']}_image.nii.gz"
        assert Path(pair["labels"]).name == f"{pair['prefix']}_labels.nii.gz"
        # the run name distinguishes two runs of one case in Slicer
        assert case.name in Path(pair["image"]).name


def test_collect_review_clears_copies_from_an_earlier_naming_scheme(tmp_path):
    case = _cine_case(tmp_path)
    stale = case / "review" / "1_cine_fit"
    stale.mkdir(parents=True)
    (stale / "image.nii.gz").write_bytes(b"old")
    (stale / "combined_labels.nii.gz").write_bytes(b"old")
    notes = stale / "notes.txt"
    notes.write_text("keep me", encoding="utf-8")
    collect_review(case)
    assert not (stale / "image.nii.gz").exists()
    assert not (stale / "combined_labels.nii.gz").exists()
    assert notes.read_text(encoding="utf-8") == "keep me"
