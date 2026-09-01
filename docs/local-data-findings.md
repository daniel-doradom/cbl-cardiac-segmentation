# De-identified local DICOM findings

This document intentionally omits patient identifiers and UIDs. It records only
technical patterns needed to justify Milestone 1 behavior.

## Exported CT directory

A representative Weasis export contained 1,229 readable classic single-frame
CT objects in one study but seven SeriesInstanceUIDs: two one-image localizers,
three primary axial reconstructions at 1, 2, and 3 mm thickness, and two derived
MPR reconstructions. The 1 mm primary axial series had 228 unique locations,
512×512 dimensions, 0.3945 mm in-plane spacing, one orientation, and no repeated
positions. A derived MPR series had 737 locations and different dimensions.

This confirms that an export folder is not a series and that silently choosing
the largest series could select a derived MPR rather than the intended primary
reconstruction.

## Raw CT directory

A representative raw export contained four series: two localizers, a monitoring
series with four acquisitions at one spatial position, and a 34-location 1 mm
primary axial reconstruction. The monitoring series demonstrates that repeated
positions do not necessarily mean a usable cardiac cine volume.

## MRI directories

The two core MRI patterns are documented in
[mri-backends.md](mri-backends.md): static 3D MDE/LGE and 20-frame gated FIESTA
cine. Both use classic single-frame MR objects. In the MDE stack, apparent
orientation variation was only a last-decimal (~1e-6) header difference, so
geometric consistency uses a documented numerical tolerance rather than exact
string equality. Slice-position increments were approximately regular rather
than textually identical.

The representative Weasis MR pixel data use JPEG Lossless, Non-Hierarchical,
First-Order Prediction (Process 14 [Selection Value 1]); pydicom therefore needs
the declared `pylibjpeg` and `pylibjpeg-libjpeg` plugins for preparation.

A broader raw MRI export contained 12 series spanning localizers, 2D MDE,
functional short-axis cine, and real-time views. Relevant temporal tags varied
by series and some were missing. This supports the small conservative temporal
implementation rather than a speculative vendor-independent phase guesser.

## Implications

- Group by UIDs before characterizing an acquisition.
- Sort in patient space, not by filenames or `InstanceNumber` alone.
- Preserve all unique positions in a coherent selected series/frame.
- Require an explicit frame whenever a defensible temporal dimension exists.
- Surface ambiguity rather than treating every repeated position as cine.
- Keep enhanced/multiframe handling outside the classic-object converter until
  per-frame functional groups are implemented and tested.
