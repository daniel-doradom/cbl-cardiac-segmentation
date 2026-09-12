function value = dicom_numeric_value(info, field_name, fallback)
%DICOM_NUMERIC_VALUE Read the first numeric DICOM value without character-code conversion.
value = fallback;
if ~isfield(info, field_name) || isempty(info.(field_name))
    return;
end
raw = info.(field_name);
if iscell(raw)
    raw = raw{1};
end
if isnumeric(raw)
    value = double(raw(1));
else
    values = split(string(raw), '\');
    value = str2double(values(1));
end
if ~isscalar(value) || ~isfinite(value)
    error('vtseg:InvalidDicomNumber', 'Invalid numeric DICOM field: %s', field_name);
end
end
