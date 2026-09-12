function main_ct_tetmesh(main_path, gs_range)
%MAIN_CT_TETMESH Review imported CT masks and generate biventricular meshes.
%
% main_path is an export-matlab-seg case created from a Slicer-approved,
% promoted CT short-axis MPR. CT has no cine/LGE scar stage in this workflow.

if nargin < 2 || isempty(gs_range)
    gs_range = [];
end
setup_vtseg();

required_directories = {'raw', 'seg', 'mesh', 'remesh', 'global'};
for index = 1:numel(required_directories)
    path = fullfile(main_path, required_directories{index});
    if ~isfolder(path)
        error('Missing MATLAB case directory: %s', path);
    end
end
manifest_path = fullfile(main_path, 'seg', 'vtseg_export_manifest.json');
if ~isfile(manifest_path)
    error('Missing generic vtseg export manifest: %s', manifest_path);
end
manifest = jsondecode(fileread(manifest_path));
if ~isfield(manifest, 'modality') || ~strcmp(manifest.modality, 'CT')
    error('main_ct_tetmesh requires a CT export-matlab-seg case.');
end

raw_path = [fullfile(main_path, 'raw'), filesep];
seg_path = [fullfile(main_path, 'seg'), filesep];
mesh_path = [fullfile(main_path, 'mesh'), filesep];
remesh_path = [fullfile(main_path, 'remesh'), filesep];
global_path = [fullfile(main_path, 'global'), filesep];
required_masks = {'Lendo.mat', 'Rendo.mat', 'Epi.mat', 'myocardium.mat'};
for index = 1:numel(required_masks)
    if ~isfile(fullfile(seg_path, required_masks{index}))
        error('Missing imported CT mask: %s', required_masks{index});
    end
end
if isempty(dir(fullfile(raw_path, '*.dcm')))
    error('No DICOM files found in raw/. Run export-matlab-seg before this script.');
end
if isempty(gs_range)
    first_raw = dir(fullfile(raw_path, '*.dcm'));
    gs_range = vtseg.dicom_display_range(fullfile(raw_path, first_raw(1).name));
end

% The shared viewer/reviewer reads DICOM RescaleSlope/Intercept. For CT it
% therefore displays Hounsfield units and uses DICOM window metadata when set.
review_figure = vtseg.visualize_bivme_lge_masks(main_path, gs_range);
uiwait(review_figure);
vtseg.readdata(raw_path, seg_path);
vtseg.ventriclesSegmentation_v2(raw_path, seg_path, gs_range);
vtseg.Gen_mesh(seg_path, mesh_path);
vtseg.iso2meshEP(mesh_path, remesh_path, global_path, 0);
vtseg.corLoc2Gol(seg_path, remesh_path, global_path);
vtseg.saveNearestDicomPixelValues(global_path, raw_path);
vtseg.export_global_tet_meshes_to_vtk(global_path);
disp('Imported CT-mask review and biventricular mesh generation complete.');
end
