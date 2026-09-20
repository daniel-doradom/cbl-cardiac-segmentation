function audit_path = save_component_review_audit(seg_path, actions)
%SAVE_COMPONENT_REVIEW_AUDIT Save accepted component actions beside work/.

seg_path = char(seg_path);
vtseg.assert_editable_matlab_path(seg_path);
work_path = fileparts(strip_trailing_separator(seg_path));
audit_path = fullfile(work_path, 'component_review_audit.json');
if isempty(actions)
    return;
end

existing_actions = struct([]);
if isfile(audit_path)
    try
        existing = jsondecode(fileread(audit_path));
        if isfield(existing, 'actions')
            existing_actions = existing.actions;
        end
    catch audit_error
        warning('vtseg:ComponentAuditRead', ...
            'Could not read the existing component audit (%s). Replacing it.', ...
            audit_error.message);
    end
end
all_actions = append_actions(existing_actions, actions);
audit = struct( ...
    'schema_version', 1, ...
    'updated_at', utc_timestamp(), ...
    'actions', all_actions);

file_id = fopen(audit_path, 'w');
if file_id < 0
    error('vtseg:ComponentAuditWrite', 'Unable to write %s.', audit_path);
end
cleanup = onCleanup(@() fclose(file_id));
fprintf(file_id, '%s\n', jsonencode(audit));
end

function combined = append_actions(existing, added)
if isempty(existing)
    combined = added;
elseif isempty(added)
    combined = existing;
else
    combined = [existing(:); added(:)];
end
end

function value = utc_timestamp()
value = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
end

function path = strip_trailing_separator(path)
while numel(path) > 1 && ismember(path(end), ['/' char(92)])
    path(end) = [];
end
end
