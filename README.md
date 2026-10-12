# CBL Cardiac Segmentation

Automatic heart segmentation from cardiac MRI and CT, turned into
biventricular tetrahedral meshes for ventricular tachycardia (VT) and
electrocardiographic imaging (ECGI) research. The pipeline does the slow part,
outlining the ventricles slice by slice, automatically, and leaves a person to
review and correct the result before a mesh is built.

This is research software. It is not a medical device and is not for clinical
use. It never modifies the source DICOM data.

## Pipeline

```text
 MRI (cine + LGE)                     CT (native + short-axis MPR)
 biv-me fits the heart on cine MRI    TotalSegmentator segments the native CT
 fit is aligned onto the LGE scan     masks are mapped onto the short-axis MPR
            \                                    /
             +----> LV endocardium, RV endocardium, epicardium/myocardium
                                     |
                        review in 3D Slicer (choose slices)
                                     |
                  export to MATLAB (editable copy + read-only original)
                                     |
           correct masks in MATLAB (edit, grow/shrink, remove islands)
                                     |
                     biventricular surface and tetrahedral mesh
```

## Status

- **MRI:** working on multi-view cine MRI with a matching LGE scan. biv-me
  corrects slice shifts between breath holds; the fit is rigidly aligned onto
  the LGE grid. Scar is not segmented automatically; an optional manual LGE
  scar step runs in MATLAB before meshing.
- **CT:** working on native cardiac CT with a short-axis reformat. The RV free
  wall is usually missing from the automatic myocardium, so the export can add
  a 3 mm starting estimate around the RV that must be checked in MATLAB.
- **Both:** every result is reviewed by a person in 3D Slicer and MATLAB before
  meshing. The Python and MATLAB code have automated tests on synthetic data.

## Requirements

- Python 3.10 or newer (3.11 tested), with the packages in `pyproject.toml`
- **MRI:** [biv-me](https://github.com/UOA-Heart-Mechanics-Research/biv-me)
  and its models; SimpleITK and PyVista for LGE alignment
- **CT:** [TotalSegmentator](https://github.com/wasserth/TotalSegmentator)
  2.18 with the `heartchambers_highres` task (free academic license), and a GPU
- [3D Slicer](https://www.slicer.org/) for reviewing masks
- MATLAB with the Image Processing and Statistics toolboxes, and
  [iso2mesh](https://github.com/fangq/iso2mesh), for correction and meshing

## Quick start

```bash
git clone https://github.com/daniel-doradom/cbl-cardiac-segmentation.git
cd cbl-cardiac-segmentation
pip install -e '.[dev,registration]'   # add ,ct for TotalSegmentator
python -m vtseg --help                 # lists every pipeline step
python -m pytest -q                    # Python tests
```

In MATLAB, an exported case is reviewed and meshed with:

```matlab
addpath('matlab');
setup_vtseg('Iso2meshPath', '/path/to/iso2mesh');
vtseg.main_ct_tetmesh(exportFolder, []);               % CT
vtseg.main_bivme_lge_tetmesh(exportFolder, [], false); % MRI
```

MATLAB tests: `runtests('matlab/tests')`.

## Documentation

- [docs/usage.md](docs/usage.md): every command, inputs and outputs
- [docs/manual-workflow.md](docs/manual-workflow.md): one case end to end,
  including Slicer review and MATLAB correction
- [docs/ct-backend.md](docs/ct-backend.md) and
  [docs/bivme-backend.md](docs/bivme-backend.md): the two automatic backends
- [docs/pipeline.md](docs/pipeline.md) and
  [docs/validation.md](docs/validation.md): design and validation notes
- [README-short.md](README-short.md): setup for members of our lab

## Credits

This pipeline builds on
[biv-me](https://github.com/UOA-Heart-Mechanics-Research/biv-me) (MRI fitting),
[TotalSegmentator](https://github.com/wasserth/TotalSegmentator) (CT
segmentation), [iso2mesh](https://github.com/fangq/iso2mesh) (meshing) and
[3D Slicer](https://www.slicer.org/) (review). They keep their own licenses;
please cite them as their authors ask. The MATLAB meshing stages
(`Gen_mesh`, `iso2meshEP`, `corLoc2Gol`) come from our lab's earlier
VT/ECGI meshing workflow.

## License

MIT, see [LICENSE](LICENSE). Patient data is not included and is not covered
by this license.

## Citation

```bibtex
@software{dorado_cbl_cardiac_segmentation,
  author = {Dorado, Daniel},
  title  = {{CBL Cardiac Segmentation}: automatic cardiac MRI and CT
            segmentation for VT/ECGI meshing},
  year   = {2026},
  url    = {https://github.com/daniel-doradom/cbl-cardiac-segmentation}
}
```
