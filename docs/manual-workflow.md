# Manual Review and Mesh Workflow

Automatic outputs live under `results/<case>/segmentation/<backend>/`. Each
backend writes three binary canonical masks and `combined_labels.nii.gz` with
the fixed mapping 0 background, 1 LV blood pool, 2 RV blood pool, and 3
myocardium.

Use 3D Slicer to inspect the prepared reference image with the automatic masks.
Slicer sessions and optional exports remain under `results/<case>/manual/slicer/`
and are review artifacts only. MATLAB corrections are the authoritative source
for mesh generation.

Export a selected mask stack to `results/<case>/manual/matlab/`, run the tracked
`matlab/+vtseg` workflow, then import the corrected stacks to
`results/<case>/manual/normalized/`. The import reconstructs the reference
NIfTI grid, leaving unselected source slices empty and recording that limitation
in provenance and QC. All artifacts remain ignored by Git and are transferred
between authorized machines with `rsync`.
