function [masks, details] = apply_offset_suggestion(masks, requests, slice, pixel_spacing)
%APPLY_OFFSET_SUGGESTION Repeat grow/shrink changes from a neighbouring slice.
%   [masks, details] = vtseg.apply_offset_suggestion(masks, requests, slice, ...
%       pixel_spacing)
%
%   masks is a struct of full 3D stacks Lendo, Rendo, Epi and lepi (lepi may
%   be empty). requests is a struct array of kept offsets with fields
%     Structure      'Lendo', 'Rendo', 'Epi' or 'lepi'
%     Mode           'whole' or 'stretch'
%     OffsetMm       offset in mm (positive grows)
%     FadeMm         stretch fade in mm (ignored for 'whole')
%     StretchPoints  3x2 [x y] full-image points on SourceSlice ('stretch')
%     SourceSlice    slice where the offset was chosen
%     Covered        slices that already have this offset
%   Each request is applied to slice in order, so a later structure sees the
%   neighbour limits left by an earlier one. A whole outline uses
%   vtseg.offset_mask_slices; a stretch is carried from its source slice by
%   vtseg.offset_mask_stretch_slices. A request whose Covered list already
%   holds slice is skipped, so nothing is applied twice.
%
%   details has one entry per request: Structure, Slice, Changed, Skipped
%   and the pixel and area counts of the underlying function.

template = struct('Structure', '', 'Slice', slice, 'Changed', false, 'Skipped', '', ...
    'AddedPixels', 0, 'RemovedPixels', 0, 'BlockedPixels', 0, ...
    'AreaChangeMm2', 0, 'ComponentCount', 0, 'StretchLengthMm', NaN);
details = repmat(template, numel(requests), 1);
for index = 1:numel(requests)
    request = requests(index);
    entry = template;
    entry.Structure = request.Structure;
    if ismember(slice, request.Covered)
        entry.Skipped = 'this slice already has this change';
        details(index) = entry;
        continue;
    end
    if strcmp(request.Mode, 'stretch')
        [stack, info] = vtseg.offset_mask_stretch_slices(masks, request.Structure, slice, ...
            pixel_spacing, request.StretchPoints, request.SourceSlice, ...
            request.OffsetMm, request.FadeMm);
    else
        [stack, info] = vtseg.offset_mask_slices(masks, request.Structure, slice, ...
            pixel_spacing, request.OffsetMm);
    end
    masks.(request.Structure) = stack;
    names = fieldnames(info);
    for name_index = 1:numel(names)
        if isfield(entry, names{name_index})
            entry.(names{name_index}) = info.(names{name_index});
        end
    end
    entry.Structure = request.Structure;
    details(index) = entry;
end
end
