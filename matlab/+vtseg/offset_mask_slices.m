function [stack, details] = offset_mask_slices(masks, structure, slices, pixel_spacing, offset_mm)
%OFFSET_MASK_SLICES Grow or shrink one structure's whole outline on several slices.
%   [stack, details] = vtseg.offset_mask_slices(masks, structure, slices, ...
%       pixel_spacing, offset_mm)
%
%   masks is a struct of full 3D stacks Lendo, Rendo, Epi and lepi (lepi may
%   be empty). structure names the stack to change ('Lendo', 'Rendo', 'Epi'
%   or 'lepi'); slices lists the slice numbers to change. Each slice uses
%   vtseg.offset_mask with its own neighbour limits from
%   vtseg.mask_offset_limits, so growth stops at that slice's neighbours.
%
%   A slice without that structure is left alone, and so is a slice where a
%   shrink would remove the structure entirely. details has one entry per
%   requested slice: Slice, Changed, Skipped ('' or the reason), and the
%   AddedPixels, RemovedPixels, BlockedPixels, AreaChangeMm2 and
%   ComponentCount reported by vtseg.offset_mask.

if ~isfield(masks, structure) || isempty(masks.(structure))
    error('vtseg:OffsetStructure', 'masks has no "%s" stack.', structure);
end
stack = logical(masks.(structure));
slice_count = size(stack, 3);
slices = unique(round(double(slices(:)')));
if any(slices < 1 | slices > slice_count)
    error('vtseg:OffsetSlices', 'Slices must lie between 1 and %d.', slice_count);
end
lepi = [];
if isfield(masks, 'lepi')
    lepi = masks.lepi;
end

template = struct('Slice', NaN, 'Changed', false, 'Skipped', '', ...
    'AddedPixels', 0, 'RemovedPixels', 0, 'BlockedPixels', 0, ...
    'AreaChangeMm2', 0, 'ComponentCount', 0);
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
    lepi_slice = [];
    if ~isempty(lepi)
        lepi_slice = lepi(:, :, k);
    end
    limits = vtseg.mask_offset_limits(structure, masks.Lendo(:, :, k), ...
        masks.Rendo(:, :, k), masks.Epi(:, :, k), lepi_slice);
    [offset, info] = vtseg.offset_mask(current, pixel_spacing, offset_mm, limits);
    entry.BlockedPixels = info.BlockedPixels;
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
