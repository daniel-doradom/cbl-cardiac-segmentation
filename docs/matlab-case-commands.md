# MATLAB Case Commands

These commands run the Slicer-approved MATLAB exports exposed through
`results/best/`. Run the setup block once at the beginning of each MATLAB
session, then run one case command at a time.

Each export contains two copies:

- `original/` is the untouched baseline and must not be edited.
- `work/` is the editable copy used for review, correction, and meshing.

The commands below explicitly select `work/`.

## Session setup

```matlab
clear classes; clear functions; rehash

repoRoot = '/home/daniel-dorado/Desktop/CISC890-DR/VT/vt-segmentation-eval';
addpath(fullfile(repoRoot, 'matlab'));
setup_vtseg('Iso2meshPath', fullfile(repoRoot, '.external', 'iso2mesh'));

best = fullfile(repoRoot, 'results', 'best');
```

## CT cases

These ten exports include the optional 3 mm synthetic RV free-wall proxy. The
proxy is an initialization aid and must be inspected and corrected during the
MATLAB review.

```matlab
vtseg.main_ct_tetmesh(fullfile(best, 'nsha01-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k390-537-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha04-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k664-833-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha05-ct', 'manual', 'matlab-direct-mpr-rv-wall-3mm-k390-494-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha07-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k360-483-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha08-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k430-568-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha09-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k350-479-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha10-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k472-660-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha15-ct', 'manual', 'matlab-direct-mpr-rv-wall-3mm-k625-698-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha17-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k279-519-20slices', 'work'), []);
vtseg.main_ct_tetmesh(fullfile(best, 'nsha18-ct', 'manual', 'matlab-native-mapped-rv-wall-3mm-k420-586-20slices', 'work'), []);
```

## MRI cases

These three cases passed Slicer review and have MATLAB exports. The final
argument controls the scar stage; `false` skips it.

```matlab
vtseg.main_bivme_lge_tetmesh(fullfile(best, 'nsha06',      'manual', 'matlab-source-025-099-20slices', 'work'), [], false);
vtseg.main_bivme_lge_tetmesh(fullfile(best, 'nsha03-post', 'manual', 'matlab-source-032-076-20slices', 'work'), [], false);
vtseg.main_bivme_lge_tetmesh(fullfile(best, 'nsha02-post', 'manual', 'matlab-source-030-090-20slices', 'work'), [], false);
```
