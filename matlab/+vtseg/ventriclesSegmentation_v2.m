function ventriclesSegmentation_v2(path_image,path_out, gs_range)% manual segmentation of ventricles
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
        Im = dicomread(f_info);
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

if last_segmented_slice > numel(folder)
    error('Mask stack has %d slices, but only %d DICOM files were found for review.', ...
        last_segmented_slice, numel(folder));
end

if last_segmented_slice > 0
    display_crop = load_display_crop(path_out, size(Epi, 1), size(Epi, 2));
    if lower(lstr) == 'y'
        [Lendo, Rendo, Epi, lepi, save_confirmed] = review_and_correct_masks( ...
            path_image, folder, last_segmented_slice, gs_range, ...
            Lendo, Rendo, Epi, lepi, true, display_crop);
    else
        [Lendo, Rendo, Epi, ~, save_confirmed] = review_and_correct_masks( ...
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
myocardium = Epi & ~Lendo & ~Rendo;
save(fullfile(path_out, 'myocardium.mat'), 'myocardium');

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

function [Lendo, Rendo, Epi, lepi, save_confirmed] = review_and_correct_masks( ...
        path_image, folder, last_segmented_slice, gs_range, ...
        Lendo, Rendo, Epi, lepi, has_lepi, display_crop)

    save_confirmed = false;

    figure_handle = figure('Name', 'Review/correct masks', ...
        'NumberTitle', 'off', 'Color', 'w', 'CloseRequestFcn', @quit_review);
    ax = axes('Parent', figure_handle, 'Units', 'normalized', ...
        'Position', [0.05 0.12 0.67 0.77]);

    reference_image = double(read_slice_image(path_image, folder(1).name));
    [window_limits, initial_window] = review_window_limits(reference_image, gs_range);
    window_center = min(window_limits(2), max(window_limits(1), mean(initial_window)));
    window_width = diff(initial_window);
    window_span = diff(window_limits);
    minimum_width = max(window_span / 1000, eps(window_span));

    uicontrol(figure_handle, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.77 0.80 0.18 0.04], 'String', 'Window center', ...
        'BackgroundColor', 'w');
    center_slider = uicontrol(figure_handle, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.77 0.75 0.18 0.04], 'Min', window_limits(1), ...
        'Max', window_limits(2), 'Value', window_center, ...
        'SliderStep', [0.01 0.10], 'Callback', @on_display_control_change);
    uicontrol(figure_handle, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.77 0.67 0.18 0.04], 'String', 'Window width', ...
        'BackgroundColor', 'w');
    width_slider = uicontrol(figure_handle, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.77 0.62 0.18 0.04], 'Min', minimum_width, ...
        'Max', window_span, 'Value', max(minimum_width, min(window_span, window_width)), ...
        'SliderStep', [0.01 0.10], 'Callback', @on_display_control_change);
    uicontrol(figure_handle, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.77 0.54 0.18 0.04], 'String', 'Contour width', ...
        'BackgroundColor', 'w');
    contour_width_slider = uicontrol(figure_handle, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.77 0.49 0.18 0.04], 'Min', 0.1, 'Max', 4, 'Value', 1.5, ...
        'SliderStep', [0.05 / 3.9 0.5 / 3.9], 'Callback', @on_display_control_change);
    contour_toggle = uicontrol(figure_handle, 'Style', 'togglebutton', 'Units', 'normalized', ...
        'Position', [0.77 0.42 0.18 0.05], 'String', 'Show contours', 'Value', 1, ...
        'Callback', @on_display_control_change);
    display_text = uicontrol(figure_handle, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.77 0.27 0.20 0.10], 'HorizontalAlignment', 'left', ...
        'BackgroundColor', 'w');
    setappdata(figure_handle, 'vtsegReviewDisplayControls', struct( ...
        'center_slider', center_slider, 'width_slider', width_slider, ...
        'contour_width_slider', contour_width_slider, 'contour_toggle', contour_toggle, ...
        'display_text', display_text));
    update_display_control_text();

    previous_button = uicontrol(figure_handle, 'Style', 'pushbutton', ...
        'Units', 'normalized', 'Position', [0.05 0.93 0.11 0.045], ...
        'String', 'Previous', 'Callback', @(~, ~) choose_navigation('previous'));
    next_button = uicontrol(figure_handle, 'Style', 'pushbutton', ...
        'Units', 'normalized', 'Position', [0.17 0.93 0.13 0.045], ...
        'String', 'Keep / Next', 'Callback', @(~, ~) choose_navigation('next'));
    correct_button = uicontrol(figure_handle, 'Style', 'pushbutton', ...
        'Units', 'normalized', 'Position', [0.31 0.93 0.13 0.045], ...
        'String', 'Modify', 'Callback', @(~, ~) choose_navigation('modify'));
    uicontrol(figure_handle, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.46 0.935 0.07 0.035], 'String', 'Go to slice', ...
        'BackgroundColor', 'w');
    slice_field = uicontrol(figure_handle, 'Style', 'edit', 'Units', 'normalized', ...
        'Position', [0.54 0.93 0.06 0.045], 'String', '1', ...
        'Callback', @(~, ~) choose_navigation('jump'));
    jump_button = uicontrol(figure_handle, 'Style', 'pushbutton', ...
        'Units', 'normalized', 'Position', [0.61 0.93 0.07 0.045], ...
        'String', 'Go', 'Callback', @(~, ~) choose_navigation('jump'));
    finish_button = uicontrol(figure_handle, 'Style', 'pushbutton', ...
        'Units', 'normalized', 'Position', [0.69 0.93 0.12 0.045], ...
        'String', 'Finish review', 'Callback', @(~, ~) choose_navigation('finish'));
    quit_button = uicontrol(figure_handle, 'Style', 'pushbutton', ...
        'Units', 'normalized', 'Position', [0.82 0.93 0.13 0.045], ...
        'String', 'Quit without saving', 'Callback', @(~, ~) choose_navigation('quit'));
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
            old_Lendo = Lendo(:, :, k);
            old_Rendo = Rendo(:, :, k);
            old_Epi = Epi(:, :, k);
            if has_lepi
                old_lepi = lepi(:, :, k);
            end

            candidate_Lendo = Lendo;
            candidate_Rendo = Rendo;
            candidate_Epi = Epi;
            candidate_lepi = lepi;
            correction_valid = false;
            set(navigation_controls, 'Enable', 'off');

            while ~correction_valid
                [candidate_Lendo, candidate_Rendo, candidate_Epi, candidate_lepi] = ...
                    correct_slice_masks( ...
                        ax, display_image, k, candidate_Lendo, candidate_Rendo, ...
                        candidate_Epi, candidate_lepi, has_lepi, display_crop, gs_range);

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
            keep_str = choose_review_action(figure_handle, ...
                'Keep these modifications?', {'Keep changes', 'keep'; 'Discard changes', 'discard'});
            if ~isvalid(figure_handle)
                return;
            end
            set(navigation_controls, 'Enable', 'on');

            if strcmp(keep_str, 'keep')
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
        contour_handles = findobj(ax, 'Type', 'contour');
        if ~isempty(contour_handles)
            if contour_width <= 0
                set(contour_handles, 'Visible', 'off');
            else
                set(contour_handles, 'Visible', 'on', 'LineWidth', contour_width);
            end
        end
        set_active_edit_roi_visibility(figure_handle, contour_width > 0);
        update_display_control_text();
        drawnow;
    end

    function update_display_control_text()
        [current_window, contour_width] = current_review_display_settings(ax, gs_range);
        if contour_width <= 0
            contour_label = 'Contours: hidden';
        else
            contour_label = sprintf('Contours: %.2f', contour_width);
        end
        set(display_text, 'String', sprintf( ...
            'Center: %.1f\nWidth: %.1f\n%s', ...
            mean(current_window), diff(current_window), contour_label));
    end
end

function [Lendo, Rendo, Epi, lepi] = correct_slice_masks( ...
        ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range)

    current_mask = Lendo(display_crop.rows, display_crop.columns, k);
    [new_mask, did_update, replace_entire_slice] = correct_one_mask( ...
        ax, display_image, current_mask, 'LV endocardium', 'r', gs_range);
    if did_update
        Lendo(:, :, k) = apply_mask_update( ...
            Lendo(:, :, k), new_mask, display_crop, replace_entire_slice);
        show_current_correction_masks( ...
            ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range);
    end

    current_mask = Rendo(display_crop.rows, display_crop.columns, k);
    [new_mask, did_update, replace_entire_slice] = correct_one_mask( ...
        ax, display_image, current_mask, 'RV endocardium', 'c', gs_range);
    if did_update
        Rendo(:, :, k) = apply_mask_update( ...
            Rendo(:, :, k), new_mask, display_crop, replace_entire_slice);
        show_current_correction_masks( ...
            ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range);
    end

    current_mask = Epi(display_crop.rows, display_crop.columns, k);
    [new_mask, did_update, replace_entire_slice] = correct_one_mask( ...
        ax, display_image, current_mask, 'Epicardium', 'g', gs_range);
    if did_update
        Epi(:, :, k) = apply_mask_update( ...
            Epi(:, :, k), new_mask, display_crop, replace_entire_slice);
        show_current_correction_masks( ...
            ax, display_image, k, Lendo, Rendo, Epi, lepi, has_lepi, display_crop, gs_range);
    end

    if has_lepi
        current_mask = lepi(display_crop.rows, display_crop.columns, k);
        [new_mask, did_update, replace_entire_slice] = correct_one_mask( ...
            ax, display_image, current_mask, 'LV epicardium', 'b', gs_range);
        if did_update
            lepi(:, :, k) = apply_mask_update( ...
                lepi(:, :, k), new_mask, display_crop, replace_entire_slice);
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
    title(ax, sprintf('Slice %d correction preview', k));
    drawnow;
end

function [mask, did_update, replace_entire_slice] = correct_one_mask( ...
        ax, Im, current_mask, structure_name, color, gs_range)
    did_update = false;
    replace_entire_slice = false;
    mask = logical(current_mask);

    figure_handle = ancestor(ax, 'figure');
    action = choose_review_action(figure_handle, ...
        sprintf('%s action', structure_name), ...
        {'Keep', 'keep'; 'Edit', 'edit'; 'Redraw', 'redraw'; 'Clear', 'clear'});

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
        [mask, did_update] = edit_existing_mask(ax, Im, current_mask, color, gs_range);
        return;
    end

    if strcmp(action, 'redraw')
        mask = redraw_mask_components(ax, Im, color, gs_range);
        did_update = true;
        replace_entire_slice = true;
        return;
    end
end

function [mask, did_update] = edit_existing_mask(ax, Im, current_mask, color, gs_range)
mask = logical(current_mask);
did_update = false;
contours = vtseg.mask_to_editable_contours(mask);
if isempty(contours)
    fprintf('This mask is empty. Use redraw to create it from scratch.\n');
    return;
end

[display_gs_range, contour_width] = current_review_display_settings(ax, gs_range);
cla(ax);
imshow(Im, display_gs_range, 'Parent', ax);
hold(ax, 'on');
plot_mask_contour(ax, mask, color, contour_width);

rois = cell(numel(contours), 1);
for index = 1:numel(contours)
    rois{index} = drawpolygon(ax, ...
        'Position', contours(index).Position, ...
        'Color', color, ...
        'LineWidth', contour_width, ...
        'FaceAlpha', 0.10);
end
title(ax, 'Drag contour vertices, then accept or cancel below');

figure_handle = ancestor(ax, 'figure');
setappdata(figure_handle, 'vtsegActiveEditRois', rois);
set_active_edit_roi_visibility(figure_handle, contour_width > 0);
setappdata(figure_handle, 'vtsegContourEditAction', '');
accept_button = uicontrol(figure_handle, ...
    'Style', 'pushbutton', ...
    'String', 'Accept contour edits', ...
    'Units', 'normalized', ...
    'Position', [0.62 0.02 0.20 0.055], ...
    'Callback', @(~, ~) finish_contour_edit(figure_handle, 'accept'));
cancel_button = uicontrol(figure_handle, ...
    'Style', 'pushbutton', ...
    'String', 'Cancel', ...
    'Units', 'normalized', ...
    'Position', [0.83 0.02 0.12 0.055], ...
    'Callback', @(~, ~) finish_contour_edit(figure_handle, 'cancel'));
uiwait(figure_handle);

if ~isvalid(figure_handle)
    return;
end
action = getappdata(figure_handle, 'vtsegContourEditAction');
if isappdata(figure_handle, 'vtsegActiveEditRois')
    rmappdata(figure_handle, 'vtsegActiveEditRois');
end
if isvalid(accept_button)
    delete(accept_button);
end
if isvalid(cancel_button)
    delete(cancel_button);
end
if ~strcmp(action, 'accept')
    return;
end

edited_contours = contours;
kept = false(numel(rois), 1);
for index = 1:numel(rois)
    if ~isempty(rois{index}) && isvalid(rois{index}) && size(rois{index}.Position, 1) >= 3
        edited_contours(index).Position = rois{index}.Position;
        kept(index) = true;
    end
end
edited_contours = edited_contours(kept);
mask = vtseg.editable_contours_to_mask(edited_contours, size(Im));
did_update = true;
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

function action = choose_review_action(figure_handle, prompt, choices)
%CHOOSE_REVIEW_ACTION Present one modal action panel inside the review figure.
action = 'cancel';
if ~isvalid(figure_handle)
    return;
end

setappdata(figure_handle, 'vtsegReviewChoice', '');
panel = uipanel(figure_handle, 'Units', 'normalized', ...
    'Position', [0.74 0.05 0.23 0.18], 'Title', prompt, ...
    'BackgroundColor', 'w');
choice_count = size(choices, 1);
for index = 1:choice_count
    row = floor((index - 1) / 2);
    column = mod(index - 1, 2);
    width = 0.42;
    height = 0.30;
    x = 0.06 + column * 0.47;
    y = 0.58 - row * 0.36;
    uicontrol(panel, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [x y width height], 'String', choices{index, 1}, ...
        'Callback', @(~, ~) finish_review_action(figure_handle, choices{index, 2}));
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
    Im = dicomread(f_info);
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

    title(ax, sprintf('Slice %d: %s', k, file_name), 'Interpreter', 'none');
    drawnow;
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
            contour(ax, mask, [0.5 0.5], color, ...
                'LineWidth', 1.5, 'Visible', 'off');
        else
            contour(ax, mask, [0.5 0.5], color, 'LineWidth', line_width);
        end
    end
end

function plot_final_segmentation_overview( ...
        path_image, folder, n_slices, gs_range, Lendo, Rendo, Epi, seg_path, display_crop)

    slice_labels = load_export_slice_labels(seg_path, folder, n_slices);

    n_cols = ceil(sqrt(n_slices));
    n_rows = ceil(n_slices / n_cols);

    figure('Name', 'Final segmentation');
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

        title(slice_labels{k}, 'Interpreter', 'none', 'FontSize', 8);
    end

    sgtitle('Final segmentation contours: Epi green, Lendo red, Rendo cyan');

    figure('Name', 'Final segmentation - raw images');
    tiledlayout(n_rows, n_cols, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    for k = 1:n_slices
        Im = read_slice_image(path_image, folder(k).name);

        nexttile;
        imshow(Im(display_crop.rows, display_crop.columns), gs_range);
        title(slice_labels{k}, 'Interpreter', 'none', 'FontSize', 8);
    end

    sgtitle('Final segmentation crop: raw images');
end

function labels = load_export_slice_labels(seg_path, folder, n_slices)
% Match each compact MATLAB mask index to its base-to-apex source position.
labels = cell(n_slices, 1);
for k = 1:n_slices
    labels{k} = {sprintf('Mask %d', k), folder(k).name};
end

manifest_path = fullfile(seg_path, 'bivme_export_manifest.json');
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

function Im = read_slice_image(path_image, file_name)
    f = strcat(path_image, file_name);
    f_info = dicominfo(f);
    Im = dicomread(f_info);
end
