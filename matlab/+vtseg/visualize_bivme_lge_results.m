function review_figure = visualize_bivme_lge_results(main_path, gs_range, animate_alignment)
%VISUALIZE_BIVME_LGE_RESULTS Review MATLAB masks and generated biv-me/LGE meshes.
%
% main_path is a MATLAB case written by vtseg's export-matlab-seg command and
% processed by main_bivme_lge_tetmesh.  It opens the interactive DICOM/mask
% review window and creates mesh and node-value figures when mesh outputs are
% present. Set animate_alignment=true to step through raw DICOM slices with
% nearby mesh nodes.

if nargin < 2 || isempty(gs_range)
    gs_range = [];
end
if nargin < 3
    animate_alignment = false;
end

setup_vtseg();

raw_path = [fullfile(main_path, 'raw'), filesep];
remesh_path = [fullfile(main_path, 'remesh'), filesep];
global_path = [fullfile(main_path, 'global'), filesep];
if ~isfolder(raw_path) || ~isfolder(remesh_path) || ~isfolder(global_path)
    error('Expected raw/, remesh/, and global/ under MATLAB case: %s', main_path);
end

% Always make the mask review available, even if a later mesh read fails.
review_figure = vtseg.visualize_bivme_lge_masks(main_path, gs_range);

required = {
    fullfile(remesh_path, 'sur_heart.cor'), fullfile(remesh_path, 'sur_heart.tri'), ...
    fullfile(remesh_path, 'sur_dense_heart.cor'), fullfile(remesh_path, 'sur_dense_heart.tri'), ...
    fullfile(remesh_path, 'tet_heart.cor'), fullfile(remesh_path, 'tet_heart.tet'), ...
    fullfile(remesh_path, 'tet_dense_heart.cor'), fullfile(remesh_path, 'tet_dense_heart.tet')};
if ~all(cellfun(@isfile, required))
    warning('Mesh outputs are incomplete. Review masks now; run main_bivme_lge_tetmesh to generate meshes.');
    return;
end

sur_nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'sur_heart.cor'), 3, 'double');
sur_elems = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'sur_heart.tri'), 3, 'int32');
sur_dense_nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'sur_dense_heart.cor'), 3, 'double');
sur_dense_elems = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'sur_dense_heart.tri'), 3, 'int32');
tet_nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'tet_heart.cor'), 3, 'double');
tet_elems = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'tet_heart.tet'), 4, 'int32');
tet_dense_nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'tet_dense_heart.cor'), 3, 'double');
tet_dense_elems = vtseg.DicomUtils.read_Geometry_heart(fullfile(remesh_path, 'tet_dense_heart.tet'), 4, 'int32');

show_mesh_panels(sur_nodes, sur_elems, sur_dense_nodes, sur_dense_elems, ...
    tet_nodes, tet_elems, tet_dense_nodes, tet_dense_elems);
show_node_value_panels(global_path);

if animate_alignment
    required_global = {fullfile(global_path, 'tet_dense_heart.cor')};
    if ~all(cellfun(@isfile, required_global))
        warning('No global dense tetrahedral coordinates found for slice-to-mesh animation.');
        return;
    end
    tet_dense_global = vtseg.DicomUtils.read_Geometry_heart( ...
        fullfile(global_path, 'tet_dense_heart.cor'), 3, 'double');
    [dicoms_struct, dicoms_imgs] = vtseg.DicomUtils.readDicomFiles(raw_path);
    vtseg.DicomUtils.animate_slice_mesh_alignment(tet_dense_global, dicoms_struct, dicoms_imgs, 1.0, 0.25);
end
end

function show_mesh_panels(sur_nodes, sur_elems, sur_dense_nodes, sur_dense_elems, ...
        tet_nodes, tet_elems, tet_dense_nodes, tet_dense_elems)
figure('Name', 'biv-me LGE generated meshes', 'NumberTitle', 'off', 'Color', 'w');
tiledlayout(1, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; plotmesh(sur_nodes, sur_elems); format_mesh_axes(gca, 'Surface mesh');
nexttile; plotmesh(sur_dense_nodes, sur_dense_elems); format_mesh_axes(gca, 'Dense surface mesh');
nexttile; plotmesh(tet_nodes, tet_elems); format_mesh_axes(gca, 'Tetrahedral mesh');
nexttile; plotmesh(tet_dense_nodes, tet_dense_elems); format_mesh_axes(gca, 'Dense tetrahedral mesh');
end

function show_node_value_panels(global_path)
files = {
    fullfile(global_path, 'tet_heart.cor'), fullfile(global_path, 'tet_node_values.val'), ...
    fullfile(global_path, 'tet_dense_heart.cor'), fullfile(global_path, 'tet_dense_node_values.val')};
if ~all(cellfun(@isfile, files))
    warning('Global node-value outputs are unavailable; skipping node-value figure.');
    return;
end

tet_nodes = vtseg.DicomUtils.read_Geometry_heart(files{1}, 3, 'double');
tet_values = vtseg.DicomUtils.read_Geometry_heart(files{2}, 1, 'double');
dense_nodes = vtseg.DicomUtils.read_Geometry_heart(files{3}, 3, 'double');
dense_values = vtseg.DicomUtils.read_Geometry_heart(files{4}, 1, 'double');

figure('Name', 'biv-me LGE mesh node values', 'NumberTitle', 'off', 'Color', 'w');
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
scatter3(tet_nodes(:, 1), tet_nodes(:, 2), tet_nodes(:, 3), 10, tet_values, 'filled');
format_value_axes(gca, 'Coarse mesh node values');
nexttile;
scatter3(dense_nodes(:, 1), dense_nodes(:, 2), dense_nodes(:, 3), 10, dense_values, 'filled');
format_value_axes(gca, 'Dense mesh node values');
end

function format_mesh_axes(ax, plot_title)
axis(ax, 'equal');
view(ax, 75, 30);
xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z');
title(ax, plot_title);
lighting(ax, 'gouraud'); camlight(ax, 'headlight'); material(ax, 'dull');
end

function format_value_axes(ax, plot_title)
axis(ax, 'equal'); view(ax, 3);
xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z');
title(ax, plot_title); colorbar(ax); colormap(ax, gray(256));
end
