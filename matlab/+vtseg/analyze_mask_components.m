function analysis = analyze_mask_components(mask, pixel_spacing)
%ANALYZE_MASK_COMPONENTS Describe 8-connected foreground components in 2D.

if nargin < 2 || isempty(pixel_spacing)
    pixel_spacing = [1, 1];
end
if ndims(mask) ~= 2
    error('vtseg:ComponentMaskDimensions', 'Component review requires a 2D mask.');
end
pixel_spacing = double(pixel_spacing(:)');
if numel(pixel_spacing) ~= 2 || any(~isfinite(pixel_spacing)) || any(pixel_spacing <= 0)
    error('vtseg:ComponentPixelSpacing', ...
        'Pixel spacing must contain two positive finite values.');
end

mask = logical(mask);
connected = bwconncomp(mask, 8);
areas_pixels = cellfun(@numel, connected.PixelIdxList);
areas_mm2 = areas_pixels .* prod(pixel_spacing);
largest_index = [];
if ~isempty(areas_pixels)
    [~, largest_index] = max(areas_pixels);
end

analysis = struct( ...
    'Count', connected.NumObjects, ...
    'PixelIdxList', {connected.PixelIdxList}, ...
    'AreasPixels', areas_pixels, ...
    'AreasMm2', areas_mm2, ...
    'LargestIndex', largest_index, ...
    'ImageSize', size(mask), ...
    'PixelSpacing', pixel_spacing);
end
