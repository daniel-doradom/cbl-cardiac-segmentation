function [dense_contours, changed] = deform_editable_contours(original_contours, edited_contours)
%DEFORM_EDITABLE_CONTOURS Smoothly apply control-point movement to dense boundaries.
%
% The sparse controls produced by mask_to_editable_contours carry the native
% pixel boundary in DensePosition. Moving a control point is interpolated
% around that closed boundary. With no moved controls, the caller can retain
% its source mask bit-for-bit.
%
% The polygon editor lets a reviewer add or delete vertices as well as drag
% them, so the edited polygon may not have the same vertex count as the
% controls it started from. When counts differ, each edited vertex is paired
% with an original control when the two are mutual nearest neighbours; an
% unpaired edited vertex is a new control anchored to the closest point of the
% dense boundary; an unpaired original control was deleted and simply drops
% out. Deleting controls without moving anything therefore changes nothing.

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

    dense_position = original.DensePosition;
    parameters = double(original.DenseParameter(:));
    if numel(parameters) ~= size(dense_position, 1)
        parameters = closed_parameters(dense_position);
    end
    control_parameters = double(original.SampleParameter(:));
    if numel(control_parameters) ~= size(original.Position, 1)
        control_parameters = linspace(0, 1, size(original.Position, 1) + 1)';
        control_parameters(end) = [];
    end

    if size(edited.Position, 1) == size(original.Position, 1)
        displacement = edited.Position - original.Position;
    else
        [control_parameters, displacement] = match_changed_controls( ...
            original.Position, control_parameters, edited.Position, ...
            dense_position, parameters);
    end

    if isempty(displacement) || ~any(abs(displacement(:)) > 1e-9)
        dense_contours(index).Position = dense_position;
        continue;
    end
    changed = true;
    dense_contours(index).Position = dense_position + periodic_interpolate( ...
        control_parameters, displacement, parameters);
end
end

function [control_parameters, displacement] = match_changed_controls( ...
        original_position, original_parameters, edited_position, dense_position, dense_parameters)
%MATCH_CHANGED_CONTROLS Controls for an edited polygon whose vertex count changed.
original_count = size(original_position, 1);
edited_count = size(edited_position, 1);
distance = sqrt( ...
    (edited_position(:, 1) - original_position(:, 1)') .^ 2 + ...
    (edited_position(:, 2) - original_position(:, 2)') .^ 2);          % edited x original
[~, nearest_original] = min(distance, [], 2);
[~, nearest_edited] = min(distance, [], 1);

control_parameters = zeros(0, 1);
displacement = zeros(0, 2);
for edited_index = 1:edited_count
    original_index = nearest_original(edited_index);
    if original_count > 0 && nearest_edited(original_index) == edited_index
        % Mutual nearest neighbours: this vertex is that control, possibly moved.
        control_parameters(end + 1, 1) = original_parameters(original_index); %#ok<AGROW>
        displacement(end + 1, :) = edited_position(edited_index, :) ...
            - original_position(original_index, :); %#ok<AGROW>
    else
        % A vertex the reviewer added: anchor it to the nearest dense point.
        dense_distance = sum((dense_position - edited_position(edited_index, :)) .^ 2, 2);
        [~, nearest_dense] = min(dense_distance);
        shift = edited_position(edited_index, :) - dense_position(nearest_dense, :);
        if norm(shift) >= 0.25
            control_parameters(end + 1, 1) = dense_parameters(nearest_dense); %#ok<AGROW>
            displacement(end + 1, :) = shift; %#ok<AGROW>
        end
    end
end
% Two vertices may anchor to one parameter; interp1 needs unique sample points.
[control_parameters, keep] = unique(control_parameters, 'stable');
displacement = displacement(keep, :);
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
