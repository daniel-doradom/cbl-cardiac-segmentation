function contours = mask_to_editable_contours(mask, vertex_spacing, max_vertices, pixel_spacing, options)
%MASK_TO_EDITABLE_CONTOURS Convert a binary mask to editable polygon vertices.
%
% Each returned struct contains Position as [x y] image coordinates, an
% IsHole flag, and its nesting Depth. Boundaries are sampled at roughly
% vertex_spacing pixels by default and capped at max_vertices so drawpolygon
% remains practical to edit. When pixel_spacing is supplied as [row column]
% millimetres, vertex_spacing is interpreted in millimetres. DensePosition
% retains the original boundary so an editor can deform it without losing
% native mask detail.
%
% options is an optional struct:
%   mode      'uniform' (default) places handles at equal distances along the
%             boundary. 'simplify' places them where the boundary bends
%             (Douglas-Peucker) and only adds more where a straight or gently
%             curved stretch would otherwise leave a gap longer than
%             vertex_spacing, so a narrow crescent no longer crowds its two
%             walls with handles.
%   tolerance In 'simplify' mode, how far the dense boundary may stray from
%             the handle polygon before another handle is placed, in the same
%             unit as vertex_spacing. Default 1.
% Both modes keep every handle on the dense boundary with its arc-length
% parameter in SampleParameter, so deform_editable_contours works unchanged.

if nargin < 5 || isempty(options)
    options = struct();
end
mode = 'uniform';
if isfield(options, 'mode') && ~isempty(options.mode)
    mode = lower(char(options.mode));
end
if ~any(strcmp(mode, {'uniform', 'simplify'}))
    error('vtseg:EditableContourMode', ...
        'options.mode must be ''uniform'' or ''simplify''.');
end
tolerance = 1;
if isfield(options, 'tolerance') && ~isempty(options.tolerance)
    tolerance = double(options.tolerance);
end
if ~isscalar(tolerance) || ~isfinite(tolerance) || tolerance <= 0
    error('vtseg:EditableContourTolerance', 'options.tolerance must be a positive scalar.');
end
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

[boundaries, ~, ~, adjacency] = bwboundaries(logical(mask), 8, 'holes');
contours = repmat( ...
    struct('Position', zeros(0, 2), 'IsHole', false, 'Depth', 0, ...
        'DensePosition', zeros(0, 2), 'DenseParameter', zeros(0, 1), ...
        'SampleParameter', zeros(0, 1), 'InitialPosition', zeros(0, 2), ...
        'OriginalMask', false(size(mask))), 0, 1);

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
    if strcmp(mode, 'simplify')
        [position, sample_parameter, dense_parameter] = simplify_closed_boundary( ...
            dense_position, tolerance, vertex_spacing, max_vertices, pixel_spacing);
    else
        [position, sample_parameter, dense_parameter] = resample_closed_boundary( ...
            dense_position, vertex_spacing, max_vertices, pixel_spacing);
    end
    if size(position, 1) < 3
        continue;
    end
    % bwboundaries does not promise holes follow every outer boundary.
    % Odd nesting levels are holes; even levels are filled components.
    depth = boundary_depth(adjacency, index);
    contours(end + 1, 1) = struct( ...
        'Position', position, ...
        'IsHole', mod(depth, 2) == 1, ...
        'Depth', depth, ...
        'DensePosition', dense_position, ...
        'DenseParameter', dense_parameter, ...
        'SampleParameter', sample_parameter, ...
        'InitialPosition', position, ...
        'OriginalMask', logical(mask)); %#ok<AGROW>
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
% bwboundaries stores each boundary's parent in its row. Following these
% links gives 0 for an outer boundary, 1 for a hole, and 2 for an island.
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
% A small component can vanish when a four-point approximation is rasterized
% back onto pixels. Preserve its native boundary: it remains removable in the
% editor without making normal ventricular contours denser.
if size(points, 1) <= 12 || target_count == size(points, 1)
    sampled = points;
    sample_parameter = dense_parameter;
    return;
end

sample_at = linspace(0, perimeter, target_count + 1)';
sample_at(end) = [];
candidate_positions = [ ...
    interp1(cumulative, closed(:, 1), sample_at, 'linear'), ...
    interp1(cumulative, closed(:, 2), sample_at, 'linear')];
% Keep the established one-output unique call for backwards-compatible
% boundary ordering; the parameter lookup does not influence the polygon.
sampled = unique(candidate_positions, 'rows', 'stable');
[~, sample_indices] = ismember(sampled, candidate_positions, 'rows');
sample_parameter = sample_at(sample_indices) ./ perimeter;
end

function [sampled, sample_parameter, dense_parameter] = simplify_closed_boundary( ...
        points, tolerance, max_gap, max_vertices, pixel_spacing)
%SIMPLIFY_CLOSED_BOUNDARY Handles where the boundary bends, none where it does not.
% Uniform arc-length spacing crowds a narrow crescent: its two walls are far
% apart along the boundary but close on screen, so their handles overlap
% visually while straight stretches look sparse. Douglas-Peucker keeps a
% handle only where dropping it would move the polygon more than `tolerance`
% from the dense boundary, then any run longer than `max_gap` is split so
% every stretch stays editable. If that still exceeds max_vertices, both
% limits are relaxed together until it fits.
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
cumulative = [0; cumsum(segment_lengths)];
dense_parameter = cumulative(1:end-1) ./ perimeter;
point_count = size(points, 1);
if point_count <= 12
    sampled = points;
    sample_parameter = dense_parameter;
    return;
end

keep = false(point_count, 1);
for attempt = 1:25
    keep = douglas_peucker_closed(metric_points(1:point_count, :), tolerance);
    keep = fill_long_gaps(keep, cumulative, perimeter, max_gap);
    if nnz(keep) <= max_vertices
        break;
    end
    tolerance = tolerance * 1.5;
    max_gap = max_gap * 1.5;
end
if nnz(keep) < 3
    fallback = round(linspace(1, point_count, 4));
    keep(fallback(1:3)) = true;
end
indices = find(keep);
sampled = points(indices, :);
sample_parameter = dense_parameter(indices);
end

function keep = douglas_peucker_closed(points, tolerance)
% Anchor on the first point and the point farthest from it, then simplify
% the two open runs between them; the second run wraps back to the first point.
point_count = size(points, 1);
keep = false(point_count, 1);
distances = sqrt(sum((points - points(1, :)) .^ 2, 2));
[~, far] = max(distances);
keep(1) = true;
keep(far) = true;
keep = douglas_peucker_run(points, 1:far, tolerance, keep);
keep = douglas_peucker_run(points, [far:point_count, 1], tolerance, keep);
end

function keep = douglas_peucker_run(points, run, tolerance, keep)
stack = [1, numel(run)];
while ~isempty(stack)
    first = stack(end, 1);
    last = stack(end, 2);
    stack(end, :) = [];
    if last - first < 2
        continue;
    end
    inner = run(first + 1:last - 1);
    deviation = point_segment_distance(points(inner, :), points(run(first), :), points(run(last), :));
    [largest, at] = max(deviation);
    if largest > tolerance
        split = first + at;
        keep(run(split)) = true;
        stack(end + 1, :) = [first, split]; %#ok<AGROW>
        stack(end + 1, :) = [split, last]; %#ok<AGROW>
    end
end
end

function distance = point_segment_distance(query, segment_start, segment_end)
direction = segment_end - segment_start;
length_squared = sum(direction .^ 2);
if length_squared == 0
    distance = sqrt(sum((query - segment_start) .^ 2, 2));
    return;
end
along = ((query - segment_start) * direction') ./ length_squared;
along = max(0, min(1, along));
nearest = segment_start + along * direction;
distance = sqrt(sum((query - nearest) .^ 2, 2));
end

function keep = fill_long_gaps(keep, cumulative, perimeter, max_gap)
% Split every kept-to-kept run longer than max_gap into equal pieces, placing
% each extra handle on the dense point nearest the target arc position.
point_count = numel(keep);
kept = find(keep);
if isempty(kept)
    return;
end
for k = 1:numel(kept)
    start_index = kept(k);
    if k < numel(kept)
        gap = cumulative(kept(k + 1)) - cumulative(start_index);
    else
        gap = perimeter - cumulative(start_index) + cumulative(kept(1));
    end
    if gap <= max_gap
        continue;
    end
    pieces = ceil(gap / max_gap);
    for piece = 1:pieces - 1
        target = mod(cumulative(start_index) + gap * piece / pieces, perimeter);
        [~, nearest] = min(abs(cumulative(1:point_count) - target));
        keep(nearest) = true;
    end
end
end
