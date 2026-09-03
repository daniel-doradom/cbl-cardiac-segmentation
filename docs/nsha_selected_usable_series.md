# NSHA Usable Cardiac Imaging Series Register

This is a sanitized, human-readable selection register for the authorized NSHA
diagnostics collection. It records only reusable acquisition characteristics;
it deliberately excludes DICOM UIDs, dates, patient/study labels, source paths,
and pixel data. Exact identifiers belong only in ignored case-local inventories
created with `vtseg inspect-dicom`.

## Audit scope and rules

- **Audit date:** 2026-09-03
- **Coverage:** 16 available diagnostics case directories; 25 distinct studies.
- **Method:** header-only DICOM parsing. No image pixels were read.
- **Geometry-ready:** a series has consistent dimensions, pixel spacing, image
  orientation, and regular inter-slice spacing according to header checks.
- **Important:** geometry-ready does not establish clinical image quality,
  contrast phase, cardiac phase, artifact burden, or segmentation suitability.
- **Study labels:** `S1`, `S2`, and `S3` are opaque local labels used only in
  this register. They are not DICOM identifiers and must not be used to select
  a series programmatically.

## Status legend

| Status | Meaning |
|---|---|
| `candidate` | Header characteristics support visual review as a possible input. |
| `selected_by_notes` | A prior human note identifies a candidate, but selection still needs DICOM-level verification. |
| `needs_review` | Available, but quality, identity, or suitability remains unresolved. |
| `not_usable` | Incomplete or insufficient for the intended workflow. |
| `not_available` | The modality is absent from the available diagnostics directory. |

## Per-case, per-study audit

The `Series summary` column gives `series count; geometry-ready count` followed
by the largest relevant stack observed as `positions x frames`. Counts are
header-derived and rounded to this selection purpose.

### Header-audit completeness

| Case | Readable DICOM headers | Skipped files |
|---|---:|---:|
| NSHA1 | 861 | 57 |
| NSHA2 | 3,212 | 114 |
| NSHA3 | 2,088 | 134 |
| NSHA4 | 9,288 | 132 |
| NSHA5 | 2,985 | 135 |
| NSHA6 | 2,841 | 78 |
| NSHA7 | 448 | 67 |
| NSHA8 | 2,315 | 24 |
| NSHA9 | 530 | 12 |
| NSHA10 | 442 | 11 |
| NSHA11 | 1,885 | 22 |
| NSHA12 | 40 | 3 |
| NSHA13 | 1,042 | 11 |
| NSHA15 | 1,155 | 12 |
| NSHA17 | 492 | 12 |
| NSHA18 | 495 | 12 |

Skipped files include non-DICOM ancillary content and unreadable/nonconforming
files. The table is an audit-completeness signal, not a judgment that a case is
invalid.

| Case | Study | Modality | Series summary | Usable input assessment | Status |
|---|---:|---|---|---|---|
| NSHA1 | S1 | CT | 7 CT; 6 ready; largest regular stacks 236 x 1 | Multiple header-ready CT reconstructions. Prior notes identify a cardiac candidate, but final reconstruction requires visual review. | `candidate` |
| NSHA2 | S1 | CT | 12 CT; 7 ready; largest regular stack 220 x 1 | At least one regular CT volume is available; choose after visual review. | `candidate` |
| NSHA2 | S2 | MRI | 7 cine, 5 LGE/MDE, 6 other; 16/18 ready; cine 22 x 20, LGE 112 x 1 | Full cine-plus-LGE study. Prior notes identify a pre-procedure cine/LGE pair; verify the exact pair locally. | `selected_by_notes` |
| NSHA2 | S3 | MRI | 8 cine, 2 LGE/MDE, 4 other; 12/14 ready; cine 15 x 20, LGE 92 x 1 | Full cine-plus-LGE study. Prior notes identify a post-procedure cine/LGE pair; verify the exact pair locally. | `selected_by_notes` |
| NSHA3 | S1 | MRI | 6 cine, 5 LGE/MDE, 6 other; 15/17 ready; cine 18 x 20, LGE 100 x 1 | Strong cine-plus-LGE candidate. A cine/LGE pair from this study was used for the current biv-me workflow, with adaptive view correction. | `selected_by_notes` |
| NSHA3 | S2 | MRI | 6 cine, 2 LGE/MDE, 4 other; 10/12 ready; cine 21 x 20, LGE 92 x 1 | Alternative cine-plus-LGE study; no final selection recorded. | `candidate` |
| NSHA4 | S1 | MRI | 2 cine, 4 LGE/MDE, 6 other; 10/12 ready; possible cine 15 x 1, LGE 9 x 1 | MRI is present but cine temporal structure is not yet adequate for an automatic biv-me choice. | `needs_review` |
| NSHA4 | S2 | CT | 24 CT; 19 ready; largest regular stack 572 x 1 | Multiple high-coverage CT volumes are available. Map this opaque study to the intended cardiac versus validation acquisition before selection. | `candidate` |
| NSHA4 | S3 | CT | 8 CT; 4 ready; largest regular stack 375 x 1 | CT volumes are available, but several have inconsistent geometry. Needs visual and header review before use. | `needs_review` |
| NSHA5 | S1 | CT | 11 CT; 7 ready; largest regular stack 454 x 1 | Multiple candidate CT reconstructions. Prior notes distinguish cardiac/soft-tissue/fat purposes; exact use remains unresolved. | `candidate` |
| NSHA5 | S2 | CT | 11 CT; 7 ready; largest regular stack 267 x 1 | Second CT study with usable regular volumes; map study role before choosing a reconstruction. | `candidate` |
| NSHA6 | S1 | MRI | 4 cine, 2 LGE/MDE, 4 other; 8/10 ready; cine 16 x 20, LGE 100 x 1 | Full cine-plus-LGE study. Prior notes select cine for structure; LGE remains a candidate. | `selected_by_notes` |
| NSHA6 | S2 | CT | 10 CT; 6 ready; largest regular stack 443 x 1 | Usable CT candidates are available; no final selection recorded. | `candidate` |
| NSHA7 | S1 | CT | 4 CT; 2 ready; largest regular stack 112 x 1 | Limited CT set; candidate selection needs visual review. | `needs_review` |
| NSHA8 | S1 | CT | 8 CT; 4 ready; largest regular stack 439 x 1 | CT candidates are available. Map this opaque study to the intended acquisition before choosing. | `candidate` |
| NSHA8 | S2 | CT | 10 CT; 7 ready; largest regular stack 228 x 1 | Second CT study with usable regular volumes; final reconstruction remains unresolved. | `candidate` |
| NSHA9 | S1 | CT | 8 CT; 7 ready; largest regular stack 243 x 1 | Several geometry-ready CT candidates are available; visual selection is pending. | `candidate` |
| NSHA10 | S1 | CT | 8 CT; 7 ready; largest regular stack 213 x 1 | Prior notes identify a selected CT workflow input; verify that the available source still matches the prior export. | `selected_by_notes` |
| NSHA11 | S1 | MRI | 7 cine, 2 LGE/MDE, 5 other; 11/14 ready; cine 18 x 20, LGE 140 x 1 | Cine-plus-LGE data are present despite prior quality concerns. Requires visual review before declaring usable. | `needs_review` |
| NSHA11 | S2 | CT | 8 CT; 4 ready; largest regular stack 202 x 1 | CT is present but half of the series fail geometry checks. Choose only after visual review. | `needs_review` |
| NSHA12 | S1 | CT | 4 CT; 4 ready; largest regular stack 34 x 1 | Very limited coverage compared with other CT cases. | `not_usable` |
| NSHA13 | S1 | MRI | 6 cine, 5 LGE/MDE, 4 other; 13/15 ready; cine 19 x 20, LGE 160 x 1 | Strong cine-plus-LGE candidate. No cine/LGE pairing has been selected and reviewed yet. | `candidate` |
| NSHA14 | — | CT/MRI | No authorized diagnostics directory available. | No source data audited. | `not_available` |
| NSHA15 | S1 | CT | 9 CT; 5 ready; largest regular stack 272 x 1 | Candidate CT volumes are present. Prior notes identify structure and fat-analysis goals; final selection needs visual review. | `candidate` |
| NSHA16 | — | CT/MRI | No authorized diagnostics directory available. | No source data audited. | `not_available` |
| NSHA17 | S1 | CT | 6 CT; 6 ready; largest regular stack 228 x 1 | Geometry is consistently usable. Prior notes select a CT candidate but flag a prior derived export for replacement. | `selected_by_notes` |
| NSHA18 | S1 | CT | 6 CT; 6 ready; largest regular stack 222 x 1 | Geometry is consistently usable. Prior notes identify CT candidates but no final selection. | `candidate` |

## Recommended next actions

### MRI cases

For a biv-me plus LGE workflow, start only from a study that has both a
multi-frame cine short-axis stack and a regular LGE/MDE stack. The strongest
header-based candidates are NSHA2 S2/S3, NSHA3 S1/S2, NSHA6 S1, NSHA11 S1, and
NSHA13 S1. Use the full original MR study, not an MPR export.

Before inference, create an ignored case-local inventory and record the exact
cine and LGE series in its ignored provenance:

```bash
PYTHONPATH=src python -m vtseg inspect-dicom /authorized/full-mr-study \
  --json results/local-case/source/dicom_inventory.json
```

Then visually confirm the cine short-axis stack, a true 4-chamber cine view,
and the native LGE/MDE stack. Header classification alone cannot make those
clinical/anatomical decisions.

### CT cases

For TotalSegmentator, choose one regular, complete CT reconstruction after
visual review. Prefer the reconstruction intended for cardiac anatomy and avoid
mixing a derived MPR export with its source series. The existing notes may
prioritize a phase or reconstruction, but current image quality must be checked
in Slicer before segmentation.

## Unresolved items

- Exact DICOM Study/Series UIDs and descriptive labels are intentionally absent
  from this tracked document. They must be retrieved from ignored local
  inventories at run time.
- Header checks cannot verify image quality, metallic artifact burden, contrast
  timing, the optimal CT reconstruction, or clinical suitability.
- NSHA4 has two CT studies whose clinical roles require local mapping before
  selecting a series.
- The opaque S2/S3 labels in multi-study cases are stable only for this audit;
  map them to the intended local study before relying on a prior pre/post
  designation.
- NSHA5 and NSHA8 each have two CT studies; their intended roles and final
  reconstruction choices remain unresolved.
- NSHA4 MRI has ambiguous cine temporal structure and is not ready for
  automatic biv-me selection without dedicated review.
- NSHA11 MRI is header-plausible but prior notes questioned quality; it needs
  visual acceptance before use.
- NSHA12 has only a limited CT stack and remains unsuitable for the planned
  full-volume workflow.
- NSHA14 and NSHA16 have no available diagnostics directory to audit.
- Prior-note selections for NSHA1, NSHA2, NSHA6, NSHA10, and NSHA17 require
  re-verification against the currently available source data before reuse.
