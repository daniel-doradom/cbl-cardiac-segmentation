# 3D Slicer validation procedure

Automated QC only flags technical anomalies. Every segmentation must be reviewed
against the prepared source image before any geometry experiment.

1. Open 3D Slicer and use **Add Data** to load `volume/image.nii.gz`.
2. Load the three files in `segmentation/normalized/` as label maps or import
   them into one Segmentation node. Assign unambiguous LV, RV, and myocardium
   names/colors.
3. Confirm each mask overlays the source image without translation, mirroring,
   axis permutation, or slice offset in axial, sagittal, and coronal views.
4. Inspect the LV blood pool through the entire available extent.
5. Inspect the RV blood pool, including the free wall and RVOT where visible and
   applicable to the acquisition.
6. Inspect myocardium and its inner/outer boundaries.
7. Inspect basal extent and valve-plane behavior.
8. Inspect the apex for premature termination or leakage.
9. Inspect the septal region and LV/RV separation.
10. Look for missing slices, abrupt inter-slice changes, islands, holes, border
    contact, and anatomically implausible overlap.
11. Compare findings with `qc/mask_qc.json`; automated warnings do not override
    visual evidence, and absence of warnings is not proof of correctness.
12. Record each structure's failures and an overall correction burden:
    **minor**, **moderate**, **major**, or **unusable**. Keep the record only in
    the ignored case directory or another approved research system.

Suggested review record fields are acquisition type, backend/version/task,
reviewer, review date, LV/RV/myocardium findings, basal/apical/septal/RVOT
findings, alignment result, correction burden, and accept/reject decision.

No quantitative performance claim should be made until representative cases
have reference contours and a prespecified evaluation protocol.

The [SlicerTotalSegmentator extension](https://github.com/lassoan/SlicerTotalSegmentator)
can be useful for interactive comparison and supports licensed-task setup, but
this repository's reproducible segmentation path uses the backend CLI. Slicer
is the inspection/correction environment, not a required click-through inference
dependency.
