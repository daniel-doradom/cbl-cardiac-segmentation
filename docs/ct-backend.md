# CT backend: TotalSegmentator

Current upstream registry verification used TotalSegmentator 2.18.0. The
`heartchambers_highres` task is CT-only, requires a TotalSegmentator license,
and declares seven classes: heart myocardium, left/right atria, left/right
ventricles, aorta, and pulmonary artery. This repository requires three of them.

## Preflight and setup

Use a Python 3.11/3.12 environment with the optional `ct` dependencies. Then:

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

## Current machine boundary at repository creation

The host has Python 3.14.4, no installed TotalSegmentator or PyTorch package,
and an NVIDIA GeForce RTX 4060 Laptop GPU visible on PCIe. `nvidia-smi` cannot
communicate with the NVIDIA driver, so CUDA is not currently usable from this
environment. The 2.18.0 wheel and pure task registry were inspected separately:
task discovery and the required label map are verified, but model inference is
not claimed.
