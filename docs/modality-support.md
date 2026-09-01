# Modality and acquisition support

| Input | Inspection | Preparation | Segmentation | Status |
|---|---:|---:|---:|---|
| Classic single-frame CT, one spatial volume | yes | yes | TotalSegmentator `heartchambers_highres` | backend/license/weights required |
| Classic single-frame MR, static 3D MDE/LGE | yes | yes | none configured | candidate gap documented |
| Classic single-frame MR, gated cine with consistent temporal tags | yes | explicit frame required | none configured | cine candidates ranked |
| Repeated positions with ambiguous phase encoding | yes | no | no | fails with reason |
| Enhanced/multiframe DICOM | identified | no | no | future dedicated converter |
| Other modality | yes where headers are readable | no | no | unsupported |

MRI is not treated as a homogeneous model domain. The acquisition classifier is
descriptive and conservative: MDE/LGE tokens indicate delayed-enhancement data;
CINE/FIESTA/SSFP tokens indicate cine/bSSFP; otherwise the type remains
`mr_other`. This aids review but never selects a model silently.
