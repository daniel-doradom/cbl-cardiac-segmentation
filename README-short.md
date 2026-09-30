# Start here

A short guide to this repo. The full details are in
[`docs/manual-workflow.md`](docs/manual-workflow.md); this page tells you what
exists, what to install, and in which order things run.

## What it does

It turns a patient's cardiac scan into a biventricular tetrahedral mesh for
VT/ECGI work, with as little hand segmentation as possible.

1. **Automatic segmentation.** MRI uses biv-me on the cine series and then
   aligns the fit onto the LGE series. CT uses TotalSegmentator on the native
   CT and maps the masks onto a short-axis reformat (MPR) exported from Weasis.
2. **Review in 3D Slicer.** A person checks the masks and picks the slice
   range to keep.
3. **Export to MATLAB.** `export-matlab-seg` writes a MATLAB case with a
   `work/` copy to edit and a read-only `original/` copy.
4. **Correct and mesh in MATLAB.** A review window steps through the slices;
   each mask can be kept, edited, redrawn or cleared, and the mesh is built
   at the end.

## What to install

| Piece | Where | Used for |
| --- | --- | --- |
| This repo | clone `main` | everything |
| `bivme311` conda env | see `docs/bivme-backend.md` | MRI, LGE alignment, tests |
| biv-me checkout and models | `.backends/biv-me` | MRI |
| `vtseg-ct121` conda env with `pip install -e '.[ct]'` | see `README.md` | CT |
| TotalSegmentator license | `totalseg_set_license` | CT |
| MATLAB, Image Processing and Statistics toolboxes | your machine | correction and meshing |
| iso2mesh | `.external/iso2mesh` | meshing |
| 3D Slicer | your machine | reviewing masks |

`.backends/`, `.external/`, `data/` and `results/` are ignored by Git. Put the
authorized scans under `data/diagnostics` (a symlink is fine); they must never
be committed.

## Running a case

The commands are in `docs/manual-workflow.md`. The short order:

- **MRI:** sections 3 (segment and align), 4 (export the slices chosen in
  Slicer), 5 (review and mesh in MATLAB).
- **CT:** the "CT-to-MATLAB workflow" section, then section 5.

In MATLAB, one case looks like this:

```matlab
clear classes; clear functions; rehash
repoRoot = '/path/to/vt-segmentation-eval';
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg('Iso2meshPath', fullfile(repoRoot, '.external', 'iso2mesh'));
vtseg.main_ct_tetmesh('/path/to/results/best/<case>-ct/manual/<export>', []);
```

For MRI the call is `vtseg.main_bivme_lge_tetmesh(caseFolder, [], false)`.

## The MATLAB review window

After **Modify**, each mask offers **Keep**, **Edit**, **Redraw**, **Clear**
and **Back**. Inside **Edit**:

- drag the handles, or use **Handle density** to place fewer or more;
- **Review Islands** finds stray pieces of mask and holes inside it;
- **Grow / shrink** moves the outline out or in by up to 5 mm, either the
  whole outline or one stretch you pick with three clicks, on this slice or
  on a range of slices. **Compare slices** shows every affected slice before
  you apply it.

Nothing is saved until **Finish review** and **Save reviewed masks**; **Quit
without saving** stops before meshing.

## Where results go

- `results/legacy/<run>/` keeps every finished run.
- `results/best/<case>` points at the run chosen after Slicer review.

## Using Claude Code

`CLAUDE.md` gives Claude the repo's rules: which environment to use, how to
run the tests, and what must never be committed. Asking Claude to run a case
step by step from `docs/manual-workflow.md` works well; the MATLAB review
window itself needs you at the screen.
