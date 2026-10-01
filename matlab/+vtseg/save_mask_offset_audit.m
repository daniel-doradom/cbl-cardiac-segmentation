function audit_path = save_mask_offset_audit(seg_path, records)
%SAVE_MASK_OFFSET_AUDIT Append accepted grow/shrink records beside work/.
%   audit_path = vtseg.save_mask_offset_audit(seg_path, records)
%
%   Writes <work>/mask_offset_audit.json next to component_review_audit.json.
%   records is a struct array; missing fields are filled with empty values.
%   One record per structure and slice changed: slice_number,
%   source_dicom_filename, structure, mode ('whole' or 'stretch'), offset_mm,
%   fade_mm, stretch_length_mm, set_on_slice (where the offset was chosen),
%   added_pixels, removed_pixels, blocked_pixels, area_change_mm2, timestamp,
%   accepted_suggestion (true when taken from a neighbouring slice's suggestion).

seg_path = char(seg_path);
vtseg.assert_editable_matlab_path(seg_path);
work_path = fileparts(strip_trailing_separator(seg_path));
audit_path = fullfile(work_path, 'mask_offset_audit.json');
if isempty(records)
    return;
end

existing = struct([]);
if isfile(audit_path)
    try
        previous = jsondecode(fileread(audit_path));
        if isfield(previous, 'records')
            existing = previous.records;
        end
    catch audit_error
        warning('vtseg:OffsetAuditRead', ...
            'Could not read the existing offset audit (%s). Replacing it.', audit_error.message);
    end
end
all_records = [normalize(existing); normalize(records)];
audit = struct('schema_version', 2, 'updated_at', utc_timestamp(), 'records', all_records);

file_id = fopen(audit_path, 'w');
if file_id < 0
    error('vtseg:OffsetAuditWrite', 'Unable to write %s.', audit_path);
end
cleanup = onCleanup(@() fclose(file_id));
fprintf(file_id, '%s\n', jsonencode(audit));
end

function normalized = normalize(records)
template = struct( ...
    'slice_number', NaN, 'source_dicom_filename', '', 'structure', '', ...
    'mode', '', 'offset_mm', NaN, 'fade_mm', NaN, 'stretch_length_mm', NaN, ...
    'set_on_slice', NaN, 'added_pixels', 0, 'removed_pixels', 0, ...
    'blocked_pixels', 0, 'area_change_mm2', 0, 'timestamp', '', ...
    'accepted_suggestion', false);
normalized = repmat(template, 0, 1);
names = fieldnames(template);
for index = 1:numel(records)
    record = template;
    for name_index = 1:numel(names)
        name = names{name_index};
        if isfield(records, name) && ~isempty(records(index).(name))
            record.(name) = records(index).(name);
        end
    end
    normalized(end + 1, 1) = record; %#ok<AGROW>
end
end

function path = strip_trailing_separator(path)
while numel(path) > 1 && any(path(end) == ['/', '\'])
    path = path(1:end - 1);
end
end

function value = utc_timestamp()
value = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
end
