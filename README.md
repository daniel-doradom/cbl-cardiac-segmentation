# VT Segmentation Evaluation

This is an experimental, non-clinical environment for measuring how much of a
manual cardiac segmentation stage can be replaced or reduced while preserving
the geometry required by a later VT/ECGI workflow. It is intentionally separate
from the legacy MATLAB project and does not modify source DICOM data.

Milestone 1 provides structured DICOM inspection, explicit series/frame
selection, full-volume DICOM-to-NIfTI preparation, modality routing, a CT
TotalSegmentator adapter, canonical masks, automated mask QC, provenance, and
3D Slicer-ready files.

## Canonical mask interface

Every configured backend must produce exactly these downstream names:

```text
lv_blood_pool.nii.gz
rv_blood_pool.nii.gz
myocardium.nii.gz
```

Backend-specific labels do not leave the adapter. For CT, the mapping is:

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
- **MRI:** DICOM inspection and geometry-preserving preparation are supported.
  The backend remains deliberately unconfigured because sequence type matters.
  Representative local data include both static 3D MDE/LGE and gated cine bSSFP
  patterns. See [docs/mri-backends.md](docs/mri-backends.md).
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

Re-run mask QC after a controlled mask update:

```bash
python -m vtseg qc-masks results/local-case
```

Expected case outputs are:

```text
results/local-case/
├── source/
│   ├── dicom_inventory.json
│   ├── selected_series.json
│   └── preparation_provenance.json
├── volume/image.nii.gz
├── segmentation/
│   ├── raw/
│   ├── normalized/
│   │   ├── lv_blood_pool.nii.gz
│   │   ├── rv_blood_pool.nii.gz
│   │   └── myocardium.nii.gz
│   ├── segmentation_metadata.json
│   └── provenance.json
└── qc/mask_qc.json
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
