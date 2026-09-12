function gs_range = dicom_display_range(dicom_path)
%DICOM_DISPLAY_RANGE Return a WindowCenter/WindowWidth range when present.
% Empty means imshow's normal automatic range, appropriate for legacy MR data.
gs_range = [];
info = dicominfo(dicom_path);
if ~isfield(info, 'WindowCenter') || ~isfield(info, 'WindowWidth')
    return;
end
center = double(info.WindowCenter(1));
width = double(info.WindowWidth(1));
if isfinite(center) && isfinite(width) && width > 0
    gs_range = [center - width / 2, center + width / 2];
end
end
