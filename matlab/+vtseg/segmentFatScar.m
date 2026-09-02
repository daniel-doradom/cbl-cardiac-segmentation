function segmentFatScar(seg_path, raw_path, gs_range)
    % Read DICOMs in the same file order used by ventriclesSegmentation_v2.
    [dicoms_imgs, modality] = read_dicoms_in_segmentation_order(raw_path);

    if strlength(modality) == 0
        modality = input('Modality not found in DICOM header. Please enter the imaging modality (CT/MRI): ', 's');
    end

    modality = upper(string(modality));
    fprintf('Detected imaging modality: %s\n', modality);


    % modality = 'MRI' % for testing purposes, remove this line in production TBD/TODO
    if modality == "CT"
        % Perform CT-specific fat segmentation (TBD)
        fprintf('CT fat segmentation is not yet implemented!!!\n');
    elseif modality == "MR" || modality == "MRI"
        % Perform MRI-specific scar segmentation
        scar_slices = input('Slices to inspect for scar, e.g. [5 6 7] (empty = all) >> ');
        save_scar_mask_fwhm(seg_path, dicoms_imgs, gs_range, scar_slices);

    else
        error('Unsupported imaging modality: %s.', modality);
    end
end

function [dicoms_imgs, modality] = read_dicoms_in_segmentation_order(raw_path)
    folder = dir(strcat(raw_path, '*.dcm'));
    folder = folder(~[folder.isdir]);

    if isempty(folder)
        error('No DICOM files found in: %s', raw_path);
    end

    modality = "";

    for k = 1:numel(folder)
        dicom_path = strcat(raw_path, folder(k).name);
        info = dicominfo(dicom_path);
        img = dicomread(info);

        if k == 1 && isfield(info, 'Modality')
            modality = string(info.Modality);
        end

        if k == 1
            dicoms_imgs = zeros([size(img), numel(folder)], 'like', img);
        elseif ~isequal(size(img), size(dicoms_imgs(:, :, 1)))
            error('DICOM image %s has size %s, expected %s.', ...
                dicom_path, mat2str(size(img)), ...
                mat2str(size(dicoms_imgs(:, :, 1))));
        end

        dicoms_imgs(:, :, k) = img;
    end

    fprintf('Read %d DICOMs in segmentation order from: %s\n', ...
        numel(folder), raw_path);
end

function [scar_mask, initial_region, fwhm_thresholds] = save_scar_mask_fwhm(seg_path, dicoms_imgs, gs_range, scar_slices)
%SAVE_SCAR_MASK_FWHM Segment scar from a manual seed using the FWHM method.
%
% For each selected slice, the user selects one seed point inside obvious
% scar. An initial region is built from pixels with intensity greater than
% 50% of the seed intensity and restricted to myocardium. The FWHM threshold
% is then applied to the whole myocardium.
% Logic:
    % 1. myocardium = epi_mask - endocardial_masks
    % 2. User selects one seed point inside obvious scar.
    % 3. initial_region = pixels with intensity > 0.5 * intensity(seed_point)
    % 4. initial_region = initial_region AND myocardium
    % 5. Imax = max(intensity(initial_region))
    % 6. Imin = min(intensity(myocardium))
    % 7. threshold = Imin + 0.5 * (Imax - Imin)
    % 8. scar_mask = myocardium AND (image >= threshold)

    % dicoms_imgs = double(dicoms_imgs);
    myocardium_path = fullfile(seg_path, 'myocardium.mat');
    if ~isfile(myocardium_path)
        save_myo_mask(seg_path);
    end
    load(myocardium_path, 'myocardium');
    myocardium = logical(myocardium);

    if ndims(dicoms_imgs) ~= 3 || ndims(myocardium) ~= 3
        error('dicoms_imgs and myocardium must both be 3D stacks.');
    end

    if ~isequal(size(dicoms_imgs), size(myocardium))
        error('Image stack size %s does not match myocardium size %s.', ...
            mat2str(size(dicoms_imgs)), mat2str(size(myocardium)));
    end

    n_slices = size(dicoms_imgs, 3);
    if isempty(scar_slices)
        scar_slices = 1:n_slices;
    end
    scar_slices = unique(scar_slices(:).', 'stable');
    scar_slices = scar_slices(scar_slices >= 1 & scar_slices <= n_slices);

    if isempty(scar_slices)
        error('No valid scar slices were selected. Valid range is 1-%d.', n_slices);
    end

    scar_mask = false(size(myocardium));
    initial_region = false(size(myocardium));
    fwhm_thresholds = nan(1, n_slices);
    seed_points = nan(n_slices, 2);
    seed_intensities = nan(1, n_slices);
    Imax_values = nan(1, n_slices);
    Imin_values = nan(1, n_slices);

    figure_handle = figure('Name', 'FWHM scar segmentation', ...
        'NumberTitle', 'off');

    for n_slice = scar_slices
        if ~isvalid(figure_handle)
            disp('FWHM scar segmentation window was closed.');
            break;
        end

        img_slice = dicoms_imgs(:, :, n_slice);
        myo_mask = myocardium(:, :, n_slice);

        if ~any(myo_mask(:))
            warning('Slice %d has an empty myocardium mask. Skipping.', n_slice);
            continue;
        end

        clf(figure_handle);
        ax = axes('Parent', figure_handle);
        imshow(img_slice, gs_range, 'Parent', ax); colormap(gca, gray); axis image;
        hold(ax, 'on');
        contour(ax, myo_mask, [0.5 0.5], 'g', 'LineWidth', 1);
        title(ax, sprintf('Slice %d: myocardium outline', n_slice));

        prompt = sprintf('Select scar seed point on slice %d? (y/n/quit) >> ', n_slice);
        str = input(prompt, 's');

        if strcmpi(str, 'quit')
            break;
        end

        if isempty(str) || strcmpi(str, 'n')
            continue;
        end

        disp('Click one seed point inside obvious scar.');
        [x_seed, y_seed] = ginput(1);

        if isempty(x_seed) || isempty(y_seed)
            warning('No seed point was selected on slice %d. Skipping.', n_slice);
            continue;
        end

        seed_col = round(x_seed);
        seed_row = round(y_seed);

        if seed_row < 1 || seed_row > size(img_slice, 1) || ...
                seed_col < 1 || seed_col > size(img_slice, 2)
            warning('Seed point on slice %d is outside the image. Skipping.', n_slice);
            continue;
        end

        if ~myo_mask(seed_row, seed_col)
            warning('Seed point on slice %d is outside myocardium. Skipping.', n_slice);
            continue;
        end

        seed_intensity = img_slice(seed_row, seed_col);

        if ~isfinite(seed_intensity)
            warning('Seed point on slice %d has a non-finite intensity. Skipping.', n_slice);
            continue;
        end

        initial_slice = (img_slice > 0.5 * seed_intensity) & myo_mask;

        if ~any(initial_slice(:))
            warning('Initial region on slice %d is empty. Skipping.', n_slice);
            continue;
        end

        initial_values = img_slice(initial_slice);
        myo_values = img_slice(myo_mask);
        initial_values = initial_values(isfinite(initial_values));
        myo_values = myo_values(isfinite(myo_values));

        if isempty(initial_values) || isempty(myo_values)
            warning('Slice %d does not have finite values for thresholding. Skipping.', n_slice);
            continue;
        end

        Imax = max(initial_values);
        Imin = min(myo_values);
        fwhm_threshold = Imin + 0.5 * (Imax - Imin);
        scar_slice = myo_mask & (img_slice >= fwhm_threshold);

        initial_region(:, :, n_slice) = initial_slice;
        scar_mask(:, :, n_slice) = scar_slice;

        fwhm_thresholds(n_slice) = fwhm_threshold;
        seed_points(n_slice, :) = [seed_col, seed_row];
        seed_intensities(n_slice) = seed_intensity;
        Imax_values(n_slice) = Imax;
        Imin_values(n_slice) = Imin;

        plot(ax, seed_col, seed_row, 'y+', 'LineWidth', 1.5, 'MarkerSize', 10);
        contour(ax, initial_slice, [0.5 0.5], 'y', 'LineWidth', 1);
        contour(ax, scar_slice, [0.5 0.5], 'r', 'LineWidth', 1.5);
        title(ax, sprintf('Slice %d: Imin = %.3f, Imax = %.3f, threshold = %.3f', ...
            n_slice, Imin, Imax, fwhm_threshold));
        drawnow;
        pause(1);
    end

    ask_user_confirmation_and_save_scar_mask( ...
        seg_path, dicoms_imgs, myocardium, scar_mask, initial_region, ...
        fwhm_thresholds, scar_slices, gs_range, seed_points, ...
        seed_intensities, Imax_values, Imin_values);
end

function ask_user_confirmation_and_save_scar_mask( ...
        seg_path, dicoms_imgs, myocardium, scar_mask, initial_region, ...
        fwhm_thresholds, scar_slices, gs_range, seed_points, ...
        seed_intensities, Imax_values, Imin_values)

    output_file = fullfile(seg_path, 'scar_mask_fwhm.mat');
    review_scar_mask_fwhm(dicoms_imgs, myocardium, scar_mask, initial_region, ...
        fwhm_thresholds, scar_slices, gs_range, seed_points, ...
        Imax_values, Imin_values);

    while true
        scar_slice_flags = squeeze(any(any(scar_mask, 1), 2));
        initial_slice_flags = squeeze(any(any(initial_region, 1), 2));
        n_scar_slices = nnz(scar_slice_flags);
        n_initial_slices = nnz(initial_slice_flags);

        user_choice = questdlg( ...
            sprintf(['Save FWHM scar mask?\n\n' ...
                'Slices with initial region: %d\n' ...
                'Slices with scar: %d\n' ...
                'Scar voxels: %d'], ...
                n_initial_slices, n_scar_slices, nnz(scar_mask)), ...
            'Confirm FWHM Scar Mask', ...
            'Save', ...
            'Review Again', ...
            'Cancel', ...
            'Save');

        switch user_choice
            case 'Save'
                save(output_file, ...
                    'scar_mask', 'initial_region', 'fwhm_thresholds', ...
                    'scar_slices', 'seed_points', 'seed_intensities', ...
                    'Imax_values', 'Imin_values');
                fprintf('Saved FWHM scar mask, initial region, and thresholds to:\n%s\n', ...
                    output_file);
                return;

            case 'Review Again'
                review_scar_mask_fwhm(dicoms_imgs, myocardium, scar_mask, ...
                    initial_region, fwhm_thresholds, scar_slices, gs_range, ...
                    seed_points, Imax_values, Imin_values);

            otherwise
                fprintf('FWHM scar mask was not saved.\n');
                return;
        end
    end
end

function review_scar_mask_fwhm( ...
        dicoms_imgs, myocardium, scar_mask, initial_region, ...
        fwhm_thresholds, scar_slices, gs_range, seed_points, ...
        Imax_values, Imin_values)

    figure_handle = figure('Name', 'Review FWHM scar mask', ...
        'NumberTitle', 'off');

    for n_slice = scar_slices
        if ~isvalid(figure_handle)
            disp('FWHM scar mask review window was closed.');
            return;
        end

        img_slice = dicoms_imgs(:, :, n_slice);
        myo_mask = myocardium(:, :, n_slice);
        initial_slice = initial_region(:, :, n_slice);
        scar_slice = scar_mask(:, :, n_slice);

        clf(figure_handle);
        ax = axes('Parent', figure_handle);
        imshow(img_slice, gs_range, 'Parent', ax); colormap(gca, gray); axis image;
        hold(ax, 'on');

        overlay_mask(ax, myo_mask, [0 1 0], 0.10);
        overlay_mask(ax, initial_slice, [1 1 0], 0.18);
        overlay_mask(ax, scar_slice, [1 0 0], 0.28);

        % Plot contours for myocardium (green), initial region (yellow), and scar (red)
        if any(myo_mask(:))
            contour(ax, myo_mask, [0.5 0.5], 'g', 'LineWidth', 1);
        end

        if any(initial_slice(:))
            contour(ax, initial_slice, [0.5 0.5], 'y', 'LineWidth', 1);
        end

        if any(scar_slice(:))
            contour(ax, scar_slice, [0.5 0.5], 'r', 'LineWidth', 1.5);
        end

        if all(isfinite(seed_points(n_slice, :)))
            plot(ax, seed_points(n_slice, 1), seed_points(n_slice, 2), ...
                'y+', 'LineWidth', 1.5, 'MarkerSize', 10);
        end

        if isnan(fwhm_thresholds(n_slice))
            title(ax, sprintf('Slice %d: no scar seed', n_slice));
        else
            title(ax, sprintf('Slice %d: Imin = %.3f, Imax = %.3f, threshold = %.3f', ...
                n_slice, Imin_values(n_slice), Imax_values(n_slice), ...
                fwhm_thresholds(n_slice)));
        end
        drawnow;
        pause(2);
    end
end

function overlay_mask(ax, mask, color, alpha)
    if ~any(mask(:))
        return;
    end

    overlay = zeros([size(mask), 3]);
    overlay(:, :, 1) = color(1);
    overlay(:, :, 2) = color(2);
    overlay(:, :, 3) = color(3);

    image(ax, overlay, 'AlphaData', alpha * double(mask), ...
        'HitTest', 'off');
end
