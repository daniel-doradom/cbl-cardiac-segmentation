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

Source code moves with Git (`git pull --ff-only`). The ignored `results/` tree
moves with **Unison**, two-way, so automatic outputs come down from the server
and MATLAB outputs go back up without a manual copy.

**Server, once, no sudo needed** (`~/.local/bin` is already on `PATH`):

```bash
curl -sL https://github.com/bcpierce00/unison/releases/download/v2.53.8/unison-2.53.8-ubuntu-22.04-x86_64-static.tar.gz | tar -xz -C /tmp
cp /tmp/unison-2.53.8-ubuntu-22.04-x86_64-static/bin/unison* ~/.local/bin/
```

**Workstation, once.** Install Unison (`sudo apt install unison`; any 2.52+
talks to 2.53.8), then create `~/.unison/vtseg-results.prf`:

```
root = /path/to/vt-segmentation-eval/results
root = ssh://USER@LAB_HOST//home/USER/VT/vt-segmentation-eval/results
servercmd = /home/USER/.local/bin/unison
fastcheck = true
times = true
links = true
```

`servercmd` is required: the SSH session Unison opens is non-interactive and
does not see the login `PATH`. Run `unison vtseg-results` once interactively.
The first run reports "no archive files" and lists every difference; **g**
accepts the proposed copies, `<-?->` marks a conflict to decide by hand.

**Automatic runs.** A user-level systemd timer keeps the two sides within a
few minutes of each other without a terminal, survives reboots, and resumes
after sleep. Use the paths that `which unison` and `echo $SSH_AUTH_SOCK` print
on the workstation:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/unison-vtseg.service <<'EOF'
[Unit]
Description=Two-way sync of vtseg results with the lab server
[Service]
Type=oneshot
Environment=SSH_AUTH_SOCK=%t/gcr/ssh
ExecStart=/usr/bin/unison vtseg-results -batch -terse
EOF
cat > ~/.config/systemd/user/unison-vtseg.timer <<'EOF'
[Unit]
Description=Run the vtseg results sync every 10 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload && systemctl --user enable --now unison-vtseg.timer
```

`systemctl --user list-timers unison-vtseg.timer` shows the next run;
`journalctl --user -u unison-vtseg` shows what each run did. `-batch` copies
everything unambiguous and leaves a conflict for an interactive run.

Conflicts should not arise: the server writes a MATLAB export only once, into
`work/` and a read-only `original/` (see step 4), and MATLAB writes only into
`work/`, so no file is edited on both sides. Do not run `rsync` against
`results/` alongside Unison; a deletion on either side is propagated to the
other, so keep anything you want to preserve outside `results/`.

## 2. Choose the correct input

For MRI, provide the **full original cardiac-MR Diagnostics directory**, not a
Weasis MPR export. Biv-me needs multi-view cine bSSFP/FIESTA information; LGE
alignment needs a native LGE/MDE series from the same exam. MPR exports are
useful for visual inspection but are not a substitute for the full study.

For CT, provide the original CT study and select one explicit regular cardiac
CT series. For the CT-to-MATLAB comparison workflow, also provide a complete
short-axis Weasis MPR as **DICOM**, not screenshots or NIfTI-only output. Store
that ignored MPR export under `data/derived/ct-mpr/<case>/`. The native CT and
MPR must share both Study Instance UID and Frame of Reference UID; the pipeline
refuses to invent a registration if they do not.

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
alignment have been inspected in 3D Slicer and selected for manual work.
`best` holds symlinks, not copies: point the case name at the accepted run
before exporting MATLAB slices, for example:

```bash
ln -sfn ../legacy/nsha03-post-mri-v1 results/best/nsha03-post
```

CT picks use the `-ct` suffix (`results/best/nsha04-ct`). Nothing is
duplicated, and a better run later is adopted by moving the link. Do not run a
new automatic segmentation directly inside `results/best/`.

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

Inside that directory the exporter writes two copies of the case:

- `work/` is the MATLAB case. Point `main_bivme_lge_tetmesh` or
  `main_ct_tetmesh` at it, or at the export directory itself: both step into
  `work/`. Corrections, `info.mat`, the review crop and the meshes are written
  there and nowhere else.
- `original/` is a read-only copy of the exported DICOMs and mask stacks.
  Nothing writes there after the export, so the manual stage can always be
  compared with, or restarted from, exactly what was exported.

Because the server writes only at export time and MATLAB writes only into
`work/`, the two sides of a two-way file sync never edit the same file, which is
what keeps that sync free of conflicts. `--flat` restores the single-folder
layout for tooling that expects it.

`--slicer-approved` is a required acknowledgment that the matching LGE image
and labels were inspected in 3D Slicer. The exporter records the approval and
UTC timestamp in both `manifest.json` and `provenance.json`; it does not collect
reviewer identity.

## 5. Review, correct, and mesh in MATLAB

On the personal workstation, once Unison has brought the export down:

```matlab
clear classes
clear functions
rehash

repoRoot = '/path/to/vt-segmentation-eval';
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg();

caseDirectory = fullfile(repoRoot, 'results', 'case-mri', 'manual', ...
    'matlab-source-START-END-COUNTslices');   % the script steps into work/
vtseg.main_bivme_lge_tetmesh(caseDirectory, [], false);
```

The first window asks for one rectangular display crop on a representative
slice. Draw the rectangle, then double-click inside it to confirm. The crop is
display-only: it does not crop DICOMs or masks. It is reused by the correction
window and the final raw/contour overview figures, and its ignored case-local
record is `seg/review_display_crop.json`. The correction window opens next.
The read-only slice viewer with fill and opacity controls is not part of this
script; open it separately with `vtseg.visualize_bivme_lge_masks(caseDirectory, [])`
or through `vtseg.visualize_bivme_lge_results`.

In the **Mask correction: review slices** window (its title bar reads
`FigN: Mask correction: review slices`, N being MATLAB's figure number), use
**Previous**, **Keep / Next**,
**Modify**, and **Go to slice** in the header bar to navigate. Display
settings and the contour legend sit in the right-hand column. Select
**Modify** to disable navigation and show structure-specific LV, RV, and Epi
actions in the lower part of that column. While one structure's prompt is
open, its name is shown in its contour colour, the other legend rows grey
out, and the other contours on the image thin, so it is clear which outline
the choice applies to:

- `keep` leaves that structure exactly as imported.
- `edit` initializes physical-space draggable controls from the existing mask.
  Handles can be dragged, added or deleted (right-click menu); deleting handles
  without moving any leaves the mask unchanged.
  By default, they are 8 mm apart with at most 64 controls per boundary, so a
  fine CT MPR does not create more handles merely because it has smaller
  voxels. Select **Handle density** for **Simplify handles**, **Handle
  spacing**, **Detail tolerance**, **Maximum handles**, **Apply density**, and
  **Reset edits**. Uniform spacing is measured along the boundary, so on a
  narrow crescent the two walls, far apart along the outline but close on
  screen, look crowded while straighter stretches look sparse. Turn on
  **Simplify handles** to place handles only where the boundary bends by more
  than **Detail tolerance** (default 1 mm) and to fill straight stretches only
  as far as needed to keep every gap under **Largest gap**, which reaches
  40 mm in this mode. On a smooth wall a 1 mm tolerance still places a handle
  about every 15 mm, so to thin a crescent's walls raise **Largest gap** or
  **Detail tolerance**; the tips keep their handles either way. A component of
  twelve or fewer boundary pixels keeps all of them as handles so it cannot
  vanish; if such a cluster is unwanted, `redraw` the structure without it.
  Either mode keeps every handle on the imported boundary and changes nothing
  until a handle is moved and accepted. The largest outer boundary is drawn
  solid; smaller disconnected components are dashed.
- accepting without moving a control preserves the imported mask exactly. When
  a control moves, MATLAB smoothly deforms the dense original boundary before
  rasterizing it, rather than replacing the mask with the sparse control
  polygon.
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

## CT-to-MATLAB workflow

Use a fresh `legacy/` folder for each native CT and MPR run. The example below
uses NSHA04's native `Cardiac CT - 28 SEP 2021` DICOM study and a full DICOM
short-axis MPR stored at `data/derived/ct-mpr/nsha04-cardiac-sa/`. First run
`inspect-dicom` for each input and replace both UID placeholders with explicit,
regular CT series UIDs from their inventories.

```bash
conda activate vtseg-ct121
export LD_LIBRARY_PATH="$CONDA_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
nativeStudy='data/diagnostics/NSHA4/Diagnostics/ECGi-VT- 01-04- Cardiac CT- 28 SEP 2021/DICOM'
mprStudy='data/derived/ct-mpr/nsha04-cardiac-sa'
nativeCase='results/legacy/nsha04-ct-native-v1'
mprCase='results/legacy/nsha04-ct-sa-v1'
nativeSeriesUid='NATIVE_CARDIAC_CT_SERIES_UID'
mprSeriesUid='SHORT_AXIS_MPR_SERIES_UID'

PYTHONPATH=src python -m vtseg inspect-dicom "$nativeStudy" --json "$nativeCase/source/dicom_inventory.json"
PYTHONPATH=src python -m vtseg inspect-dicom "$mprStudy" --json "$mprCase/source/dicom_inventory.json"
PYTHONPATH=src python -m vtseg prepare-series "$nativeStudy" --series "$nativeSeriesUid" --output "$nativeCase"
PYTHONPATH=src python -m vtseg prepare-series "$mprStudy" --series "$mprSeriesUid" --output "$mprCase"
PYTHONPATH=src python -m vtseg check-ct-backend
PYTHONPATH=src python -m vtseg segment-ct "$nativeCase" --device gpu --force-split
PYTHONPATH=src python -m vtseg segment-ct "$mprCase" --device gpu
PYTHONPATH=src python -m vtseg map-ct-masks-to-mpr "$nativeCase" "$mprCase"
PYTHONPATH=src python -m vtseg collect-review "$mprCase"
```

`check-ct-backend` confirms that the command and task are discoverable; license,
weights, GPU access, and actual inference are checked by `segment-ct` itself.

One-line equivalents:

```bash
PYTHONPATH=src python -m vtseg inspect-dicom "$nativeStudy" --json "$nativeCase/source/dicom_inventory.json"
PYTHONPATH=src python -m vtseg inspect-dicom "$mprStudy" --json "$mprCase/source/dicom_inventory.json"
PYTHONPATH=src python -m vtseg prepare-series "$nativeStudy" --series "$nativeSeriesUid" --output "$nativeCase"
PYTHONPATH=src python -m vtseg prepare-series "$mprStudy" --series "$mprSeriesUid" --output "$mprCase"
PYTHONPATH=src python -m vtseg segment-ct "$nativeCase" --device gpu --force-split
PYTHONPATH=src python -m vtseg segment-ct "$mprCase" --device gpu
PYTHONPATH=src python -m vtseg map-ct-masks-to-mpr "$nativeCase" "$mprCase"
PYTHONPATH=src python -m vtseg collect-review "$mprCase"
```

Open both pairs in Slicer, always loading image and labels from the same pair:

| Folder | Candidate |
| --- | --- |
| `review/1_direct_mpr/` | TotalSegmentator run directly on the short-axis MPR |
| `review/2_native_ct_mapped/` | Native full-CT TotalSegmentator masks resampled onto that exact MPR grid |

Both pairs use the same MPR volume geometry. Select the candidate manually;
there is no automatic winner. The rule adopted after reviewing ten cases: the
native CT segmentation mapped onto the MPR is better than segmenting the MPR
directly, so take `native_ct_mapped` unless it is empty or unusable, and only
then take the direct `totalsegmentator` set.

Record the pick with a symlink, as for MRI. Both mask sets stay inside the run,
so the export reads from the chosen one and writes next to it:

```bash
bestCase='results/best/nsha04-ct'
ln -sfn "../legacy/$(basename "$mprCase")" "$bestCase"
chosen=native_ct_mapped     # or totalsegmentator for a direct pick
PYTHONPATH=src python -m vtseg preview-matlab-slices "$bestCase/segmentation/$chosen/normalized" --reference "$bestCase" --slice-order reverse-reference
PYTHONPATH=src python -m vtseg export-matlab-seg "$bestCase/segmentation/$chosen/normalized" --reference "$bestCase" --output "$bestCase/manual/matlab-native-mapped-kBASE-APEX-COUNTslices" --slicer-approved --slice-order reverse-reference --start-slice $((BASE+1)) --end-slice $((APEX+1)) --slices COUNT
```

`preview-matlab-slices` lists the one-based positions accepted by
`--start-slice` and `--end-slice` alongside zero-based NIfTI reference indices.

**Slicer K versus stored z.** For every Weasis MPR checked so far (ten cases),
3D Slicer's K index runs opposite to the stored NIfTI z order, so a base and
apex read off Slicer as K values become positions `K + 1` in
`--slice-order reverse-reference` (the position is `N - reference_z_index`).
Passing the same numbers in `reference` order lands on empty slices and exports
masks with nothing in them. Do not assume this for a new export: confirm it by
checking that the mask is present at both chosen positions in the preview, and
confirm after exporting that the manifest's per-slice voxel counts are non-zero
at both ends. Prefer endpoints that carry real sections over the first slice
with any voxel. `promote-ct-candidate` still exists for making a standalone
copied case; the symlink convention above is what `results/best` uses.

CT exports contain `raw/` short-axis CT DICOMs, `seg/Lendo.mat`, `Rendo.mat`,
`Epi.mat`, `myocardium.mat`, and `seg/vtseg_export_manifest.json`. They retain
the source DICOM filename/position mapping.

### Optional CT RV free-wall initialization

TotalSegmentator's CT myocardium label may cover the LV wall and septum without
a complete RV free wall. For MATLAB initialization only, the exporter can grow
the RV blood pool outward by a physical in-plane distance and place the newly
added collar inside `Epi.mat` and `myocardium.mat`:

```bash
PYTHONPATH=src python -m vtseg export-matlab-seg \
  "$bestCase/segmentation/$chosen/normalized" \
  --reference "$bestCase" \
  --output "$bestCase/manual/matlab-native-mapped-rv-wall-3mm" \
  --slicer-approved \
  --slice-order reverse-reference \
  --start-slice $((BASE+1)) --end-slice $((APEX+1)) --slices COUNT \
  --rv-free-wall-mm 3.0
```

One-line equivalent:

```bash
PYTHONPATH=src python -m vtseg export-matlab-seg "$bestCase/segmentation/$chosen/normalized" --reference "$bestCase" --output "$bestCase/manual/matlab-native-mapped-rv-wall-3mm" --slicer-approved --slice-order reverse-reference --start-slice $((BASE+1)) --end-slice $((APEX+1)) --slices COUNT --rv-free-wall-mm 3.0
```

The operation is two-dimensional per slice and uses NIfTI in-plane spacing, so
`3.0` always means 3 mm rather than three pixels. `Lendo.mat` and `Rendo.mat`
remain unchanged. `seg/rv_free_wall_proxy.mat`, the manifest, and provenance
record exactly which additional voxels were synthesized. The canonical NIfTI
masks and `combined_labels.nii.gz` are never changed.

This collar is a geometric starting estimate, not an RV myocardium
segmentation. Inspect and correct every exported slice in MATLAB before mesh
generation. Omit the option, or set it to zero, to retain the established
export exactly. A positive value is rejected for MR exports.

For a trial of a reviewed candidate before promotion, export directly from the
MPR case's `segmentation/native_ct_mapped/normalized/` or
`segmentation/totalsegmentator/normalized/`, using that same MPR case as
`--reference`. Keep the trial under `results/legacy/`; promotion remains an
explicit later decision.

On the workstation run:

```matlab
repoRoot = '/path/to/vt-segmentation-eval';
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg();
caseDirectory = fullfile(repoRoot, 'results', 'best', 'nsha04-ct', ...
    'manual', 'matlab-native-mapped-kBASE-APEX-COUNTslices');   % steps into work/
vtseg.main_ct_tetmesh(caseDirectory, []);
```

The CT MATLAB entry point applies DICOM rescale slope/intercept so the review
image is in Hounsfield units. When CT Window Center/Width is present, it is the
initial display range; its existing window/level, crop, contour, edit, compare,
mesh, and VTK controls remain available. Exported CT mesh node intensities
also use HU. CT scar/fat analysis is not part of
this workflow.
