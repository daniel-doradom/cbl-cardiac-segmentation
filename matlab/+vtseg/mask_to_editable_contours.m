function contours = mask_to_editable_contours(mask, vertex_spacing, max_vertices, pixel_spacing)
%MASK_TO_EDITABLE_CONTOURS Convert a binary mask to editable polygon vertices.
%
% Each returned struct contains Position as [x y] image coordinates, an
% IsHole flag, and its nesting Depth. Boundaries are sampled at roughly
% vertex_spacing pixels by default and capped at max_vertices so drawpolygon
% remains practical to edit. When pixel_spacing is supplied as [row column]
% millimetres, vertex_spacing is interpreted in millimetres. DensePosition
% retains the original boundary so an editor can deform it without losing
% native mask detail.

if nargin < 2 || isempty(vertex_spacing)
    vertex_spacing = 6;
end
if nargin < 3 || isempty(max_vertices)
    max_vertices = 96;
end
if nargin < 4 || isempty(pixel_spacing)
    pixel_spacing = [];
else
    pixel_spacing = double(pixel_spacing(:)');
    if numel(pixel_spacing) ~= 2 || any(~isfinite(pixel_spacing)) || any(pixel_spacing <= 0)
        error('vtseg:EditableContourPixelSpacing', ...
            'Pixel spacing must be a positive [row column] millimetre pair.');
    end
end
if ~ismatrix(mask)
    error('vtseg:EditableContourDimensions', 'Mask must be a two-dimensional array.');
end
if vertex_spacing <= 0 || max_vertices < 3
    error('vtseg:EditableContourOptions', ...
        'Vertex spacing must be positive and max_vertices must be at least 3.');
end

[boundaries, ~, object_count, adjacency] = bwboundaries(logical(mask), 8, 'holes');
contours = repmat( ...
    struct('Position', zeros(0, 2), 'IsHole', false, 'Depth', 0, ...
        'DensePosition', zeros(0, 2), 'DenseParameter', zeros(0, 1), ...
        'SampleParameter', zeros(0, 1)), 0, 1);

for index = 1:numel(boundaries)
    boundary = boundaries{index};
    if size(boundary, 1) > 1 && isequal(boundary(1, :), boundary(end, :))
        boundary(end, :) = [];
    end
    position = [double(boundary(:, 2)), double(boundary(:, 1))];
    if size(unique(position, 'rows'), 1) < 3
        position = pixel_box(position);
    end
    dense_position = position;
    [position, sample_parameter, dense_parameter] = resample_closed_boundary( ...
        dense_position, vertex_spacing, max_vertices, pixel_spacing);
    if size(position, 1) < 3
        continue;
    end
    contours(end + 1, 1) = struct( ...
        'Position', position, ...
        'IsHole', index > object_count, ...
        'Depth', boundary_depth(adjacency, index), ...
        'DensePosition', dense_position, ...
        'DenseParameter', dense_parameter, ...
        'SampleParameter', sample_parameter); %#ok<AGROW>
end
end

function position = pixel_box(position)
if isempty(position)
    return;
end
minimum = min(position, [], 1) - 0.5;
maximum = max(position, [], 1) + 0.5;
position = [ ...
    minimum(1), minimum(2); ...
    maximum(1), minimum(2); ...
    maximum(1), maximum(2); ...
    minimum(1), maximum(2)];
end

function depth = boundary_depth(adjacency, index)
depth = 0;
parent = find(adjacency(index, :), 1);
while ~isempty(parent)
    depth = depth + 1;
    parent = find(adjacency(parent, :), 1);
end
end

function [sampled, sample_parameter, dense_parameter] = resample_closed_boundary( ...
        points, vertex_spacing, max_vertices, pixel_spacing)
if size(points, 1) < 3
    sampled = points;
    sample_parameter = zeros(size(points, 1), 1);
    dense_parameter = sample_parameter;
    return;
end

closed = [points; points(1, :)];
if isempty(pixel_spacing)
    metric_points = closed;
else
    % Image positions are [x y], whereas DICOM spacing is [row column].
    metric_points = closed .* [pixel_spacing(2), pixel_spacing(1)];
end
segment_lengths = sqrt(sum(diff(metric_points, 1, 1) .^ 2, 2));
perimeter = sum(segment_lengths);
if perimeter == 0
    sampled = zeros(0, 2);
    sample_parameter = zeros(0, 1);
    dense_parameter = sample_parameter;
    return;
end

target_count = max(3, min(max_vertices, round(perimeter / vertex_spacing)));
target_count = min(target_count, size(points, 1));
cumulative = [0; cumsum(segment_lengths)];
dense_parameter = cumulative(1:end-1) ./ perimeter;
if target_count == size(points, 1)
    sampled = points;
    sample_parameter = dense_parameter;
    return;
end

sample_at = linspace(0, perimeter, target_count + 1)';
sample_at(end) = [];
sampled = [ ...
    interp1(cumulative, closed(:, 1), sample_at, 'linear'), ...
    interp1(cumulative, closed(:, 2), sample_at, 'linear')];
[sampled, keep] = unique(sampled, 'rows', 'stable');
sample_parameter = sample_at(keep) ./ perimeter;
end
