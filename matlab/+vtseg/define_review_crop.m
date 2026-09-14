function [row_range, column_range] = define_review_crop(main_path, gs_range, images, masks, colors)
%DEFINE_REVIEW_CROP Draw the one display crop shared by every review window.
%
% Shows the slice with the largest epicardium and lets the reviewer draw one
% rectangle; double-click inside it to confirm. The crop is display only. It
% is written to seg/review_display_crop.json, which the mask correction
% window and the final overview figures read. Pass images, masks and colors
% when the case is already loaded (as the slice viewer does); otherwise they
% are read with load_review_case.

if nargin < 2 || isempty(gs_range)
    gs_range = [];
end
if nargin < 5
    [~, images, masks, ~, colors] = vtseg.load_review_case(main_path);
end
seg_path = fullfile(main_path, 'seg');
[row_range, column_range] = select_display_crop(images, masks, colors, gs_range);
write_display_crop(seg_path, row_range, column_range, size(images));
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

selection_figure = vtseg.ReviewStyle.newFigure('Mask review: define crop', ...
    'Units', 'normalized', 'Position', [0.15 0.12 0.70 0.78]);
selection_axes = axes('Parent', selection_figure, 'Units', 'normalized', ...
    'Position', [0.03 0.03 0.94 0.87]);
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
vtseg.ReviewStyle.axesTitle(selection_axes, sprintf(['Draw the review crop on slice %d, ' ...
    'then double-click inside it. The crop affects display only.'], reference_slice));

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
