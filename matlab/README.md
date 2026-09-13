# MATLAB Manual Review and Meshing

This directory contains the maintained MATLAB implementation. It is source
code only; all DICOM, masks, corrections, meshes, and figures remain under an
ignored `results/<case>/manual/matlab/` case directory.

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

caseDirectory = fullfile(repoRoot, 'results', 'case-name', 'manual', 'matlab');
vtseg.main_bivme_lge_tetmesh(caseDirectory, [], false);
```

For a Slicer-approved CT short-axis MPR export promoted under `results/best/`,
use the CT entry point instead. It has the same correction, mesh, and VTK
output stages, but no MRI scar/LGE stage:

```matlab
ctCaseDirectory = fullfile(repoRoot, 'results', 'best', 'nsha04-ct', ...
    'manual', 'matlab-source-START-END-COUNTslices');
vtseg.main_ct_tetmesh(ctCaseDirectory, []);
```

CT DICOMs are displayed after RescaleSlope/RescaleIntercept is applied (HU),
using the DICOM Window Center/Width as the initial range when supplied.

Use `vtseg.visualize_bivme_lge_masks(caseDirectory, [])` for the interactive
slice/mask review. It first prompts for one rectangular display crop on a
representative slice; that ROI is reused for the slider, mask-fill toggle, and
opacity control, correction window, and final overview figures without changing
the source DICOMs or masks. MATLAB corrections are authoritative for mesh
generation.

During correction, use the in-window **Previous**, **Keep / Next**, and
**Modify** controls. Each LV, RV, and epicardial mask then supports `keep`,
`edit`, `redraw`, and `clear`:

- `edit` initializes movable controls from each existing mask boundary. The
  default is 8 mm between controls and at most 64 controls per boundary,
  independent of CT or MRI pixel resolution. The compact **Handle density**
  view exposes **Simplify handles**, **Handle spacing**, **Detail tolerance**,
  **Maximum handles**, **Apply density**, and **Reset edits**. Uniform spacing
  measures distance along the boundary, so on a narrow crescent such as the RV
  the two walls, far apart along the outline but close on screen, look
  crowded. **Simplify handles** instead keeps a handle only where the boundary
  bends by more than **Detail tolerance**, and adds handles on straight or
  gently curved stretches only to keep every gap under the spacing value,
  which is relabelled **Largest gap**. The separate **Components** view lets
  the reviewer remove or restore a disconnected component. The primary
  component is solid; disconnected components are dashed.
- accepting an edit with no moved controls leaves the imported mask unchanged.
  When a control is moved, its displacement is smoothly applied to the dense
  original boundary before it is rasterized, preserving native CT detail.
- `redraw` discards that structure on the slice and draws one or more new
  components from scratch.
- `clear` removes that structure from the entire slice.
- `keep` preserves the imported mask exactly.

Invalid cavity overlap or a cavity extending outside Epi cannot be accepted.
After final confirmation, `myocardium.mat` is regenerated as
`Epi & ~Lendo & ~Rendo` before scar analysis and mesh generation.

For the full server-to-Slicer-to-MATLAB procedure, source-slice selection
semantics, synchronization commands, corrected-mask import, and recovery from
late-stage mesh export errors, see [the manual workflow runbook](../docs/manual-workflow.md).
