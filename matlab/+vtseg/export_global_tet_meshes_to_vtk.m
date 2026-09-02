function export_global_tet_meshes_to_vtk(global_path)
% Export coarse and dense global tetrahedral/surface heart meshes to legacy VTK.
%
% Usage:
%   export_global_tet_meshes_to_vtk('C:\path\to\global')

    if nargin < 1 || isempty(global_path)
        error('Provide global_path, the folder containing the global heart mesh files.');
    end

    exportOneTetMesh(global_path, 'tet_heart.cor', 'tet_heart.tet', 'tet_node_values.val', 'tet_heart.vtk', 'tet_node_values');
    exportOneTetMesh(global_path, 'tet_dense_heart.cor', 'tet_dense_heart.tet', 'tet_dense_node_values.val', 'tet_dense_heart.vtk', 'tet_dense_node_values');
    exportOneSurfaceMesh(global_path, 'sur_heart.cor', 'sur_heart.tri', 'sur_node_values.val', 'sur_heart.vtk', 'sur_node_values');
    exportOneSurfaceMesh(global_path, 'sur_dense_heart.cor', 'sur_dense_heart.tri', 'sur_dense_node_values.val', 'sur_dense_heart.vtk', 'sur_dense_node_values');
end

function exportOneTetMesh(global_path, cor_name, tet_name, val_name, vtk_name, scalar_name)
    nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, cor_name), 3, 'double');
    tets = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, tet_name), 4, 'int32');
    values = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, val_name), 1, 'double');
    values = values(:);

    if numel(values) ~= size(nodes, 1)
        error('%s has %d values but %s has %d nodes.', val_name, numel(values), cor_name, size(nodes, 1));
    end

    if any(tets(:) < 1) || any(tets(:) > size(nodes, 1))
        error('%s contains node indices outside 1:%d.', tet_name, size(nodes, 1));
    end

    vtk_path = fullfile(global_path, vtk_name);
    fid = fopen(vtk_path, 'w');
    if fid < 0
        error('Could not create %s.', vtk_path);
    end
    cleanup = onCleanup(@() fclose(fid));

    fprintf(fid, '# vtk DataFile Version 3.0\n');
    fprintf(fid, 'Heart tetrahedral mesh\n');
    fprintf(fid, 'ASCII\n');
    fprintf(fid, 'DATASET UNSTRUCTURED_GRID\n');
    fprintf(fid, 'POINTS %d double\n', size(nodes, 1));
    fprintf(fid, '%.12g %.12g %.12g\n', nodes.');
    fprintf(fid, 'CELLS %d %d\n', size(tets, 1), size(tets, 1) * 5);
    fprintf(fid, '4 %d %d %d %d\n', (tets - 1).');
    fprintf(fid, 'CELL_TYPES %d\n', size(tets, 1));
    fprintf(fid, '%d\n', repmat(10, size(tets, 1), 1));
    fprintf(fid, 'POINT_DATA %d\n', size(nodes, 1));
    fprintf(fid, 'SCALARS %s double 1\n', scalar_name);
    fprintf(fid, 'LOOKUP_TABLE default\n');
    fprintf(fid, '%.12g\n', values);

    fprintf('Wrote %s with %d nodes and %d tetrahedra.\n', vtk_path, size(nodes, 1), size(tets, 1));
end

function exportOneSurfaceMesh(global_path, cor_name, tri_name, val_name, vtk_name, scalar_name)
    nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, cor_name), 3, 'double');
    tris = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, tri_name), 3, 'int32');
    values = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, val_name), 1, 'double');
    values = values(:);

    if numel(values) ~= size(nodes, 1)
        error('%s has %d values but %s has %d nodes.', val_name, numel(values), cor_name, size(nodes, 1));
    end

    if any(tris(:) < 1) || any(tris(:) > size(nodes, 1))
        error('%s contains node indices outside 1:%d.', tri_name, size(nodes, 1));
    end

    vtk_path = fullfile(global_path, vtk_name);
    fid = fopen(vtk_path, 'w');
    if fid < 0
        error('Could not create %s.', vtk_path);
    end
    cleanup = onCleanup(@() fclose(fid));

    fprintf(fid, '# vtk DataFile Version 3.0\n');
    fprintf(fid, 'Heart surface mesh\n');
    fprintf(fid, 'ASCII\n');
    fprintf(fid, 'DATASET UNSTRUCTURED_GRID\n');
    fprintf(fid, 'POINTS %d double\n', size(nodes, 1));
    fprintf(fid, '%.12g %.12g %.12g\n', nodes.');
    fprintf(fid, 'CELLS %d %d\n', size(tris, 1), size(tris, 1) * 4);
    fprintf(fid, '3 %d %d %d\n', (tris - 1).');
    fprintf(fid, 'CELL_TYPES %d\n', size(tris, 1));
    fprintf(fid, '%d\n', repmat(5, size(tris, 1), 1));
    fprintf(fid, 'POINT_DATA %d\n', size(nodes, 1));
    fprintf(fid, 'SCALARS %s double 1\n', scalar_name);
    fprintf(fid, 'LOOKUP_TABLE default\n');
    fprintf(fid, '%.12g\n', values);

    fprintf('Wrote %s with %d nodes and %d triangles.\n', vtk_path, size(nodes, 1), size(tris, 1));
end
