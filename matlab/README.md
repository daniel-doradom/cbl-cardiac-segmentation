# MATLAB Manual Review and Meshing

This directory contains the maintained MATLAB implementation. It is source
code only; all DICOM, masks, corrections, meshes, and figures remain under an
ignored export directory, `results/<case>/manual/<export>/`.

Each export directory holds `work/`, the case MATLAB reads and writes, and
`original/`, a read-only copy of the exported masks and DICOMs that nothing
touches afterwards. The entry points accept either the export directory or its
`work/` sub-folder and always work in `work/`.

## Prerequisites

- MATLAB with Image Processing Toolbox.
- A compatible iso2mesh checkout. The recommended local location is
  `<repo>/.external/iso2mesh`; it is ignored by Git, so Iso2Mesh source and
  any separately licensed binaries are not redistributed by this repository.
  Alternatively, set `VTSEG_ISO2MESH` or pass `Iso2meshPath`. The setup
  function verifies `surf2mesh` and `plotmesh`; iso2mesh is not vendored here.

## Run

```matlab
clear classes
clear functions
rehash

repoRoot = '/path/to/vt-segmentation-eval';
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg(); % Finds <repo>/.external/iso2mesh when installed there.

caseDirectory = fullfile(repoRoot, 'results', 'best', 'nsha06', 'manual', ...
    'matlab-source-025-099-20slices');   % the script steps into work/
vtseg.main_bivme_lge_tetmesh(caseDirectory, [], false);
```

For a Slicer-approved CT short-axis MPR export promoted under `results/best/`,
use the CT entry point instead. It has the same correction, mesh, and VTK
output stages, but no MRI scar/LGE stage:

```matlab
ctCaseDirectory = fullfile(repoRoot, 'results', 'best', 'nsha04-ct', ...
    'manual', 'matlab-native-mapped-k661-833-20slices');   % steps into work/
vtseg.main_ct_tetmesh(ctCaseDirectory, []);
```

CT DICOMs are displayed after RescaleSlope/RescaleIntercept is applied (HU),
using the DICOM Window Center/Width as the initial range when supplied.

For CT cases whose automatic myocardium lacks the RV free wall,
`export-matlab-seg --rv-free-wall-mm 3.0` can initialize an approximate wall
by expanding the RV blood pool in-plane before creating `Epi.mat`. The original
`Rendo.mat` remains unchanged, leaving a synthetic collar between the RV
endocardial and epicardial contours. The export records that collar separately
as `seg/rv_free_wall_proxy.mat`. It is only an editable geometric starting
estimate; inspect and correct every slice before meshing. The option does not
modify canonical NIfTI masks and is not available for MR exports.

Both entry points first ask for one rectangular display crop on a
representative slice, then open the correction window. The crop is reused by
the correction window and the final overview figures without changing the
source DICOMs or masks. The read-only slice viewer with fill and opacity
controls is a separate tool: `vtseg.visualize_bivme_lge_masks(caseDirectory, [])`.
MATLAB corrections are authoritative for mesh generation.

During correction, use the in-window **Previous**, **Keep / Next**, and
**Modify** controls. Each LV, RV, and epicardial mask then supports `keep`,
`edit`, `Review Islands`, `redraw`, and `clear`:

- `edit` initializes movable controls from each existing mask boundary. Drag
  them, or add and delete vertices from the polygon's right-click menu;
  deleting handles without moving any leaves the mask unchanged. The
  default is 8 mm between controls and at most 64 controls per boundary,
  independent of CT or MRI pixel resolution. The compact **Handle density**
  view exposes **Simplify handles**, **Handle spacing**, **Detail tolerance**,
  **Maximum handles**, **Apply density**, and **Reset edits**. Uniform spacing
  measures distance along the boundary, so on a narrow crescent such as the RV
  the two walls, far apart along the outline but close on screen, look
  crowded. **Simplify handles** instead keeps a handle only where the boundary
  bends by more than **Detail tolerance**, and adds handles on straight or
  gently curved stretches only to keep every gap under the spacing value,
  which is relabelled **Largest gap** and reaches 40 mm in this mode. To thin
  a crescent's smooth walls, raise **Largest gap** or **Detail tolerance**;
  the tips keep their handles either way. A component with twelve or fewer
  boundary pixels keeps every one of them as a handle so it cannot vanish
  during contour editing; use `Review Islands` to review and remove it. The
  primary component is drawn solid; disconnected components are dashed.
- accepting an edit with no moved controls leaves the imported mask unchanged.
  When a control is moved, its displacement is smoothly applied to the dense
  original boundary before it is rasterized, preserving native CT detail.
- `Review Islands` reviews disconnected foreground islands and enclosed
  background holes on the current slice. A closed contour inside a filled mask
  is a hole, not an island; toggle **Review: Islands** to **Review: Holes** to
  inspect it. Regions touching only at a pixel corner count as separate
  (4-connectivity). The largest component is green, the selected component is
  yellow, and other potential islands are magenta. Select components by
  clicking or with **Previous**/**Next**. **Keep largest** and **Remove
  selected** only stage removals. In hole mode the same buttons become **Fill
  all holes** and **Fill selected hole**; exterior background is never listed.
  **Restore** returns to the input mask. **Apply**
  shows a before/after comparison and requires **Keep changes** before the
  candidate reaches the normal slice-level confirmation. **Cancel** and
  **Discard changes** leave the mask untouched. A small component is only a
  review candidate, because disconnected foreground can represent valid
  anatomy.
- `redraw` discards that structure on the slice and draws one or more new
  components from scratch.
- `clear` removes that structure from the entire slice.
- `keep` preserves the imported mask exactly.

Invalid cavity overlap or a cavity extending outside Epi cannot be accepted.
After final confirmation, `myocardium.mat` is regenerated as
`Epi & ~Lendo & ~Rendo` before scar analysis and mesh generation.
Accepted component decisions are recorded in the ignored
`work/component_review_audit.json`. The audit includes slice and DICOM
identity, structure, action, original and final component counts, removed or
filled areas in pixels and mm2, and a timestamp. Component cleanup and all other
manual changes are confined to `work/`; the entry points reject `original/`
as an editable case.

For the full server-to-Slicer-to-MATLAB procedure, source-slice selection
semantics, synchronization commands, corrected-mask import, and recovery from
late-stage mesh export errors, see [the manual workflow runbook](../docs/manual-workflow.md).

## Tests

Run the MATLAB unit suite from a session where the repository's `matlab/`
directory is on the path:

```matlab
clear functions
rehash
addpath(fullfile(repoRoot, 'matlab'));
results = runtests(fullfile(repoRoot, 'matlab', 'tests'));
assertSuccess(results);
```

The component-review tests cover 4- and 8-connected island detection,
reversible staging, hole preservation, physical area, myocardium consistency,
audit output, and protection of `original/`.
