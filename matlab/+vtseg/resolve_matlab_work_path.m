function work_path = resolve_matlab_work_path(main_path)
%RESOLVE_MATLAB_WORK_PATH Resolve an export root to its editable work copy.

work_path = char(main_path);
vtseg.assert_editable_matlab_path(work_path);
if ~isfolder(fullfile(work_path, 'raw')) && isfolder(fullfile(work_path, 'work', 'raw'))
    work_path = fullfile(work_path, 'work');
end
vtseg.assert_editable_matlab_path(work_path);
end
