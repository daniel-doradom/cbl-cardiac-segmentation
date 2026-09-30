function [stack, details] = offset_mask_stretch_slices(masks, structure, slices, ...
        pixel_spacing, points, source_slice, offset_mm, fade_mm)
%OFFSET_MASK_STRETCH_SLICES Carry a one-stretch grow/shrink to other slices.
%   [stack, details] = vtseg.offset_mask_stretch_slices(masks, structure, ...
%       slices, pixel_spacing, points, source_slice, offset_mm, fade_mm)
%
%   points is 3x2 [x y] in full-image coordinates on source_slice: the two
%   ends of the stretch and a point in its middle. On each slice in slices
%   the three points are moved by how far the LV centre moved between the
%   two slices, then vtseg.offset_mask_stretch snaps them to that slice's
%   outline and applies the offset with that slice's neighbour limits. Moving
%   points, rather than an angle range, keeps the stretch on the chosen side
%   of a crescent such as the RV, whose outline a ray from the LV centre
%   crosses twice. When a slice has no LV, the structure's own centre is
%   used on both slices instead.
%
%   masks is a struct of full 3D stacks Lendo, Rendo, Epi and lepi (lepi may
%   be empty). A slice without the structure is skipped, as is one where
%   the moved points give no valid stretch or a shrink would erase it.
%   details has one entry per slice like vtseg.offset_mask_slices, plus
%   StretchLengthMm.

if ~isfield(masks, structure) || isempty(masks.(structure))
    error('vtseg:OffsetStructure', 'masks has no "%s" stack.', structure);
end
stack = logical(masks.(structure));
slice_count = size(stack, 3);
slices = unique(round(double(slices(:)')));
if any(slices < 1 | slices > slice_count)
    error('vtseg:OffsetSlices', 'Slices must lie between 1 and %d.', slice_count);
end
if ~isequal(size(points), [3, 2])
    error('vtseg:StretchPoints', 'points must be 3x2 [x y].');
end
lepi = [];
if isfield(masks, 'lepi')
    lepi = masks.lepi;
end

template = struct('Slice', NaN, 'Changed', false, 'Skipped', '', ...
    'AddedPixels', 0, 'RemovedPixels', 0, 'BlockedPixels', 0, ...
    'AreaChangeMm2', 0, 'ComponentCount', 0, 'StretchLengthMm', NaN);
details = repmat(template, numel(slices), 1);
for index = 1:numel(slices)
    k = slices(index);
    entry = template;
    entry.Slice = k;
    current = stack(:, :, k);
    if ~any(current(:))
        entry.Skipped = 'no mask on this slice';
        details(index) = entry;
        continue;
    end
    shift = centre_shift(masks.Lendo, stack, source_slice, k);
    moved = points + shift;
    lepi_slice = [];
    if ~isempty(lepi)
        lepi_slice = lepi(:, :, k);
    end
    limits = vtseg.mask_offset_limits(structure, masks.Lendo(:, :, k), ...
        masks.Rendo(:, :, k), masks.Epi(:, :, k), lepi_slice);
    try
        [offset, info] = vtseg.offset_mask_stretch( ...
            current, pixel_spacing, moved, offset_mm, fade_mm, limits);
    catch failure
        entry.Skipped = sprintf('no valid stretch (%s)', failure.message);
        details(index) = entry;
        continue;
    end
    entry.BlockedPixels = info.BlockedPixels;
    entry.StretchLengthMm = info.StretchLengthMm;
    if ~any(offset(:))
        entry.Skipped = 'would remove the whole structure';
        details(index) = entry;
        continue;
    end
    entry.AddedPixels = info.AddedPixels;
    entry.RemovedPixels = info.RemovedPixels;
    entry.AreaChangeMm2 = info.AreaChangeMm2;
    entry.ComponentCount = info.ComponentCount;
    entry.Changed = info.AddedPixels > 0 || info.RemovedPixels > 0;
    stack(:, :, k) = offset;
    details(index) = entry;
end
end

function shift = centre_shift(lv_stack, stack, source_slice, k)
%CENTRE_SHIFT [dx dy] from the source slice's centre to slice k's centre.
% The LV centre is used when both slices have an LV, else the structure's.
source = centre(lv_stack(:, :, source_slice));
target = centre(lv_stack(:, :, k));
if any(isnan([source, target]))
    source = centre(stack(:, :, source_slice));
    target = centre(stack(:, :, k));
end
if any(isnan([source, target]))
    shift = [0, 0];
else
    shift = target - source;
end
end

function point = centre(mask)
[rows, columns] = find(mask);
if isempty(rows)
    point = [NaN, NaN];
else
    point = [mean(columns), mean(rows)];
end
end
