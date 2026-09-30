# CLAUDE.md

Guidance for Claude Code working in this repository. Read `README-short.md`
first for the big picture, `docs/manual-workflow.md` for every step in detail.

## What this repo does

Automatic cardiac segmentation for VT/ECGI meshing, then manual correction and
meshing in MATLAB:

- **MRI:** biv-me fits the heart on multi-view cine MRI; `align-bivme-lge`
  moves the fit onto the LGE series. Masks: LV endocardium, RV endocardium,
  epicardium.
- **CT:** TotalSegmentator (`heartchambers_highres`) segments the native CT;
  the masks are mapped onto a short-axis MPR exported from Weasis.
- **Both:** a person reviews the masks in 3D Slicer, then `export-matlab-seg`
  writes a MATLAB case; MATLAB (`matlab/+vtseg`) reviews, corrects and builds
  the tetrahedral mesh.

Everything is research, non-clinical. Source DICOMs are never modified.

## Data rules (do not break)

- Patient data, NIfTI, DICOM and every generated case stay out of Git.
  `data/` and `results/` are ignored except their READMEs; never force-add.
- Never put DICOM UIDs, dates, patient labels or source paths into tracked
  files. Files named `docs/*.local.md` are personal, ignored notes.
- Never write into a MATLAB export's `original/` folder; it is the read-only
  baseline. All edits happen in `work/`.
- Use only the GPU allocated to the shell (`CUDA_VISIBLE_DEVICES`), never one
  picked from `nvidia-smi`.

## Environments

| Task | Environment |
| --- | --- |
| Tests, MRI (biv-me), LGE alignment | `conda` env `bivme311` (has pytest, SimpleITK, pyvista) |
| CT (TotalSegmentator, MPR mapping) | `conda` env `vtseg-ct121` (CUDA 12.1) |
| MATLAB correction and meshing | MATLAB with Image Processing and Statistics toolboxes |

The CLI is `python -m vtseg <command>` with `PYTHONPATH=src` from the repo
root. `python -m vtseg --help` lists the commands.

External pieces, all ignored by Git: biv-me in `.backends/biv-me`, iso2mesh in
`.external/iso2mesh`. If a copied iso2mesh fails with "Permission denied" on
`cgalsurf.mexa64`, its `bin/` files lost their executable bit.

## Tests

```bash
PYTHONPATH=src ~/miniconda3/envs/bivme311/bin/python -m pytest -q
```

MATLAB tests live in `matlab/tests/` and run headless:

```bash
matlab -batch "addpath('matlab'); results = runtests('matlab/tests'); assert(all([results.Passed]))"
```

Run both after any change to the code they cover.

## Results layout

- `results/legacy/<run>/` holds every finished run; a case can have several
  runs with different settings. Runs that failed before producing masks are
  deleted.
- `results/best/<case>` is a symlink to the chosen run (`nsha04-ct` for CT).
  A pick moves only after a person has reviewed it in 3D Slicer; a new run
  is a candidate, not a replacement.
- A MATLAB export is `<run>/manual/<export>/` with `work/` (editable) and
  `original/` (read-only). `main_ct_tetmesh` and `main_bivme_lge_tetmesh`
  step into `work/` on their own.

## Things that are easy to get wrong

- **CT slice order:** for Weasis MPRs, the Slicer K index runs opposite to
  the NIfTI z index. Export with `--slice-order reverse-reference`; MATLAB
  slice position is K + 1.
- **CT mask choice:** prefer the native-CT masks mapped onto the MPR over
  TotalSegmentator run directly on the MPR, unless the mapped set is empty.
- **RV free wall on CT:** TotalSegmentator's myocardium usually lacks it.
  `export-matlab-seg --rv-free-wall-mm 3.0` adds a 3 mm collar around the RV
  as a starting estimate; it must still be reviewed in MATLAB.
- **MRI breath-hold shift:** biv-me corrects slice shifts between breath
  holds; `--breathhold-shift none` turns that off when it makes things worse.
- **MATLAB GUI:** the review window needs a display. Headless MATLAB can run
  tests and build figures, but it cannot wait for button presses (`uiwait`),
  so interactive review is always done by a person.

## Working style

- Keep changes small and in feature branches; commit with clear messages that
  say why. Run the tests before committing.
- Explain results to people in plain words first, technical detail after.
