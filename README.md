# VT Segmentation Evaluation

This is an experimental, non-clinical environment for measuring how much of a
manual cardiac segmentation stage can be replaced or reduced while preserving
the geometry required by a later VT/ECGI workflow. It is intentionally separate
from the legacy MATLAB project and does not modify source DICOM data.

Milestone 1 provides structured DICOM inspection, explicit series/frame
selection, full-volume DICOM-to-NIfTI preparation, modality routing, a CT
TotalSegmentator adapter, an experimental cine-CMR biv-me adapter, canonical
masks, automated mask QC, provenance, and 3D Slicer-ready files.

For the complete repeatable operator procedure, including authorized data
placement, server inference, Slicer review, MATLAB correction/meshing, and
result synchronization, use [the Manual Review and Mesh Runbook](docs/manual-workflow.md).

## Canonical mask interface

Every configured automatic backend must produce these downstream names:

```text
lv_blood_pool.nii.gz
rv_blood_pool.nii.gz
myocardium.nii.gz
combined_labels.nii.gz
```

`combined_labels.nii.gz` is `uint8`: 0 background, 1 LV blood pool, 2 RV
blood pool, and 3 myocardium. Individual masks are the editable source of
truth; the combined file is validated from them. Backend-specific labels do not
leave the adapter. For CT, the mapping is:

```text
heart_ventricle_left  -> lv_blood_pool
heart_ventricle_right -> rv_blood_pool
heart_myocardium      -> myocardium
```

These volumetric masks are not the legacy endocardial/epicardial surfaces.
Surface derivation needs a separate algorithm and validation milestone.

## Modality status

- **CT:** TotalSegmentator `heartchambers_highres` is the first backend under
  evaluation. It is a licensed task (free academic/non-commercial licensing is
  available upstream). The pipeline never falls back to another task.
- **MRI:** biv-me is available as an experimental backend for multi-view cine
  CMR DICOM only. It is not valid for CT and does not segment scar in static
  MDE/LGE. A separate rigid alignment stage can transfer fitted cine geometry
  into a native LGE grid. The adapter preserves
  native guidepoints and meshes, then rasterizes one selected phase into the
  prepared source geometry. See [docs/bivme-backend.md](docs/bivme-backend.md).
- **Human QC:** all outputs are research results and require visual inspection
  and, when necessary, correction in 3D Slicer before downstream experiments.

## Setup

Use Python 3.11 or 3.12 for the CT environment; this avoids current deep-learning
wheel gaps in newer interpreters.

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e '.[dev]'
```

The base dependencies include `pylibjpeg`/`pylibjpeg-libjpeg` because the
representative local exports use JPEG Lossless Process 14 pixel encoding.

For CT inference, install the pinned optional backend in that isolated environment:

```bash
python -m pip install -e '.[ct]'
totalseg_info --classes -ta heartchambers_highres
totalseg_set_license -l YOUR_ACADEMIC_OR_COMMERCIAL_LICENSE
python -m vtseg check-ct-backend
```

Do not place a license value in Git-tracked configuration or shell history.
TotalSegmentator stores a validated license in its user configuration.

## Workflow

Inspect without loading pixels:

```bash
python -m vtseg inspect-dicom /path/to/local/patient-export
```

The command reports Study/Series UIDs, acquisition metadata, geometry
consistency, repeated positions, and defensible temporal structure. It does not
silently choose an acquisition.

Prepare a static series:

```bash
python -m vtseg prepare-series /path/to/local/patient-export \
  --series SERIES_INSTANCE_UID \
  --output results/local-case
```

Prepare one explicitly selected cine frame (zero-based):

```bash
python -m vtseg prepare-series /path/to/local/patient-export \
  --series SERIES_INSTANCE_UID \
  --frame 0 \
  --output results/local-case
```

Run CT segmentation and QC:

```bash
python -m vtseg segment-ct results/local-case --device gpu

# For a very large CT with constrained system memory:
python -m vtseg segment-ct results/local-case --device gpu --force-split
```

Run the separately installed biv-me backend on a prepared cine-CMR case:

```bash
python -m vtseg check-bivme-backend \
  --bivme-root .backends/biv-me \
  --python-executable "$HOME/miniconda3/envs/bivme311/bin/python"

python -m vtseg segment-mri-bivme results/local-mri-case \
  --dicom-directory /path/to/multiview-cine-cmr-dicoms \
  --bivme-root .backends/biv-me \
  --python-executable "$HOME/miniconda3/envs/bivme311/bin/python" \
  --device gpu

python -m vtseg align-bivme-lge results/local-mri-case \
  --dicom-directory /path/to/full-cardiac-mr-study

python -m vtseg export-matlab-seg \
  results/local-mri-case/segmentation/bivme/lge_aligned/normalized \
  --reference results/local-mri-case/references/lge \
  --output results/local-mri-case/manual/matlab \
  --start-slice 1 --end-slice 100 --slices 12
```

`align-bivme-lge` registers and rasterizes in-process rather than shelling out,
so it needs the `registration` extra (`pip install -e ".[registration]"`,
SimpleITK and PyVista) or must be run from the biv-me environment.

The prepared source volume must be an explicit frame from a cine MR series. The
full multi-view CMR DICOM directory is passed to biv-me by a temporary symlink;
the adapter does not copy DICOM pixels into this repository.

`export-matlab-seg` writes an ignored MATLAB case with DICOM files in `raw/`
and matching `Lendo.mat`, `Rendo.mat`, `Epi.mat`, and `myocardium.mat` stacks
in `seg/`. It orders the stack base-to-apex from the mask extent. `--start-slice`
and `--end-slice` are one-based positions in that order; `--slices` retains
both endpoints and distributes intermediate slices as evenly as possible. In MATLAB, run
`vtseg.main_bivme_lge_tetmesh` from the tracked `matlab/` directory (after
`setup_vtseg` verifies a separately installed iso2mesh)
with the exported case directory; it opens the imported masks for correction,
then produces the legacy biventricular mesh outputs. Pass `true` as its third
argument to launch the manual LGE scar workflow before meshing.

Before meshing, `vtseg.visualize_bivme_lge_masks(case_directory)` opens an interactive
MATLAB review window with image/mask contours, a slice slider, a mask-fill
toggle, and adjustable fill opacity.

After meshing, `vtseg.visualize_bivme_lge_results(case_directory)` combines that
interactive review with generated surface/tetrahedral mesh and node-value
figures. Its optional third argument enables slice-to-mesh animation.

Re-run mask QC after a controlled mask update:

```bash
python -m vtseg qc-masks results/local-case
```

Import MATLAB-corrected masks back into the canonical manual location:

```bash
python -m vtseg import-matlab-seg results/local-mri-case/manual/matlab \
  --reference results/local-mri-case/references/lge \
  --output results/local-mri-case/manual/normalized
```

### Fresh Cine-MRI to Manual Review

Store authorized DICOM studies in ignored `data/diagnostics/` storage (a local
symlink is supported); do not add imaging data to Git. For each case, use the
full original cardiac-MR Diagnostics directory, not a Weasis MPR export. The
study must include multi-view cine bSSFP/FIESTA acquisitions for biv-me and a
native LGE/MDE acquisition for alignment.

```bash
study=data/diagnostics/CASE/Diagnostics
case=results/case-mri

# Write an ignored inventory, review it locally, and select an explicit cine
# short-axis series UID and temporal frame.
python -m vtseg inspect-dicom "$study" --json "$case/source/dicom_inventory.json"
python -m vtseg prepare-series "$study" --series SERIES_INSTANCE_UID --frame FRAME \
  --output "$case"

# Run only after confirming this shell owns the selected GPU allocation.
CUDA_VISIBLE_DEVICES=GPU_ID python -m vtseg check-bivme-backend
CUDA_VISIBLE_DEVICES=GPU_ID python -m vtseg segment-mri-bivme "$case" \
  --dicom-directory "$study" --device gpu

# Selects native LGE/MDE, phase-matches cine geometry, and writes LGE-space masks.
python -m vtseg align-bivme-lge "$case" --dicom-directory "$study"
```

Both stages collect the reviewable pairs into `<case>/review/`:
`1_cine_fit/`, `2_cine_lge_phase/`, and `3_lge/`, each holding an
`_image.nii.gz` and a `_labels.nii.gz` of matching geometry, named for the run
they came from (`3_nsha06-mri-bound_lge_image.nii.gz`). In 3D Slicer open one
folder at a time, loading the image as a Volume and the labels as a
LabelMapVolume; because the run name is in the file name, two runs can be
compared side by side without their node names clashing. `vtseg collect-review "$case"` rebuilds them for an
existing case. Review alignment and masks before choosing the base-to-apex
slice range for MATLAB export. Preview the one-based
export positions first; the suggested range excludes empty slices, and each
entry maps an export position to a zero-based LGE reference index:

```bash
python -m vtseg preview-matlab-slices \
  "$case/segmentation/bivme/lge_aligned/normalized" \
  --reference "$case/references/lge"
```

Then export the reviewed range:

```bash
python -m vtseg export-matlab-seg \
  "$case/segmentation/bivme/lge_aligned/normalized" \
  --reference "$case/references/lge" --output "$case/manual/matlab" \
  --start-slice START --end-slice END --slices COUNT
```

`--start-slice` and `--end-slice` use the one-based **source slice** numbers
shown during the base-to-apex MATLAB review. Use those reviewed source numbers
directly with the default slice order. For example, retaining source slice 25
through source slice 100 as 20 evenly spaced MATLAB slices is:

```bash
python -m vtseg export-matlab-seg \
  "$case/segmentation/bivme/lge_aligned/normalized" \
  --reference "$case/references/lge" \
  --output "$case/manual/matlab-source-025-100-20slices" \
  --start-slice 25 --end-slice 100 --slices 20
```

This retains both endpoints. Do not add `--slice-order reference` when
selecting reviewed source slice numbers; that option instead selects by the
prepared NIfTI reference-volume order.

In MATLAB, add the repository `matlab/` folder, run `setup_vtseg`, then run
`vtseg.main_bivme_lge_tetmesh` on `$case/manual/matlab`. After correction and
mesh generation, use `import-matlab-seg` above to create canonical manual NIfTI
masks and QC.

Expected case outputs are:

```text
results/local-case/
├── source/
│   ├── dicom_inventory.json
│   ├── selected_series.json
│   └── preparation_provenance.json
├── volume/image.nii.gz
├── segmentation/totalsegmentator/
│   ├── raw/
│   ├── normalized/
│   │   ├── lv_blood_pool.nii.gz
│   │   ├── rv_blood_pool.nii.gz
│   │   ├── myocardium.nii.gz
│   │   └── combined_labels.nii.gz
│   ├── segmentation_metadata.json
│   └── provenance.json
└── manual/
    ├── slicer/
    ├── matlab/{raw,seg,mesh,remesh,global}/
    └── normalized/
```

biv-me outputs are backend-scoped so they can coexist with other experiments:

```text
results/local-mri-case/
├── segmentation/bivme/
│   ├── raw/
│   │   ├── guidepoints/
│   │   ├── models/
│   │   └── execution.log
│   ├── normalized/
│   │   ├── lv_blood_pool.nii.gz
│   │   ├── rv_blood_pool.nii.gz
│   │   ├── myocardium.nii.gz
│   │   └── combined_labels.nii.gz
│   ├── segmentation_metadata.json
│   └── provenance.json
└── segmentation/bivme/qc/mask_qc.json
```

The entire `results/` tree is ignored except its placeholder README. UIDs and
source paths occur only in ignored case-level metadata and console output.

## Conservative behavior

- All coherent spatial slices are retained; no 12/16/20-slice subsampling occurs.
- Repeated positions require a consistent `TemporalPositionIdentifier` or
  `TriggerTime` across all slice locations and an explicit `--frame`.
- Instance-number patterns alone are not considered proof of cardiac phase.
- Mixed geometry, irregular spacing, ambiguous cine, and enhanced multiframe
  DICOM fail clearly instead of being collapsed into a questionable volume.
- NIfTI affines are built from DICOM patient geometry. DICOM LPS world
  coordinates are explicitly converted to NIfTI RAS; array order is never used
  as a substitute for patient-space orientation.

## Tests

```bash
python -m pytest
```

Tests use synthetic non-PHI DICOM and NIfTI fixtures. TotalSegmentator model
inference and real-case Slicer review are intentionally separate integration and
validation activities.

## Current non-goals

Milestone 1 does not implement surface generation, epicardial/endocardial
surface derivation, mesh repair, remeshing, tetrahedralization, scar replacement,
CT fat segmentation, legacy mesh export, node-intensity mapping, or downstream
VT/ECGI analysis. It does not claim that `Gen_mesh`, `iso2meshEP`, `corLoc2Gol`,
or other legacy stages can be removed.

See [docs/pipeline.md](docs/pipeline.md),
[docs/legacy-pipeline.md](docs/legacy-pipeline.md), and
[docs/validation.md](docs/validation.md).
