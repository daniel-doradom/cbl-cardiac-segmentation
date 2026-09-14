function [files, images, masks, names, colors, slice_metadata] = load_review_case(main_path)
%LOAD_REVIEW_CASE Read the exported DICOM stack and the four masks of a MATLAB case.
%
% raw/ must hold the DICOM subset written by vtseg and seg/ must hold
% Lendo.mat, Rendo.mat, Epi.mat and myocardium.mat. Returns the DICOM file
% list, the image stack, the masks as a cell array in the order LV blood pool,
% RV blood pool, epicardium, myocardium, their display names and colours, and
% per-slice provenance read from bivme_export_manifest.json when present.

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
