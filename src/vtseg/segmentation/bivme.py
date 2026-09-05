"""Adapter for the upstream biv-me cine-CMR DICOM-to-mesh pipeline."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

import nibabel as nib

from vtseg.dicom.series import scan_headers
from vtseg.errors import BackendUnavailable, SeriesSelectionError
from vtseg.provenance import (
    base_provenance,
    git_commit,
    software_versions,
    utc_now,
    write_json,
    write_provenance,
)
from vtseg.qc.masks import run_backend_qc
from vtseg.segmentation.base import BackendStatus, SegmentationBackend

TASK = "cine_cmr_biventricular_mesh"
CASE_ALIAS = "case"
VIEW_PREDICTION_COLUMNS = (
    "Series Number", "Series Description", "Slice Location",
    "Predicted View", "Vote Share", "Confidence", "Frames Per Slice",
)
MODEL_TERMS_WARNING = (
    "biv-me code is Apache-2.0, but the separate public model repository does not "
    "currently declare model-weight license terms; verify terms for the intended use"
)


def _resolve_executable(value: str | Path | None) -> Path | None:
    candidate = str(value or os.environ.get("BIVME_PYTHON") or sys.executable)
    resolved = shutil.which(candidate)
    path = Path(resolved or candidate).expanduser()
    return path.resolve() if path.is_file() else None


def _bivme_root(value: str | Path | None) -> Path:
    return Path(value or os.environ.get("BIVME_ROOT") or ".backends/biv-me").expanduser().resolve()


def _subprocess_environment(root: Path, *, device: str | None = None) -> dict[str, str]:
    environment = os.environ.copy()
    source = str(root / "src")
    existing = environment.get("PYTHONPATH")
    environment["PYTHONPATH"] = source if not existing else os.pathsep.join((source, existing))
    if device == "cpu":
        environment["CUDA_VISIBLE_DEVICES"] = ""
    return environment


def _selected_study_instances(inventory: Any, study_uid: str) -> list[Any]:
    instances = [instance for instance in inventory.instances if instance.study_uid == study_uid]
    if not instances:
        raise SeriesSelectionError("prepared cine study is absent from the biv-me DICOM input")
    return instances


def _version_from_config(root: Path) -> str | None:
    config_path = root / "src" / "bivme" / "configs" / "config.toml"
    if not config_path.is_file():
        return None
    match = re.search(
        r'^version\s*=\s*"([^"]+)"',
        config_path.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    return match.group(1) if match else None


def _installed_versions(python: Path, root: Path) -> dict[str, str | None]:
    script = """
import importlib.metadata
import importlib.util
import json

packages = {"bivme": "bivme", "torch": "torch", "nnunetv2": "nnunetv2", "pyvista": "pyvista"}
result = {}
for distribution, module in packages.items():
    if importlib.util.find_spec(module) is None:
        result[distribution] = None
        continue
    try:
        result[distribution] = importlib.metadata.version(distribution)
    except importlib.metadata.PackageNotFoundError:
        result[distribution] = "importable"
print(json.dumps(result))
"""
    completed = subprocess.run(
        [str(python), "-c", script],
        capture_output=True,
        text=True,
        timeout=30,
        env=_subprocess_environment(root),
    )
    if completed.returncode != 0:
        return {}
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {}


def _model_artifacts(root: Path) -> tuple[bool, dict[str, int]]:
    model_root = root / "src" / "bivme" / "preprocessing" / "dicom" / "models"
    segmentation = list((model_root / "Segmentation").rglob("*.pth"))
    view_selection = [
        path
        for path in (model_root / "ViewSelection").rglob("*")
        if path.is_file() and path.suffix.lower() in {".pth", ".joblib"}
    ]
    segmentation_ready = [path for path in segmentation if path.stat().st_size > 1024]
    view_ready = [path for path in view_selection if path.stat().st_size > 1024]
    counts = {
        "segmentation_models": len(segmentation_ready),
        "view_selection_models": len(view_ready),
    }
    return bool(segmentation_ready and view_ready), counts


def _model_commit(root: Path) -> str | None:
    model_root = root / "src" / "bivme" / "preprocessing" / "dicom" / "models"
    return git_commit(model_root) if (model_root / ".git").exists() else None


def _gpu_preflight(python: Path, root: Path) -> dict[str, Any]:
    script = """
import json
import os
import torch

marker_names = [
    "SLURM_JOB_ID", "SLURM_STEP_GPUS", "SLURM_JOB_GPUS", "PBS_JOBID", "PBS_GPUFILE",
    "LSB_JOBID", "CUDA_VISIBLE_DEVICES", "VTSEG_GPU_ALLOCATION_CONFIRMED",
]
print(json.dumps({
    "cuda_available": bool(torch.cuda.is_available()),
    "device_count": int(torch.cuda.device_count()),
    "allocation_markers": [name for name in marker_names if os.environ.get(name)],
}))
"""
    completed = subprocess.run(
        [str(python), "-c", script],
        capture_output=True,
        text=True,
        timeout=30,
        env=_subprocess_environment(root),
    )
    if completed.returncode != 0:
        raise BackendUnavailable("biv-me GPU preflight could not import or query PyTorch")
    try:
        probe = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise BackendUnavailable("biv-me GPU preflight returned an invalid result") from exc
    if not probe.get("cuda_available") or int(probe.get("device_count", 0)) < 1:
        raise BackendUnavailable("the biv-me environment cannot see an allocated CUDA GPU")
    if not probe.get("allocation_markers"):
        raise BackendUnavailable(
            "CUDA is visible, but this shell has no scheduler/allocation marker; obtain an allocation "
            "or set VTSEG_GPU_ALLOCATION_CONFIRMED=1 after independently confirming exclusive access"
        )
    return probe


def _toml_string(value: str | Path) -> str:
    return json.dumps(str(value))


def _toml_boolean(value: bool) -> str:
    return "true" if value else "false"


def build_config(
    *,
    input_root: Path,
    raw_directory: Path,
    correct_mode: str,
    workers: int,
    generate_plots: bool,
    view_selection: str = "default",
    ed_frame: int = 0,
) -> str:
    return f"""title = "vtseg biv-me adapter"
version = "1.2.0"

[modules]
preprocessing = true
fitting = true

[multiprocessing]
workers = {workers}

[logging]
show_detailed_logging = true
generate_log_file = true

[plotting]
generate_plots_preprocessing = false
generate_plots_fitting = {_toml_boolean(generate_plots)}
include_images = false
export_images = false

[input_pp]
source = {_toml_string(input_root)}
batch_ID = "run"
analyst_id = "vtseg"
processing = {_toml_string(raw_directory / "processing")}
states = {_toml_string(raw_directory / "states")}

[view-selection]
option = {_toml_string(view_selection)}
correct_mode = {_toml_string(correct_mode)}
show_videos = false

[contouring]
smooth_landmarks = true
apply_postprocessing = true

[output_pp]
overwrite = false
output_directory = {_toml_string(raw_directory / "guidepoints")}

[input_fitting]
gp_directory = {_toml_string(raw_directory / "guidepoints" / "run")}
gp_suffix = ""
si_suffix = ""

[breathhold_correction]
shifting = "derived_from_ed"
ed_frame = {ed_frame}

[gp_processing]
sampling = 1
num_of_phantom_points_mv = 30
num_of_phantom_points_tv = 30
num_of_phantom_points_pv = 20
num_of_phantom_points_av = 20

[fitting_weights]
guide_points = 100.0
convex_problem = 1000000.0
transmural = 0.01
lsq_trans_weight = 0.001

[refitting]
perform_refits = true
threshold_factor = 1.2

[output_fitting]
export_control_mesh = false
mesh_format = ".vtk"
closed_mesh = true
output_meshes = ["LV_ENDOCARDIAL", "RV_ENDOCARDIAL", "EPICARDIAL"]
overwrite = false
output_directory = {_toml_string(raw_directory / "models")}
"""


class BivMeMRIBackend(SegmentationBackend):
    def __init__(
        self,
        *,
        root: str | Path | None = None,
        python_executable: str | Path | None = None,
    ) -> None:
        self.root = _bivme_root(root)
        self.python = _resolve_executable(python_executable)

    def status(self) -> BackendStatus:
        version = _version_from_config(self.root)
        main_script = self.root / "src" / "bivme" / "main.py"
        if not main_script.is_file():
            return BackendStatus(
                "biv-me", False, version, TASK,
                "biv-me source is not installed; configure BIVME_ROOT or --bivme-root", {},
            )
        if version is None or not version.startswith("1.2."):
            return BackendStatus(
                "biv-me", False, version, TASK,
                "the adapter currently supports biv-me 1.2.x only", {},
            )
        if self.python is None:
            return BackendStatus(
                "biv-me", False, version, TASK,
                "the configured biv-me Python executable does not exist", {},
            )
        versions = _installed_versions(self.python, self.root)
        missing = [
            name
            for name in ("bivme", "torch", "nnunetv2", "pyvista")
            if not versions.get(name)
        ]
        weights_ready, model_counts = _model_artifacts(self.root)
        capabilities: dict[str, Any] = {
            "versions": versions,
            "model_artifacts": model_counts,
            "model_commit": _model_commit(self.root),
            "supports": ["cine CMR DICOM", "LV cavity", "RV cavity", "biventricular myocardium"],
            "model_weight_terms_declared_upstream": False,
        }
        blockers = []
        if missing:
            blockers.append("missing required packages: " + ", ".join(missing))
        if not weights_ready:
            blockers.append("model artifacts are absent or still Git LFS pointer files")
        if blockers:
            return BackendStatus(
                "biv-me", False, version, TASK,
                "biv-me " + "; ".join(blockers), capabilities,
            )
        return BackendStatus(
            "biv-me", True, version, TASK,
            "biv-me, nnU-Net, PyTorch, PyVista, and model artifacts are discoverable", capabilities,
        )

    def run(
        self,
        case_dir: Path,
        *,
        dicom_directory: Path,
        device: str = "gpu",
        frame: int | None = None,
        correct_mode: str = "automatic",
        workers: int = 4,
        generate_plots: bool = False,
        ed_frame: int = 0,
        view_predictions: Path | None = None,
        repo_root: Path | None = None,
    ) -> dict[str, Any]:
        case = case_dir.resolve()
        image_path = case / "volume" / "image.nii.gz"
        selection_path = case / "source" / "selected_series.json"
        if not image_path.is_file() or not selection_path.is_file():
            raise SeriesSelectionError("case is not prepared: missing volume or selected-series metadata")
        selection = json.loads(selection_path.read_text(encoding="utf-8"))
        summary = selection["series_characterization"]
        if summary.get("modality") != "MR":
            raise SeriesSelectionError(
                f"biv-me MRI adapter refuses modality {summary.get('modality')!r}"
            )
        temporal_selection = selection.get("selected_temporal_frame") or {}
        selected_frame = frame if frame is not None else temporal_selection.get("frame")
        if selected_frame is None:
            raise SeriesSelectionError(
                "biv-me requires a prepared frame from a cine MR series; prepare the SAX series with --frame"
            )
        selected_frame = int(selected_frame)
        if selected_frame < 0:
            raise SeriesSelectionError("biv-me frame must be non-negative")
        if workers < 1:
            raise SeriesSelectionError("biv-me workers must be positive")
        if device not in {"gpu", "cpu"}:
            raise SeriesSelectionError("biv-me device must be 'gpu' or 'cpu'")
        if correct_mode not in {"automatic", "adaptive", "manual"}:
            raise SeriesSelectionError("invalid biv-me view-correction mode")
        ed_frame = int(ed_frame)
        if ed_frame < 0:
            raise SeriesSelectionError("biv-me ed-frame must be non-negative")
        supplied_views: Path | None = None
        if view_predictions is not None:
            supplied_views = Path(view_predictions).expanduser().resolve()
            if not supplied_views.is_file():
                raise SeriesSelectionError(
                    f"biv-me view-predictions file not found: {supplied_views}"
                )
            rows = supplied_views.read_text(encoding="utf-8").splitlines()
            if not rows:
                raise SeriesSelectionError("biv-me view-predictions file is empty")
            columns = [column.strip() for column in rows[0].split(",")]
            missing = [name for name in VIEW_PREDICTION_COLUMNS if name not in columns]
            if missing:
                raise SeriesSelectionError(
                    "biv-me view-predictions file is missing required columns: "
                    + ", ".join(missing)
                )
            if len(rows) < 2:
                raise SeriesSelectionError(
                    "biv-me view-predictions file has a header but no series rows"
                )
        available_frames = summary.get("inferred_temporal_frames")
        bounded = (
            bool(summary.get("temporal_inference_defensible"))
            and isinstance(available_frames, int)
            and not isinstance(available_frames, bool)
            and available_frames > 0
        )
        ed_frame_bound_warning: str | None = None
        if bounded:
            if ed_frame >= available_frames:
                raise SeriesSelectionError(
                    f"biv-me ed-frame {ed_frame} is out of range for a cine series with "
                    f"{available_frames} temporal frames; valid values are 0-{available_frames - 1}"
                )
        elif ed_frame > 0:
            ed_frame_bound_warning = (
                f"could not bound ed-frame {ed_frame}: the prepared series reports no defensible "
                "temporal frame count, so an out-of-range phase would fail inside biv-me fitting"
            )

        backend_dir = case / "segmentation" / "bivme"
        raw_dir = backend_dir / "raw"
        normalized_dir = backend_dir / "normalized"
        metadata_path = backend_dir / "segmentation_metadata.json"
        if normalized_dir.exists() or (raw_dir / "models").exists():
            raise BackendUnavailable(f"refusing to overwrite existing biv-me outputs in {backend_dir}")

        status = self.status()
        if not status.available or self.python is None:
            write_json(metadata_path, {
                "status": "blocked", "backend": "biv-me", "backend_version": status.version,
                "task": TASK, "message": status.detail, "timestamp": utc_now(),
            })
            raise BackendUnavailable(status.detail)
        if device == "gpu":
            try:
                _gpu_preflight(self.python, self.root)
            except BackendUnavailable as exc:
                write_json(metadata_path, {
                    "status": "blocked", "backend": "biv-me", "backend_version": status.version,
                    "task": TASK, "device": device, "message": str(exc), "timestamp": utc_now(),
                })
                raise

        dicom_root = dicom_directory.expanduser().resolve()
        inventory = scan_headers(dicom_root)
        selected_study_uid = str(summary.get("study_uid") or "")
        if not selected_study_uid:
            raise SeriesSelectionError("prepared cine metadata lacks a StudyInstanceUID")
        study_instances = _selected_study_instances(inventory, selected_study_uid)
        modalities = {str(record.dataset.Modality) for record in study_instances}
        if modalities != {"MR"}:
            raise SeriesSelectionError("the prepared cine study must contain only MR DICOM instances")
        orientations = {
            tuple(round(float(value), 5) for value in record.dataset.ImageOrientationPatient)
            for record in study_instances
            if hasattr(record.dataset, "ImageOrientationPatient")
        }
        view_selection = "load" if supplied_views is not None else (
            "image-only" if len(orientations) == 1 else "default"
        )

        raw_dir.mkdir(parents=True, exist_ok=False)
        if supplied_views is not None:
            # biv-me's "load" branch reads
            # states/<batch_ID>/<case>/<analyst_id>/view_predictions.csv
            states_dir = raw_dir / "states" / "run" / CASE_ALIAS / "vtseg"
            states_dir.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(supplied_views, states_dir / "view_predictions.csv")
        log_path = raw_dir / "execution.log"
        with tempfile.TemporaryDirectory(prefix="vtseg-bivme-") as temporary:
            temporary_root = Path(temporary)
            input_root = temporary_root / "input"
            input_root.mkdir()
            study_input = input_root / CASE_ALIAS
            study_input.mkdir()
            for index, record in enumerate(study_instances, start=1):
                source = Path(record.path)
                suffix = source.suffix or ".dcm"
                (study_input / f"{index:06d}{suffix}").symlink_to(source)
            config_path = temporary_root / "config.toml"
            config_path.write_text(
                build_config(
                    input_root=input_root,
                    raw_directory=raw_dir,
                    correct_mode=correct_mode,
                    workers=workers,
                    generate_plots=generate_plots,
                    view_selection=view_selection,
                    ed_frame=ed_frame,
                ),
                encoding="utf-8",
            )
            command = [
                str(self.python), str(Path(__file__).with_name("bivme_runner.py")),
                str(self.root / "src" / "bivme" / "main.py"),
                "--config_file", str(config_path), "--case_name", CASE_ALIAS,
            ]
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                env=_subprocess_environment(self.root, device=device),
                cwd=self.root / "src" / "bivme",
            )
            log_path.write_text(
                completed.stdout + "\n--- STDERR ---\n" + completed.stderr,
                encoding="utf-8",
            )

        model_dir = raw_dir / "models" / CASE_ALIAS
        frame_suffix = f"{selected_frame:03}"
        meshes = {
            "lv": model_dir / "vtk-meshes" / f"{CASE_ALIAS}_LV_ENDOCARDIAL_{frame_suffix}.vtk",
            "rv": model_dir / "vtk-meshes" / f"{CASE_ALIAS}_RV_ENDOCARDIAL_{frame_suffix}.vtk",
            "epicardial": model_dir / "vtk-meshes" / f"{CASE_ALIAS}_EPICARDIAL_{frame_suffix}.vtk",
        }
        model_file = model_dir / f"{CASE_ALIAS}_model_frame_{frame_suffix}.txt"
        outputs_complete = model_file.is_file() and all(path.is_file() for path in meshes.values())
        if completed.returncode != 0 or not outputs_complete:
            message = "biv-me inference/fitting failed or did not produce the selected phase meshes"
            write_json(metadata_path, {
                "status": "failed", "backend": "biv-me", "backend_version": status.version,
                "task": TASK, "device": device, "message": message,
                "return_code": completed.returncode, "timestamp": utc_now(),
            })
            raise BackendUnavailable(message)

        rasterizer = Path(__file__).with_name("bivme_rasterize.py")
        raster_report_path = raw_dir / "rasterization_report.json"
        raster_command = [
            str(self.python), str(rasterizer),
            "--source", str(image_path),
            "--lv-mesh", str(meshes["lv"]),
            "--rv-mesh", str(meshes["rv"]),
            "--epicardial-mesh", str(meshes["epicardial"]),
            "--output", str(normalized_dir),
            "--report", str(raster_report_path),
        ]
        rasterized = subprocess.run(
            raster_command,
            capture_output=True,
            text=True,
            env=_subprocess_environment(self.root, device=device),
        )
        with log_path.open("a", encoding="utf-8") as execution_log:
            execution_log.write(
                "\n--- RASTERIZATION STDOUT ---\n" + rasterized.stdout
                + "\n--- RASTERIZATION STDERR ---\n" + rasterized.stderr
            )
        if rasterized.returncode != 0 or not normalized_dir.is_dir():
            message = "biv-me meshes were produced, but source-geometry rasterization failed"
            write_json(metadata_path, {
                "status": "failed", "backend": "biv-me", "backend_version": status.version,
                "task": TASK, "device": device, "message": message,
                "return_code": rasterized.returncode, "timestamp": utc_now(),
            })
            raise BackendUnavailable(message)

        qc_path = backend_dir / "qc" / "mask_qc.json"
        qc = run_backend_qc(
            case,
            normalized_directory=normalized_dir,
            report_path=qc_path,
        )
        raster_report = json.loads(raster_report_path.read_text(encoding="utf-8"))
        warnings = list(qc.get("warnings", []))
        warnings.append(
            "adapter disabled biv-me's ambiguous 'loc' substring exclusion for cine ingestion"
        )
        if supplied_views is not None:
            warnings.append(
                "view predictions were supplied explicitly; biv-me's own view "
                "classification was bypassed"
            )
        if view_selection == "image-only":
            warnings.append(
                "single-orientation cine input used biv-me image-only view selection"
            )
        if any(count > 0 for count in raster_report.get("mesh_open_edges", {}).values()):
            warnings.append("one or more biv-me surfaces report open edges; inspect the rasterized masks")
        warnings.append(MODEL_TERMS_WARNING)
        if ed_frame_bound_warning is not None:
            warnings.append(ed_frame_bound_warning)
        warnings = sorted(set(warnings))

        source_image = nib.load(str(image_path))
        output_files = [
            str((normalized_dir / f"{name}.nii.gz").relative_to(case))
            for name in ("lv_blood_pool", "rv_blood_pool", "myocardium", "combined_labels")
        ] + [
            str(path.relative_to(case)) for path in meshes.values()
        ] + [str(qc_path.relative_to(case)), str(log_path.relative_to(case))]
        external_versions = status.capabilities.get("versions", {})
        provenance = base_provenance(
            git_commit=git_commit(repo_root) if repo_root else None,
            input_study_uid=selection["study_uid"],
            selected_series_uid=selection["series_uid"],
            selected_temporal_frame=temporal_selection,
            modality="MR",
            acquisition_characterization={
                "acquisition_type": summary.get("acquisition_type"),
                "series_description": summary.get("series_description"),
                "protocol_name": summary.get("protocol_name"),
            },
            source_dicom_count=selection["selected_instance_count"],
            prepared_volume_dimensions=list(source_image.shape),
            voxel_spacing=list(source_image.header.get_zooms()[:3]),
            affine=source_image.affine.tolist(),
            segmentation_backend="biv-me",
            backend_version=status.version,
            model_task=TASK,
            model_options={
                "frame": selected_frame,
                "ed_frame": ed_frame,
                "view_predictions": str(supplied_views) if supplied_views else None,
                "view_correction": correct_mode,
                "view_selection": view_selection,
                "cine_filter_compatibility": "ambiguous loc exclusion disabled",
                "workers": workers,
                "generate_plots": generate_plots,
                "closed_mesh": True,
                "model_commit": status.capabilities.get("model_commit"),
                "coordinate_conversion": raster_report.get("coordinate_conversion"),
            },
            device=device,
            output_files=output_files,
            software_versions={**software_versions(), **external_versions},
            warnings=warnings,
        )
        write_provenance(backend_dir / "provenance.json", provenance)
        write_json(metadata_path, {
            "status": "complete",
            "backend": "biv-me",
            "backend_version": status.version,
            "task": TASK,
            "device": device,
            "frame": selected_frame,
            "ed_frame": ed_frame,
            "view_selection": view_selection,
            "native_outputs_preserved": True,
            "normalized_outputs": {
                # relative to the case, so a case directory can be moved or renamed
                name: str((normalized_dir / f"{name}.nii.gz").relative_to(case))
                for name in ("lv_blood_pool", "rv_blood_pool", "myocardium", "combined_labels")
            },
            "timestamp": utc_now(),
        })
        return provenance
