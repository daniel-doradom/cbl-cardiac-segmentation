classdef DicomUtils
%DICOMUTILS Utility methods for selecting and exporting DICOM slices.

    methods (Static)

        function [dicoms, dicoms_imgs] = readDicomFiles(source)
            source = string(source);


            if ~isfolder(source)
                error('DicomUtils:InvalidSource', ...
                    '>> Source directory does not exist: %s', source);
            end


            entries = dir(fullfile(source, '**', '*'));
            entries = entries(~[entries.isdir]);


            paths = strings(numel(entries), 1);


            for i = 1:numel(entries)
                paths(i) = string(fullfile(entries(i).folder, entries(i).name));
            end


            paths = sort(paths);


            dicoms = repmat(struct( ...
                'path', "", ...
                'sliceLocation', NaN, ...
                'sliceThickness', NaN, ...
                'instanceNumber', NaN), numel(paths), 1);


            imgs_cell = cell(numel(paths), 1);


            count = 0;


            for i = 1:numel(paths)
                path = paths(i);


                try
                    info = dicominfo(path);
                    img = vtseg.read_dicom_image(info);
                    if isempty(img) || any(size(img) == 0)
                        warning('DicomUtils:EmptyImage', ...
                            '>> Skipping empty DICOM image: %s', path);
                        continue;
                    end
                catch
                    continue;
                end


                count = count + 1;


                dicoms(count).path = path;


                dicoms(count).sliceLocation = ...
                    vtseg.DicomUtils.getNumericField(info, 'SliceLocation');


                dicoms(count).sliceThickness = ...
                    vtseg.DicomUtils.getNumericField(info, 'SliceThickness');


                dicoms(count).instanceNumber = ...
                    vtseg.DicomUtils.getNumericField(info, 'InstanceNumber');


                imgs_cell{count} = img;
            end


            dicoms = dicoms(1:count);
            imgs_cell = imgs_cell(1:count);


            if isempty(dicoms)
                error('DicomUtils:NoDicoms', ...
                    '>> No readable DICOM files found under: %s', source);
            end


            % Sort structs exactly as before
            [dicoms, sort_idx] = vtseg.DicomUtils.sortDicomFiles(dicoms);


            % Apply the same sorting to images
            imgs_cell = imgs_cell(sort_idx);


            % Convert image cell array to 3D stack: rows x cols x slices
            first_size = size(imgs_cell{1});


            if numel(first_size) ~= 2
                error('DicomUtils:Non2DImage', ...
                    'Expected 2D DICOM slices, but first image has size %s.', ...
                    mat2str(first_size));
            end


            dicoms_imgs = zeros([first_size, numel(imgs_cell)], 'like', imgs_cell{1});


            for k = 1:numel(imgs_cell)
                if ~isequal(size(imgs_cell{k}), first_size)
                    error('DicomUtils:ImageSizeMismatch', ...
                        '>> Image %d has size %s, expected %s.', ...
                        k, mat2str(size(imgs_cell{k})), mat2str(first_size));
                end


                dicoms_imgs(:,:,k) = imgs_cell{k};
            end

            fprintf('>> Read %d DICOM files from: %s\n', numel(dicoms), source);
            fprintf('>> Image stack size: %s\n', mat2str(size(dicoms_imgs)));
        end



        function targetInstances = define_target_Instances_from_temporal_Sequence( ...
                start_instanceNum, end_instanceNum, n_slices)

            frames_per_slice = input('How many frames are there per slice? ');
            temporal_frame = input(sprintf('Which temporal frame should be selected [1-%d]? ', frames_per_slice));


            validateattributes(start_instanceNum, {'numeric'}, {'scalar', 'integer', 'positive'});
            validateattributes(end_instanceNum, {'numeric'}, {'scalar', 'integer', '>=', start_instanceNum});
            validateattributes(n_slices, {'numeric'}, {'scalar', 'integer', 'positive'});
            validateattributes(frames_per_slice, {'numeric'}, {'scalar', 'integer', 'positive'});
            validateattributes(temporal_frame, {'numeric'}, {'scalar', 'integer', '>=', 1, '<=', frames_per_slice});


            % Assumption:
            % Instance numbers are ordered as:
            % slice 1 frame 1, slice 1 frame 2, ..., slice 1 frame N,
            % slice 2 frame 1, slice 2 frame 2, ..., etc.


            offset = mod(temporal_frame - 1 - mod(start_instanceNum - 1, frames_per_slice), ...
                         frames_per_slice);


            first_same_time_instance = start_instanceNum + offset;


            same_time_instances = first_same_time_instance : frames_per_slice : end_instanceNum;


            n_available = numel(same_time_instances);
            n_to_select = min(n_slices, n_available);


            if n_available < n_slices
                warning(['Only %d spatial slices are available for temporal frame %d. ' ...
                         'Selecting all available slices instead.'], ...
                         n_available, temporal_frame);
            end


            selected_indices = round(linspace(1, n_available, n_to_select));
            targetInstances = same_time_instances(selected_indices);
        end



        function selected_dicoms = select_valid_dicoms(dicoms, targetInstances)

            if isempty(dicoms)
                error('DicomUtils:EmptyDicoms', ...
                    'The DICOM array is empty.');
            end

            if isempty(targetInstances)
                error('DicomUtils:EmptyTargets', ...
                    'No target instance numbers were provided.');
            end

            instance_numbers = [dicoms.instanceNumber].';

            valid_mask = ~isnan(instance_numbers);

            valid_dicoms = dicoms(valid_mask);
            valid_instance_numbers = instance_numbers(valid_mask);

            if isempty(valid_dicoms)
                error('DicomUtils:NoInstanceNumbers', ...
                    'No DICOM files contain a valid InstanceNumber.');
            end

            selected_indices = zeros(numel(targetInstances), 1);

            for i = 1:numel(targetInstances)
                target = targetInstances(i);

                [~, selected_indices(i)] = min( ...
                    abs(valid_instance_numbers - target));
            end

            selected_indices = unique( ...
                selected_indices, 'stable');

            selected_dicoms = valid_dicoms(selected_indices);

            if numel(selected_dicoms) < numel(targetInstances)
                warning('DicomUtils:DuplicateSelections', ...
                    ['Only %d unique DICOM files were selected for ' ...
                     '%d target instances.'], ...
                    numel(selected_dicoms), ...
                    numel(targetInstances));
            end
        end


        function crop_rect = plot_cropped_myocardium_masks(seg_path, ref_slice)
            myocardium_file = fullfile(seg_path, 'myocardium.mat');
            load(myocardium_file, 'myocardium');

            myocardium = logical(myocardium);
            n_myo_slices = size(myocardium, 3);

            if nargin < 2 || isempty(ref_slice)
                ref_slice = round(n_myo_slices / 2);
            end

            ref_slice = max(1, min(n_myo_slices, round(ref_slice)));

            vtseg.ReviewStyle.newFigure('DICOM selection: define myocardium crop');
            imshow(myocardium(:, :, ref_slice));
            vtseg.ReviewStyle.axesTitle(gca, sprintf(['Draw crop box on Slice %d, ' ...
                'then double-click inside it'], ref_slice));

            h = drawrectangle('Color', 'r');
            wait(h);

            crop_pos = round(h.Position);

            x1 = max(1, crop_pos(1));
            y1 = max(1, crop_pos(2));
            x2 = min(size(myocardium, 2), x1 + crop_pos(3) - 1);
            y2 = min(size(myocardium, 1), y1 + crop_pos(4) - 1);

            close;

            crop_rect = [x1 y1 x2 - x1 + 1 y2 - y1 + 1];

            n_cols = ceil(sqrt(n_myo_slices));
            n_rows = ceil(n_myo_slices / n_cols);

            vtseg.ReviewStyle.newFigure('DICOM selection: cropped myocardium masks');
            tiledlayout(n_rows, n_cols, ...
                'TileSpacing', 'compact', ...
                'Padding', 'compact');

            for k = 1:n_myo_slices
                nexttile;
                cropped_mask = myocardium(y1:y2, x1:x2, k);
                imshow(cropped_mask);
                vtseg.ReviewStyle.axesTitle(gca, sprintf('Slice %d', k));
            end

            vtseg.ReviewStyle.figureTitle(gcf, 'Cropped Myocardium Masks');
        end


        function plot_selected_dicoms(selected_dicoms, display_time, gs_range)

            if nargin < 2 || isempty(display_time)
                display_time = 0.2;
            end


            if nargin < 3 || isempty(gs_range)
                gs_range = [];
            end

            if isempty(selected_dicoms)
                error('DicomUtils:EmptySelection', ...
                    'selected_dicoms is empty.');
            end

            if ~isscalar(display_time) || display_time < 0
                error('DicomUtils:InvalidDisplayTime', ...
                    'display_time must be a nonnegative scalar.');
            end

            figureHandle = vtseg.ReviewStyle.newFigure('DICOM selection: selected slices');

            axesHandle = axes('Parent', figureHandle);

            for i = 1:numel(selected_dicoms)

                if ~isvalid(figureHandle)
                    fprintf('Display window was closed.\n');
                    return;
                end

                dicomPath = selected_dicoms(i).path;

                if ~isfile(dicomPath)
                    warning('DicomUtils:MissingFile', ...
                        'Skipping missing file: %s', dicomPath);
                    continue;
                end

                try
                    imageData = dicomread(dicomPath);
                catch exception
                    warning('DicomUtils:ReadFailed', ...
                        'Could not read %s: %s', ...
                        dicomPath, exception.message);
                    continue;
                end

                imshow(imageData, gs_range, 'Parent', axesHandle);

                vtseg.ReviewStyle.axesTitle(axesHandle, sprintf( ...
                    ['Selected slice %d of %d | Instance %g | ' ...
                     'SliceLocation %.6f'], ...
                    i, ...
                    numel(selected_dicoms), ...
                    selected_dicoms(i).instanceNumber, ...
                    selected_dicoms(i).sliceLocation));

                drawnow;
                pause(display_time);
            end
        end


        function ask_user_confirmation_and_save_dicoms( ...
                selected_dicoms, output_dir)

            if isempty(selected_dicoms)
                error('DicomUtils:EmptySelection', ...
                    'No DICOM slices were selected.');
            end

            while true
                user_choice = questdlg( ...
                    sprintf('Save these %d selected slices?', ...
                        numel(selected_dicoms)), ...
                    'Confirm DICOM Selection', ...
                    'Save', ...
                    'Review Again', ...
                    'Cancel', ...
                    'Save');

                switch user_choice
                    case 'Save'
                        vtseg.DicomUtils.save_selected_dicoms( ...
                            selected_dicoms, output_dir);
                        return;

                    case 'Review Again'
                        vtseg.DicomUtils.plot_selected_dicoms( ...
                            selected_dicoms, 0.5);

                    otherwise
                        fprintf('Selection was not saved.\n');
                        return;
                end
            end
        end


        function save_selected_dicoms( ...
                selected_dicoms, output_dir)

            if isempty(selected_dicoms)
                error('DicomUtils:EmptyInput', ...
                    'selected_dicoms is empty.');
            end

            output_dir = char(output_dir);

            if ~isfolder(output_dir)
                [success, message] = mkdir(output_dir);

                if ~success
                    error('DicomUtils:CreateOutputFailed', ...
                        'Could not create "%s": %s', ...
                        output_dir, message);
                end
            end

            folder_names = { ...
                'raw', 'seg', 'mesh', 'remesh', 'global'};

            for i = 1:numel(folder_names)
                folder_path = fullfile( ...
                    output_dir, folder_names{i});

                if ~isfolder(folder_path)
                    [success, message] = mkdir(folder_path);

                    if ~success
                        error('DicomUtils:CreateFolderFailed', ...
                            'Could not create "%s": %s', ...
                            folder_path, message);
                    end
                end
            end

            output_dir_raw = fullfile(output_dir, 'raw');

            old_files = dir( ...
                fullfile(output_dir_raw, 'IM*.dcm'));

            for i = 1:numel(old_files)
                delete(fullfile( ...
                    old_files(i).folder, ...
                    old_files(i).name));
            end

            for i = 1:numel(selected_dicoms)
                source_file = char(selected_dicoms(i).path);

                if ~isfile(source_file)
                    error('DicomUtils:MissingSource', ...
                        'Source DICOM does not exist: %s', ...
                        source_file);
                end

                output_name = sprintf( ...
                    'IM%06d.dcm', i - 1);

                destination_file = fullfile( ...
                    output_dir_raw, output_name);

                [success, message] = copyfile( ...
                    source_file, destination_file);

                if ~success
                    error('DicomUtils:CopyFailed', ...
                        'Failed to copy "%s" to "%s": %s', ...
                        source_file, destination_file, message);
                end

                fprintf( ...
                    '%s | instance=%g | sliceLoc=%.6f\n', ...
                    output_name, ...
                    selected_dicoms(i).instanceNumber, ...
                    selected_dicoms(i).sliceLocation);
            end

            fprintf( ...
                '\nSaved %d selected DICOM files to:\n%s\n', ...
                numel(selected_dicoms), output_dir_raw);
        end

        % ================================================================================
        %                           visualize_generated_meshes.m
        % ================================================================================

        % ======================== Reading Functions =========================
        function values = read_Geometry_heart(file_path, columns, precision)
            fid = fopen(file_path,'rb');
            values = fread(fid,[columns,inf],precision)';
            fclose(fid);
        end






        function validateFaces(faces, number_of_nodes, file_name)
            if any(faces(:) < 1) || any(faces(:) > number_of_nodes)
                error('%s contains node indices outside 1:%d.', file_name, number_of_nodes);
            end
            fprintf('>> Validated %s!! all node indices are within 1:%d.\n', file_name, number_of_nodes);
        end






        % ======================== DICOM Transformation Functions =========================



        function [pixel_values, locations] = nearestDicomPixelValues(vertices, dicoms, dicom_images)
        % Return the physically nearest DICOM pixel center for every mesh vertex.
        %
        % locations contains the selected slice, row, column, and distance in mm.


            number_of_vertices = size(vertices, 1);
            number_of_slices = numel(dicoms);


            pixel_values = nan(number_of_vertices, 1);
            best_distance = inf(number_of_vertices, 1);
            best_slice = nan(number_of_vertices, 1);
            best_row = nan(number_of_vertices, 1);
            best_column = nan(number_of_vertices, 1);


            for k = 1:number_of_slices
                info = dicominfo(dicoms(k).path);
                image = vtseg.DicomUtils.applyDicomRescale(double(dicom_images(:,:,k)), info);


                image_position = double(info.ImagePositionPatient(:));
                orientation = double(info.ImageOrientationPatient(:));
                spacing = double(info.PixelSpacing(:));


                direction_along_columns = orientation(1:3);
                direction_along_rows = orientation(4:6);


                relative_position = vertices - image_position.';
                column_index = round((relative_position * direction_along_columns) / spacing(2));
                row_index = round((relative_position * direction_along_rows) / spacing(1));


                valid = row_index >= 0 & row_index < size(image, 1) & column_index >= 0 & column_index < size(image, 2);


                nearest_pixel_position = image_position.' + column_index * spacing(2) * direction_along_columns.' + row_index * spacing(1) * direction_along_rows.';


                distance = vecnorm(vertices - nearest_pixel_position, 2, 2);
                replace = valid & distance < best_distance;


                if any(replace)
                    linear_index = sub2ind(size(image), row_index(replace) + 1, column_index(replace) + 1);


                    pixel_values(replace) = image(linear_index);
                    best_distance(replace) = distance(replace);
                    best_slice(replace) = k;
                    best_row(replace) = row_index(replace) + 1;
                    best_column(replace) = column_index(replace) + 1;
                end
            end


            locations = table(best_slice, best_row, best_column, best_distance, 'VariableNames', {'SliceIndex', 'PixelRow', 'PixelColumn', 'DistanceMm'});
        end


        function [pixel_values, locations] = nearestDicomPixelValues_V2(vertices, dicoms, dicom_images)
            % Find the globally nearest DICOM pixel center using a 3D point cloud.
            % Requires Statistics and Machine Learning Toolbox for knnsearch.

            number_of_slices = numel(dicoms);

            pixel_positions = [];
            pixel_intensities = [];
            pixel_slices = [];
            pixel_rows = [];
            pixel_columns = [];

            for k = 1:number_of_slices
                info = dicominfo(dicoms(k).path);

                image = double(dicom_images(:,:,k));
                image = vtseg.DicomUtils.applyDicomRescale(image, info);

                image_position = double(info.ImagePositionPatient(:)).';
                orientation = double(info.ImageOrientationPatient(:));
                spacing = double(info.PixelSpacing(:));

                column_direction = orientation(1:3).';
                row_direction = orientation(4:6).';

                number_of_rows = size(image, 1);
                number_of_columns = size(image, 2);

                % Create all zero-based pixel indices
                [rows, columns] = ndgrid( ...
                    0:number_of_rows-1, ...
                    0:number_of_columns-1);

                rows = rows(:);
                columns = columns(:);

                % Convert pixel indices into 3D patient coordinates
                slice_positions = image_position ...
                    + columns * spacing(2) .* column_direction ...
                    + rows * spacing(1) .* row_direction;

                % Add this slice to the global pixel point cloud
                pixel_positions = [pixel_positions; slice_positions];
                pixel_intensities = [pixel_intensities; image(:)];
                pixel_slices = [pixel_slices; repmat(k, numel(image), 1)];
                pixel_rows = [pixel_rows; rows + 1];
                pixel_columns = [pixel_columns; columns + 1];
            end

            % Search the entire 3D pixel point cloud
            [nearest_index, nearest_distance] = knnsearch( ...
                pixel_positions, vertices, 'K', 1);

            pixel_values = pixel_intensities(nearest_index);

            best_slice = pixel_slices(nearest_index);
            best_row = pixel_rows(nearest_index);
            best_column = pixel_columns(nearest_index);
            best_distance = nearest_distance;

            locations = table( ...
                best_slice, best_row, best_column, best_distance, ...
                'VariableNames', ...
                {'SliceIndex', 'PixelRow', 'PixelColumn', 'DistanceMm'});
        end


        function image = applyDicomRescale(image, info)
            if isfield(info, 'RescaleSlope')
                image = image * double(info.RescaleSlope);
            end
            if isfield(info, 'RescaleIntercept')
                image = image + double(info.RescaleIntercept);
            end
        end






        function [X, Y, Z, image_position, plane_normal] = dicomPlaneCoordinates(info, image_size)


            required_fields = {'ImagePositionPatient', 'ImageOrientationPatient', 'PixelSpacing'};


            for i = 1:numel(required_fields)
                if ~isfield(info, required_fields{i})
                    error('DICOM is missing %s.', required_fields{i});
                end
            end


            image_position = double(info.ImagePositionPatient(:));
            orientation = double(info.ImageOrientationPatient(:));
            pixel_spacing = double(info.PixelSpacing(:));


            direction_along_columns = orientation(1:3);
            direction_along_rows = orientation(4:6);
            plane_normal = cross(direction_along_columns, direction_along_rows);
            plane_normal = plane_normal / norm(plane_normal);


            row_spacing = pixel_spacing(1);
            column_spacing = pixel_spacing(2);
            [column_index, row_index] = meshgrid(0:image_size(2)-1, 0:image_size(1)-1);


            X = image_position(1) + column_index * column_spacing * direction_along_columns(1) + row_index * row_spacing * direction_along_rows(1);
            Y = image_position(2) + column_index * column_spacing * direction_along_columns(2) + row_index * row_spacing * direction_along_rows(2);
            Z = image_position(3) + column_index * column_spacing * direction_along_columns(3) + row_index * row_spacing * direction_along_rows(3);
        end






        % ======================== Plotting Functions =========================

        function plot_heart_and_slices(tet_nodes, tet_elems, dicoms, dicom_images, slice_alpha)
            vtseg.ReviewStyle.newFigure('Mesh alignment: global mesh and slices'); hold on;


            % plot mesh
            plotmesh(tet_nodes, tet_elems); vtseg.ReviewStyle.axesTitle(gca, 'Heart Surface Mesh');



            % plot slices
            for k = 1:numel(dicoms)
                info = dicominfo(dicoms(k).path);
                image = vtseg.DicomUtils.applyDicomRescale(double(dicom_images(:,:,k)), info);
                [X, Y, Z] = vtseg.DicomUtils.dicomPlaneCoordinates(info, size(image));
                surf(X, Y, Z, image, 'EdgeColor', 'none', 'FaceAlpha', slice_alpha);
            end


            vtseg.ReviewStyle.axesTitle(gca, sprintf('Heart mesh over %d selected DICOM slices', numel(dicoms)));
            xlabel('Patient X (mm)'); ylabel('Patient Y (mm)'); zlabel('Patient Z (mm)');
            axis equal tight; axis vis3d; view(3); grid on;lighting gouraud; camlight headlight; material dull; rotate3d on;
        end






        function animate_slice_mesh_alignment(tet_nodes, dicoms, dicom_images, near_plane_tolerance_mm, animation_pause_seconds)
            vtseg.ReviewStyle.newFigure('Mesh alignment: per-slice');
            for k = 1:numel(dicoms)
                clf;

                info = dicominfo(dicoms(k).path);
                image = vtseg.DicomUtils.applyDicomRescale(double(dicom_images(:,:,k)), info);
                [X, Y, Z, image_position, plane_normal] = vtseg.DicomUtils.dicomPlaneCoordinates(info, size(image));


                distance_to_plane = (tet_nodes - image_position.') * plane_normal;
                near_plane = abs(distance_to_plane) <= near_plane_tolerance_mm;


                surf(X, Y, Z, image, 'FaceColor', 'texturemap', 'EdgeColor', 'none', 'FaceAlpha', 0.85); hold on;

                scatter3(tet_nodes(near_plane,1), tet_nodes(near_plane,2), tet_nodes(near_plane,3), 10, 'r', 'filled');


                camtarget(mean([X(:), Y(:), Z(:)], 1));
                campos(mean([X(:), Y(:), Z(:)], 1) + 500 * plane_normal.');
                camup([0 0 1]); camproj orthographic;


                vtseg.ReviewStyle.axesTitle(gca, sprintf('Slice %d/%d: %d mesh nodes within %.1f mm', k, numel(dicoms), nnz(near_plane), near_plane_tolerance_mm));
                xlabel('Patient X (mm)'); ylabel('Patient Y (mm)'); zlabel('Patient Z (mm)');
                colormap gray; axis vis3d; grid on; rotate3d on;


                drawnow; pause(animation_pause_seconds);
            end
        end


    end


    methods (Static, Access = private)

        function value = getNumericField(info, fieldName)

            value = NaN;

            if ~isfield(info, fieldName)
                return;
            end

            rawValue = info.(fieldName);

            if isnumeric(rawValue)
                if ~isempty(rawValue)
                    value = double(rawValue(1));
                end
                return;
            end

            if ischar(rawValue) || isstring(rawValue)
                converted = str2double(string(rawValue));

                if ~isnan(converted)
                    value = converted;
                end
            end
        end


        function [dicoms, sort_idx] = sortDicomFiles(dicoms)

            n = numel(dicoms);

            sliceLocations = reshape( ...
                [dicoms.sliceLocation], [], 1);

            instanceNumbers = reshape( ...
                [dicoms.instanceNumber], [], 1);

            paths = reshape( ...
                string({dicoms.path}), [], 1);

            originalIndex = (1:n).';

            sliceMissing = isnan(sliceLocations);
            instanceMissing = isnan(instanceNumbers);

            sliceSortValues = sliceLocations;
            sliceSortValues(sliceMissing) = Inf;

            instanceSortValues = instanceNumbers;
            instanceSortValues(instanceMissing) = Inf;

            sortTable = table( ...
                sliceMissing, ...
                sliceSortValues, ...
                instanceMissing, ...
                instanceSortValues, ...
                paths, ...
                originalIndex, ...
                'VariableNames', { ...
                    'SliceMissing', ...
                    'SliceLocation', ...
                    'InstanceMissing', ...
                    'InstanceNumber', ...
                    'Path', ...
                    'OriginalIndex'});

            sortTable = sortrows(sortTable, { ...
                'SliceMissing', ...
                'SliceLocation', ...
                'InstanceMissing', ...
                'InstanceNumber', ...
                'Path'});

            sort_idx = sortTable.OriginalIndex;
            dicoms = dicoms(sort_idx);
        end






    end
end
