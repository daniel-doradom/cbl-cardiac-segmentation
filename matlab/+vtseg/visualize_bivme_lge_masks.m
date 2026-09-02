function fig = visualize_bivme_lge_masks(main_path, gs_range)
%VISUALIZE_BIVME_LGE_MASKS Interactive review of exported biv-me/LGE masks.
%
% The raw/ directory must contain the DICOM subset written by vtseg and seg/
% must contain Lendo.mat, Rendo.mat, Epi.mat, and myocardium.mat.  The viewer
% keeps contours visible at all times; the Fill toggle and opacity slider only
% control the colored interior overlay.

if nargin < 2 || isempty(gs_range)
    gs_range = [];
end

raw_path = fullfile(main_path, 'raw');
seg_path = fullfile(main_path, 'seg');
files = dir(fullfile(raw_path, '*.dcm'));
if isempty(files)
    error('No DICOM files found in %s.', raw_path);
end

Lendo = load_required_mask(seg_path, 'Lendo');
Rendo = load_required_mask(seg_path, 'Rendo');
Epi = load_required_mask(seg_path, 'Epi');
myocardium = load_required_mask(seg_path, 'myocardium');
masks = {logical(Lendo), logical(Rendo), logical(Epi), logical(myocardium)};
names = {'LV blood pool', 'RV blood pool', 'Epicardium', 'Myocardium'};
colors = [0.80 0.20 0.20; 0.20 0.70 0.95; 0.20 0.85 0.35; 1.00 0.75 0.10];

slice_count = numel(files);
slice_metadata = load_slice_metadata(seg_path, files, slice_count);
for index = 1:numel(masks)
    if ndims(masks{index}) ~= 3 || size(masks{index}, 3) ~= slice_count
        error('%s stack does not match the raw DICOM slice count.', names{index});
    end
end

first_image = dicomread(fullfile(raw_path, files(1).name));
images = zeros([size(first_image), slice_count], 'like', first_image);
images(:, :, 1) = first_image;
for index = 2:slice_count
    current_image = dicomread(fullfile(raw_path, files(index).name));
    if ~isequal(size(current_image), size(first_image))
        error('DICOM image dimensions are inconsistent in raw/.');
    end
    images(:, :, index) = current_image;
end

[row_range, column_range] = select_display_crop(images, masks, colors, gs_range);
write_display_crop(seg_path, row_range, column_range, size(images));

fig = figure('Name', 'biv-me LGE mask review', 'NumberTitle', 'off', ...
    'Color', 'w', 'Units', 'normalized', 'Position', [0.12 0.12 0.76 0.76], ...
    'KeyPressFcn', @on_key);
ax = axes('Parent', fig, 'Position', [0.06 0.16 0.70 0.78]);
slice_slider = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.06 0.07 0.70 0.04], 'Min', 1, 'Max', slice_count, 'Value', 1, ...
    'SliderStep', slider_steps(slice_count), 'Callback', @on_slice_change);
slice_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.06 0.11 0.70 0.035], 'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'center');
fill_toggle = uicontrol(fig, 'Style', 'togglebutton', 'Units', 'normalized', ...
    'Position', [0.80 0.77 0.15 0.06], 'String', 'Mask fill', 'Value', 1, ...
    'Callback', @refresh_view);
uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.80 0.67 0.15 0.04], 'String', 'Fill opacity', ...
    'BackgroundColor', 'w');
opacity_slider = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
    'Position', [0.80 0.62 0.15 0.04], 'Min', 0, 'Max', 1, 'Value', 0.35, ...
    'SliderStep', [0.02 0.10], 'Callback', @refresh_view);
legend_text = sprintf('%s\n%s\n%s\n%s', names{1}, names{2}, names{3}, names{4});
uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.80 0.38 0.15 0.20], 'String', legend_text, ...
    'ForegroundColor', [0.15 0.15 0.15], 'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'left');
source_text = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.78 0.12 0.20 0.20], 'BackgroundColor', 'w', ...
    'HorizontalAlignment', 'left');

refresh_view();

    function on_slice_change(~, ~)
        set(slice_slider, 'Value', round(get(slice_slider, 'Value')));
        refresh_view();
    end

    function on_key(~, event)
        current = round(get(slice_slider, 'Value'));
        if strcmp(event.Key, 'rightarrow') || strcmp(event.Key, 'downarrow')
            set(slice_slider, 'Value', min(slice_count, current + 1));
        elseif strcmp(event.Key, 'leftarrow') || strcmp(event.Key, 'uparrow')
            set(slice_slider, 'Value', max(1, current - 1));
        else
            return;
        end
        refresh_view();
    end

    function refresh_view(~, ~)
        slice = round(get(slice_slider, 'Value'));
        set(slice_slider, 'Value', slice);
        cla(ax);
        image_slice = images(row_range, column_range, slice);
        imshow(image_slice, gs_range, 'Parent', ax);
        colormap(ax, gray(256));
        hold(ax, 'on');

        fill_image = zeros([size(image_slice, 1), size(image_slice, 2), 3]);
        fill_mask = false(size(image_slice, 1), size(image_slice, 2));
        % Draw outer structures first so cavities remain visible above them.
        for index = [3 4 1 2]
            current_mask = masks{index}(row_range, column_range, slice);
            for channel = 1:3
                plane = fill_image(:, :, channel);
                plane(current_mask) = colors(index, channel);
                fill_image(:, :, channel) = plane;
            end
            fill_mask = fill_mask | current_mask;
        end
        % Explicit Parent/CData syntax works across MATLAB graphics versions;
        % image(ax, data) is parsed as indexed image data in some releases.
        fill_handle = image('Parent', ax, 'CData', fill_image, ...
            'XData', [1 size(fill_image, 2)], 'YData', [1 size(fill_image, 1)]);
        if get(fill_toggle, 'Value')
            set(fill_handle, 'AlphaData', get(opacity_slider, 'Value') * double(fill_mask), ...
                'AlphaDataMapping', 'none');
        else
            set(fill_handle, 'AlphaData', zeros(size(fill_mask)), 'AlphaDataMapping', 'none');
        end

        for index = 1:numel(masks)
            current_mask = masks{index}(row_range, column_range, slice);
            if any(current_mask(:)) && any(~current_mask(:))
                contour(ax, current_mask, [0.5 0.5], ...
                    'Color', colors(index, :), 'LineWidth', 1.4);
            end
        end
        axis(ax, 'image');
        axis(ax, 'off');
        title(ax, sprintf('Base-to-apex MATLAB slice %d of %d', slice, slice_count));
        set(slice_text, 'String', sprintf('Slice %d / %d', slice, slice_count));
        current = slice_metadata(slice);
        set(source_text, 'String', sprintf( ...
            'MATLAB mask: %d / %d\nRaw DICOM: %s\nBase-to-apex source: %s\nReference z-index: %s', ...
            slice, slice_count, current.dicom_file, current.base_to_apex_slice, ...
            current.reference_index));
        hold(ax, 'off');
        drawnow;
    end
end

function [row_range, column_range] = select_display_crop(images, masks, colors, gs_range)
%SELECT_DISPLAY_CROP Define one display-only crop shared by every review slice.
epicardium = masks{3};
areas = squeeze(sum(sum(epicardium, 1), 2));
[~, reference_slice] = max(areas);

height = size(images, 1);
width = size(images, 2);
row_range = 1:height;
column_range = 1:width;

selection_figure = figure('Name', 'Define review crop', 'NumberTitle', 'off', ...
    'Color', 'w');
selection_axes = axes('Parent', selection_figure);
imshow(images(:, :, reference_slice), gs_range, 'Parent', selection_axes);
colormap(selection_axes, gray(256));
hold(selection_axes, 'on');
for index = 1:numel(masks)
    current_mask = masks{index}(:, :, reference_slice);
    if any(current_mask(:)) && any(~current_mask(:))
        contour(selection_axes, current_mask, [0.5 0.5], ...
            'Color', colors(index, :), 'LineWidth', 1.4);
    end
end
title(selection_axes, sprintf(['Draw the review crop on slice %d, then double-click inside it. ' ...
    'The crop affects display only.'], reference_slice));

roi = drawrectangle(selection_axes, 'Color', [1.00 0.75 0.10], 'LineWidth', 1.4);
wait(roi);
if isvalid(roi) && ~isempty(roi.Position)
    position = round(roi.Position);
    first_column = max(1, position(1));
    first_row = max(1, position(2));
    last_column = min(width, first_column + max(1, position(3)) - 1);
    last_row = min(height, first_row + max(1, position(4)) - 1);
    column_range = first_column:last_column;
    row_range = first_row:last_row;
end
if isvalid(selection_figure)
    close(selection_figure);
end
end

function write_display_crop(seg_path, row_range, column_range, image_size)
crop = struct( ...
    'schema_version', 1, ...
    'row_start', row_range(1), ...
    'row_end', row_range(end), ...
    'column_start', column_range(1), ...
    'column_end', column_range(end), ...
    'image_height', image_size(1), ...
    'image_width', image_size(2));
fid = fopen(fullfile(seg_path, 'review_display_crop.json'), 'w');
if fid < 0
    warning('vtseg:DisplayCropNotSaved', 'Unable to save the display crop for downstream review plots.');
    return;
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(crop));
end

function metadata = load_slice_metadata(seg_path, files, slice_count)
metadata = repmat(struct('dicom_file', '', 'base_to_apex_slice', 'not recorded', ...
    'reference_index', 'not recorded'), slice_count, 1);
for index = 1:slice_count
    metadata(index).dicom_file = files(index).name;
end

manifest_path = fullfile(seg_path, 'bivme_export_manifest.json');
if ~isfile(manifest_path)
    return;
end
manifest = jsondecode(fileread(manifest_path));
if ~isfield(manifest, 'slices') || numel(manifest.slices) ~= slice_count
    return;
end
for index = 1:slice_count
    entry = manifest.slices(index);
    if isfield(entry, 'dicom_file')
        metadata(index).dicom_file = entry.dicom_file;
    end
    if isfield(entry, 'base_to_apex_reference_slice')
        metadata(index).base_to_apex_slice = num2str(entry.base_to_apex_reference_slice);
    end
    if isfield(entry, 'reference_volume_index')
        metadata(index).reference_index = num2str(entry.reference_volume_index);
    end
end
end

function value = load_required_mask(seg_path, variable_name)
path = fullfile(seg_path, [variable_name '.mat']);
if ~isfile(path)
    error('Missing mask file: %s', path);
end
loaded = load(path, variable_name);
if ~isfield(loaded, variable_name)
    error('Mask file does not contain %s.', variable_name);
end
value = loaded.(variable_name);
end

function steps = slider_steps(slice_count)
if slice_count <= 1
    steps = [1 1];
else
    steps = [1 / (slice_count - 1), min(10 / (slice_count - 1), 1)];
end
end
