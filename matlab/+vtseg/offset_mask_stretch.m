function [offset, details, stretch] = offset_mask_stretch( ...
        mask, pixel_spacing, points, offset_mm, fade_mm, limits)
%OFFSET_MASK_STRETCH Grow or shrink one stretch of a mask outline, in mm.
%   [offset, details, stretch] = vtseg.offset_mask_stretch( ...
%       mask, pixel_spacing, points, offset_mm, fade_mm, limits)
%
%   points is 3x2 [x y] in image coordinates (x = column, y = row): the two
%   ends of the stretch, then one point on the side of the outline to move.
%   A closed outline splits into two arcs between the ends; the third point
%   picks one. Each point snaps to the nearest outline point of the piece
%   nearest the first click.
%
%   The full offset applies in the middle of the stretch and fades smoothly
%   to zero over fade_mm at both ends (cosine fade), so no step appears at
%   the ends. A stretch shorter than twice fade_mm fades over half its
%   length. A pixel moves by the same rule as vtseg.offset_mask, with the
%   allowed distance scaled by the fade weight of the nearest outline pixel;
%   outline pixels outside the stretch have weight zero and never move.
%   limits.blocked and limits.protected act as in vtseg.offset_mask.
%
%   stretch describes the selection for display: Points ([x y] along the
%   arc), Weights (0..1 at each point), LengthMm, and SnappedPoints (3x2).

if nargin < 5 || isempty(fade_mm)
    fade_mm = 5;
end
if nargin < 6 || isempty(limits)
    limits = struct();
end
mask = logical(mask);
pixel_spacing = double(pixel_spacing(:)');
if numel(pixel_spacing) ~= 2 || any(~isfinite(pixel_spacing)) || any(pixel_spacing <= 0)
    error('vtseg:OffsetSpacing', 'pixel_spacing must be two positive values in mm.');
end
if ~isequal(size(points), [3, 2]) || any(~isfinite(points(:)))
    error('vtseg:StretchPoints', 'points must be 3x2 [x y]: two ends, then the side to move.');
end
if ~isscalar(offset_mm) || ~isfinite(offset_mm)
    error('vtseg:OffsetValue', 'offset_mm must be one finite number.');
end
if ~isscalar(fade_mm) || ~isfinite(fade_mm) || fade_mm < 0
    error('vtseg:StretchFade', 'fade_mm must be zero or positive.');
end
if ~any(mask(:))
    error('vtseg:StretchEmpty', 'The mask is empty; there is no outline to offset.');
end

outline = nearest_outline(mask, points(1, :), pixel_spacing);
n = size(outline, 1);
snapped = zeros(3, 1);
for point_index = 1:3
    snapped(point_index) = nearest_index(outline, points(point_index, :), pixel_spacing);
end
if snapped(1) == snapped(2)
    error('vtseg:StretchEnds', 'The two ends snap to the same outline point; pick them further apart.');
end

forward = mod((snapped(1) - 1):(snapped(1) - 1 + mod(snapped(2) - snapped(1), n)), n) + 1;
if ismember(snapped(3), forward)
    arc = forward;
else
    arc = mod((snapped(2) - 1):(snapped(2) - 1 + mod(snapped(1) - snapped(2), n)), n) + 1;
    arc = fliplr(arc);
end
arc_rc = outline(arc, :);
steps = hypot(diff(arc_rc(:, 1)) * pixel_spacing(1), diff(arc_rc(:, 2)) * pixel_spacing(2));
position = [0; cumsum(steps)];
length_mm = position(end);
fade = min(fade_mm, length_mm / 2);
if fade <= 0
    weights = ones(numel(arc), 1);
else
    weights = 0.5 - 0.5 * cos(pi * min(1, min(position, length_mm - position) / fade));
end

% Weight of every edge pixel. The traced outline visits only some edge
% pixels (at a pointed tip, a pixel diagonal to the background is an edge
% pixel but is skipped), so each edge pixel next to the chosen outline takes
% the weight of the nearest traced point: the fade weight on the stretch,
% zero elsewhere on that outline. Edge pixels of holes and other pieces stay
% zero. A skipped pixel with weight zero would shield the pixels behind it.
traced = false(size(mask));
traced_weight = zeros(size(mask));
traced(sub2ind(size(mask), outline(:, 1), outline(:, 2))) = true;
arc_linear = sub2ind(size(mask), arc_rc(:, 1), arc_rc(:, 2));
for arc_index = 1:numel(arc)
    traced_weight(arc_linear(arc_index)) = max( ...
        traced_weight(arc_linear(arc_index)), weights(arc_index));
end
[traced_distance, nearest_traced] = bwdist(traced);
boundary = (mask & ~imerode(mask, true(3))) | traced;
weight_map = zeros(size(mask));
near_outline = boundary & traced_distance <= 1.5;
weight_map(near_outline) = traced_weight(nearest_traced(near_outline));
[~, nearest_boundary] = bwdist(boundary);
reach = abs(offset_mm) * weight_map(nearest_boundary);

blocked = limit_mask(limits, 'blocked', size(mask));
protected = limit_mask(limits, 'protected', size(mask));
offset = mask;
would_add = false(size(mask));
if offset_mm > 0
    would_add = ~mask & reach > 0 & distance_mm(mask, pixel_spacing) <= reach + 1e-9;
    offset = mask | (would_add & ~blocked);
elseif offset_mm < 0 && any(~mask(:))
    removable = mask & reach > 0 & distance_mm(~mask, pixel_spacing) <= reach + 1e-9;
    offset = mask & ~(removable & ~protected);
end

pixel_area = prod(pixel_spacing);
added = nnz(offset & ~mask);
removed = nnz(mask & ~offset);
components = bwconncomp(offset, 8);
details = struct( ...
    'OffsetMm', offset_mm, ...
    'FadeMm', fade, ...
    'AddedPixels', added, ...
    'RemovedPixels', removed, ...
    'BlockedPixels', nnz(would_add & blocked), ...
    'AreaChangeMm2', (added - removed) * pixel_area, ...
    'ComponentCount', components.NumObjects, ...
    'StretchLengthMm', length_mm);
stretch = struct( ...
    'Points', fliplr(arc_rc), ...
    'Weights', weights, ...
    'LengthMm', length_mm, ...
    'SnappedPoints', fliplr(outline(snapped, :)));
end

function outline = nearest_outline(mask, point, pixel_spacing)
%NEAREST_OUTLINE Outer boundary [row col] of the piece nearest the point.
boundaries = bwboundaries(mask, 8, 'noholes');
best = inf;
outline = [];
for index = 1:numel(boundaries)
    candidate = boundaries{index};
    if size(candidate, 1) > 1 && isequal(candidate(1, :), candidate(end, :))
        candidate = candidate(1:end - 1, :);
    end
    [~, distance] = nearest_index(candidate, point, pixel_spacing);
    if distance < best
        best = distance;
        outline = candidate;
    end
end
if size(outline, 1) < 3
    error('vtseg:StretchOutline', 'The selected piece is too small to offset one stretch.');
end
end

function [index, distance] = nearest_index(outline_rc, point_xy, pixel_spacing)
d = hypot((outline_rc(:, 1) - point_xy(2)) * pixel_spacing(1), ...
    (outline_rc(:, 2) - point_xy(1)) * pixel_spacing(2));
[distance, index] = min(d);
end

function distance = distance_mm(source, pixel_spacing)
[~, nearest] = bwdist(source);
[rows, columns] = ndgrid(1:size(source, 1), 1:size(source, 2));
[source_rows, source_columns] = ind2sub(size(source), double(nearest));
distance = hypot((rows - source_rows) * pixel_spacing(1), ...
    (columns - source_columns) * pixel_spacing(2));
end

function value = limit_mask(limits, name, image_size)
value = false(image_size);
if isfield(limits, name) && ~isempty(limits.(name))
    value = logical(limits.(name));
    if ~isequal(size(value), image_size)
        error('vtseg:OffsetLimitSize', 'limits.%s must match the mask size.', name);
    end
end
end
