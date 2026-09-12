function image = read_dicom_image(path_or_info)
%READ_DICOM_IMAGE Read a DICOM image in modality values (HU for CT).
% MRI is unchanged because missing rescale fields default to slope 1/intercept 0.
if ischar(path_or_info) || isstring(path_or_info)
    info = dicominfo(path_or_info);
    pixels = dicomread(info);
else
    info = path_or_info;
    pixels = dicomread(info);
end
slope = 1;
intercept = 0;
if isfield(info, 'RescaleSlope') && ~isempty(info.RescaleSlope)
    slope = double(info.RescaleSlope);
end
if isfield(info, 'RescaleIntercept') && ~isempty(info.RescaleIntercept)
    intercept = double(info.RescaleIntercept);
end
image = double(pixels) .* slope + intercept;
end
