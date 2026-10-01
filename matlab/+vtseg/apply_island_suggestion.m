function [masks, detail] = apply_island_suggestion(masks, request, slice, pixel_spacing)
%APPLY_ISLAND_SUGGESTION Repeat Keep largest / Fill all holes on another slice.
%   [masks, detail] = vtseg.apply_island_suggestion(masks, request, slice, ...
%       pixel_spacing)
%
%   masks is a struct of full 3D stacks Lendo, Rendo, Epi and lepi. request
%   has Structure and Islands, a struct with
%     KeepLargest     true: keep only the largest piece on this slice
%     FillAllHoles    true: fill every enclosed hole on this slice
%     Connectivity    4 or 8, as used in Review Islands
%   Only these two Review Islands rules are suggested; removing or filling
%   one chosen island or hole is not carried to other slices.
%
%   detail reports Structure, Slice, Changed, Skipped, RemovedCount,
%   FilledCount, OriginalComponentCount, FinalComponentCount,
%   RemovedAreasPixels/Mm2, FilledHoleAreasPixels/Mm2, AddedPixels,
%   RemovedPixels and AreaChangeMm2.

islands = request.Islands;
connectivity = islands.Connectivity;
structure = request.Structure;
detail = struct('Structure', structure, 'Slice', slice, 'Changed', false, 'Skipped', '', ...
    'RemovedCount', 0, 'FilledCount', 0, 'OriginalComponentCount', 0, ...
    'FinalComponentCount', 0, 'RemovedAreasPixels', [], 'RemovedAreasMm2', [], ...
    'FilledHoleAreasPixels', [], 'FilledHoleAreasMm2', [], ...
    'AddedPixels', 0, 'RemovedPixels', 0, 'AreaChangeMm2', 0);
mask = logical(masks.(structure)(:, :, slice));
if ~any(mask(:))
    detail.Skipped = 'no mask on this slice';
    return;
end
components = vtseg.analyze_mask_components(mask, pixel_spacing, connectivity);
holes = vtseg.analyze_mask_holes(mask, pixel_spacing, connectivity);
detail.OriginalComponentCount = components.Count;

remove = false(components.Count, 1);
if islands.KeepLargest
    remove(setdiff(1:components.Count, components.LargestIndex)) = true;
end
fill = false(holes.Count, 1);
if islands.FillAllHoles
    fill(:) = true;
end

result = mask;
for index = find(remove)'
    result(components.PixelIdxList{index}) = false;
end
for index = find(fill)'
    result(holes.PixelIdxList{index}) = true;
end
detail.RemovedCount = nnz(remove);
detail.FilledCount = nnz(fill);
detail.RemovedAreasPixels = components.AreasPixels(remove);
detail.RemovedAreasMm2 = components.AreasMm2(remove);
detail.FilledHoleAreasPixels = holes.AreasPixels(fill);
detail.FilledHoleAreasMm2 = holes.AreasMm2(fill);
detail.AddedPixels = nnz(result & ~mask);
detail.RemovedPixels = nnz(mask & ~result);
detail.AreaChangeMm2 = (detail.AddedPixels - detail.RemovedPixels) * prod(pixel_spacing);
detail.FinalComponentCount = vtseg.analyze_mask_components( ...
    result, pixel_spacing, connectivity).Count;
detail.Changed = detail.AddedPixels > 0 || detail.RemovedPixels > 0;
if ~detail.Changed
    detail.Skipped = 'no island or hole on this slice';
end
masks.(structure)(:, :, slice) = result;
end
