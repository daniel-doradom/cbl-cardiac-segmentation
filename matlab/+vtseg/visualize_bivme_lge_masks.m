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

[files, images, masks, names, colors, slice_metadata] = vtseg.load_review_case(main_path);
slice_count = numel(files);
[row_range, column_range] = vtseg.define_review_crop(main_path, gs_range, images, masks, colors);

% Same layout as the mask correction window: header bar, image on the left
% with its slice slider underneath, settings / legend / slice info on the right.
fig = vtseg.ReviewStyle.newFigure('Mask review: slices', ...
    'Units', 'normalized', 'Position', [0.06 0.08 0.88 0.84], ...
    'KeyPressFcn', @on_key, 'CloseRequestFcn', @finish_review);
ax = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.02 0.10 0.70 0.79]);

header = vtseg.ReviewStyle.section(fig, [0.015 0.915 0.970 0.070], '');
slice_text = vtseg.ReviewStyle.label(header, [0.010 0.15 0.220 0.70], '', 'left', false);
vtseg.ReviewStyle.label(header, [0.240 0.15 0.480 0.70], ...
    'Drag the slider under the image, or use the arrow keys, to move through the slices', ...
    'left', true);
vtseg.ReviewStyle.button(header, [0.745 0.15 0.245 0.70], 'Continue to correction', ...
    @finish_review, 'primary');

slice_slider = vtseg.ReviewStyle.slider(fig, [0.02 0.03 0.70 0.045], 1, slice_count, 1, ...
    slider_steps(slice_count), @on_slice_change);

display_panel = vtseg.ReviewStyle.section(fig, [0.735 0.560 0.250 0.340], 'Display');
fill_toggle = vtseg.ReviewStyle.toggle(display_panel, [0.05 0.80 0.90 0.15], ...
    'Mask fill', 1, @refresh_view);
vtseg.ReviewStyle.label(display_panel, [0.05 0.64 0.55 0.10], 'Fill opacity', 'left', false);
opacity_value = vtseg.ReviewStyle.label(display_panel, [0.60 0.64 0.35 0.10], '', 'right', true);
opacity_slider = vtseg.ReviewStyle.slider(display_panel, [0.05 0.53 0.90 0.10], 0, 1, 0.35, ...
    [0.02 0.10], @refresh_view);
vtseg.ReviewStyle.label(display_panel, [0.05 0.38 0.55 0.10], 'Contour width', 'left', false);
contour_value = vtseg.ReviewStyle.label(display_panel, [0.60 0.38 0.35 0.10], '', 'right', true);
contour_width_slider = vtseg.ReviewStyle.slider(display_panel, [0.05 0.27 0.90 0.10], 0.1, 4, 1.4, ...
    [0.05 / 3.9 0.5 / 3.9], @refresh_view);
contour_toggle = vtseg.ReviewStyle.toggle(display_panel, [0.05 0.06 0.90 0.15], ...
    'Show contours', 1, @refresh_view);

legend_panel = vtseg.ReviewStyle.section(fig, [0.735 0.330 0.250 0.210], 'Contours');
for index = 1:numel(names)
    row_y = 0.90 - index * 0.16 - (index - 1) * 0.05;
    uicontrol(legend_panel, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.07, row_y + 0.02, 0.10, 0.12], 'String', '', ...
        'BackgroundColor', colors(index, :));
    vtseg.ReviewStyle.label(legend_panel, [0.22 row_y 0.74 0.16], names{index}, 'left', false);
end

slice_panel = vtseg.ReviewStyle.section(fig, [0.735 0.030 0.250 0.280], 'Slice');
source_text = vtseg.ReviewStyle.label(slice_panel, [0.05 0.06 0.90 0.88], '', 'left', true);

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

    function finish_review(~, ~)
        if isvalid(fig)
            uiresume(fig);
            delete(fig);
        end
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

        if get(contour_toggle, 'Value')
            for index = 1:numel(masks)
                current_mask = masks{index}(row_range, column_range, slice);
                if any(current_mask(:)) && any(~current_mask(:))
                    contour(ax, current_mask, [0.5 0.5], ...
                        'Color', colors(index, :), ...
                        'LineWidth', get(contour_width_slider, 'Value'));
                end
            end
        end
        axis(ax, 'image');
        axis(ax, 'off');
        vtseg.ReviewStyle.axesTitle(ax, sprintf('Base-to-apex MATLAB slice %d of %d', slice, slice_count));
        set(slice_text, 'String', sprintf('Slice %d / %d', slice, slice_count));
        set(opacity_value, 'String', sprintf('%.2f', get(opacity_slider, 'Value')));
        if get(contour_toggle, 'Value')
            set(contour_value, 'String', sprintf('%.2f', get(contour_width_slider, 'Value')));
        else
            set(contour_value, 'String', 'hidden');
        end
        current = slice_metadata(slice);
        set(source_text, 'String', sprintf( ...
            'MATLAB mask: %d / %d\nRaw DICOM: %s\nBase-to-apex source: %s\nReference z-index: %s', ...
            slice, slice_count, current.dicom_file, current.base_to_apex_slice, ...
            current.reference_index));
        hold(ax, 'off');
        drawnow;
    end
end

function steps = slider_steps(slice_count)
if slice_count <= 1
    steps = [1 1];
else
    steps = [1 / (slice_count - 1), min(10 / (slice_count - 1), 1)];
end
end
