function ventriclesSegmentation_v2(path_image,path_out, gs_range)% manual segmentation of ventricles
vtseg.assert_editable_matlab_path(path_out);
  % gs_range = [-100 2529]; %%% brightness range for showing MRI images
    % gs_range = [400 2200];
%     gs_range = [100 400];

    % gs_range = [0 100];

    % gs_range = [0 300];

% reading images and segmenting them
folder=dir(strcat(path_image,'*.dcm'));
tot_img_num=length(folder);

required_mask_files = { ...
    fullfile(path_out, 'Epi.mat'), ...
    fullfile(path_out, 'Lendo.mat'), ...
    fullfile(path_out, 'Rendo.mat'), ...
    fullfile(path_out, 'myocardium.mat')};
use_existing_masks = all(cellfun(@isfile, required_mask_files));

if use_existing_masks
    fprintf('Existing masks found. Loading masks and going directly to review/correction.\n');
    load(fullfile(path_out, 'Epi.mat'), 'Epi');
    load(fullfile(path_out, 'Lendo.mat'), 'Lendo');
    load(fullfile(path_out, 'Rendo.mat'), 'Rendo');

    if ~isequal(size(Epi), size(Lendo), size(Rendo))
        error('Existing Epi, Lendo, and Rendo masks must have the same size.');
    end

    lstr = 'n';
    if isfile(fullfile(path_out, 'lepi.mat'))
        load(fullfile(path_out, 'lepi.mat'), 'lepi');
        if ~isequal(size(lepi), size(Epi))
            error('Existing lepi mask must have the same size as Epi.');
        end
        lstr = 'y';
    end

    count = size(Epi, 3) + 1;
else
    prompt = 'Do you want to segment left ventricle epicardium(required only for  17 segments) (y/n)?   >> ';
    lstr = input(prompt, 's');
    if isempty(lstr)
        lstr='n';
    end

    count = 1;
end

if ~use_existing_masks
for file = folder'
    if ~file.isdir
        disp(['Segmenting',' ', file.name])
        f = strcat(path_image,file.name);
        f_info = dicominfo(f);
        Im = vtseg.read_dicom_image(f_info);
        [imgH,imgW,imgD] = size(Im);


        clf;
        h_img = imshow(Im,gs_range);
        xlabel(num2str(count));
        Img=double(Im(:,:,1));
        N = imgH*imgW;


        %%%segmenting left ventricle
        prompt = 'Left ventricle endocardium (y/n)?   >> ';
        str = input(prompt, 's');
        if isempty(str)
            str = 'y';
        end


        if strcmp(str, 'quit')
            Lendo(:,:,count) = zeros(size(Im));
            Rendo(:,:,count) = zeros(size(Im));
            Epi(:,:,count)   = zeros(size(Im));
            if lower(lstr) =='y'
                Epi(:,:,count)   = zeros(size(Im));
            end
            if count == 1
                disp('No segmentation done.');
            else
                disp(['Last Segmentation at', ' ', folder(count-1,:).name])
            end
            break;
        end


        if lower(str) == 'y'
            hold on;
            [BW1,~,~]=draw_polygon_mask(gca, h_img, 'r');
            Obj=double(BW1)*100;


            %--------------------


            %-------------------
            contour(BW1,[0.5 0.5],'r','LineWidth',1);
            Lendo(:,:,count) = Obj;


        else
            Lendo(:,:,count) = zeros(size(Im));
        end % segmenting left ventricle end


        %%%%segmenting right ventricle


        prompt = 'Right ventricle endocardium(y/n)?  >> ';
        str = input(prompt, 's');
        if isempty(str)
            str = 'y';
        end
        if strcmp(str, 'quit')
            Lendo(:,:,count) = zeros(size(Im));
            Rendo(:,:,count) = zeros(size(Im));
            Epi(:,:,count)   = zeros(size(Im));
            if lower(lstr) =='y'
                lepi(:,:,count)   = zeros(size(Im));
            end
            if count == 1
                disp('No segmentation done.');
            else
                disp(['Last Segmentation at', ' ', folder(count-1,:).name])
            end
            break;
        end
         if lower(str) == 'y'
            hold on;
%             %----------------------------
%             % to segment the RVOT
%             prompt = 'RVOT(y/n)?>>';
%             strr = input(prompt,'s');
%             if strcmp(strr,'y')
%                 disp('Start Segmenting The RVOT');
%                 [BW1,xj,yj]=roipoly;
%                 plot(xj,yj,'r.-','Linewidth',1);
%

%                 disp('Start Segmenting The RV');
%                 [BW2,xj2,yj2]=roipoly;
%                 BW1 = BW1 | BW2;
%                 xj = [xj;xj2];
%                 yj = [yj;yj2];
%             else
%                 disp('Start Segmenting The RV');
%                 [BW1,xj,yj]=roipoly;
%             end
%

%             %----------------------------------
 %----------------------------
            % to segment the RVOT
            a =0;
            prompt = 'RVOT(y/n)?>>';
            strr = input(prompt,'s');
            if strcmp(strr,'y')
                disp('Start Segmenting The RVOT');
                [BW1,xj,yj]=draw_polygon_mask(gca, h_img, 'c');
                a = 1;
            end

            b=0;
                prompt = 'RV(y/n)?>>';
            strr1 = input(prompt,'s');
            if strcmp(strr1,'y')
                disp('Start Segmenting The RV');
                [BW2,xj2,yj2]=draw_polygon_mask(gca, h_img, 'c');
                b=1;
            end
            if (a == 1 && b==1)

                BW1 = BW1 | BW2;
                xj = [xj;xj2];
                yj = [yj;yj2];
            elseif (b==1 && a ==0)
                 BW1 =  BW2;
                xj = xj2;
                yj = yj2;


%                 [BW1,xj,yj]=roipoly;
            end




            %----------------------------------
%            [BW1,xj,yj]=roipoly;
            if (a == 1 || b == 1)
                Obj=double(BW1)*100;
                contour(BW1,[0.5 0.5],'c','LineWidth',1);
                Rendo(:,:,count) = Obj;
            else
                Rendo(:,:,count) = zeros(size(Im));
            end
        else
            Rendo(:,:,count) = zeros(size(Im));
        end % segmentaing left ventricle end



        %%%%segmenting epicardium
        prompt = 'Epicardium (y/n)?  >> ';
        str = input(prompt, 's');
        if isempty(str)
            str = 'y';
        end
        if strcmp(str, 'quit')
            Lendo(:,:,count) = zeros(size(Im));
            Rendo(:,:,count) = zeros(size(Im));
            Epi(:,:,count)   = zeros(size(Im));
            if lower(lstr) =='y'
                Epi(:,:,count)   = zeros(size(Im));
            end
            if count == 1
                disp('No segmentation done.');
            else
                disp(['Last Segmentation at', ' ', folder(count-1,:).name])
            end
            break;
        end
        if lower(str) == 'y'
            hold on;
            [BW1,~,~]=draw_polygon_mask(gca, h_img, 'g');
            Obj=double(BW1)*100;
            contour(BW1,[0.5 0.5],'g','LineWidth',1);
            Epi(:,:,count) = Obj;
        else
            Epi(:,:,count) = zeros(size(Im));
        end
        %end segmenting epicardium


        %%% segmenting left ventricle epicardium (for 17 segmnet only)
        if lower(lstr) =='y'
            prompt = 'Left Ventricle Epicardium (for 17 segment only)(y/n)?  >> ';
            str = input(prompt, 's');
            if isempty(str)
                str = 'y';
            end


            if lower(str) == 'y'
                hold on;
                [BW1,~,~]=draw_polygon_mask(gca, h_img, 'b');
                Obj=double(BW1)*100;
                contour(BW1,[0.5 0.5],'b','LineWidth',1);
                lepi(:,:,count) = Obj;
            else
                lepi(:,:,count) = zeros(size(Im));
            end
        end
        % segmentaing epicardium end
        count = count + 1;
        disp(['Completed segmenting ',int2str(count)-1,' out of ',int2str(tot_img_num),' images!']);
        disp('----------');
    end
end
end

last_segmented_slice = count - 1;
save_confirmed = false;
component_actions = empty_component_actions();

if last_segmented_slice > numel(folder)
    error('Mask stack has %d slices, but only %d DICOM files were found for review.', ...
        last_segmented_slice, numel(folder));
end

if last_segmented_slice > 0
    display_crop = load_display_crop(path_out, size(Epi, 1), size(Epi, 2));
    if lower(lstr) == 'y'
        [Lendo, Rendo, Epi, lepi, save_confirmed, component_actions] = review_and_correct_masks( ...
            path_image, folder, last_segmented_slice, gs_range, ...
            Lendo, Rendo, Epi, lepi, true, display_crop);
    else
        [Lendo, Rendo, Epi, ~, save_confirmed, component_actions] = review_and_correct_masks( ...
            path_image, folder, last_segmented_slice, gs_range, ...
            Lendo, Rendo, Epi, [], false, display_crop);
    end
else
    fprintf('No completed segmentations to save.\n');
    return;
end

if ~save_confirmed
    fprintf('Segmentation masks were not saved.\n');
    return;
end

save(strcat(path_out,'Lendo.mat'),'Lendo');
save(strcat(path_out,'Rendo.mat'),'Rendo');
save(strcat(path_out,'Epi.mat'),'Epi');
if lower(lstr) =='y'
    save(strcat(path_out,'lepi.mat'),'lepi');
end

% Myocardium mask
Epi   = logical(Epi); Lendo = logical(Lendo); Rendo = logical(Rendo);
myocardium = vtseg.recompute_myocardium(Lendo, Rendo, Epi);
save(fullfile(path_out, 'myocardium.mat'), 'myocardium');
vtseg.save_component_review_audit(path_out, component_actions);

plot_final_segmentation_overview( ...
    path_image, folder, last_segmented_slice, gs_range, ...
    Lendo, Rendo, Epi, path_out, display_crop);

end

function [BW, xj, yj] = draw_polygon_mask(ax, image_handle, color, line_width)
    if nargin < 4
        line_width = 1;
    end
    roi = drawpolygon(ax, 'Color', color, 'LineWidth', line_width, 'FaceAlpha', 0.25);
    wait(roi);

    if isempty(roi) || ~isvalid(roi) || isempty(roi.Position)
        BW = false(size(image_handle.CData));
        xj = [];
        yj = [];
        return;
    end

    BW = createMask(roi, image_handle);
    position = roi.Position;
    xj = [position(:, 1); position(1, 1)];
    yj = [position(:, 2); position(1, 2)];
end

function [Lendo, Rendo, Epi, lepi, save_confirmed, component_actions] = review_and_correct_masks( ...
        path_image, folder, last_segmented_slice, gs_range, ...
        Lendo, Rendo, Epi, lepi, has_lepi, display_crop)

    save_confirmed = false;
    component_actions = empty_component_actions();

    theme = vtseg.ReviewStyle.theme();
    layout = review_layout();
    figure_handle = vtseg.ReviewStyle.newFigure('Mask correction: review slices', ...
        'Units', 'normalized', 'Position', [0.06 0.08 0.88 0.84], ...
        'CloseRequestFcn', @quit_review);
    ax = axes('Parent', figure_handle, 'Units', 'normalized', ...
        'Position', layout.axes, 'Color', theme.figure, ...
        'XColor', theme.muted, 'YColor', theme.muted);

    reference_image = double(read_slice_image(path_image, folder(1).name));
    [window_limits, initial_window] = review_window_limits(reference_image, gs_range);
    window_center = min(window_limits(2), max(window_limits(1), mean(initial_window)));
    window_width = diff(initial_window);
    window_span = diff(window_limits);
    minimum_width = max(window_span / 1000, eps(window_span));

    % Side panel, top: display settings, each with its live value beside the label.
    display_panel = vtseg.ReviewStyle.section(figure_handle, layout.display, 'Display');
    vtseg.ReviewStyle.label(display_panel, [0.05 0.86 0.55 0.09], 'Window center', 'left', false);
    center_value = vtseg.ReviewStyle.label(display_panel, [0.60 0.86 0.35 0.09], '', 'right', true);
    center_slider = vtseg.ReviewStyle.slider(display_panel, [0.05 0.76 0.90 0.09], ...
        window_limits(1), window_limits(2), window_center, [0.01 0.10], ...
        @on_display_control_change);
    vtseg.ReviewStyle.label(display_panel, [0.05 0.62 0.55 0.09], 'Window width', 'left', false);
    width_value = vtseg.ReviewStyle.label(display_panel, [0.60 0.62 0.35 0.09], '', 'right', true);
    width_slider = vtseg.ReviewStyle.slider(display_panel, [0.05 0.52 0.90 0.09], ...
        minimum_width, window_span, max(minimum_width, min(window_span, window_width)), ...
        [0.01 0.10], @on_display_control_change);
    vtseg.ReviewStyle.label(display_panel, [0.05 0.38 0.55 0.09], 'Contour width', 'left', false);
    contour_value = vtseg.ReviewStyle.label(display_panel, [0.60 0.38 0.35 0.09], '', 'right', true);
    contour_width_slider = vtseg.ReviewStyle.slider(display_panel, [0.05 0.28 0.90 0.09], ...
        0.1, 4, 1.5, [0.05 / 3.9 0.5 / 3.9], @on_display_control_change);
    contour_toggle = vtseg.ReviewStyle.toggle(display_panel, [0.05 0.06 0.90 0.14], ...
        'Show contours', 1, @on_display_control_change);
    setappdata(figure_handle, 'vtsegReviewDisplayControls', struct( ...
        'center_slider', center_slider, 'width_slider', width_slider, ...
        'contour_width_slider', contour_width_slider, 'contour_toggle', contour_toggle, ...
        'center_value', center_value, 'width_value', width_value, ...
        'contour_value', contour_value));
    update_display_control_text();

    % Side panel, middle: which colour is which structure.
    legend_panel = vtseg.ReviewStyle.section(figure_handle, layout.legend, 'Contours');
    review_legend(legend_panel, has_lepi);

    % Side panel, bottom: left empty. Action prompts and the contour-edit
    % buttons appear there, so the window never rearranges while working.

    % Header: navigation on the left, slice jump in the middle, session actions on the right.
    header = vtseg.ReviewStyle.section(figure_handle, layout.header, '');
    previous_button = vtseg.ReviewStyle.button(header, [0.010 0.15 0.095 0.70], 'Previous', ...
        @(~, ~) choose_navigation('previous'), 'neutral');
    next_button = vtseg.ReviewStyle.button(header, [0.112 0.15 0.115 0.70], 'Keep / Next', ...
        @(~, ~) choose_navigation('next'), 'primary');
    correct_button = vtseg.ReviewStyle.button(header, [0.234 0.15 0.095 0.70], 'Modify', ...
        @(~, ~) choose_navigation('modify'), 'neutral');
    vtseg.ReviewStyle.label(header, [0.400 0.15 0.085 0.70], 'Go to slice', 'right', true);
    slice_field = vtseg.ReviewStyle.field(header, [0.492 0.18 0.050 0.64], '1', ...
        @(~, ~) choose_navigation('jump'));
    jump_button = vtseg.ReviewStyle.button(header, [0.548 0.15 0.050 0.70], 'Go', ...
        @(~, ~) choose_navigation('jump'), 'neutral');
    finish_button = vtseg.ReviewStyle.button(header, [0.745 0.15 0.115 0.70], 'Finish review', ...
        @(~, ~) choose_navigation('finish'), 'neutral');
    quit_button = vtseg.ReviewStyle.button(header, [0.868 0.15 0.122 0.70], 'Quit without saving', ...
        @(~, ~) choose_navigation('quit'), 'danger');
    navigation_controls = [previous_button, next_button, correct_button, ...
        slice_field, jump_button, finish_button, quit_button];

    k = 1;

    while k <= last_segmented_slice
        if ~isvalid(figure_handle)
            disp('Review window was closed. Masks will not be saved.');
            return;
        end

        [display_image, ~] = show_slice_with_masks( ...
            ax, path_image, folder(k).name, gs_range, k, ...
            Lendo, Rendo, Epi, lepi, has_lepi, display_crop);

        set(slice_field, 'String', num2str(k));
        setappdata(figure_handle, 'vtsegReviewNavigationAction', '');
        uiwait(figure_handle);
        if ~isvalid(figure_handle)
            disp('Review window was closed. Masks will not be saved.');
            return;
        end
        action = getappdata(figure_handle, 'vtsegReviewNavigationAction');

        if strcmp(action, 'previous')
            k = max(1, k - 1);
            continue;
        end

        if strcmp(action, 'next')
            k = k + 1;
            continue;
        end

        if strcmp(action, 'jump')
            target_slice = str2double(get(slice_field, 'String'));
            if ~isnan(target_slice)
                target_slice = round(target_slice);
            end
            if isnan(target_slice) || target_slice < 1 || target_slice > last_segmented_slice
                errordlg(sprintf('Slice must be between 1 and %d.', last_segmented_slice), ...
                    'Invalid slice');
            else
                k = target_slice;
            end
            continue;
        end

        if strcmp(action, 'quit')
            disp('Review was quit before final confirmation. Masks will not be saved.');
            return;
        end

        if strcmp(action, 'finish')
            set(navigation_controls, 'Enable', 'off');
            save_confirmed = confirm_review_save();
            return;
        end

        if strcmp(action, 'modify')
            pixel_spacing = editable_pixel_spacing(path_image, folder(k).name);
            old_Lendo = Lendo(:, :, k);
            old_Rendo = Rendo(:, :, k);
            old_Epi = Epi(:, :, k);
            old_lepi = [];
            if has_lepi
                old_lepi = lepi(:, :, k);
            end

            candidate_Lendo = Lendo;
            candidate_Rendo = Rendo;
            candidate_Epi = Epi;
            candidate_lepi = lepi;
            candidate_component_actions = empty_component_actions();
            correction_valid = false;
            set(navigation_controls, 'Enable', 'off');

            while ~correction_valid
                [candidate_Lendo, candidate_Rendo, candidate_Epi, candidate_lepi, new_component_actions] = ...
                    correct_slice_masks( ...
                        ax, display_image, k, candidate_Lendo, candidate_Rendo, ...
                        candidate_Epi, candidate_lepi, has_lepi, display_crop, gs_range, ...
                        pixel_spacing, folder(k).name);
                candidate_component_actions = append_component_actions( ...
                    candidate_component_actions, new_component_actions);

                if ~isvalid(figure_handle)
                    disp('Review window was closed. Masks will not be saved.');
                    return;
                end

                validation_errors = validate_slice_masks( ...
                    candidate_Lendo(:, :, k), candidate_Rendo(:, :, k), ...
                    candidate_Epi(:, :, k));
                if isempty(validation_errors)
                    correction_valid = true;
                else
                    fprintf('The corrected masks cannot be accepted:\n');
                    for error_index = 1:numel(validation_errors)
                        fprintf('  - %s\n', validation_errors{error_index});
                    end
                    invalid_action = choose_review_action(figure_handle, ...
                        'Invalid correction', {'Revise', 'revise'; 'Discard edits', 'discard'});
                    if ~isvalid(figure_handle)
                        return;
                    end
                    if ~strcmp(invalid_action, 'revise')
                        candidate_Lendo(:, :, k) = old_Lendo;
                        candidate_Rendo(:, :, k) = old_Rendo;
                        candidate_Epi(:, :, k) = old_Epi;
                        if has_lepi
                            candidate_lepi(:, :, k) = old_lepi;
                        end
                        candidate_component_actions = empty_component_actions();
                        correction_valid = true;
                    end
                end
            end

            Lendo = candidate_Lendo;
            Rendo = candidate_Rendo;
            Epi = candidate_Epi;
            lepi = candidate_lepi;

            show_slice_with_masks( ...
                ax, path_image, folder(k).name, gs_range, k, ...
                Lendo, Rendo, Epi, lepi, has_lepi, display_crop);
            keep_str = 'compare';
            while strcmp(keep_str, 'compare')
                keep_str = choose_review_action(figure_handle, ...
                    'Keep these modifications?', ...
                    {'Keep changes', 'keep'; 'Compare before/after', 'compare'; ...
                     'Discard changes', 'discard'});
                if strcmp(keep_str, 'compare')
                    new_lepi = [];
                    if has_lepi
                        new_lepi = candidate_lepi(:, :, k);
                    end
                    show_before_after_comparison( ...
                        ax, display_image, folder(k).name, k, ...
                        old_Lendo, old_Rendo, old_Epi, old_lepi, ...
                        candidate_Lendo(:, :, k), candidate_Rendo(:, :, k), ...
                        candidate_Epi(:, :, k), new_lepi, ...
                        has_lepi, display_crop, gs_range);
                end
            end
            if ~isvalid(figure_handle)
                return;
            end
            set(navigation_controls, 'Enable', 'on');

            if strcmp(keep_str, 'keep')
                component_actions = append_component_actions( ...
                    component_actions, candidate_component_actions);
                k = k + 1;
            else
                Lendo(:, :, k) = old_Lendo;
                Rendo(:, :, k) = old_Rendo;
                Epi(:, :, k) = old_Epi;
                if has_lepi
                    lepi(:, :, k) = old_lepi;
                end
            end
        end
    end

    set(navigation_controls, 'Enable', 'off');
    save_confirmed = confirm_review_save();

    function choose_navigation(action)
        if isvalid(figure_handle)
            setappdata(figure_handle, 'vtsegReviewNavigationAction', action);
            uiresume(figure_handle);
        end
    end

    function quit_review(~, ~)
        if isvalid(figure_handle)
            setappdata(figure_handle, 'vtsegReviewNavigationAction', 'quit');
            uiresume(figure_handle);
            delete(figure_handle);
        end
    end

    function confirmed = confirm_review_save()
        response = choose_review_action(figure_handle, 'Finish review', ...
            {'Save reviewed masks', 'save'; 'Discard review', 'discard'});
        confirmed = strcmp(response, 'save');
    end

    function on_display_control_change(~, ~)
        [current_window, contour_width] = current_review_display_settings(ax, gs_range);
        image_handles = findobj(ax, 'Type', 'image');
        if ~isempty(image_handles)
            set(ax, 'CLim', current_window);
        end
        apply_review_contour_widths(figure_handle, ax);
        set_active_edit_roi_visibility(figure_handle, contour_width > 0);
        update_display_control_text();
        drawnow;
    end

    function update_display_control_text()
        [current_window, contour_width] = current_review_display_settings(ax, gs_range);
        set(center_value, 'String', sprintf('%.1f', mean(current_window)));
        set(width_value, 'String', sprintf('%.1f', diff(current_window)));
        if contour_width <= 0
            set(contour_value, 'String', 'hidden');
        else
            set(contour_value, 'String', sprintf('%.2f', contour_width));
        end
    end
end

function [Lendo, Rendo, Epi, lepi, component_actions] = correct_slice_masks( ...
        ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range, ...
        pixel_spacing, source_file)

    component_actions = empty_component_actions();

    current_mask = Lendo(display_crop.rows, display_crop.columns, k);
    [new_mask, did_update, replace_entire_slice, display_dirty, component_details] = correct_one_mask( ...
        ax, display_image, current_mask, 'LV endocardium', 'r', gs_range, pixel_spacing);
    component_actions = add_component_action( ...
        component_actions, component_details, k, source_file, 'Lendo');
    if did_update
        Lendo(:, :, k) = apply_mask_update( ...
            Lendo(:, :, k), new_mask, display_crop, replace_entire_slice);
    end
    if did_update || display_dirty
        show_current_correction_masks( ...
            ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range);
    end

    current_mask = Rendo(display_crop.rows, display_crop.columns, k);
    [new_mask, did_update, replace_entire_slice, display_dirty, component_details] = correct_one_mask( ...
        ax, display_image, current_mask, 'RV endocardium', 'c', gs_range, pixel_spacing);
    component_actions = add_component_action( ...
        component_actions, component_details, k, source_file, 'Rendo');
    if did_update
        Rendo(:, :, k) = apply_mask_update( ...
            Rendo(:, :, k), new_mask, display_crop, replace_entire_slice);
    end
    if did_update || display_dirty
        show_current_correction_masks( ...
            ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range);
    end

    current_mask = Epi(display_crop.rows, display_crop.columns, k);
    [new_mask, did_update, replace_entire_slice, display_dirty, component_details] = correct_one_mask( ...
        ax, display_image, current_mask, 'Epicardium', 'g', gs_range, pixel_spacing);
    component_actions = add_component_action( ...
        component_actions, component_details, k, source_file, 'Epi');
    if did_update
        Epi(:, :, k) = apply_mask_update( ...
            Epi(:, :, k), new_mask, display_crop, replace_entire_slice);
    end
    if did_update || display_dirty
        show_current_correction_masks( ...
            ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range);
    end

    if has_lepi
        current_mask = lepi(display_crop.rows, display_crop.columns, k);
        [new_mask, did_update, replace_entire_slice, display_dirty] = correct_one_mask( ...
            ax, display_image, current_mask, 'LV epicardium', 'b', gs_range, pixel_spacing);
        if did_update
            lepi(:, :, k) = apply_mask_update( ...
                lepi(:, :, k), new_mask, display_crop, replace_entire_slice);
        end
        if did_update || display_dirty
            show_current_correction_masks( ...
                ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range);
        end
    end
end

function show_current_correction_masks( ...
        ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range)
    [display_gs_range, contour_width] = current_review_display_settings(ax, gs_range);
    cla(ax);
    imshow(display_image, display_gs_range, 'Parent', ax);
    hold(ax, 'on');
    plot_mask_contour(ax, Lendo(display_crop.rows, display_crop.columns, k), 'r', contour_width);
    plot_mask_contour(ax, Rendo(display_crop.rows, display_crop.columns, k), 'c', contour_width);
    plot_mask_contour(ax, Epi(display_crop.rows, display_crop.columns, k), 'g', contour_width);
    if has_lepi
        plot_mask_contour(ax, lepi(display_crop.rows, display_crop.columns, k), 'b', contour_width);
    end
    vtseg.ReviewStyle.axesTitle(ax, sprintf('Slice %d correction preview', k));
    drawnow;
end

function actions = empty_component_actions()
actions = struct( ...
    'slice_number', {}, ...
    'source_dicom_filename', {}, ...
    'structure', {}, ...
    'original_component_count', {}, ...
    'action', {}, ...
    'removed_component_areas_pixels', {}, ...
    'removed_component_areas_mm2', {}, ...
    'timestamp', {}, ...
    'final_component_count', {});
end

function actions = add_component_action( ...
        actions, details, slice_number, source_file, structure)
if isempty(details)
    return;
end
record = struct( ...
    'slice_number', slice_number, ...
    'source_dicom_filename', source_file, ...
    'structure', structure, ...
    'original_component_count', details.OriginalComponentCount, ...
    'action', details.Action, ...
    'removed_component_areas_pixels', details.RemovedAreasPixels, ...
    'removed_component_areas_mm2', details.RemovedAreasMm2, ...
    'timestamp', component_timestamp(), ...
    'final_component_count', details.FinalComponentCount);
actions(end + 1) = record;
end

function combined = append_component_actions(existing, added)
if isempty(existing)
    combined = added;
elseif isempty(added)
    combined = existing;
else
    combined = [existing(:); added(:)];
end
end

function value = component_timestamp()
value = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
end

function [mask, did_update, replace_entire_slice, display_dirty, component_details] = correct_one_mask( ...
        ax, Im, current_mask, structure_name, color, gs_range, pixel_spacing)
%CORRECT_ONE_MASK Prompt for one structure. display_dirty is true when the
% chosen action replaced what the axes shows, so the caller must redraw the
% full slice even if the mask itself did not change (a cancelled edit).
    did_update = false;
    replace_entire_slice = false;
    display_dirty = false;
    component_details = [];
    mask = logical(current_mask);

    figure_handle = ancestor(ax, 'figure');
    emphasize_review_structure(figure_handle, ax, structure_name, color);
    action = choose_review_action(figure_handle, ...
        sprintf('%s action', structure_name), ...
        {'Keep', 'keep'; 'Edit', 'edit'; 'Components', 'components'; ...
         'Redraw', 'redraw'; 'Clear', 'clear'}, ...
        review_structure_text_color(color));
    restore_review_emphasis(figure_handle, ax);

    if strcmp(action, 'keep') || strcmp(action, 'cancel')
        return;
    end

    if strcmp(action, 'clear')
        mask = false(size(Im));
        did_update = true;
        replace_entire_slice = true;
        return;
    end

    if strcmp(action, 'edit')
        [mask, did_update] = edit_existing_mask( ...
            ax, Im, current_mask, color, gs_range, pixel_spacing);
        display_dirty = true;
        return;
    end

    if strcmp(action, 'components')
        [mask, did_update, component_details] = review_mask_components( ...
            ax, Im, current_mask, structure_name, color, gs_range, pixel_spacing);
        display_dirty = true;
        return;
    end

    if strcmp(action, 'redraw')
        mask = redraw_mask_components(ax, Im, color, gs_range);
        did_update = true;
        replace_entire_slice = true;
        display_dirty = true;
        return;
    end
end

function [mask, did_update, details] = review_mask_components( ...
        ax, Im, current_mask, structure_name, color, gs_range, pixel_spacing)
%REVIEW_MASK_COMPONENTS Stage and confirm removal of disconnected islands.
original_mask = logical(current_mask);
staged_mask = original_mask;
mask = original_mask;
did_update = false;
details = [];
selected_index = 1;
staged_action = 'keep_all';
component_connectivity = 4;
figure_handle = ancestor(ax, 'figure');
layout = review_layout();
theme = vtseg.ReviewStyle.theme();
panel = vtseg.ReviewStyle.section(figure_handle, layout.action_slot, ...
    sprintf('Components: %s', structure_name));
set(panel, 'FontSize', theme.font_size + 1, ...
    'ForegroundColor', review_structure_text_color(color));
connectivity_toggle = vtseg.ReviewStyle.toggle(panel, [0.05 0.85 0.90 0.09], ...
    'Connectivity: 4', 0, @toggle_connectivity);
status_label = vtseg.ReviewStyle.label(panel, [0.05 0.75 0.90 0.08], '', 'left', true);
vtseg.ReviewStyle.button(panel, [0.05 0.61 0.43 0.11], 'Previous', ...
    @(~, ~) move_selection(-1), 'neutral');
vtseg.ReviewStyle.button(panel, [0.52 0.61 0.43 0.11], 'Next', ...
    @(~, ~) move_selection(1), 'neutral');
vtseg.ReviewStyle.button(panel, [0.05 0.47 0.43 0.11], 'Keep largest', ...
    @(~, ~) stage_action('keep_largest'), 'neutral');
vtseg.ReviewStyle.button(panel, [0.52 0.47 0.43 0.11], 'Remove selected', ...
    @(~, ~) stage_action('remove_selected'), 'danger');
vtseg.ReviewStyle.button(panel, [0.05 0.33 0.43 0.11], 'Restore', ...
    @(~, ~) stage_action('restore'), 'neutral');
vtseg.ReviewStyle.button(panel, [0.52 0.33 0.43 0.11], 'Keep all', ...
    @(~, ~) stage_action('keep_all'), 'neutral');
vtseg.ReviewStyle.button(panel, [0.05 0.17 0.90 0.12], 'Apply', ...
    @(~, ~) finish_component_review('apply'), 'primary');
vtseg.ReviewStyle.button(panel, [0.05 0.04 0.90 0.09], 'Cancel', ...
    @(~, ~) finish_component_review('cancel'), 'neutral');

setappdata(figure_handle, 'vtsegComponentReviewAction', '');
redraw_components();
uiwait(figure_handle);
if ~isvalid(figure_handle)
    return;
end
action = getappdata(figure_handle, 'vtsegComponentReviewAction');
if isvalid(panel)
    delete(panel);
end
if ~strcmp(action, 'apply')
    return;
end

show_component_before_after( ...
    ax, Im, original_mask, staged_mask, structure_name, color, gs_range);
confirmation = choose_review_action(figure_handle, ...
    'Apply component cleanup?', ...
    {'Keep changes', 'keep'; 'Discard changes', 'discard'});
if ~strcmp(confirmation, 'keep')
    return;
end

mask = staged_mask;
did_update = ~isequal(mask, original_mask);
details = summarize_component_review( ...
    original_mask, staged_mask, staged_action, pixel_spacing, component_connectivity);

    function move_selection(offset)
        analysis = vtseg.analyze_mask_components( ...
            staged_mask, pixel_spacing, component_connectivity);
        if analysis.Count == 0
            selected_index = 0;
        else
            selected_index = mod(max(1, selected_index) - 1 + offset, analysis.Count) + 1;
        end
        redraw_components();
    end

    function select_component(index)
        selected_index = index;
        redraw_components();
    end

    function stage_action(action_name)
        analysis = vtseg.analyze_mask_components( ...
            staged_mask, pixel_spacing, component_connectivity);
        if strcmp(action_name, 'remove_selected') && analysis.Count == 0
            return;
        end
        [staged_mask, ~] = vtseg.stage_mask_component_action( ...
            original_mask, staged_mask, action_name, selected_index, ...
            pixel_spacing, component_connectivity);
        staged_action = action_name;
        updated = vtseg.analyze_mask_components( ...
            staged_mask, pixel_spacing, component_connectivity);
        if updated.Count == 0
            selected_index = 0;
        else
            selected_index = min(max(1, selected_index), updated.Count);
        end
        redraw_components();
    end

    function toggle_connectivity(~, ~)
        if get(connectivity_toggle, 'Value')
            component_connectivity = 8;
        else
            component_connectivity = 4;
        end
        set(connectivity_toggle, 'String', sprintf( ...
            'Connectivity: %d', component_connectivity));
        selected_index = 1;
        redraw_components();
    end

    function redraw_components()
        [display_gs_range, contour_width] = current_review_display_settings(ax, gs_range);
        cla(ax);
        imshow(Im, display_gs_range, 'Parent', ax);
        hold(ax, 'on');
        plot_component_boundaries(ax, original_mask, [0.45 0.48 0.53], ...
            max(0.5, contour_width), '--', []);
        analysis = vtseg.analyze_mask_components( ...
            staged_mask, pixel_spacing, component_connectivity);
        if analysis.Count == 0
            selected_index = 0;
            set(status_label, 'String', 'No foreground components remain.');
        else
            selected_index = min(max(1, selected_index), analysis.Count);
            for component_index = 1:analysis.Count
                component_color = [1.00 0.30 1.00];
                line_width = max(1.0, contour_width);
                if component_index == analysis.LargestIndex
                    component_color = [0.25 1.00 0.35];
                end
                if component_index == selected_index
                    component_color = [1.00 0.85 0.10];
                    line_width = max(2.5, 1.6 * max(1, contour_width));
                end
                component_mask = false(analysis.ImageSize);
                component_mask(analysis.PixelIdxList{component_index}) = true;
                plot_component_boundaries(ax, component_mask, component_color, ...
                    line_width, '-', component_index);
            end
            largest_text = '';
            if selected_index == analysis.LargestIndex
                largest_text = ' (largest)';
            end
            set(status_label, 'String', sprintf( ...
                '%d/%d%s | %d px | %.1f mm^2', selected_index, analysis.Count, ...
                largest_text, analysis.AreasPixels(selected_index), ...
                analysis.AreasMm2(selected_index)));
        end
        vtseg.ReviewStyle.axesTitle(ax, sprintf( ...
            '%s components (%d-connected): green largest, yellow selected, magenta candidates', ...
            structure_name, component_connectivity));
        drawnow;
    end

    function plot_component_boundaries(target_ax, component_mask, line_color, ...
            line_width, line_style, component_index)
        boundaries = bwboundaries(component_mask, 8, 'noholes');
        for boundary_index = 1:numel(boundaries)
            boundary = boundaries{boundary_index};
            line_handle = plot(target_ax, boundary(:, 2), boundary(:, 1), ...
                'Color', line_color, 'LineWidth', line_width, ...
                'LineStyle', line_style);
            if isempty(component_index)
                set(line_handle, 'HitTest', 'off', 'PickableParts', 'none');
            else
                set(line_handle, 'HitTest', 'on', 'PickableParts', 'all', ...
                    'ButtonDownFcn', @(~, ~) select_component(component_index));
            end
        end
    end

    function finish_component_review(action_name)
        if isvalid(figure_handle)
            setappdata(figure_handle, 'vtsegComponentReviewAction', action_name);
            uiresume(figure_handle);
        end
    end
end

function details = summarize_component_review( ...
        original_mask, staged_mask, action, pixel_spacing, connectivity)
original = vtseg.analyze_mask_components(original_mask, pixel_spacing, connectivity);
final = vtseg.analyze_mask_components(staged_mask, pixel_spacing, connectivity);
removed = vtseg.analyze_mask_components( ...
    logical(original_mask) & ~logical(staged_mask), pixel_spacing, connectivity);
details = struct( ...
    'Action', action, ...
    'OriginalComponentCount', original.Count, ...
    'FinalComponentCount', final.Count, ...
    'RemovedAreasPixels', removed.AreasPixels, ...
    'RemovedAreasMm2', removed.AreasMm2);
end

function show_component_before_after( ...
        review_ax, display_image, before_mask, after_mask, structure_name, color, fallback_gs_range)
[display_gs_range, contour_width] = ...
    current_review_display_settings(review_ax, fallback_gs_range);
comparison_figure = vtseg.ReviewStyle.newFigure( ...
    sprintf('Mask correction: compare %s components', structure_name), ...
    'WindowStyle', 'modal', 'Position', [160 180 1150 560]);
before_ax = subplot(1, 2, 1, 'Parent', comparison_figure);
after_ax = subplot(1, 2, 2, 'Parent', comparison_figure);
show_component_comparison(before_ax, display_image, before_mask, color, ...
    display_gs_range, contour_width, 'Before component review');
show_component_comparison(after_ax, display_image, after_mask, color, ...
    display_gs_range, contour_width, 'After component review');
vtseg.ReviewStyle.button(comparison_figure, [0.42 0.02 0.16 0.065], ...
    'Return to decision', @(~, ~) delete(comparison_figure), 'primary');
uiwait(comparison_figure);
end

function show_component_comparison( ...
        ax, display_image, mask, color, display_gs_range, contour_width, panel_title)
imshow(display_image, display_gs_range, 'Parent', ax);
hold(ax, 'on');
plot_mask_contour(ax, mask, color, max(1, contour_width));
theme = vtseg.ReviewStyle.theme();
title(ax, panel_title, 'FontWeight', 'bold', 'FontSize', 11, 'Color', theme.text);
end

function [mask, did_update] = edit_existing_mask( ...
        ax, Im, current_mask, color, gs_range, pixel_spacing)
mask = logical(current_mask);
did_update = false;
default_spacing_mm = 8;
default_max_handles = 64;
handle_spacing_mm = default_spacing_mm;
max_handle_count = default_max_handles;
% 'uniform' spaces handles equally along the boundary; 'simplify' puts them
% where the boundary bends and only fills stretches longer than the spacing.
handle_mode = 'uniform';
detail_tolerance_mm = 1;
contours = vtseg.mask_to_editable_contours( ...
    mask, default_spacing_mm, default_max_handles, pixel_spacing, edit_options());
if isempty(contours)
    fprintf('This mask is empty. Use redraw to create it from scratch.\n');
    return;
end

[display_gs_range, contour_width] = current_review_display_settings(ax, gs_range);
cla(ax);
imshow(Im, display_gs_range, 'Parent', ax);
hold(ax, 'on');

figure_handle = ancestor(ax, 'figure');
setappdata(figure_handle, 'vtsegContourEditAction', '');
rois = cell(numel(contours), 1);
reference_handles = cell(numel(contours), 1);
layout = review_layout();
theme = vtseg.ReviewStyle.theme();
edit_panel = vtseg.ReviewStyle.section(figure_handle, layout.action_slot, 'Edit contour');
edit_controls = gobjects(0);
spacing_slider = gobjects(0);
max_slider = gobjects(0);
mode_toggle = gobjects(0);
tolerance_slider = gobjects(0);
spacing_label = gobjects(0);
spacing_value = gobjects(0);
tolerance_value = gobjects(0);
max_value = gobjects(0);
rebuild_controls();
uiwait(figure_handle);

if ~isvalid(figure_handle)
    return;
end
action = getappdata(figure_handle, 'vtsegContourEditAction');
edited_contours = contours;
kept = false(numel(rois), 1);
if strcmp(action, 'accept')
    for index = 1:numel(rois)
        if ~isempty(rois{index}) && isvalid(rois{index}) && size(rois{index}.Position, 1) >= 3
            edited_contours(index).Position = rois{index}.Position;
            kept(index) = true;
        end
    end
end
for index = 1:numel(rois)
    if ~isempty(rois{index}) && isvalid(rois{index})
        delete(rois{index});
    end
    if ~isempty(reference_handles{index}) && isvalid(reference_handles{index})
        delete(reference_handles{index});
    end
end
if isappdata(figure_handle, 'vtsegActiveEditRois')
    rmappdata(figure_handle, 'vtsegActiveEditRois');
end
if isappdata(figure_handle, 'vtsegActiveEditReferenceHandles')
    rmappdata(figure_handle, 'vtsegActiveEditReferenceHandles');
end
if isvalid(edit_panel)
    delete(edit_panel);
end
if ~strcmp(action, 'accept')
    return;
end

try
    [dense_contours, moved] = vtseg.deform_editable_contours(contours, edited_contours);
catch deform_error
    % Never let an edit take the whole review session down. Fall back to the
    % edited polygons themselves and say so.
    warning('vtseg:EditDeformFallback', ...
        'Could not deform the dense boundary (%s). Using the edited polygons directly.', ...
        deform_error.message);
    dense_contours = edited_contours;
    moved = true;
end
if ~moved && all(kept)
    return;
end
mask = vtseg.editable_contours_to_mask(dense_contours(kept), size(Im));
did_update = true;

    function rebuild_controls()
        clear_edit_rois();
        spacing_mm = handle_spacing_mm;
        max_handles = max_handle_count;
        if ~isempty(spacing_slider) && isvalid(spacing_slider)
            spacing_mm = get(spacing_slider, 'Value');
        end
        if ~isempty(max_slider) && isvalid(max_slider)
            max_handles = round(get(max_slider, 'Value'));
        end
        handle_spacing_mm = spacing_mm;
        max_handle_count = max_handles;
        update_handle_control_text();
        contours = vtseg.mask_to_editable_contours( ...
            mask, spacing_mm, max_handles, pixel_spacing, edit_options());
        rois = cell(numel(contours), 1);
        reference_handles = cell(numel(contours), 1);
        primary = primary_component_index(contours);
        for contour_index = 1:numel(contours)
            reference_handles{contour_index} = plot_edit_reference( ...
                ax, contours(contour_index), color, contour_width, contour_index ~= primary);
            rois{contour_index} = drawpolygon(ax, ...
                'Position', contours(contour_index).Position, ...
                'Color', color, 'LineWidth', contour_width, 'FaceAlpha', 0.10);
        end
        setappdata(figure_handle, 'vtsegActiveEditRois', rois);
        setappdata(figure_handle, 'vtsegActiveEditReferenceHandles', reference_handles);
        set_active_edit_roi_visibility(figure_handle, contour_width > 0);
        show_edit_home();
        if strcmp(handle_mode, 'simplify')
            vtseg.ReviewStyle.axesTitle(ax, sprintf( ...
                'Drag handles: simplified to %.1f mm detail, gaps up to %.1f mm, maximum %d per boundary', ...
                detail_tolerance_mm, spacing_mm, max_handles));
        else
            vtseg.ReviewStyle.axesTitle(ax, sprintf( ...
                'Drag handles: %.1f mm spacing, maximum %d per boundary', ...
                spacing_mm, max_handles));
        end
    end

    function options = edit_options()
        options = struct('mode', handle_mode, 'tolerance', detail_tolerance_mm);
    end

    function [range_min, range_max] = spacing_range(simplifying)
        if simplifying
            range_min = 5;
            range_max = 40;
        else
            range_min = 3;
            range_max = 15;
        end
    end

    function summary = density_summary()
        if strcmp(handle_mode, 'simplify')
            summary = sprintf('Handle density (simplified, %.1f mm)', detail_tolerance_mm);
        else
            summary = sprintf('Handle density (uniform, %.1f mm)', handle_spacing_mm);
        end
    end

    function clear_edit_rois()
        for roi_index = 1:numel(rois)
            if ~isempty(rois{roi_index}) && isvalid(rois{roi_index})
                delete(rois{roi_index});
            end
            if ~isempty(reference_handles{roi_index}) && isvalid(reference_handles{roi_index})
                delete(reference_handles{roi_index});
            end
        end
    end

    function update_handle_control_text(varargin)
        if ~isempty(mode_toggle) && isvalid(mode_toggle)
            if get(mode_toggle, 'Value')
                handle_mode = 'simplify';
            else
                handle_mode = 'uniform';
            end
        end
        simplifying = strcmp(handle_mode, 'simplify');
        if ~isempty(spacing_slider) && isvalid(spacing_slider)
            % Uniform spacing is capped at 15 mm; as a largest-gap limit the
            % same slider must reach further, or a smooth wall can never be
            % thinned below what uniform spacing already gives.
            [range_min, range_max] = spacing_range(simplifying);
            clamped = min(range_max, max(range_min, get(spacing_slider, 'Value')));
            set(spacing_slider, 'Min', range_min, 'Max', range_max, 'Value', clamped, ...
                'SliderStep', [1, 5] ./ (range_max - range_min));
            handle_spacing_mm = clamped;
        end
        if ~isempty(tolerance_slider) && isvalid(tolerance_slider)
            detail_tolerance_mm = get(tolerance_slider, 'Value');
            if simplifying
                set(tolerance_slider, 'Enable', 'on');
            else
                set(tolerance_slider, 'Enable', 'off');
            end
        end
        if ~isempty(max_slider) && isvalid(max_slider)
            max_handle_count = round(get(max_slider, 'Value'));
        end
        if ~isempty(spacing_label) && isvalid(spacing_label)
            if simplifying
                set(spacing_label, 'String', 'Largest gap');
            else
                set(spacing_label, 'String', 'Handle spacing');
            end
        end
        if ~isempty(spacing_value) && isvalid(spacing_value)
            set(spacing_value, 'String', sprintf('%.1f mm', handle_spacing_mm));
        end
        if ~isempty(tolerance_value) && isvalid(tolerance_value)
            if simplifying
                set(tolerance_value, 'String', sprintf('%.1f mm', detail_tolerance_mm));
            else
                set(tolerance_value, 'String', 'off');
            end
        end
        if ~isempty(max_value) && isvalid(max_value)
            set(max_value, 'String', sprintf('%d', max_handle_count));
        end
    end

    function clear_edit_controls()
        for control_index = 1:numel(edit_controls)
            if isvalid(edit_controls(control_index))
                delete(edit_controls(control_index));
            end
        end
        edit_controls = gobjects(0);
        spacing_slider = gobjects(0);
        max_slider = gobjects(0);
        mode_toggle = gobjects(0);
        tolerance_slider = gobjects(0);
        spacing_label = gobjects(0);
        spacing_value = gobjects(0);
        tolerance_value = gobjects(0);
        max_value = gobjects(0);
    end

    function add_edit_control(control)
        edit_controls(end + 1) = control; %#ok<AGROW>
    end

    function show_edit_home()
        clear_edit_controls();
        add_edit_control(vtseg.ReviewStyle.label(edit_panel, [0.06 0.74 0.88 0.17], ...
            'Drag the visible handles to adjust this existing contour.', 'left', true));
        add_edit_control(vtseg.ReviewStyle.button(edit_panel, [0.06 0.52 0.88 0.14], ...
            density_summary(), @(~, ~) show_density_controls(), 'neutral'));
        add_edit_control(vtseg.ReviewStyle.button(edit_panel, [0.06 0.25 0.88 0.15], ...
            'Accept contour edits', @(~, ~) finish_contour_edit(figure_handle, 'accept'), 'primary'));
        add_edit_control(vtseg.ReviewStyle.button(edit_panel, [0.06 0.06 0.88 0.12], ...
            'Cancel', @(~, ~) finish_contour_edit(figure_handle, 'cancel'), 'neutral'));
    end

    function show_density_controls()
        clear_edit_controls();
        % Uniform spacing crowds the two walls of a narrow crescent, which are
        % far apart along the boundary but close on screen. Simplify handles
        % keeps handles only where the boundary bends, so that no longer
        % happens; the spacing slider then caps the longest gap instead.
        mode_toggle = vtseg.ReviewStyle.toggle(edit_panel, [0.06 0.89 0.88 0.09], ...
            'Simplify handles', double(strcmp(handle_mode, 'simplify')), ...
            @update_handle_control_text);
        add_edit_control(mode_toggle);
        spacing_label = vtseg.ReviewStyle.label(edit_panel, [0.06 0.80 0.58 0.07], ...
            'Handle spacing', 'left', false);
        add_edit_control(spacing_label);
        spacing_value = vtseg.ReviewStyle.label(edit_panel, [0.64 0.80 0.30 0.07], '', 'right', true);
        add_edit_control(spacing_value);
        [range_min, range_max] = spacing_range(strcmp(handle_mode, 'simplify'));
        spacing_slider = vtseg.ReviewStyle.slider(edit_panel, [0.06 0.73 0.88 0.06], ...
            range_min, range_max, min(range_max, max(range_min, handle_spacing_mm)), ...
            [1, 5] ./ (range_max - range_min), @update_handle_control_text);
        add_edit_control(spacing_slider);
        add_edit_control(vtseg.ReviewStyle.label(edit_panel, [0.06 0.64 0.58 0.07], ...
            'Detail tolerance', 'left', false));
        tolerance_value = vtseg.ReviewStyle.label(edit_panel, [0.64 0.64 0.30 0.07], '', 'right', true);
        add_edit_control(tolerance_value);
        tolerance_slider = vtseg.ReviewStyle.slider(edit_panel, [0.06 0.57 0.88 0.06], ...
            0.5, 5, detail_tolerance_mm, [0.5 / 4.5, 1 / 4.5], @update_handle_control_text);
        add_edit_control(tolerance_slider);
        add_edit_control(vtseg.ReviewStyle.label(edit_panel, [0.06 0.48 0.58 0.07], ...
            'Maximum handles', 'left', false));
        max_value = vtseg.ReviewStyle.label(edit_panel, [0.64 0.48 0.30 0.07], '', 'right', true);
        add_edit_control(max_value);
        max_slider = vtseg.ReviewStyle.slider(edit_panel, [0.06 0.41 0.88 0.06], ...
            20, 96, max_handle_count, [1 / 76, 8 / 76], @update_handle_control_text);
        add_edit_control(max_slider);
        add_edit_control(vtseg.ReviewStyle.button(edit_panel, [0.06 0.28 0.88 0.10], ...
            'Apply density', @(~, ~) rebuild_controls(), 'primary'));
        add_edit_control(vtseg.ReviewStyle.button(edit_panel, [0.06 0.17 0.88 0.09], ...
            'Reset edits', @(~, ~) rebuild_controls(), 'danger'));
        add_edit_control(vtseg.ReviewStyle.button(edit_panel, [0.06 0.06 0.88 0.09], ...
            'Back to edit', @(~, ~) show_edit_home(), 'neutral'));
        update_handle_control_text();
    end

end

function finish_contour_edit(figure_handle, action)
if isvalid(figure_handle)
    setappdata(figure_handle, 'vtsegContourEditAction', action);
    uiresume(figure_handle);
end
end

function set_active_edit_roi_visibility(figure_handle, is_visible)
    if ~isvalid(figure_handle) || ~isappdata(figure_handle, 'vtsegActiveEditRois')
        return;
    end
    rois = getappdata(figure_handle, 'vtsegActiveEditRois');
    for index = 1:numel(rois)
        if ~isempty(rois{index}) && isvalid(rois{index})
            if is_visible
                set(rois{index}, 'Visible', 'on');
            else
                set(rois{index}, 'Visible', 'off');
            end
        end
    end
    if isappdata(figure_handle, 'vtsegActiveEditReferenceHandles')
        references = getappdata(figure_handle, 'vtsegActiveEditReferenceHandles');
        for index = 1:numel(references)
            if ~isempty(references{index}) && isvalid(references{index})
                if is_visible
                    set(references{index}, 'Visible', 'on');
                else
                    set(references{index}, 'Visible', 'off');
                end
            end
        end
    end
end

function index = primary_component_index(contours)
%PRIMARY_COMPONENT_INDEX Largest outer contour is the anatomical main component.
outer_indices = find(~[contours.IsHole]);
if isempty(outer_indices)
    index = 1;
    return;
end
areas = zeros(numel(outer_indices), 1);
for outer_index = 1:numel(outer_indices)
    position = contours(outer_indices(outer_index)).DensePosition;
    areas(outer_index) = abs(polyarea(position(:, 1), position(:, 2)));
end
[~, largest] = max(areas);
index = outer_indices(largest);
end

function handle = plot_edit_reference(ax, contour_record, color, line_width, is_island)
%PLOT_EDIT_REFERENCE Draw dense source boundaries behind sparse draggable ROIs.
position = contour_record.DensePosition;
if isempty(position)
    handle = gobjects(0);
    return;
end
line_style = '-';
if is_island
    line_style = '--';
end
handle = plot(ax, [position(:, 1); position(1, 1)], ...
    [position(:, 2); position(1, 2)], 'Color', color, ...
    'LineStyle', line_style, 'LineWidth', max(0.1, 0.65 * line_width));
end

function mask = redraw_mask_components(ax, Im, color, gs_range)
[display_gs_range, contour_width] = current_review_display_settings(ax, gs_range);
figure_handle = ancestor(ax, 'figure');
cla(ax);
h_img = imshow(Im, display_gs_range, 'Parent', ax);
hold(ax, 'on');
mask = false(size(Im));
add_component = true;
while add_component
    [component, ~, ~] = draw_polygon_mask(ax, h_img, color, contour_width);
    mask = mask | component;
    action = choose_review_action(figure_handle, ...
        'Add another disconnected component?', ...
        {'Add component', 'add'; 'Finish redraw', 'finish'});
    add_component = strcmp(action, 'add');
end
end

function action = choose_review_action(figure_handle, prompt, choices, title_color)
%CHOOSE_REVIEW_ACTION Present one modal action panel inside the review figure.
% title_color (optional) colours the prompt; structure prompts pass the
% structure's contour colour so it is obvious which outline is being decided.
theme = vtseg.ReviewStyle.theme();
if nargin < 4 || isempty(title_color)
    title_color = theme.text;
end
action = 'cancel';
if ~isvalid(figure_handle)
    return;
end

setappdata(figure_handle, 'vtsegReviewChoice', '');
layout = review_layout();
panel = vtseg.ReviewStyle.section(figure_handle, layout.action_slot, prompt);
set(panel, 'FontSize', theme.font_size + 2, 'ForegroundColor', title_color);
choice_count = size(choices, 1);
margin = 0.06;
gap = 0.05;
height = min(0.30, (1 - 2 * margin - gap * (choice_count - 1)) / choice_count);
for index = 1:choice_count
    y = 1 - margin - index * height - (index - 1) * gap;
    vtseg.ReviewStyle.button(panel, [margin, y, 1 - 2 * margin, height], choices{index, 1}, ...
        @(~, ~) finish_review_action(figure_handle, choices{index, 2}), ...
        review_action_kind(choices{index, 2}));
end

uiwait(figure_handle);
if isvalid(figure_handle)
    selected = getappdata(figure_handle, 'vtsegReviewChoice');
    if ~isempty(selected)
        action = selected;
    end
    if isvalid(panel)
        delete(panel);
    end
end
end

function finish_review_action(figure_handle, action)
if isvalid(figure_handle)
    setappdata(figure_handle, 'vtsegReviewChoice', action);
    uiresume(figure_handle);
end
end

function updated = apply_mask_update(current, cropped_mask, display_crop, replace_entire_slice)
if replace_entire_slice
    updated = false(size(current));
else
    updated = current;
end
updated(display_crop.rows, display_crop.columns) = cropped_mask;
end

function errors = validate_slice_masks(Lendo, Rendo, Epi)
Lendo = logical(Lendo);
Rendo = logical(Rendo);
Epi = logical(Epi);
errors = {};
if any(Lendo(:) & Rendo(:))
    errors{end + 1} = 'LV and RV endocardial masks overlap.'; %#ok<AGROW>
end
if any(Lendo(:) & ~Epi(:))
    errors{end + 1} = 'LV endocardium extends outside the epicardium.'; %#ok<AGROW>
end
if any(Rendo(:) & ~Epi(:))
    errors{end + 1} = 'RV endocardium extends outside the epicardium.'; %#ok<AGROW>
end
end

function [display_image, h_img] = show_slice_with_masks( ...
        ax, path_image, file_name, gs_range, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop)

    f = strcat(path_image, file_name);
    f_info = dicominfo(f);
    Im = vtseg.read_dicom_image(f_info);
    display_image = Im(display_crop.rows, display_crop.columns);
    [display_gs_range, contour_width] = current_review_display_settings(ax, gs_range);

    cla(ax);
    h_img = imshow(display_image, display_gs_range, 'Parent', ax);
    hold(ax, 'on');

    plot_mask_contour(ax, Lendo(display_crop.rows, display_crop.columns, k), 'r', contour_width);
    plot_mask_contour(ax, Rendo(display_crop.rows, display_crop.columns, k), 'c', contour_width);
    plot_mask_contour(ax, Epi(display_crop.rows, display_crop.columns, k), 'g', contour_width);

    if has_lepi
        plot_mask_contour(ax, lepi(display_crop.rows, display_crop.columns, k), 'b', contour_width);
    end

    vtseg.ReviewStyle.axesTitle(ax, sprintf('Slice %d: %s', k, file_name));
    drawnow;
end

function show_before_after_comparison( ...
        review_ax, display_image, file_name, k, ...
        old_Lendo, old_Rendo, old_Epi, old_lepi, ...
        new_Lendo, new_Rendo, new_Epi, new_lepi, ...
        has_lepi, display_crop, fallback_gs_range)
%SHOW_BEFORE_AFTER_COMPARISON Compare the accepted candidate with its source masks.
[display_gs_range, contour_width] = ...
    current_review_display_settings(review_ax, fallback_gs_range);

theme = vtseg.ReviewStyle.theme();
comparison_figure = vtseg.ReviewStyle.newFigure( ...
    sprintf('Mask correction: compare edits, slice %d', k), ...
    'WindowStyle', 'modal', 'Position', [160 180 1150 560]);

before_ax = subplot(1, 2, 1, 'Parent', comparison_figure);
after_ax = subplot(1, 2, 2, 'Parent', comparison_figure);
show_comparison_masks( ...
    before_ax, display_image, old_Lendo, old_Rendo, old_Epi, old_lepi, ...
    has_lepi, display_crop, display_gs_range, contour_width, 'Before edit');
show_comparison_masks( ...
    after_ax, display_image, new_Lendo, new_Rendo, new_Epi, new_lepi, ...
    has_lepi, display_crop, display_gs_range, contour_width, 'After edit');

annotation(comparison_figure, 'textbox', [0.08 0.93 0.84 0.05], ...
    'String', sprintf('Slice %d: %s', k, file_name), ...
    'Interpreter', 'none', 'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', 'FontSize', 12, 'EdgeColor', 'none', ...
    'Color', theme.text);
vtseg.ReviewStyle.button(comparison_figure, [0.42 0.02 0.16 0.065], 'Return to decision', ...
    @(~, ~) delete(comparison_figure), 'primary');

uiwait(comparison_figure);
end

function show_comparison_masks( ...
        ax, display_image, Lendo, Rendo, Epi, lepi, has_lepi, ...
        display_crop, display_gs_range, contour_width, panel_title)
imshow(display_image, display_gs_range, 'Parent', ax);
hold(ax, 'on');
plot_mask_contour(ax, Lendo(display_crop.rows, display_crop.columns), 'r', contour_width);
plot_mask_contour(ax, Rendo(display_crop.rows, display_crop.columns), 'c', contour_width);
plot_mask_contour(ax, Epi(display_crop.rows, display_crop.columns), 'g', contour_width);
if has_lepi
    plot_mask_contour(ax, lepi(display_crop.rows, display_crop.columns), 'b', contour_width);
end
theme = vtseg.ReviewStyle.theme();
title(ax, panel_title, 'FontWeight', 'bold', 'FontSize', 11, 'Color', theme.text);
end

function [limits, initial_window] = review_window_limits(image, requested_window)
    finite_pixels = image(isfinite(image));
    if isempty(finite_pixels)
        limits = [0 1];
    else
        limits = [min(finite_pixels(:)) max(finite_pixels(:))];
        if limits(1) == limits(2)
            limits = limits + [-0.5 0.5];
        end
    end
    if isempty(requested_window)
        initial_window = limits;
    else
        initial_window = sort(double(requested_window(:)'));
        if numel(initial_window) ~= 2 || initial_window(1) == initial_window(2)
            initial_window = limits;
        end
    end
end

function [display_gs_range, contour_width] = current_review_display_settings(ax, fallback_gs_range)
    display_gs_range = fallback_gs_range;
    contour_width = 1.5;
    figure_handle = ancestor(ax, 'figure');
    if isempty(figure_handle) || ~isvalid(figure_handle)
        return;
    end
    controls = getappdata(figure_handle, 'vtsegReviewDisplayControls');
    if isempty(controls)
        return;
    end
    center = get(controls.center_slider, 'Value');
    width = get(controls.width_slider, 'Value');
    display_gs_range = [center - width / 2, center + width / 2];
    if get(controls.contour_toggle, 'Value')
        contour_width = get(controls.contour_width_slider, 'Value');
    else
        contour_width = 0;
    end
end

function display_crop = load_display_crop(path_out, image_height, image_width)
display_crop = struct('rows', 1:image_height, 'columns', 1:image_width);
crop_path = fullfile(path_out, 'review_display_crop.json');
if ~isfile(crop_path)
    return;
end
try
    saved = jsondecode(fileread(crop_path));
    if saved.image_height ~= image_height || saved.image_width ~= image_width
        warning('vtseg:DisplayCropIgnored', 'Saved review crop does not match the current image dimensions.');
        return;
    end
    if saved.row_start < 1 || saved.row_end > image_height || ...
            saved.column_start < 1 || saved.column_end > image_width || ...
            saved.row_start > saved.row_end || saved.column_start > saved.column_end
        warning('vtseg:DisplayCropIgnored', 'Saved review crop is outside the current image bounds.');
        return;
    end
    display_crop.rows = saved.row_start:saved.row_end;
    display_crop.columns = saved.column_start:saved.column_end;
catch
    warning('vtseg:DisplayCropIgnored', 'Unable to read the saved review crop.');
end
end

function plot_mask_contour(ax, mask, color, line_width)
    if nargin < 4
        line_width = 1.5;
    end
    mask = logical(mask);

    if any(mask(:)) && any(~mask(:))
        if line_width <= 0
            [~, handle] = contour(ax, mask, [0.5 0.5], color, ...
                'LineWidth', 1.5, 'Visible', 'off');
        else
            [~, handle] = contour(ax, mask, [0.5 0.5], color, 'LineWidth', line_width);
        end
        set(handle, 'Tag', review_contour_tag(color));
    end
end

function plot_final_segmentation_overview( ...
        path_image, folder, n_slices, gs_range, Lendo, Rendo, Epi, seg_path, display_crop)

    slice_labels = load_export_slice_labels(seg_path, folder, n_slices);

    n_cols = ceil(sqrt(n_slices));
    n_rows = ceil(n_slices / n_cols);

    vtseg.ReviewStyle.newFigure('Mask correction: final contours');
    tiledlayout(n_rows, n_cols, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    for k = 1:n_slices
        Im = read_slice_image(path_image, folder(k).name);

        nexttile;
        imshow(Im(display_crop.rows, display_crop.columns), gs_range);
        hold on;

        plot_mask_contour(gca, Epi(display_crop.rows, display_crop.columns, k), 'g');
        plot_mask_contour(gca, Lendo(display_crop.rows, display_crop.columns, k), 'r');
        plot_mask_contour(gca, Rendo(display_crop.rows, display_crop.columns, k), 'c');

        vtseg.ReviewStyle.axesTitle(gca, slice_labels{k}, 'FontSize', 8);
    end

    vtseg.ReviewStyle.figureTitle(gcf, 'Final segmentation contours: Epi green, Lendo red, Rendo cyan');

    vtseg.ReviewStyle.newFigure('Mask correction: final raw images');
    tiledlayout(n_rows, n_cols, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    for k = 1:n_slices
        Im = read_slice_image(path_image, folder(k).name);

        nexttile;
        imshow(Im(display_crop.rows, display_crop.columns), gs_range);
        vtseg.ReviewStyle.axesTitle(gca, slice_labels{k}, 'FontSize', 8);
    end

    vtseg.ReviewStyle.figureTitle(gcf, 'Final segmentation crop: raw images');
end

function labels = load_export_slice_labels(seg_path, folder, n_slices)
% Match each compact MATLAB mask index to its base-to-apex source position.
labels = cell(n_slices, 1);
for k = 1:n_slices
    labels{k} = {sprintf('Mask %d', k), folder(k).name};
end

manifest_path = fullfile(seg_path, 'vtseg_export_manifest.json');
if ~isfile(manifest_path)
    % Compatibility with MATLAB exports produced before the generic manifest.
    manifest_path = fullfile(seg_path, 'bivme_export_manifest.json');
end
if ~isfile(manifest_path)
    return;
end
manifest = jsondecode(fileread(manifest_path));
if ~isfield(manifest, 'slices') || numel(manifest.slices) ~= n_slices
    return;
end

for k = 1:n_slices
    entry = manifest.slices(k);
    filename = folder(k).name;
    if isfield(entry, 'dicom_file')
        filename = entry.dicom_file;
    end
    if isfield(entry, 'base_to_apex_reference_slice')
        labels{k} = {sprintf('Mask %d | source %d', k, ...
            entry.base_to_apex_reference_slice), filename};
    else
        labels{k} = {sprintf('Mask %d', k), filename};
    end
end
end

function layout = review_layout()
%REVIEW_LAYOUT Figure-normalized regions of the review window.
% The image gets the left 70 %; the right column holds Display, Contours and
% an action slot that stays empty until a prompt needs it.
layout = struct( ...
    'header', [0.015 0.915 0.970 0.070], ...
    'axes', [0.020 0.030 0.700 0.860], ...
    'display', [0.735 0.530 0.250 0.370], ...
    'legend', [0.735 0.320 0.250 0.190], ...
    'action_slot', [0.735 0.030 0.250 0.270]);
end

function kind = review_action_kind(action)
%REVIEW_ACTION_KIND Map a prompt's action id to a button style.
switch action
    case {'keep', 'save', 'accept'}
        kind = 'primary';
    case {'discard', 'clear', 'quit'}
        kind = 'danger';
    otherwise
        kind = 'neutral';
end
end

function [accept_position, cancel_position] = review_edit_button_positions()
%REVIEW_EDIT_BUTTON_POSITIONS Accept above Cancel, inside the action slot.
layout = review_layout();
slot = layout.action_slot;
x = slot(1) + 0.012;
width = slot(3) - 0.024;
height = 0.055;
accept_position = [x, slot(2) + slot(4) - 0.030 - height, width, height];
cancel_position = [x, accept_position(2) - 0.015 - height, width, height];
end

function review_legend(panel, has_lepi)
%REVIEW_LEGEND Colour swatch and name for each contour drawn on the image.
% Names match the structure names used by the correction prompts, and the
% rows are kept on the figure so a prompt can grey out the others.
entries = {'LV endocardium', [1 0 0]; 'RV endocardium', [0 1 1]; 'Epicardium', [0 1 0]};
if has_lepi
    entries(end + 1, :) = {'LV epicardium', [0 0 1]};
end
row_height = 0.16;
gap = 0.06;
top = 0.90;
records = struct('name', {}, 'color', {}, 'swatch', {}, 'label', {});
for index = 1:size(entries, 1)
    y = top - index * row_height - (index - 1) * gap;
    swatch = uicontrol(panel, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.07, y + 0.02, 0.10, row_height - 0.04], 'String', '', ...
        'BackgroundColor', entries{index, 2});
    label = vtseg.ReviewStyle.label(panel, [0.22 y 0.74 row_height], entries{index, 1}, 'left', false);
    records(end + 1) = struct('name', entries{index, 1}, 'color', entries{index, 2}, ...
        'swatch', swatch, 'label', label); %#ok<AGROW>
end
setappdata(ancestor(panel, 'figure'), 'vtsegReviewLegend', records);
end

function tag = review_contour_tag(color)
%REVIEW_CONTOUR_TAG Tag identifying which structure colour a contour was drawn in.
if ischar(color)
    key = color;
else
    key = sprintf('%.2f_', color);
end
tag = ['vtsegContour_' key];
end

function rgb = review_structure_text_color(color)
%REVIEW_STRUCTURE_TEXT_COLOR The structure's colour, lifted where it would be
% hard to read as text on the dark panel.
switch color
    case 'r'
        rgb = [1.00 0.30 0.30];
    case 'c'
        rgb = [0.20 1.00 1.00];
    case 'g'
        rgb = [0.35 1.00 0.35];
    case 'b'
        rgb = [0.45 0.65 1.00];
    otherwise
        theme = vtseg.ReviewStyle.theme();
        rgb = theme.text;
end
end

function apply_review_contour_widths(figure_handle, ax)
%APPLY_REVIEW_CONTOUR_WIDTHS Give every contour the slider width, then thin
% every structure except the one a prompt is currently about.
if isempty(figure_handle) || ~isvalid(figure_handle)
    return;
end
[~, contour_width] = current_review_display_settings(ax, []);
contour_handles = findobj(ax, 'Type', 'contour');
if isempty(contour_handles)
    return;
end
if contour_width <= 0
    set(contour_handles, 'Visible', 'off');
    return;
end
set(contour_handles, 'Visible', 'on', 'LineWidth', contour_width);
if ~isappdata(figure_handle, 'vtsegReviewEmphasis')
    return;
end
emphasis = getappdata(figure_handle, 'vtsegReviewEmphasis');
if isempty(emphasis)
    return;
end
active_tag = review_contour_tag(emphasis.color);
thin_width = max(0.5, 0.4 * contour_width);
for index = 1:numel(contour_handles)
    if ~strcmp(get(contour_handles(index), 'Tag'), active_tag)
        set(contour_handles(index), 'LineWidth', thin_width);
    end
end
end

function emphasize_review_structure(figure_handle, ax, structure_name, color)
%EMPHASIZE_REVIEW_STRUCTURE While a prompt is about one structure, thin the
% other contours on the image and grey out their legend rows.
if isempty(figure_handle) || ~isvalid(figure_handle)
    return;
end
setappdata(figure_handle, 'vtsegReviewEmphasis', ...
    struct('name', structure_name, 'color', color));
apply_review_contour_widths(figure_handle, ax);
style_review_legend(figure_handle, structure_name);
drawnow;
end

function restore_review_emphasis(figure_handle, ax)
%RESTORE_REVIEW_EMPHASIS Undo emphasize_review_structure.
if isempty(figure_handle) || ~isvalid(figure_handle)
    return;
end
if isappdata(figure_handle, 'vtsegReviewEmphasis')
    rmappdata(figure_handle, 'vtsegReviewEmphasis');
end
apply_review_contour_widths(figure_handle, ax);
style_review_legend(figure_handle, '');
drawnow;
end

function style_review_legend(figure_handle, active_name)
%STYLE_REVIEW_LEGEND Grey out every legend row but active_name; '' restores all.
if ~isvalid(figure_handle) || ~isappdata(figure_handle, 'vtsegReviewLegend')
    return;
end
theme = vtseg.ReviewStyle.theme();
dim_text = [0.45 0.48 0.53];
records = getappdata(figure_handle, 'vtsegReviewLegend');
for index = 1:numel(records)
    entry = records(index);
    if ~isvalid(entry.swatch) || ~isvalid(entry.label)
        continue;
    end
    if isempty(active_name)
        set(entry.swatch, 'BackgroundColor', entry.color);
        set(entry.label, 'ForegroundColor', theme.text, 'FontWeight', 'normal');
    elseif strcmp(entry.name, active_name)
        set(entry.swatch, 'BackgroundColor', entry.color);
        set(entry.label, 'ForegroundColor', theme.text, 'FontWeight', 'bold');
    else
        set(entry.swatch, 'BackgroundColor', 0.35 * entry.color + 0.65 * theme.panel);
        set(entry.label, 'ForegroundColor', dim_text, 'FontWeight', 'normal');
    end
end
end

function Im = read_slice_image(path_image, file_name)
    f = strcat(path_image, file_name);
    f_info = dicominfo(f);
    Im = vtseg.read_dicom_image(f_info);
end

function spacing = editable_pixel_spacing(path_image, file_name)
%EDITABLE_PIXEL_SPACING Return [row column] spacing for physical edit handles.
spacing = [1, 1];
try
    info = dicominfo(fullfile(path_image, file_name));
    if isfield(info, 'PixelSpacing')
        candidate = double(info.PixelSpacing(:)');
    elseif isfield(info, 'ImagerPixelSpacing')
        candidate = double(info.ImagerPixelSpacing(:)');
    else
        candidate = [];
    end
    if numel(candidate) == 2 && all(isfinite(candidate)) && all(candidate > 0)
        spacing = candidate;
    end
catch
    % A missing metadata field should not block reviewing an otherwise usable mask.
end
end
