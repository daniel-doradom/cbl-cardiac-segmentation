function analysis = analyze_mask_holes(mask, pixel_spacing, connectivity)
%ANALYZE_MASK_HOLES Describe enclosed background regions in a 2D mask.

if nargin < 2 || isempty(pixel_spacing)
    pixel_spacing = [1, 1];
end
if nargin < 3 || isempty(connectivity)
    connectivity = 8;
end
if ndims(mask) ~= 2
    error('vtseg:HoleMaskDimensions', 'Hole review requires a 2D mask.');
end
pixel_spacing = double(pixel_spacing(:)');
if numel(pixel_spacing) ~= 2 || any(~isfinite(pixel_spacing)) || any(pixel_spacing <= 0)
    error('vtseg:HolePixelSpacing', ...
        'Pixel spacing must contain two positive finite values.');
end
if ~ismember(connectivity, [4, 8])
    error('vtseg:HoleConnectivity', 'Connectivity must be 4 or 8.');
end

mask = logical(mask);
holes = imfill(mask, 'holes') & ~mask;
connected = bwconncomp(holes, connectivity);
areas_pixels = cellfun(@numel, connected.PixelIdxList);
areas_mm2 = areas_pixels .* prod(pixel_spacing);

analysis = struct( ...
    'Count', connected.NumObjects, ...
    'PixelIdxList', {connected.PixelIdxList}, ...
    'AreasPixels', areas_pixels, ...
    'AreasMm2', areas_mm2, ...
    'ImageSize', size(mask), ...
    'PixelSpacing', pixel_spacing, ...
    'Connectivity', connectivity);
end
