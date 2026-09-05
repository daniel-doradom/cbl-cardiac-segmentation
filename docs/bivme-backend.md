# MRI backend: biv-me

The experimental biv-me adapter runs the upstream cine-CMR DICOM-to-mesh
pipeline and converts one fitted cardiac phase into the same three volumetric
masks used elsewhere in this repository:

```text
LV endocardial enclosure                 -> lv_blood_pool
RV endocardial enclosure                 -> rv_blood_pool
epicardial enclosure minus both cavities -> myocardium
```

This `myocardium` includes the LV wall, septum, and RV free wall. The adapter
requests closed LV endocardial, RV endocardial, and epicardial VTK surfaces,
converts biv-me's DICOM LPS coordinates to NIfTI RAS, and tests enclosure at the
voxel centers of the prepared source image. The output shape and affine are
therefore exactly those of `volume/image.nii.gz`.

## Scope

biv-me v1.2 is designed for multi-view cine cardiovascular MR DICOM. It is not
a CT model and does not segment scar in LGE/MDE. A prepared case supplies the target SAX
frame and its NIfTI geometry; `--dicom-directory` supplies the complete
multi-view cine study needed by biv-me for view selection and model fitting.

After a successful cine fit, `align-bivme-lge` can phase-match one of the fitted
meshes to a native LGE/MDE series, estimate a rigid multimodal registration, and
rasterize the transformed meshes on the exact LGE grid. This is geometry
transfer into LGE space, not LGE scar segmentation.

The adapter refuses a prepared CT case, a non-temporal prepared MR series,
mixed-modality DICOM input, existing biv-me outputs, missing model artifacts,
or GPU execution without both PyTorch CUDA visibility and an allocation marker.
For a manually administered allocation, set
`VTSEG_GPU_ALLOCATION_CONFIRMED=1` only after independently confirming that the
visible GPU is assigned exclusively to this shell.

## Separate installation

Keep biv-me isolated from `vtseg-ct`. Its checkout and model files are ignored
under `.backends/`, and its dependencies belong in a Python 3.11 environment.

```bash
git lfs install
git clone --recurse-submodules \
  https://github.com/UOA-Heart-Mechanics-Research/biv-me.git \
  .backends/biv-me

conda create -n bivme311 python=3.11
conda activate bivme311

# Install a PyTorch build compatible with the allocated server GPU first.
python -m pip install -e .backends/biv-me
python .backends/biv-me/src/pyezzi/setup.py build_ext --inplace
python -m pip install nnunetv2

git -C .backends/biv-me/src/bivme/preprocessing/dicom/models lfs pull
```

Do not put model files in Git. The biv-me source repository is Apache-2.0, but
the separate public `biv-me-dl-models` repository currently has no license file.
There is no license key to configure. Confirm the model terms with the upstream
authors for the intended use; the adapter records this unresolved point as a
provenance warning.

## Preflight and run

Run the wrapper itself from the `vtseg-ct` environment and point it at the
separate biv-me Python executable:

```bash
conda activate vtseg-ct

python -m vtseg check-bivme-backend \
  --bivme-root .backends/biv-me \
  --python-executable "$HOME/miniconda3/envs/bivme311/bin/python"

python -m vtseg segment-mri-bivme results/local-mri-case \
  --dicom-directory /path/to/multiview-cine-cmr-dicoms \
  --bivme-root .backends/biv-me \
  --python-executable "$HOME/miniconda3/envs/bivme311/bin/python" \
  --device gpu \
  --view-correction automatic
```

`automatic` is suitable for a headless server but must be followed by visual
review. `adaptive` or `manual` invokes upstream view correction when a graphical
session is available. `--frame` overrides the prepared frame index; use it only
when the target NIfTI is known to represent that same cardiac phase.

## Native LGE alignment

Keep LGE fixed so its scar-sensitive intensities are never interpolated. The
alignment stage prepares a phase-matched cine reference and the highest-density
regular LGE/MDE stack from the same DICOM study, initializes from their shared
patient coordinate system, registers cine to LGE with rigid Mattes mutual
information, transforms the selected LPS meshes, and rasterizes them directly
on the native LGE grid.

Unlike `segment-bivme`, this stage does not shell out to the biv-me
interpreter: it performs the registration and the mesh rasterization in-process.
It therefore needs SimpleITK and PyVista in whichever environment runs it. Either
install the optional extra into `vtseg-ct`:

```bash
pip install -e ".[registration]"
```

or run the stage from the biv-me environment, which already carries both:

```bash
"$HOME/miniconda3/envs/bivme311/bin/python" -m vtseg align-bivme-lge \
  results/local-mri-case \
  --dicom-directory /path/to/full-cardiac-mr-study
```

The stage verifies both imports before writing anything, so a missing dependency
fails immediately rather than stranding partial outputs behind the
refuse-to-overwrite guard.

Use `--lge-series` to make LGE selection explicit when more than one equally
ranked stack is present. `--mesh-frame` overrides automatic TriggerTime
matching. The automatic selector prefers a regular, orientation-consistent
LGE/MDE series with the most spatial positions and coverage.

Outputs are separated from the original cine result:

```text
references/lge/
references/cine_phase_NNN/
registration/bivme_to_lge/
registration/bivme_to_lge/metric_masks/
segmentation/bivme/lge_aligned/
qc/bivme/lge_alignment.json
review/2_cine_lge_phase/
review/3_lge/
```

`metric_masks/` holds the untransformed meshes rasterized on each grid; they
restrict the mutual-information metric to the cardiac region and are kept for
inspection of the registration initialization.

Re-running the stage is refused once any of these exist. If a run fails part
way through, remove `references/lge/`, `references/cine_phase_NNN/`,
`registration/bivme_to_lge*`, and `segmentation/bivme/lge_aligned/` before
retrying. `review/` is derived and need not be removed; `vtseg collect-review`
rewrites it from whatever outputs exist.

The stored transforms explicitly distinguish SimpleITK's fixed-LGE-to-moving-
cine resampling transform from the inverse moving-cine-to-fixed-LGE transform
applied to mesh points. Transformed VTK files remain in DICOM LPS physical
coordinates; the rasterizer performs the existing LPS-to-NIfTI-RAS conversion.

## Outputs and validation

Native processing state, guidepoints, fitted models, VTK surfaces, and the raw
execution log are preserved under `segmentation/bivme/raw/`. Canonical masks,
metadata, and provenance are under `segmentation/bivme/`; QC is written to
`qc/bivme/mask_qc.json`.

Both stages also copy the reviewable image/mask pairs into `review/`
(`1_cine_fit/` from fitting, `2_cine_lge_phase/` and `3_lge/` from alignment),
each holding a `<pair>_image.nii.gz` and a `<pair>_labels.nii.gz` on one grid;
the pair name is in the filename so 3D Slicer node names stay distinct.
`vtseg collect-review <case>` rebuilds them from existing outputs. The
per-structure masks under `segmentation/` remain the canonical interface;
`review/` is a convenience copy for 3D Slicer.

Open `review/1_cine_fit/` and check SAX, long-axis, basal, apical, septal, and
RVOT regions, plus any open-surface, empty-mask, disconnected-component,
border-touching, or overlap warning. Automated QC and successful mesh fitting
are not clinical validation.

For LGE alignment, compare `review/3_lge/` against the untouched LGE, and use
`review/2_cine_lge_phase/` to separate registration error from cardiac-phase
difference: pairs 2 and 3 hold the same mesh frame in the two spaces. Same
FrameOfReferenceUID is useful initialization but does not remove breath-hold or
cardiac-phase mismatch. Do not begin scar quantification until the alignment
has been manually accepted.
