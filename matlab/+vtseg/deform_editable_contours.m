function [dense_contours, changed] = deform_editable_contours(original_contours, edited_contours)
%DEFORM_EDITABLE_CONTOURS Smoothly apply control-point movement to dense boundaries.
%
% The sparse controls produced by mask_to_editable_contours carry the native
% pixel boundary in DensePosition. Moving a control point is interpolated
% around that closed boundary. With no moved controls, the caller can retain
% its source mask bit-for-bit.

if numel(original_contours) ~= numel(edited_contours)
    error('vtseg:EditableContourCount', ...
        'Original and edited contour collections must have the same size.');
end

dense_contours = original_contours;
changed = false;
for index = 1:numel(original_contours)
    original = original_contours(index);
    edited = edited_contours(index);
    if ~isfield(original, 'DensePosition') || ~isfield(original, 'DenseParameter') || ...
            ~isfield(original, 'SampleParameter')
        error('vtseg:EditableContourMetadata', ...
            'Original contours must be created by mask_to_editable_contours.');
    end
    if size(original.Position, 1) ~= size(edited.Position, 1)
        error('vtseg:EditableContourVertices', ...
            'Editing may move control points but cannot add or remove them.');
    end

    displacement = edited.Position - original.Position;
    if ~any(abs(displacement(:)) > 1e-9)
        dense_contours(index).Position = original.DensePosition;
        continue;
    end
    changed = true;
    dense_position = original.DensePosition;
    parameters = double(original.DenseParameter(:));
    if numel(parameters) ~= size(dense_position, 1)
        parameters = closed_parameters(dense_position);
    end
    controls = double(original.SampleParameter(:));
    if numel(controls) ~= size(displacement, 1)
        controls = linspace(0, 1, size(displacement, 1) + 1)';
        controls(end) = [];
    end
    dense_contours(index).Position = dense_position + periodic_interpolate( ...
        controls, displacement, parameters);
end
end

function parameters = closed_parameters(points)
closed = [points; points(1, :)];
lengths = sqrt(sum(diff(closed, 1, 1) .^ 2, 2));
perimeter = sum(lengths);
if perimeter <= 0
    parameters = zeros(size(points, 1), 1);
else
    parameters = cumsum([0; lengths(1:end-1)]) ./ perimeter;
end
end

function values = periodic_interpolate(control_parameters, displacement, query_parameters)
% Add one copy of the first and last controls so interp1 sees the seam.
[control_parameters, order] = sort(mod(control_parameters(:), 1));
displacement = displacement(order, :);
controls = [control_parameters(end) - 1; control_parameters; control_parameters(1) + 1];
offsets = [displacement(end, :); displacement; displacement(1, :)];
query = mod(query_parameters(:), 1);
values = [ ...
    interp1(controls, offsets(:, 1), query, 'linear'), ...
    interp1(controls, offsets(:, 2), query, 'linear')];
end
