# Legacy MATLAB pipeline semantics

This document records the current boundary without redefining legacy outputs.
It is based on the handoff README/README2 and targeted read-only inspection of
the MATLAB entry point, manual contour function, geometry conversion, and mesh
generation code.

## Current workflow

The legacy workflow exports a full DICOM acquisition, selects a reduced
base-to-apex stack (commonly 16–20 slices, sometimes fewer), manually draws LV
endocardium, RV endocardium, and epicardium, constructs masks, builds an initial
surface, remeshes/tetrahedralizes it with iso2mesh, converts local coordinates
to DICOM patient coordinates, samples full-stack DICOM intensities at mesh
nodes, and exports native binary geometry plus VTK.

## Segmentation-stage files

| File | Existing meaning |
|---|---|
| `Epi.mat` | Binary outer epicardial mask stack drawn slice-by-slice. |
| `Lendo.mat` | Binary LV endocardial/blood-pool mask stack. |
| `Rendo.mat` | Binary RV endocardial/blood-pool mask stack; optional RVOT/RV polygons may be combined. |
| `myocardium.mat` | Computed exactly as `Epi & ~Lendo & ~Rendo`. |
| `lepi.mat` | Optional LV epicardial mask used by the 17-segment pathway. |
| `info.mat` | Selected-stack positions, pixel spacing, image dimensions, orientation vectors, slice count, and derived spacing. |

The new `myocardium.nii.gz` is a model-produced volumetric tissue label. It must
not be assumed identical to the legacy Boolean construction without validation.
Likewise, a blood-pool boundary is not yet a downstream endocardial surface, and
the outer myocardial boundary is not yet a validated epicardial surface.

## Later geometry files (documented, not implemented)

The initial mesh stage writes `heart_sur.cor/.tri/.idx` and related volume files.
The remesh/tetrahedral stage writes coarse and dense surface/tetrahedral forms:

```text
sur_heart.cor/.tri/.idx
sur_dense_heart.cor/.tri/.idx
tet_heart.cor/.tet
tet_dense_heart.cor/.tet
```

`.cor` contains `N×3` double node coordinates; `.tri` and `.tet` contain
one-based connectivity; `.idx` contains surface-node labels. Local files are
transformed by `corLoc2Gol` into DICOM-patient-coordinate `.cor` files under
`global/`. The connectivity is unchanged.

Later `_node_values.val` files contain one rescaled nearest-DICOM intensity per
node. `_node_locations.val` contains `[SliceIndex PixelRow PixelColumn
DistanceMm]`. ASCII VTK exports contain nodes, triangle/tetra connectivity, and
the sampled intensity scalar.

## What Milestone 1 evaluates

Milestone 1 evaluates structured acquisition selection, full-volume
preparation, automated LV/RV/myocardium masks, automated QC, and Slicer review.
It does not replace or remove `Gen_mesh`, `iso2meshEP`, `corLoc2Gol`, DICOM
intensity sampling, VTK/native export, scar/fat logic, or downstream VT/ECGI.
