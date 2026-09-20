function assert_editable_matlab_path(path)
%ASSERT_EDITABLE_MATLAB_PATH Reject any path located under original/.

path = char(path);
parts = regexp(path, '[\\/]+', 'split');
if any(strcmpi(parts, 'original'))
    error('vtseg:ReadOnlyOriginal', ...
        'Refusing to modify the read-only original export. Select work/.');
end
end
