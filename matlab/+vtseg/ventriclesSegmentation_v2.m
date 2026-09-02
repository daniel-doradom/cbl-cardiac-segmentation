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
    if lower(lstr) == 'y'
        [Lendo, Rendo, Epi, lepi, save_confirmed] = review_and_correct_masks( ...
            path_image, folder, last_segmented_slice, gs_range, ...
            Lendo, Rendo, Epi, lepi, true);
    else
        [Lendo, Rendo, Epi, ~, save_confirmed] = review_and_correct_masks( ...
            path_image, folder, last_segmented_slice, gs_range, ...
            Lendo, Rendo, Epi, [], false);
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
    Lendo, Rendo, Epi, path_out);

end

function [BW, xj, yj] = draw_polygon_mask(ax, image_handle, color)
    roi = drawpolygon(ax, 'Color', color, 'LineWidth', 1, 'FaceAlpha', 0.25);
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
        Lendo, Rendo, Epi, lepi, has_lepi)

    save_confirmed = false;

    figure_handle = figure('Name', 'Review/correct masks', ...
        'NumberTitle', 'off');
    ax = axes('Parent', figure_handle);

    k = 1;

    while k <= last_segmented_slice
        if ~isvalid(figure_handle)
            disp('Review window was closed. Masks will not be saved.');
            return;
        end

        [Im, h_img] = show_slice_with_masks( ...
            ax, path_image, folder(k).name, gs_range, k, ...
            Lendo, Rendo, Epi, lepi, has_lepi);

        prompt = sprintf( ...
            'Slice %d/%d correction? [y/n/back(b)/quit/#] >> ', ...
            k, last_segmented_slice);
        str = input(prompt, 's');

        if isempty(str) || strcmpi(str, 'n')
            k = k + 1;
            continue;
        end

        target_slice = str2double(str);
        if ~isnan(target_slice)
            target_slice = round(target_slice);
            if target_slice >= 1 && target_slice <= last_segmented_slice
                k = target_slice;
            else
                fprintf('Slice must be between 1 and %d.\n', ...
                    last_segmented_slice);
            end
            continue;
        end

        if strcmpi(str, 'back') || strcmpi(str, 'b')
            k = max(1, k - 1);
            continue;
        end

        if strcmpi(str, 'quit')
            disp('Review was quit before final confirmation. Masks will not be saved.');
            return;
        end

        if strcmpi(str, 'y')
            old_Lendo = Lendo(:, :, k);
            old_Rendo = Rendo(:, :, k);
            old_Epi = Epi(:, :, k);
            if has_lepi
                old_lepi = lepi(:, :, k);
            end

            [Lendo, Rendo, Epi, lepi] = correct_slice_masks( ...
                ax, h_img, Im, k, Lendo, Rendo, Epi, lepi, has_lepi);

            show_slice_with_masks( ...
                ax, path_image, folder(k).name, gs_range, k, ...
                Lendo, Rendo, Epi, lepi, has_lepi);
            keep_str = input('Keep these corrections? [y/n] >> ', 's');

            if isempty(keep_str) || strcmpi(keep_str, 'y')
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

    save_str = input('Save reviewed/corrected masks? [y/n] >> ', 's');
    save_confirmed = isempty(save_str) || strcmpi(save_str, 'y');
end

function [Lendo, Rendo, Epi, lepi] = correct_slice_masks( ...
        ax, h_img, Im, k, Lendo, Rendo, Epi, lepi, has_lepi)

    prompt = 'Redraw LV endocardium? [y/n/clear] >> ';
    [new_mask, did_update] = redraw_one_mask(ax, h_img, Im, prompt, 'r');
    if did_update
        Lendo(:, :, k) = new_mask;
    end

    prompt = 'Redraw RV endocardium? [y/n/clear] >> ';
    [new_mask, did_update] = redraw_one_mask(ax, h_img, Im, prompt, 'c');
    if did_update
        Rendo(:, :, k) = new_mask;
    end

    prompt = 'Redraw epicardium? [y/n/clear] >> ';
    [new_mask, did_update] = redraw_one_mask(ax, h_img, Im, prompt, 'g');
    if did_update
        Epi(:, :, k) = new_mask;
    end

    if has_lepi
        prompt = 'Redraw LV epicardium? [y/n/clear] >> ';
        [new_mask, did_update] = redraw_one_mask(ax, h_img, Im, prompt, 'b');
        if did_update
            lepi(:, :, k) = new_mask;
        end
    end
end

function [mask, did_update] = redraw_one_mask(ax, h_img, Im, prompt, color)
    did_update = false;
    mask = zeros(size(Im));

    str = input(prompt, 's');

    if isempty(str) || strcmpi(str, 'n')
        return;
    end

    did_update = true;

    if strcmpi(str, 'clear')
        return;
    end

    if strcmpi(str, 'y')
        [BW, ~, ~] = draw_polygon_mask(ax, h_img, color);
        mask = double(BW) * 100;
    else
        did_update = false;
    end
end

function [Im, h_img] = show_slice_with_masks( ...
        ax, path_image, file_name, gs_range, k, Lendo, Rendo, Epi, lepi, has_lepi)

    f = strcat(path_image, file_name);
    f_info = dicominfo(f);
    Im = dicomread(f_info);

    cla(ax);
    h_img = imshow(Im, gs_range, 'Parent', ax);
    hold(ax, 'on');

    plot_mask_contour(ax, Lendo(:, :, k), 'r');
    plot_mask_contour(ax, Rendo(:, :, k), 'c');
    plot_mask_contour(ax, Epi(:, :, k), 'g');

    if has_lepi
        plot_mask_contour(ax, lepi(:, :, k), 'b');
    end

    title(ax, sprintf( ...
        'Slice %d: LV endo red, RV endo cyan, Epi green, LV epi blue', k));
    drawnow;
end

function plot_mask_contour(ax, mask, color)
    mask = logical(mask);

    if any(mask(:))
        contour(ax, mask, [0.5 0.5], color, 'LineWidth', 1.5);
    end
end

function plot_final_segmentation_overview( ...
        path_image, folder, n_slices, gs_range, Lendo, Rendo, Epi, seg_path)

    slice_labels = load_export_slice_labels(seg_path, folder, n_slices);

    crop_str = input('Crop final contour overview? [y/n] >> ', 's');
    do_crop = strcmpi(crop_str, 'y');

    ref_slice = round(n_slices / 2);
    ref_img = read_slice_image(path_image, folder(ref_slice).name);

    x1 = 1;
    y1 = 1;
    x2 = size(ref_img, 2);
    y2 = size(ref_img, 1);

    if do_crop
        figure('Name', 'Define final overview crop');
        imshow(ref_img, gs_range);
        hold on;
        plot_mask_contour(gca, Epi(:, :, ref_slice), 'g');
        plot_mask_contour(gca, Lendo(:, :, ref_slice), 'r');
        plot_mask_contour(gca, Rendo(:, :, ref_slice), 'c');
        title(sprintf(['Draw crop box on Slice %d, ' ...
            'then double-click inside it'], ref_slice));

        h = drawrectangle('Color', 'y');
        wait(h);

        crop_pos = round(h.Position);
        x1 = max(1, crop_pos(1));
        y1 = max(1, crop_pos(2));
        x2 = min(size(ref_img, 2), x1 + crop_pos(3) - 1);
        y2 = min(size(ref_img, 1), y1 + crop_pos(4) - 1);

        close;
    end

    n_cols = ceil(sqrt(n_slices));
    n_rows = ceil(n_slices / n_cols);

    figure('Name', 'Final segmentation');
    tiledlayout(n_rows, n_cols, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    for k = 1:n_slices
        Im = read_slice_image(path_image, folder(k).name);

        nexttile;
        imshow(Im(y1:y2, x1:x2), gs_range);
        hold on;

        plot_mask_contour(gca, Epi(y1:y2, x1:x2, k), 'g');
        plot_mask_contour(gca, Lendo(y1:y2, x1:x2, k), 'r');
        plot_mask_contour(gca, Rendo(y1:y2, x1:x2, k), 'c');

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
        imshow(Im(y1:y2, x1:x2), gs_range);
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
