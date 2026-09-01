# MRI backend feasibility assessment

Assessment date: 2026-09-01. This is a research triage based on representative
local headers and current upstream documentation; it is not a validation claim.

## Observed MRI domains

Two exported acquisitions prove that this dataset cannot use one generic “MRI”
assumption:

1. **Static 3D MDE/LGE:** 100 classic single-frame MR objects, one series, one
   study, 512×512, 0.9375×0.9375 mm in-plane, 1.8 mm thickness with approximately
   0.9 mm center spacing, 100 unique spatial positions, approximately 89.1 mm
   coverage, no repeated positions, one trigger time, and
   `CardiacNumberOfImages=1`. The sequence description identifies 3D MDE with
   navigator timing; it is not cine. The scanner is a 1.5 T GE system, with
   `ScanningSequence=GR` and `SequenceVariant=SS/SK`.
2. **Gated short-axis FIESTA cine:** 320 classic single-frame MR objects, one
   series, 512×512, 0.9375×0.9375 mm in-plane, 8 mm slice spacing, 16 unique
   locations with 20 images at every location, 20 consistent `TriggerTime`
   values, and `CardiacNumberOfImages=20`. No
   `TemporalPositionIdentifier` is populated. This is a defensible 20-frame
   short-axis cine when a frame is selected explicitly.

Another representative raw MR export contained 12 different series in one
folder, including localizers, 2D MDE, short-axis cine, and real-time sequences.
One functional short-axis series had six positions repeated 20 times. Therefore
folder names and `InstanceNumber` alone are not reliable acquisition selectors.

## TotalSegmentator MRI

**Project/publication:** [TotalSegmentator](https://github.com/wasserth/TotalSegmentator),
including its MRI publication linked from that repository.

**Current capability:** TotalSegmentator 2.18.0 exposes `total_mr` as an open
MR task with 50 labels. Its registry contains one whole `heart` label and
`aorta`; it does not contain LV blood pool, RV blood pool, or myocardium labels.
`heartchambers_highres` contains the needed CT labels but is explicitly a CT
task and licensed. Task names ending in `_mr` are the MR models, apart from
documented special cases unrelated to cardiac chambers.

**Domain:** `total_mr` is a 3D multi-organ model for volumetric MRI, not a
cardiac cine or LGE chamber/myocardium model. Even if its whole-heart label ran
on a prepared acquisition, that label cannot be split into the required masks
without another validated algorithm.

**Verdict:** technically runnable on some 3D MR NIfTI data, but not a valid
Milestone 1 MRI backend because all three required anatomical distinctions are
missing. It must not be substituted for `heartchambers_highres`, and the CT task
must not be run on MR.

## Pretrained alternatives

### 1. PGE-UNet (cine candidate)

- **Project/model:** [PGE-UNet](https://github.com/QuocKhanhLuong/PGE-UNet)
- **Publication:** *Integrating Physics Guidance Into Deep Learning for Cine
  Cardiovascular Segmentation*, Computerized Medical Imaging and Graphics 134,
  102798 (2026), DOI 10.1016/j.compmedimag.2026.102798.
- **Maintenance:** new 2026 official implementation; small project history, so
  integration maturity remains unproven.
- **Assumptions:** short-axis cine CMR. ACDC and multi-centre/multi-vendor M&Ms
  checkpoints are provided. It is not an LGE model.
- **Dimensionality/labels:** 2.5D, five adjacent slices; BG, LV, RV, myocardium.
  All three canonical structures are available for the FIESTA cine acquisition.
- **Input/preprocessing:** repository scripts convert source NIfTI to `.npy`,
  construct five-slice inputs, normalize/preprocess per dataset, and synthesize
  a pseudo B1 map. A production adapter would need to reproduce and test those
  transformations, then map the output back to the source affine.
- **Orientation/resampling:** not accepted implicitly. The prepared frame must
  be transformed to the checkpoint's documented training layout and predictions
  inverse-transformed; round-trip geometry tests are mandatory.
- **Weights:** official ACDC and M&Ms state-dict checkpoints plus checksums are
  published on Hugging Face.
- **License:** research purposes only; commercial use requires author contact.
- **Hardware/dependencies:** documented Python 3.11, PyTorch 2.6, CUDA 12.4.
- **Risks:** newer/less independently exercised code; no turnkey arbitrary-case
  inference command is documented; physics-derived preprocessing increases the
  adapter and validation burden.
- **Suitability:** strongest next **cine** candidate because the M&Ms checkpoint
  matches the required labels and has multi-centre/multi-vendor training context.

### 2. UK Biobank cardiac FCN (cine baseline)

- **Project/model:** [baiwenjia/ukbb_cardiac](https://github.com/baiwenjia/ukbb_cardiac),
  with a [TensorFlow 2 compatibility fork/workflow](https://github.com/chfc-cmi/cmr-seg-tl).
- **Publication:** Bai et al., *Automated cardiovascular magnetic resonance
  image analysis with fully convolutional networks*, JCMR 20:65 (2018),
  DOI 10.1186/s12968-018-0471-x.
- **Maintenance:** established but old; the compatibility fork addresses some
  deployment and end-diastolic-frame assumptions.
- **Assumptions:** UK Biobank-style short-axis cine/bSSFP, not LGE/MDE.
- **Dimensionality/labels:** 2D slice-wise FCN over cine NIfTI; LV cavity,
  myocardium, and RV cavity are produced.
- **Input/preprocessing:** 4D short-axis NIfTI through `deploy_network.py`; the
  repository deployment code performs its expected normalization/resampling.
  An adapter must record the selected frame and verify inverse geometry.
- **Orientation/resampling:** deployment conventions must be audited against the
  oblique DICOM-derived RAS affine. No output is accepted until it overlays the
  source after inverse transformation.
- **Weights:** pretrained `FCN_sa` weights are downloaded by the demo workflow.
- **License:** Apache-2.0 code; dataset/model terms still require review for the
  intended research use.
- **Hardware/dependencies:** original TensorFlow 1-era stack; GPU useful but not
  conceptually required. The TF2 fork is preferable for feasibility testing.
- **Risks:** homogeneous training domain and old dependencies; known domain-shift
  risk on heterogeneous scans.
- **Suitability:** valuable reproducible baseline for the observed FIESTA cine,
  but ranked below the multi-centre PGE-UNet checkpoint.

### 3. CardiacSegmenter (cine candidate; LGE partial candidate)

- **Project/model:** [Hakim-F/CardiacSegmenter](https://github.com/Hakim-F/CardiacSegmenter)
- **Publication:** linked from the repository; pretrained sequence-specific
  models accompany the code.
- **Maintenance:** legacy (Python 3.4, TensorFlow 1.1/1.2); no modern release or
  active packaging.
- **Assumptions:** sequence-specific 2D U-Nets. The cine model expects 4D
  short-axis cine; the LGE model expects 3D LGE.
- **Dimensionality/labels:** cine produces LV endocardium, LV myocardium, and RV
  endocardium, satisfying the canonical structures. LGE produces LV
  endocardium, LV myocardium, and scar—but **not RV**, so it cannot satisfy the
  canonical interface for the 3D MDE stack.
- **Input/preprocessing:** NIfTI input through sequence-specific scripts. The
  legacy code's cropping, normalization, slice stacking, and output restoration
  must be audited and containerized before use.
- **Orientation/resampling:** undocumented as a patient-space contract; requires
  explicit round-trip tests and Slicer overlay review.
- **Weights:** pretrained cine and LGE models are linked from the repository.
- **License:** no clear repository license was found; use is blocked until code
  and weight terms are clarified.
- **Hardware/dependencies:** CPU reportedly needs about 12 GB RAM; the supported
  TensorFlow/Python versions are obsolete and should be isolated in a container.
- **Risks:** unclear license, obsolete dependencies, and no RV output from the
  LGE checkpoint.
- **Suitability:** a secondary cine comparison only after license clarification;
  the LGE checkpoint can inform an exploratory partial-label experiment but is
  not a backend for this pipeline.

## Strong methods not counted as deployable pretrained alternatives

- [MyoPS2020](https://github.com/HiLab-git/MyoPS2020) produces LV, RV, and
  myocardium/pathology labels, but its fine model requires co-registered C0,
  LGE/DE, and T2 channels plus a coarse channel. The local representative is a
  single MDE series, and the official repository documents training rather than
  distributing a ready checkpoint.
- [PointCloudUDA / Adapt Everywhere](https://github.com/sulaimanvesal/PointCloudUDA)
  directly addresses bSSFP-to-LGE adaptation and the right label family, but its
  repository documents training/evaluation with a user-supplied model path and
  does not publish a ready inference checkpoint. Its PyTorch 1.4/CUDA 10 stack
  is also legacy.
- Generic nnU-Net is a strong framework for training on curated local or public
  cardiac labels, but a framework without a sequence-matched trained checkpoint
  is not a pretrained backend.

## Ranked recommendation

1. **Benchmark PGE-UNet's M&Ms checkpoint on explicit frames from the gated
   FIESTA series.** It matches cine acquisition physics, supplies LV/RV/myocardium,
   has current reproducible weights, and is trained on multi-centre/multi-vendor
   data. First build a one-model adapter with reversible preprocessing and
   patient-space geometry tests.
2. **Benchmark the UK Biobank FCN/TF2 fork on the same frames as a baseline.**
   Its older, homogeneous domain makes it less likely to generalize, but it is a
   useful independent comparison with the exact required labels.
3. **Consider CardiacSegmenter cine only after license clarification and
   containerization.** Do not treat its LGE model as complete because RV is absent.

There is **no reviewed off-the-shelf pretrained candidate that currently meets
all three canonical masks for the observed static 3D MDE/LGE acquisition**.
The next MDE-specific research step should verify whether additional aligned C0
and T2 series exist for a MyoPS-style benchmark; otherwise, curate a small
reference set and evaluate transfer learning/domain adaptation using MS-CMRSeg
or MM-WHS-style LGE data. Do not extrapolate cine benchmark success to MDE.
