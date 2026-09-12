# CT backend: TotalSegmentator

Current upstream registry verification used TotalSegmentator 2.18.0. The
`heartchambers_highres` task is CT-only, requires a TotalSegmentator license,
and declares seven classes: heart myocardium, left/right atria, left/right
ventricles, aorta, and pulmonary artery. This repository requires three of them.

## Preflight and setup

Use a compatible Python environment with the optional `ct` dependencies. On
the lab server, activate the Python 3.11 / CUDA 12.1 environment before CT GPU
inference:

```bash
conda activate vtseg-ct121
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

The older `vtseg-ct` environment uses CUDA 13 PyTorch and cannot initialize on
the server's CUDA 12.4 driver. Then:

```bash
totalseg_info --classes -ta heartchambers_highres
totalseg_set_license -l YOUR_LICENSE
python -m vtseg check-ct-backend
```

Academic/non-commercial license information is available from the
[upstream TotalSegmentator repository](https://github.com/wasserth/TotalSegmentator).
Never store or pass a real license in tracked files. Model dependencies and
weights are installed/configured outside application runtime.

## Execution

```bash
python -m vtseg segment-ct results/local-case --device gpu
```

For a large volume that exhausts system memory, use the upstream
split-processing mode:

```bash
python -m vtseg segment-ct results/local-case --device gpu --force-split
```

This processes the volume in parts and records `force_split: true` in
segmentation provenance. It may take longer and should not be used for a small
field of view.

The adapter invokes the supported CLI with `-ta heartchambers_highres`, requests
an upstream JSON run report, preserves raw masks/logs, verifies required class
files and exact source geometry, copies them to canonical names, runs QC, and
writes provenance. `--higher-order-resampling` and `--force-split` are opt-in
and recorded.

No fallback task exists. A missing CLI, absent task, license failure, unavailable
weights, or inference error leaves a machine-readable failed/blocked status.

## Short-axis MPR comparison

For CT manual meshing, run TotalSegmentator twice: once on the full native CT
and once directly on a complete DICOM short-axis MPR. Then use
`vtseg map-ct-masks-to-mpr <native-case> <mpr-case>` to resample the native
canonical masks onto the MPR grid with nearest-neighbor interpolation. The
command requires matching Frame of Reference UID and will fail rather than
estimate a registration. A Weasis `DERIVED/SECONDARY/MPR` export may receive a
new Study Instance UID, so that UID is recorded as a warning rather than used
as a rejection criterion. `vtseg collect-review <mpr-case>`
creates the two Slicer-ready comparisons. Promote only the reviewer-selected
candidate with `vtseg promote-ct-candidate`; see the manual workflow runbook
for the complete commands and MATLAB export.

## Validation boundary

The server's `vtseg-ct121` environment runs TotalSegmentator 2.18.0 with the
required cardiac classes. `check-ct-backend` checks discovery only; it
does not prove that a license, weights, GPU allocation, or a patient-case
inference run is ready. The NSHA04 native CT series has been checked for regular
3-D positions and a consistent Frame of Reference UID. A complete short-axis
MPR DICOM series is still needed for the CT comparison acceptance run. For
very dense MPR grids, topology and pairwise-overlap QC are intentionally
skipped to avoid unsafe multi-gigabyte connected-component allocations; image
geometry, mask volume, and border checks still run, and Slicer review remains
required.
