function [offset, details] = offset_mask(mask, pixel_spacing, offset_mm, limits)
%OFFSET_MASK Grow (positive) or shrink (negative) a 2D mask by a distance in mm.
%   [offset, details] = vtseg.offset_mask(mask, pixel_spacing, offset_mm, limits)
%
%   A background pixel joins the mask when its centre lies within offset_mm
%   of a mask pixel centre; a mask pixel leaves it when its centre lies
%   within |offset_mm| of a background pixel centre. This is the same rule
%   the Python exporter uses for the CT RV free-wall collar, so a 3 mm grow
%   here matches a 3 mm collar there. Steps smaller than one pixel therefore
%   change nothing, which matters on MRI (about 1.5 mm pixels).
%
%   pixel_spacing is [row column] in mm. limits (optional) is a struct:
%     .blocked   pixels growth may never add (a neighbouring structure);
%     .protected pixels shrinking may never remove (a structure inside).
%   Growing never removes a pixel and shrinking never adds one.
%
%   details reports AddedPixels, RemovedPixels, BlockedPixels (pixels the
%   offset would have added but a neighbour stopped), AreaChangeMm2 and
%   ComponentCount (8-connected pieces after the offset).

if nargin < 2 || isempty(pixel_spacing)
    pixel_spacing = [1, 1];
end
if nargin < 4 || isempty(limits)
    limits = struct();
end
mask = logical(mask);
pixel_spacing = double(pixel_spacing(:)');
if numel(pixel_spacing) ~= 2 || any(~isfinite(pixel_spacing)) || any(pixel_spacing <= 0)
    error('vtseg:OffsetSpacing', 'pixel_spacing must be two positive values in mm.');
end
if ~isscalar(offset_mm) || ~isfinite(offset_mm)
    error('vtseg:OffsetValue', 'offset_mm must be one finite number.');
end
blocked = limit_mask(limits, 'blocked', size(mask));
protected = limit_mask(limits, 'protected', size(mask));

offset = mask;
would_add = false(size(mask));
if offset_mm > 0 && any(mask(:))
    would_add = ~mask & distance_mm(mask, pixel_spacing) <= offset_mm + 1e-9;
    offset = mask | (would_add & ~blocked);
elseif offset_mm < 0 && any(mask(:))
    if any(~mask(:))
        removable = mask & distance_mm(~mask, pixel_spacing) <= -offset_mm + 1e-9;
        offset = mask & ~(removable & ~protected);
    end
end

pixel_area = prod(pixel_spacing);
added = nnz(offset & ~mask);
removed = nnz(mask & ~offset);
components = bwconncomp(offset, 8);
details = struct( ...
    'OffsetMm', offset_mm, ...
    'AddedPixels', added, ...
    'RemovedPixels', removed, ...
    'BlockedPixels', nnz(would_add & blocked), ...
    'AreaChangeMm2', (added - removed) * pixel_area, ...
    'ComponentCount', components.NumObjects);
end

function distance = distance_mm(source, pixel_spacing)
%DISTANCE_MM Distance in mm from every pixel centre to the nearest source pixel.
% bwdist finds the nearest source pixel on the pixel grid; the distance to it
% is then measured in mm. For square pixels, as in these exports, this is
% the exact Euclidean distance.
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
