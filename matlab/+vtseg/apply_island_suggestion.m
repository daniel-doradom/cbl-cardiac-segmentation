function [masks, detail] = apply_island_suggestion(masks, request, slice, pixel_spacing, match_mm)
%APPLY_ISLAND_SUGGESTION Repeat a Review Islands change from a neighbouring slice.
%   [masks, detail] = vtseg.apply_island_suggestion(masks, request, slice, ...
%       pixel_spacing, match_mm)
%
%   masks is a struct of full 3D stacks Lendo, Rendo, Epi and lepi. request
%   has Structure, SourceSlice and Islands, a struct with
%     KeepLargest     true: keep only the largest piece on this slice
%     FillAllHoles    true: fill every enclosed hole on this slice
%     RemovedPoints   Nx2 [x y] full-image centres of islands removed on the
%                     source slice
%     FilledPoints    Mx2 [x y] full-image centres of holes filled there
%     Connectivity    4 or 8, as used in Review Islands
%   The rules apply as they are. The points are moved by how far the LV
%   centre moved between the two slices, and each one picks the nearest
%   island (any piece but the largest) or hole within match_mm (default
%   10 mm); a point with nothing that close picks nothing. The largest piece
%   is never removed.
%
%   detail reports Structure, Slice, Changed, Skipped, RemovedCount,
%   FilledCount, OriginalComponentCount, FinalComponentCount,
%   RemovedAreasPixels/Mm2, FilledHoleAreasPixels/Mm2, AddedPixels,
%   RemovedPixels and AreaChangeMm2.

if nargin < 5 || isempty(match_mm)
    match_mm = 10;
end
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
shift = centre_shift(masks.Lendo, masks.(structure), request.SourceSlice, slice);
components = vtseg.analyze_mask_components(mask, pixel_spacing, connectivity);
holes = vtseg.analyze_mask_holes(mask, pixel_spacing, connectivity);
detail.OriginalComponentCount = components.Count;

remove = false(components.Count, 1);
candidates = setdiff(1:components.Count, components.LargestIndex);
if islands.KeepLargest
    remove(candidates) = true;
else
    remove(pick(components, candidates, islands.RemovedPoints + shift)) = true;
end
fill = false(holes.Count, 1);
if islands.FillAllHoles
    fill(:) = true;
else
    fill(pick(holes, 1:holes.Count, islands.FilledPoints + shift)) = true;
end

result = mask;
for index = find(remove)'
    result(components.PixelIdxList{index}) = false;
end
for index = find(fill)'
    result(holes.PixelIdxList{index}) = true;
end
pixel_area = prod(pixel_spacing);
detail.RemovedCount = nnz(remove);
detail.FilledCount = nnz(fill);
detail.RemovedAreasPixels = components.AreasPixels(remove);
detail.RemovedAreasMm2 = components.AreasMm2(remove);
detail.FilledHoleAreasPixels = holes.AreasPixels(fill);
detail.FilledHoleAreasMm2 = holes.AreasMm2(fill);
detail.AddedPixels = nnz(result & ~mask);
detail.RemovedPixels = nnz(mask & ~result);
detail.AreaChangeMm2 = (detail.AddedPixels - detail.RemovedPixels) * pixel_area;
detail.FinalComponentCount = vtseg.analyze_mask_components( ...
    result, pixel_spacing, connectivity).Count;
detail.Changed = detail.AddedPixels > 0 || detail.RemovedPixels > 0;
if ~detail.Changed
    detail.Skipped = 'no matching island or hole on this slice';
end
masks.(structure)(:, :, slice) = result;

    function chosen = pick(regions, allowed, points)
        % For each point, the nearest allowed region within match_mm.
        chosen = [];
        for point_index = 1:size(points, 1)
            best = inf;
            best_index = [];
            for region = allowed(:)'
                [rows, columns] = ind2sub(regions.ImageSize, regions.PixelIdxList{region});
                distance = min(hypot((rows - points(point_index, 2)) * pixel_spacing(1), ...
                    (columns - points(point_index, 1)) * pixel_spacing(2)));
                if distance < best
                    best = distance;
                    best_index = region;
                end
            end
            if best <= match_mm
                chosen(end + 1) = best_index; %#ok<AGROW>
            end
        end
        chosen = unique(chosen);
    end
end

function shift = centre_shift(lv_stack, stack, source_slice, k)
%CENTRE_SHIFT [dx dy] from the source slice's centre to slice k's centre,
% using the LV when both slices have one and the structure otherwise.
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
