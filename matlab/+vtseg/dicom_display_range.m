function gs_range = dicom_display_range(dicom_path)
%DICOM_DISPLAY_RANGE Return a WindowCenter/WindowWidth range when present.
% Empty means imshow's normal automatic range, appropriate for legacy MR data.
gs_range = [];
info = dicominfo(dicom_path);
if ~isfield(info, 'WindowCenter') || ~isfield(info, 'WindowWidth')
    return;
end
center = vtseg.dicom_numeric_value(info, 'WindowCenter', NaN);
width = vtseg.dicom_numeric_value(info, 'WindowWidth', NaN);
if isfinite(center) && isfinite(width) && width > 0
    gs_range = [center - width / 2, center + width / 2];
end
end
