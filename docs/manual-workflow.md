# Manual Review and Mesh Runbook

This is the supported, reproducible workflow for a research case. Python runs
the automatic segmentation on the authorized lab server. 3D Slicer is used for
visual review. MATLAB is the authoritative place for manual correction and
mesh generation.

All commands below use placeholders. Keep DICOMs, NIfTIs, masks, meshes, logs,
and MATLAB exports under ignored `data/` or `results/`; do not commit them.

## 1. One-time setup

### Server

- Clone this repository and use its current `main` branch.
- Make `data/diagnostics` an ignored local directory or symlink to authorized
  storage. It must never contain Git-tracked imaging data.
- Install/configure the separate `bivme311` environment and biv-me checkout as
  described in [the biv-me backend guide](bivme-backend.md).
- Before GPU inference, obtain an allocation and expose only the GPU assigned
  to your shell. Confirm it with PyTorch before running inference:

```bash
export CUDA_VISIBLE_DEVICES=GPU_ID
conda activate bivme311
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.device_count(), torch.cuda.get_device_name(0))"
```

One-line equivalent:

```bash
export CUDA_VISIBLE_DEVICES=GPU_ID; conda activate bivme311; python -c "import torch; print(torch.cuda.is_available(), torch.cuda.device_count(), torch.cuda.get_device_name(0))"
```

The command must report one visible allocated device. Do not select a GPU just
because it appears in `nvidia-smi`; follow the allocation policy of the lab.

### Personal workstation

- Clone the same repository and pull source changes with Git.
- Install 3D Slicer and MATLAB with Image Processing Toolbox.
- Install iso2mesh separately in an authorized location. It is a dependency,
  not a copy of code maintained by this repository.

Before beginning a review session, update source code and copy ignored case
artifacts from the server:

```bash
cd /path/to/vt-segmentation-eval && git pull --ff-only
rsync -av --partial --progress USER@LAB_HOST:~/VT/vt-segmentation-eval/results/ \
  /path/to/vt-segmentation-eval/results/
```

One-line equivalent:

```bash
cd /path/to/vt-segmentation-eval && git pull --ff-only && rsync -av --partial --progress USER@LAB_HOST:~/VT/vt-segmentation-eval/results/ /path/to/vt-segmentation-eval/results/
```

This is intentionally one-way: automatic outputs are created on the server and
reviewed locally. If a corrected MATLAB result must be returned to the server,
use an explicit reverse `rsync` for that one case after review.

## 2. Choose the correct input

For MRI, provide the **full original cardiac-MR Diagnostics directory**, not a
Weasis MPR export. Biv-me needs multi-view cine bSSFP/FIESTA information; LGE
alignment needs a native LGE/MDE series from the same exam. MPR exports are
useful for visual inspection but are not a substitute for the full study.

For CT, provide the original CT series or an authorized source directory from
which the desired series can be explicitly selected. TotalSegmentator runs on
the prepared CT volume.

## 3. Run automatic cine-MRI segmentation and LGE alignment

###### User Inputs:

1. `CUDA_VISIBLE_DEVICES=GPU_ID`				$\rightarrow$ See `nvtop` and choose most free gpu.
2. `study=data/diagnostics/CASE/Diagnostics` 	$\rightarrow$ Full MRI Exam path
3. `case=results/legacy/nshaXX-mri-RUN_LABEL` 		$\rightarrow$ unique automatic-run folder
4. `cineSeriesUid='xxxxx-xxxx-xxxxx-xxxx'` 		$\rightarrow$ cine short-axis series UID (see in Weasis)
5. `lgeSeriesUid ='xxxxx-xxxx-xxxxx-xxxx'` 		$\rightarrow$ matching lge series UID (see in Weasis)

### Output-folder rule

Use `results/legacy/<case>-<run-label>` for every new automatic run, including
retries with a different frame, view correction, or registration option. This
preserves the raw result and prevents the pipeline's overwrite protection from
blocking a distinct experiment.

Use `results/best/<case>` only after the automatic masks and native LGE
alignment have been inspected in 3D Slicer and selected for manual work. Copy
the accepted candidate into `best` before exporting MATLAB slices; for example:

```bash
cp -a results/legacy/nsha03-post-v1 results/best/nsha03-post
```

Do not run a new automatic segmentation directly inside `results/best/`.

On the server, from the repository root:

```bash
conda activate bivme311
export CUDA_VISIBLE_DEVICES=GPU_ID

study=data/diagnostics/CASE/Diagnostics
case=results/legacy/nshaXX-mri-RUN_LABEL

# Inventory the study, then inspect the JSON locally and choose an explicit
# cine short-axis series UID and temporal frame (zero based). Replace these
# quoted placeholders with actual values from the inventory; do not type the
# words SERIES_INSTANCE_UID or FRAME into prepare-series.
cineSeriesUid='SERIES_INSTANCE_UID_FROM_INVENTORY'
frame=0
lgeSeriesUid='MATCHING_LGE_SERIES_UID_FROM_THE_SAME_STUDY'

PYTHONPATH=src python -m vtseg inspect-dicom "$study" \
  --json "$case/source/dicom_inventory.json"
PYTHONPATH=src python -m vtseg prepare-series "$study" \
  --series "$cineSeriesUid" --frame "$frame" --output "$case"

# Verify the installed backend, then run the cine model on the allocated GPU.
PYTHONPATH=src python -m vtseg check-bivme-backend
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" \
  --dicom-directory "$study" --device gpu

# Select native LGE/MDE, register cine geometry, and rasterize LGE-space masks.
PYTHONPATH=src python -m vtseg align-bivme-lge "$case" \
  --dicom-directory "$study" --lge-series "$lgeSeriesUid"
```

One-line equivalents:

```bash
PYTHONPATH=src python -m vtseg inspect-dicom "$study" --json "$case/source/dicom_inventory.json"
PYTHONPATH=src python -m vtseg prepare-series "$study" --series "$cineSeriesUid" --frame "$frame" --output "$case"
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" --dicom-directory "$study" --device gpu
PYTHONPATH=src python -m vtseg align-bivme-lge "$case" --dicom-directory "$study" --lge-series "$lgeSeriesUid"
```

`PYTHONPATH=src` makes the checked-out package runnable even when it has not
been installed into that conda environment. It may be omitted when `vtseg` is
already installed in the active environment.

The `prepare-series` success message has the form `Prepared MR volume with N spatial slices at .../volume/image.nii.gz`. That confirms the selected cine
volume and `source/selected_series.json` were written and it is safe to start
`segment-mri-bivme`. A `>` prompt after a line-continuation backslash is Bash
asking for the next line of the same command; it is normal and is not an error. Biv-me can
run without printing progress immediately. Do not interrupt it while the shell
has not returned to its usual prompt. On successful return it prints
`biv-me segmentation, rasterization, and QC complete`; only then run
`align-bivme-lge`.

When an input directory contains more than one cardiac-MR study, do not mix a
cine series from one study with an LGE series from another. Choose the cine
short-axis and native LGE/MDE series from the same study group. Passing
`--lge-series` makes that choice reproducible rather than relying on automatic
selection among competing LGE stacks. The biv-me adapter stages only instances
from the prepared cine study before view selection, so unrelated studies in the
same Diagnostics directory cannot be mixed into fitting.

### Review in 3D Slicer

`segment-mri-bivme` and `align-bivme-lge` collect the reviewable image/mask
pairs into `<case>/review/`. To rebuild them for an existing case without
re-running either stage:

```bash
PYTHONPATH=src python -m vtseg collect-review "$case"
```

| Folder                       | Pair                                     |
| ---------------------------- | ---------------------------------------- |
| `review/1_cine_fit/`       | cine at the fitted frame                 |
| `review/2_cine_lge_phase/` | cine at the LGE-matched phase            |
| `review/3_lge/`            | native LGE, masks aligned into LGE space |

Each folder holds an `_image.nii.gz` and a `_labels.nii.gz` of matching
geometry, named `<number>_<run>_<pair>_...`, for example
`1_nsha06-mri-bound_cine_fit_image.nii.gz`. Load them as a Volume and a
LabelMapVolume from **one** folder at a time; the three pairs have different
geometries and will not overlay each other. The file names carry both the run
and the pair because 3D Slicer takes node names from them: all six stay
distinct in the node list, and two runs of the same case can be opened together
to compare them. Labels are `uint8`: 0 background, 1 LV
blood pool, 2 RV blood pool, 3 myocardium. Per-structure binary masks stay
under `segmentation/`.

Pairs 1 and 2 differ only by cardiac phase, so comparing 2 against 3 shows the
cine-to-LGE registration with the phase difference removed.
`review/review.json` records each pair's frame, source paths, and the
registration displacement.

Inspect the full base-to-apex range and the mask-to-image alignment before
exporting anything to MATLAB. QC warnings are prompts for this manual check,
not automatic approval.

### When automatic view selection misses 4-chamber cine

Biv-me fitting requires SAX plus a 4-chamber cine view to establish tricuspid
valve landmarks. If `raw/execution.log` reports that no 4-chamber view was
selected or no tricuspid valve points were found, do not proceed to LGE
alignment and do not expect changing `--frame` to fix it. The view-selection
step precedes per-frame fitting.

Use biv-me's interactive adaptive mode from a graphical session (for example,
an authorized X-forwarded SSH session), so it opens a review window only when
views are missing or uncertain. Confirm the correct 4-chamber cine assignment,
then let the pipeline continue. Do not use adaptive/manual mode in a headless
session with no display; it aborts with `_tkinter.TclError: no display name and no $DISPLAY environment variable`.

X11 forwarding is negotiated when the connection is made, so it cannot be
enabled from inside an existing session:

```bash
ssh -Y cbl          # on local-machine; -Y, not -X, or Tk is refused
echo "$DISPLAY"     # on server, expected: localhost:10.0
```

Preserve the failed attempt and use a new case output:

```bash
case=results/legacy/case-mri-adaptive
PYTHONPATH=src python -m vtseg prepare-series "$study" \
  --series "$cineSeriesUid" --frame "$frame" --output "$case"
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" \
  --dicom-directory "$study" --device gpu --view-correction adaptive
```

One-line equivalents:

```bash
PYTHONPATH=src python -m vtseg prepare-series "$study" --series "$cineSeriesUid" --frame "$frame" --output "$case"
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" --dicom-directory "$study" --device gpu --view-correction adaptive
```

Run `align-bivme-lge` only after adaptive biv-me fitting reports successful
segmentation, rasterization, and QC.

### When only the ED phase lacks tricuspid valve points

A correctly assigned 4-chamber view still fails if the valve is missing from
the one phase biv-me anchors to. The log shows a single
`Tricuspid valve not found on 4ch slice N phase 0` followed by
`Cannot initialize reference dataset!`, while other phases are clean:

```bash
grep -c "Tricuspid valve not found" "$case/segmentation/bivme/raw/execution.log"
```

If the count is small, move the breath-hold reference to a phase that has valve
points. `--ed-frame` sets only that reference; the exported mesh phase stays the
frame given to `prepare-series`. If that frame also failed to fit, move both:

```bash
PYTHONPATH=src python -m vtseg prepare-series "$study" \
  --series "$cineSeriesUid" --frame 1 --output "$case"
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" \
  --dicom-directory "$study" --device gpu --view-correction adaptive --ed-frame 1
```

One-line equivalents:

```bash
PYTHONPATH=src python -m vtseg prepare-series "$study" --series "$cineSeriesUid" --frame 1 --output "$case"
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" --dicom-directory "$study" --device gpu --view-correction adaptive --ed-frame 1
```

The default is `--ed-frame 0`. Values are bounded against
`inferred_temporal_frames` when the header temporal count is defensible, and
recorded as `ed_frame` in `provenance.json`. Anchoring off end-diastole shifts
where the breath-hold shift is measured, so QC the result rather than treating
it as an ED-anchored fit. If many phases lack valve points, the 4-chamber
segmentation is inadequate and moving the reference will not help.

### When the slice shift is not a breath hold

biv-me lines each short-axis slice up against where the other slices cross it
(Sinclair slice shifting), solving at the ED frame and reusing that answer for
every frame. It needs long-axis contours to find those crossings and it bounds
nothing, so a study whose long-axis views are unreliable can have slices thrown
much further than a breath hold. Check it after a fit:

```bash
head -40 "$case/segmentation/bivme/raw/models/case/shift_file.txt"
```

Accepted cases so far keep a median under 5 mm and no slice past 15 mm. If
slices have moved tens of millimetres, refit with the correction off and compare:

```bash
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" \
  --dicom-directory "$study" --device gpu --breathhold-shift none
```

One-line equivalent:

```bash
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" --dicom-directory "$study" --device gpu --breathhold-shift none
```

`--breathhold-shift` accepts `derived_from_ed` (default), `average_all_frames`
and `none`. A non-default choice is recorded in provenance and raised as a
warning. It removes shift damage but cannot fix unreliable contours, so compare
`review/1_cine_fit/` between the two runs rather than trusting the residual,
which is computed against the run's own guide points either way.

### Reproducing a corrected view assignment without the GUI

`--view-predictions` replaces biv-me's view classification with a CSV, so a
corrected assignment can be re-run headlessly and reproducibly:

```bash
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" \
  --dicom-directory "$study" --device gpu \
  --view-predictions "$prior/segmentation/bivme/raw/processing/run/case/view-classification/view_predictions.csv"
```

One-line equivalent:

```bash
PYTHONPATH=src python -m vtseg segment-mri-bivme "$case" --dicom-directory "$study" --device gpu --view-predictions "$prior/segmentation/bivme/raw/processing/run/case/view-classification/view_predictions.csv"
```

Take the CSV from a run whose assignment was already correct, or edit the
`Predicted View` column of an automatic run. Only one series may hold each of
`2ch`, `3ch`, `4ch`, `RVOT`, `LVOT`, `2ch-RV`; duplicates are not arbitrated
when predictions are supplied. The run records `view_predictions` in provenance
and warns that classification was bypassed.

## 4. Matlab export exactly the slices selected in Slicer

Two different coordinate systems appear in the workflow:

- **Source slice number**: the base-to-apex source number shown in the MATLAB
  review/overview and used by the default exporter. These are the values to
  record while deciding the base and apex in the established Slicer/Weasis
  review workflow.
- **Reference z-index**: the zero-based index in the prepared LGE NIfTI grid.
  This is metadata for tracing a slice; it is not the default input to
  `--start-slice` or `--end-slice`.

To retain source slices `START` through `END`, including both endpoints, and
select `COUNT` regularly spaced slices between them:

```bash
PYTHONPATH=src python -m vtseg export-matlab-seg \
  "$case/segmentation/bivme/lge_aligned/normalized" \
  --reference "$case/references/lge" \
  --output "$case/manual/matlab-source-START-END-COUNTslices" \
  --slicer-approved \
  --start-slice START --end-slice END --slices COUNT
```

One-line equivalent:

```bash
PYTHONPATH=src python -m vtseg export-matlab-seg "$case/segmentation/bivme/lge_aligned/normalized" --reference "$case/references/lge" --output "$case/manual/matlab-source-START-END-COUNTslices" --slicer-approved --start-slice START --end-slice END --slices COUNT
```

For example, source 25 through source 100 as 20 MATLAB slices is:

```bash
PYTHONPATH=src python -m vtseg export-matlab-seg \
  "$case/segmentation/bivme/lge_aligned/normalized" \
  --reference "$case/references/lge" \
  --output "$case/manual/matlab-source-025-100-20slices" \
  --slicer-approved \
  --start-slice 25 --end-slice 100 --slices 20
```

One-line equivalent:

```bash
PYTHONPATH=src python -m vtseg export-matlab-seg "$case/segmentation/bivme/lge_aligned/normalized" --reference "$case/references/lge" --output "$case/manual/matlab-source-025-100-20slices" --slicer-approved --start-slice 25 --end-slice 100 --slices 20
```

Do **not** add `--slice-order reference` for this source-slice workflow; that
option changes the interpretation to the NIfTI reference order and is the
common cause of an unexpected MATLAB stack. With `--slices`, the exporter
always includes the requested start and end and spaces intermediate source
slices as evenly as possible. Omit `--slices` to export every source slice in
the inclusive range.

Each export gets its own output directory. This preserves the selected range,
raw DICOM subset, mask stacks, and manifest together and prevents an accidental
overwrite of a prior review.

`--slicer-approved` is a required acknowledgment that the matching LGE image
and labels were inspected in 3D Slicer. The exporter records the approval and
UTC timestamp in both `manifest.json` and `provenance.json`; it does not collect
reviewer identity.

## 5. Review, correct, and mesh in MATLAB

On the personal workstation, after the server-to-workstation `rsync`:

```matlab
clear classes
clear functions
rehash

repoRoot = '/path/to/vt-segmentation-eval';
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg();

caseDirectory = fullfile(repoRoot, 'results', 'case-mri', 'manual', ...
    'matlab-source-START-END-COUNTslices');
vtseg.main_bivme_lge_tetmesh(caseDirectory, [], false);
```

The initial interactive viewer asks for one rectangular display ROI on a
representative slice. Draw the rectangle, then double-click inside it to
confirm. The crop is display-only: it does not crop DICOMs or masks. The same
ROI is reused for the slice slider, fill toggle, fill-opacity slider,
contour-width slider, correction view, and final raw/contour overview figures.
Use **Continue to correction** to leave this viewer. Its ignored case-local
record is `seg/review_display_crop.json`.

In the **Review/correct masks** window, use **Previous**, **Keep / Next**,
**Modify**, and **Go to slice** in the header bar to navigate. Display
settings and the contour legend sit in the right-hand column. Select
**Modify** to disable navigation and show structure-specific LV, RV, and Epi
actions in the lower part of that column. While one structure's prompt is
open, its name is shown in its contour colour, the other legend rows grey
out, and the other contours on the image thin, so it is clear which outline
the choice applies to:

- `keep` leaves that structure exactly as imported.
- `edit` initializes draggable polygon vertices from the existing mask. All
  disconnected components, including RV/RVOT components, remain available;
  move the needed points and click **Accept contour edits**.
- `redraw` discards that structure on the slice and draws one or more new
  components from scratch.
- `clear` removes that structure from the slice.

MATLAB blocks acceptance when LV and RV overlap or either cavity extends
outside Epi. Rejecting a correction restores that slice's original masks.
Select **Finish review**, then choose **Save reviewed masks** or **Discard
review** in the figure. After saving, `myocardium.mat` is regenerated as
`Epi & ~Lendo & ~Rendo`, keeping scar analysis and mesh geometry consistent.

The viewer shows the current MATLAB mask number plus the raw DICOM filename,
source number, and reference z-index. Use this information when deciding which
source range to export next. Close the interactive viewer to proceed to the
correction and meshing stages. The mesh workflow consumes the MATLAB correction
files after the in-figure save choice.

Use `true` as the third argument to `main_bivme_lge_tetmesh` only when the
optional manual LGE scar workflow is intended before meshing.

## 6. Resume a late MATLAB export failure

If the correction and mesh figures completed but MATLAB failed specifically
while running `vtseg.saveNearestDicomPixelValues`, first pull the latest source
on the workstation and rerun only the late export stage:

```matlab
clear classes
clear functions
rehash
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg('Iso2meshPath', '/authorized/path/to/iso2mesh');

globalPath = fullfile(caseDirectory, 'global');
rawPath = fullfile(caseDirectory, 'raw');
vtseg.saveNearestDicomPixelValues(globalPath, rawPath);
vtseg.export_global_tet_meshes_to_vtk(globalPath);
```

Only use this resume path when mesh generation had already completed and masks
were not changed afterwards. Otherwise rerun `vtseg.main_bivme_lge_tetmesh` so
the mesh reflects the current correction files.

## 7. Import corrected masks back to the canonical contract

After manual correction, create canonical corrected NIfTIs in the ignored
manual area:

```bash
PYTHONPATH=src python -m vtseg import-matlab-seg \
  "$case/manual/matlab-source-START-END-COUNTslices" \
  --reference "$case/references/lge" \
  --output "$case/manual/normalized"
```

One-line equivalent:

```bash
PYTHONPATH=src python -m vtseg import-matlab-seg "$case/manual/matlab-source-START-END-COUNTslices" --reference "$case/references/lge" --output "$case/manual/normalized"
```

This writes the three individual masks, `combined_labels.nii.gz`, QC, and
provenance. Because only a selected source range was corrected, unselected
slices are empty in this imported canonical volume; that limitation is recorded
in its provenance and QC.

## Troubleshooting

| Symptom                                                 | Action                                                                                                                                                             |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `No module named vtseg`                               | Run commands from the repository root with`PYTHONPATH=src`, or install the package into the active environment.                                                  |
| GPU is not visible                                      | Do not run inference. Obtain the proper allocation, set`CUDA_VISIBLE_DEVICES` to that allocation, and verify with the PyTorch command in step 1.                 |
| MATLAB says iso2mesh is missing                         | Run`clear classes`, `clear functions`, `rehash`, then `setup_vtseg('Iso2meshPath', '/authorized/path/to/iso2mesh')`.                                       |
| MATLAB stack contains excluded source slices            | Re-export with the default ordering and source values: do not use`--slice-order reference`.                                                                      |
| MATLAB reports`getNumericField` access/collision      | Pull the latest repository source, clear MATLAB classes/functions, then use the targeted resume instructions above if meshing already completed.                   |
| Existing output refuses overwrite                       | Choose a new, descriptive`--output` directory. Do not delete prior case artifacts merely to rerun an experiment.                                                 |
| `No 4ch views were selected` in `raw/execution.log` | Correct the view assignment: see[When automatic view selection misses 4-chamber cine](#when-automatic-view-selection-misses-4-chamber-cine).                        |
| `No tricuspid valve points` at the ED phase only      | Move the breath-hold reference with`--ed-frame`; see [When only the ED phase lacks tricuspid valve points](#when-only-the-ed-phase-lacks-tricuspid-valve-points). |
| `TclError: no display name and no $DISPLAY`           | Reconnect with`ssh -Y`, or supply `--view-predictions` instead of using the GUI.                                                                               |
| Nothing to open in 3D Slicer                            | Run`vtseg collect-review "$case"` to build `<case>/review/`.                                                                                                   |

## CT variation

CT uses the same prepare, Slicer review, and ignored-result conventions, but
uses TotalSegmentator instead of biv-me:

```bash
conda activate vtseg-ct
PYTHONPATH=src python -m vtseg segment-ct results/case-ct \
  --device gpu --force-split
```

One-line equivalent:

```bash
conda activate vtseg-ct && PYTHONPATH=src python -m vtseg segment-ct results/case-ct --device gpu --force-split
```

Its automatic output is
`results/case-ct/segmentation/totalsegmentator/normalized/`. The canonical mask
contract is the same, but the biv-me/LGE alignment and cine-MRI MATLAB export
steps do not apply to CT without a separately validated CT manual workflow.
