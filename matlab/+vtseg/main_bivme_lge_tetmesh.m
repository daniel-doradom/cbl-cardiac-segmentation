function main_bivme_lge_tetmesh(main_path, gs_range, run_scar)
%MAIN_BIVME_LGE_TETMESH Review imported biv-me/LGE masks and generate meshes.
%
% main_path is a vtseg export-matlab-seg output with raw/, seg/, mesh/,
% remesh/, and global/.  The raw files are generated in the same slice order
% as the Lendo/Rendo/Epi stacks.  Existing masks are opened for correction by
% ventriclesSegmentation_v2; no automatic re-segmentation is performed.

if nargin < 2 || isempty(gs_range)
    gs_range = [];
end
if nargin < 3
    run_scar = false;
end

setup_vtseg();

required_directories = {'raw', 'seg', 'mesh', 'remesh', 'global'};
for index = 1:numel(required_directories)
    path = fullfile(main_path, required_directories{index});
    if ~isfolder(path)
        error('Missing MATLAB case directory: %s', path);
    end
end

raw_path = [fullfile(main_path, 'raw'), filesep];
seg_path = [fullfile(main_path, 'seg'), filesep];
mesh_path = [fullfile(main_path, 'mesh'), filesep];
remesh_path = [fullfile(main_path, 'remesh'), filesep];
global_path = [fullfile(main_path, 'global'), filesep];

required_masks = {'Lendo.mat', 'Rendo.mat', 'Epi.mat', 'myocardium.mat'};
for index = 1:numel(required_masks)
    if ~isfile(fullfile(seg_path, required_masks{index}))
        error('Missing imported biv-me mask: %s', required_masks{index});
    end
end

if isempty(dir(fullfile(raw_path, '*.dcm')))
    error('No DICOM files found in raw/. Run export-matlab-seg before this script.');
end

% One display crop, drawn once, is shared by the correction window and the
% final overview figures. The slice viewer with fill and opacity controls is
% not part of this script; open it with vtseg.visualize_bivme_lge_masks.
vtseg.define_review_crop(main_path, gs_range);

% Rebuild geometry from the exact DICOM stack paired with the imported masks.
vtseg.readdata(raw_path, seg_path);

% Existing masks trigger the legacy review/correction UI and are saved only
% after its explicit confirmation.
vtseg.ventriclesSegmentation_v2(raw_path, seg_path, gs_range);

if run_scar
    vtseg.segmentFatScar(seg_path, raw_path, gs_range);
end

vtseg.Gen_mesh(seg_path, mesh_path);
vtseg.iso2meshEP(mesh_path, remesh_path, global_path, 0);
vtseg.corLoc2Gol(seg_path, remesh_path, global_path);
vtseg.saveNearestDicomPixelValues(global_path, raw_path);
vtseg.export_global_tet_meshes_to_vtk(global_path);
disp('Imported-mask review and biventricular mesh generation complete.');
end
