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

repoRoot = '/path/to/cbl-cardiac-segmentation';
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
`edit`, `redraw`, `clear`, and `back`:

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
  during contour editing; use **Review Islands** to review and remove it. The
  primary component is drawn solid; disconnected components are dashed.
- accepting an edit with no moved controls leaves the imported mask unchanged.
  When a control is moved, its displacement is smoothly applied to the dense
  original boundary before it is rasterized, preserving native CT detail.
- **Review Islands**, a button inside `edit`, reviews disconnected foreground
  islands and enclosed background holes on the current slice. Pending handle
  moves are applied first, and the editor reopens on the result so the
  contour can still be adjusted before **Accept contour edits**. **Cancel** in
  the editor returns the mask that entered `edit`, undoing island changes as
  well. A closed contour inside a filled mask is a hole,
  not an island; toggle **Review: Islands** to **Review: Holes** to inspect it.
  The panel defaults to 4-connectivity so corner-touching regions remain separate review
  candidates; toggle **Connectivity** to use 8-connectivity instead. The
  largest component is green, the selected component is yellow, and other
  potential islands are magenta. Select components by clicking or with
  **Previous**/**Next**. **Keep largest** and **Remove selected** only stage
  removals. In hole mode the same buttons become **Fill all holes** and
  **Fill selected hole**; exterior background is never listed. **Restore** and
  **Keep all** return to the input mask. **Apply**
  shows a before/after comparison and requires **Keep changes** before the
  candidate reaches the normal slice-level confirmation. **Cancel** and
  **Discard changes** leave the mask untouched. A small component is only a
  review candidate, because disconnected foreground can represent valid
  anatomy.
- **Grow / shrink**, a button inside `edit`, moves the current structure's
  outline out or in by -5 to +5 mm in 0.5 mm steps, on the current slice,
  with a live preview (dashed before, solid after). The toggle at the top
  chooses **Whole outline** or **One stretch**. For one stretch, click its two
  ends on the image, then one point on the side to move: the two ends split
  the outline into two arcs and the third click picks one (yellow). The
  offset is full in the middle and fades to zero over **Fade** (0-50 mm,
  default 5) at both ends; **Reset points** starts the picking again. In
  **Whole outline** mode, **Scope** cycles through this slice, slices
  from-to (type the range in the two boxes) and all slices; the current
  slice is always included, and the status line shows how many other slices
  change. **Compare slices**, next to **Apply**, shows what the offset would
  do on every slice of the scope before anything is applied, in the same
  viewer as **Compare before/after** below; the panel stays open to adjust
  the offset. The other slices are changed once that structure is accepted,
  each with its own neighbour stops, and are skipped when they have no such
  mask or a shrink would erase it. Every changed slice then goes through the
  overlap check, **Keep these modifications?** names them, and **Discard**
  restores all of them. **Compare before/after** then opens every changed
  slice: one by one, before and after side by side, stepping with **Previous
  slice** / **Next slice** or the arrow keys, or **Show all slices** as tiles
  with the old outline white and dashed over the new one; clicking a tile
  opens that slice. **Scope** also works in **One stretch** mode: the stretch
  is carried to each other slice by moving its two ends and its middle point
  by how far the LV centre moved, then snapping them to that slice's outline,
  so a free-wall stretch stays on the free wall rather than jumping to the
  septal side of the RV. A slice where the moved points give no valid
  stretch, typically a small apical RV, is skipped and named in the command
  window; check the scope with **Compare slices** first. Accepted offsets are recorded, one line per slice,
  in `work/mask_offset_audit.json`. Growth stops at
  neighbouring structures: the LV and RV cavities stop at each other and at
  the outside of Epi, and Epi never shrinks into either cavity. The usual
  overlap check still runs before the slice is accepted. A pixel moves only
  when its centre comes within the offset, so a step smaller than one pixel,
  common on MRI, changes nothing. **Apply** reopens the editor with fresh
  handles; **Cancel** in the editor undoes it together with any other edit.
- **Suggestions from the previous slice.** When a Grow / shrink is kept on a
  slice, arriving on the slice next to it shows the same change as a
  suggestion: the current outline white and dashed, the suggested one solid,
  and the prompt "Use the change from slice N here?". **Accept** applies it
  (after the overlap check), **Adjust** opens Modify with the suggestion as
  the starting point (Discard restores the slice as it was), and **Skip**
  leaves the slice alone. Nothing is ever applied without one of these
  choices. A suggestion moves one slice at a time and only while it keeps
  being accepted; Skip stops it on that side, and slices already changed
  through Scope get none. A newer Grow / shrink of the same structure
  replaces the older suggestion. The **Suggestions** switch in the header
  turns them off. Accepted suggestions are marked `accepted_suggestion` in
  `work/mask_offset_audit.json`, with `set_on_slice` naming the slice the
  change came from. **Keep largest** and **Fill all holes** from Review
  Islands are suggested the same way, as rules applied to the new slice's
  own islands and holes; removing or filling one chosen island or hole is
  not suggested. A structure can carry a Grow / shrink and an island
  suggestion together, the Grow / shrink applied first. Accepted island
  suggestions appear in `work/component_review_audit.json` with action
  `suggested` and `suggested_from_slice`. Handle drags are not suggested.
- `redraw` discards that structure on the slice and draws one or more new
  components from scratch.
- `clear` removes that structure from the entire slice.
- `keep` preserves the imported mask exactly.
- `back` returns to the previous structure on this slice. On the LV
  endocardium it leaves Modify and the slice keeps the masks it had before.

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
