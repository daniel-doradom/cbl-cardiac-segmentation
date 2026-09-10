function mask = editable_contours_to_mask(contours, image_size)
%EDITABLE_CONTOURS_TO_MASK Rasterize editable outer and hole polygons.

if numel(image_size) ~= 2 || any(image_size < 1)
    error('vtseg:EditableContourImageSize', 'image_size must be [rows columns].');
end

mask = false(image_size);
if isempty(contours)
    return;
end
if isfield(contours, 'Depth')
    [~, order] = sort([contours.Depth]);
else
    order = 1:numel(contours);
end
for index = order
    position = contours(index).Position;
    if size(position, 1) < 3
        continue;
    end
    polygon = poly2mask(position(:, 1), position(:, 2), image_size(1), image_size(2));
    if contours(index).IsHole
        mask = mask & ~polygon;
    else
        mask = mask | polygon;
    end
end
end
