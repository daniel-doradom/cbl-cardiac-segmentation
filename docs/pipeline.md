# Milestone 1 pipeline

## Replacement boundary

```text
patient DICOM directory
        ↓
header-only recursive inventory
        ↓
study / series / acquisition characterization
        ↓
explicit researcher series and frame selection
        ↓
complete coherent 3-D NIfTI volume
        ↓
CT adapter or explicit unconfigured-MRI status
        ↓
canonical masks → automated QC → 3D Slicer review
```

The downstream geometry pipeline consumes only canonical masks and will not
need to know which model generated them. That downstream pipeline is not part
of this milestone.

## Inspection and selection rules

The scanner recursively reads headers with pixel loading disabled. Instances
are grouped by `StudyInstanceUID` and then `SeriesInstanceUID`. The report
preserves populated standard metadata and reports absent values as absent.

Spatial position is the projection of `ImagePositionPatient` onto the normal
formed from `ImageOrientationPatient`. Instance number is a tie-breaker, not the
primary spatial coordinate. Repeated spatial positions trigger temporal
analysis. A frame is defensible only when every spatial position has the same
set of unique `TemporalPositionIdentifier` values or, as observed in local GE
cine data, `TriggerTime` values. A zero-based `--frame` remains mandatory.

Classic single-frame CT/MR objects are supported. Enhanced multiframe objects
are identified but fail preparation because their per-frame functional groups
need a dedicated standards-aware implementation.

## Conversion geometry

The pixel array has shape `(rows, columns, slices)`. Its DICOM LPS affine uses:

- array row axis: second DICOM orientation vector × row spacing;
- array column axis: first DICOM orientation vector × column spacing;
- array slice axis: median adjacent `ImagePositionPatient` difference;
- origin: first spatially ordered `ImagePositionPatient`.

The affine is premultiplied by `diag(-1, -1, 1, 1)` for NIfTI RAS world
coordinates. Both qform and sform are written. Source and masks must have the
same dimensions and affine before normalization succeeds.

## Provenance and case data

Preparation and segmentation provenance include the selected UIDs, temporal
choice, modality/acquisition summary, DICOM count, dimensions, spacing, affine,
backend/task/version/options/device, software versions, outputs, warnings, and
errors. These JSON files remain under ignored case directories.

## Failure boundaries

- Unsupported or mixed modality: fail.
- Missing/inconsistent dimensions, spacing, orientation, or positions: fail.
- Repeated locations without defensible temporal metadata: fail.
- No explicit frame for defensible cine: fail.
- Existing prepared image or normalized outputs: refuse overwrite.
- Missing CT CLI/task/license/weights: identify the boundary and fail.
- MR without validated backend: retain the prepared image and write an explicit
  machine-readable `not_configured` status.
