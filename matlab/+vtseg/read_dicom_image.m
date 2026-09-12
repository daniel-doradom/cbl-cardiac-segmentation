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
slope = vtseg.dicom_numeric_value(info, 'RescaleSlope', 1);
intercept = vtseg.dicom_numeric_value(info, 'RescaleIntercept', 0);
image = double(pixels) .* slope + intercept;
end
