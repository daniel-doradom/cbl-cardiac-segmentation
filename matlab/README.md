# MATLAB Manual Review and Meshing

This directory contains the maintained MATLAB implementation. It is source
code only; all DICOM, masks, corrections, meshes, and figures remain under an
ignored `results/<case>/manual/matlab/` case directory.

## Prerequisites

- MATLAB with Image Processing Toolbox.
- A compatible, separately installed iso2mesh checkout. Set
  `VTSEG_ISO2MESH` to that checkout before starting MATLAB. The setup function
  verifies `surf2mesh` and `plotmesh`; iso2mesh is not vendored here.

## Run

```matlab
clear classes
clear functions
rehash

repoRoot = '/path/to/vt-segmentation-eval';
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg('Iso2meshPath', '/authorized/path/to/iso2mesh');

caseDirectory = fullfile(repoRoot, 'results', 'case-name', 'manual', 'matlab');
vtseg.main_bivme_lge_tetmesh(caseDirectory, [], false);
```

Use `vtseg.visualize_bivme_lge_masks(caseDirectory, [])` for the interactive
slice/mask review. It first prompts for one rectangular display crop on a
representative slice; that ROI is reused for the slider, mask-fill toggle, and
opacity control, correction window, and final overview figures without changing
the source DICOMs or masks. MATLAB corrections are authoritative for mesh
generation.

During correction, press Enter at the slice prompt to keep it unchanged or
answer `y` to review its structures. Each LV, RV, and epicardial mask then
supports `keep`, `edit`, `redraw`, and `clear`:

- `edit` initializes movable polygon vertices from every existing mask
  component. Move only the needed vertices and click **Accept contour edits**.
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
