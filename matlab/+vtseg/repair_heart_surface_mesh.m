function repair_info = repair_heart_surface_mesh(mesh_path, mesh_prefix)
%REPAIR_HEART_SURFACE_MESH Repair holes/intersections in a saved surface mesh.
%
% Default use after Gen_mesh and before iso2meshEP:
%   repair_heart_surface_mesh(densemesh_path)
%
% To repair the remeshed surface shown by visualize_generated_meshes:
%   repair_heart_surface_mesh(coarsemesh_path, 'sur_heart')

    if nargin < 2 || isempty(mesh_prefix)
        mesh_prefix = 'heart_sur';
    end

    mesh_path = char(mesh_path);
    mesh_prefix = char(mesh_prefix);

    cor_file = fullfile(mesh_path, [mesh_prefix '.cor']);
    tri_file = fullfile(mesh_path, [mesh_prefix '.tri']);
    idx_file = fullfile(mesh_path, [mesh_prefix '.idx']);

    if ~isfile(cor_file) || ~isfile(tri_file)
        error('Could not find %s.cor and %s.tri in:\n%s', ...
            mesh_prefix, mesh_prefix, mesh_path);
    end

    [tri_precision, idx_precision] = mesh_file_precision(mesh_prefix);

    node = read_binary_matrix(cor_file, 3, 'double');
    face = read_binary_matrix(tri_file, 3, tri_precision);
    face = double(face);

    fprintf('\nOriginal mesh: %d nodes, %d faces\n', ...
        size(node, 1), size(face, 1));

    [node_fixed, face_fixed] = meshcheckrepair(node, face, 'meshfix');
    face_fixed = double(face_fixed);

    fprintf('Repaired mesh: %d nodes, %d faces\n\n', ...
        size(node_fixed, 1), size(face_fixed, 1));

    idx_fixed = [];
    if isfile(idx_file)
        idx = read_binary_vector(idx_file, idx_precision);
        if numel(idx) == size(node, 1)
            nearest_original_node = nearest_vertices(node_fixed, node);
            idx_fixed = idx(nearest_original_node);
        else
            warning(['Skipping idx repair because %s.idx has %d labels, ' ...
                'but %s.cor has %d nodes.'], mesh_prefix, numel(idx), ...
                mesh_prefix, size(node, 1));
        end
    end

    repair_info = struct();
    repair_info.mesh_path = mesh_path;
    repair_info.mesh_prefix = mesh_prefix;
    repair_info.original_nodes = size(node, 1);
    repair_info.original_faces = size(face, 1);
    repair_info.fixed_nodes = size(node_fixed, 1);
    repair_info.fixed_faces = size(face_fixed, 1);
    repair_info.saved = false;
    repair_info.backup_path = '';

    while true
        show_before_after_mesh(node, face, node_fixed, face_fixed, mesh_prefix);

        user_choice = questdlg( ...
            sprintf('Save repaired %s mesh?', mesh_prefix), ...
            'Confirm Mesh Repair', ...
            'Save', ...
            'Review Again', ...
            'Cancel', ...
            'Save');

        if isempty(user_choice)
            user_choice = 'Cancel';
        end

        switch user_choice
            case 'Save'
                backup_path = backup_original_files( ...
                    mesh_path, mesh_prefix, cor_file, tri_file, idx_file);

                write_binary_matrix(cor_file, node_fixed, 'double');
                write_binary_matrix(tri_file, face_fixed, tri_precision);

                if ~isempty(idx_fixed)
                    write_binary_vector(idx_file, idx_fixed, idx_precision);
                end

                repair_info.saved = true;
                repair_info.backup_path = backup_path;
                save(fullfile(mesh_path, [mesh_prefix '_repair_info.mat']), ...
                    'repair_info');

                fprintf('Saved repaired mesh files to:\n%s\n', mesh_path);
                fprintf('Original files backed up to:\n%s\n', backup_path);
                return;

            case 'Review Again'
                continue;

            otherwise
                fprintf('Repaired mesh was not saved.\n');
                return;
        end
    end
end

function [tri_precision, idx_precision] = mesh_file_precision(mesh_prefix)
    if strcmp(mesh_prefix, 'heart_sur') || strcmp(mesh_prefix, 'lv_sur')
        tri_precision = 'double';
        idx_precision = 'double';
    else
        tri_precision = 'int32';
        idx_precision = 'int32';
    end
end

function values = read_binary_matrix(file_path, columns, precision)
    fid = fopen(file_path, 'rb');
    if fid < 0
        error('Could not open file for reading:\n%s', file_path);
    end
    values = fread(fid, [columns, inf], precision)';
    fclose(fid);
end

function values = read_binary_vector(file_path, precision)
    fid = fopen(file_path, 'rb');
    if fid < 0
        error('Could not open file for reading:\n%s', file_path);
    end
    values = fread(fid, inf, precision);
    fclose(fid);
end

function write_binary_matrix(file_path, values, precision)
    fid = fopen(file_path, 'wb');
    if fid < 0
        error('Could not open file for writing:\n%s', file_path);
    end
    fwrite(fid, values', precision);
    fclose(fid);
end

function write_binary_vector(file_path, values, precision)
    fid = fopen(file_path, 'wb');
    if fid < 0
        error('Could not open file for writing:\n%s', file_path);
    end
    fwrite(fid, values(:), precision);
    fclose(fid);
end

function nearest_idx = nearest_vertices(query_nodes, reference_nodes)
    nearest_idx = zeros(size(query_nodes, 1), 1);

    if exist('knnsearch', 'file') == 2
        nearest_idx = knnsearch(reference_nodes, query_nodes);
        return;
    end

    for i = 1:size(query_nodes, 1)
        d2 = sum((reference_nodes - query_nodes(i, :)).^2, 2);
        [~, nearest_idx(i)] = min(d2);
    end
end

function backup_path = backup_original_files( ...
        mesh_path, mesh_prefix, cor_file, tri_file, idx_file)

    timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    backup_path = fullfile(mesh_path, ...
        sprintf('%s_backup_%s', mesh_prefix, timestamp));

    if ~isfolder(backup_path)
        mkdir(backup_path);
    end

    copyfile(cor_file, fullfile(backup_path, [mesh_prefix '.cor']));
    copyfile(tri_file, fullfile(backup_path, [mesh_prefix '.tri']));

    if isfile(idx_file)
        copyfile(idx_file, fullfile(backup_path, [mesh_prefix '.idx']));
    end
end

function show_before_after_mesh(node, face, node_fixed, face_fixed, mesh_prefix)
    fig = figure('Name', ['Mesh repair: ' mesh_prefix], 'NumberTitle', 'off');

    ax1 = subplot(1, 2, 1);
    plot_surface(ax1, node, face, 'Original');

    ax2 = subplot(1, 2, 2);
    plot_surface(ax2, node_fixed, face_fixed, 'After meshcheckrepair');

    camera_link = linkprop([ax1 ax2], {'CameraPosition', 'CameraTarget', ...
        'CameraUpVector', 'CameraViewAngle'});
    setappdata(fig, 'CameraLink', camera_link);
    rotate3d(fig, 'on');
end

function plot_surface(ax, node, face, plot_title)
    patch(ax, ...
        'Vertices', node, ...
        'Faces', face, ...
        'FaceColor', [0.75 0.20 0.18], ...
        'EdgeColor', [0.10 0.10 0.10], ...
        'EdgeAlpha', 0.08, ...
        'FaceAlpha', 0.95);

    title(ax, sprintf('%s\n%d nodes, %d faces', ...
        plot_title, size(node, 1), size(face, 1)));
    axis(ax, 'equal');
    grid(ax, 'on');
    view(ax, 3);
    xlabel(ax, 'X');
    ylabel(ax, 'Y');
    zlabel(ax, 'Z');
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    material(ax, 'dull');
end
