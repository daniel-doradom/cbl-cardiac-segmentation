# Modality and acquisition support

| Input | Inspection | Preparation | Segmentation | Status |
|---|---:|---:|---:|---|
| Classic single-frame CT, one spatial volume | yes | yes | TotalSegmentator `heartchambers_highres` | backend/license/weights required |
| Classic single-frame MR, static 3D MDE/LGE | yes | yes | cine geometry alignment only | rigid biv-me mesh transfer; scar segmentation not configured |
| Classic single-frame MR, gated cine with consistent temporal tags | yes | explicit frame required | biv-me (experimental) | full multi-view cine DICOM and external environment required |
| Repeated positions with ambiguous phase encoding | yes | no | no | fails with reason |
| Enhanced/multiframe DICOM | identified | no | no | future dedicated converter |
| Other modality | yes where headers are readable | no | no | unsupported |

MRI is not treated as a homogeneous model domain. The acquisition classifier is
descriptive and conservative: MDE/LGE tokens indicate delayed-enhancement data;
CINE/FIESTA/SSFP tokens indicate cine/bSSFP; otherwise the type remains
`mr_other`. This aids review but never selects a model silently.

The biv-me route uses the prepared cine frame as its output grid but requires
the complete multi-view cine CMR DICOM input for upstream view selection,
contouring, and model fitting. It cannot be used for the CT or static MDE/LGE
rows.

After cine fitting, the experimental `align-bivme-lge` stage can select and
prepare a native LGE/MDE target from the same study, phase-match a fitted cine
mesh, rigidly register cine to fixed LGE, and rasterize transformed masks on the
LGE grid. This does not make biv-me an LGE segmentation model and does not
identify scar.
