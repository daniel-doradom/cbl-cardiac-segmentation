function tests = test_mask_offset_stretch_slices
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

% Five slices. The LV sits left, the RV right of it; both move 4 px to the
% right per slice. The stretch is the right side of the RV on slice 1.
function masks = fixture()
[rr, cc] = ndgrid(1:100, 1:140);
Lendo = false(100, 140, 5); Rendo = Lendo; Epi = Lendo;
for k = 1:5
    shift = 4 * (k - 1);
    Lendo(:, :, k) = hypot(rr - 50, cc - (35 + shift)) <= 12;
    Rendo(:, :, k) = hypot(rr - 50, cc - (65 + shift)) <= 13 - k;
    Epi(:, :, k) = hypot(rr - 50, cc - (35 + shift)) <= 18 | ...
        hypot(rr - 50, cc - (65 + shift)) <= 25 - k;
end
masks = struct('Lendo', Lendo, 'Rendo', Rendo, 'Epi', Epi, 'lepi', []);
end

function points = right_side_on_slice_one()
% Ends at the top and bottom of the slice-1 RV (radius 12), middle at its right.
points = [65, 38; 65, 62; 77, 50];
end

function testSourceSliceMatchesTheSingleSliceStretch(testCase)
masks = fixture();
stack = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 1, [1, 1], ...
    right_side_on_slice_one(), 1, 3, 4);
limits = vtseg.mask_offset_limits('Rendo', masks.Lendo(:, :, 1), masks.Rendo(:, :, 1), ...
    masks.Epi(:, :, 1), []);
expected = vtseg.offset_mask_stretch(masks.Rendo(:, :, 1), [1, 1], ...
    right_side_on_slice_one(), 3, 4, limits);
verifyEqual(testCase, stack(:, :, 1), expected);
end

function testStretchFollowsTheShiftedHeart(testCase)
masks = fixture();
[stack, details] = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 2:5, [1, 1], ...
    right_side_on_slice_one(), 1, 3, 4);
for k = 2:5
    added = stack(:, :, k) & ~masks.Rendo(:, :, k);
    [~, columns] = find(added);
    verifyNotEmpty(testCase, columns, sprintf('slice %d grows', k));
    verifyGreaterThanOrEqual(testCase, min(columns), 65 + 4 * (k - 1), ...
        sprintf('slice %d grows only on the right side of its RV', k));
end
verifyTrue(testCase, all([details.Changed]));
end

function testOtherSlicesAreUntouched(testCase)
masks = fixture();
stack = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 3, [1, 1], ...
    right_side_on_slice_one(), 1, 3, 4);
verifyEqual(testCase, stack(:, :, [1, 2, 4, 5]), masks.Rendo(:, :, [1, 2, 4, 5]));
end

function testGrowthStopsAtEachSlicesNeighbours(testCase)
masks = fixture();
stack = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 1:5, [1, 1], ...
    [65, 38; 65, 62; 53, 50], 1, 5, 2);
verifyFalse(testCase, any(stack(:) & masks.Lendo(:)), 'The RV may never grow into the LV.');
end

function testEmptySliceIsSkipped(testCase)
masks = fixture();
masks.Rendo(:, :, 4) = false;
[~, details] = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 4, [1, 1], ...
    right_side_on_slice_one(), 1, 3, 4);
verifyEqual(testCase, details.Skipped, 'no mask on this slice');
end

function testCollapsedStretchIsSkippedWithAReason(testCase)
masks = fixture();
masks.Rendo(:, :, 5) = false; masks.Rendo(50, 81, 5) = true;
[stack, details] = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 5, [1, 1], ...
    right_side_on_slice_one(), 1, 3, 4);
verifyEqual(testCase, stack(:, :, 5), masks.Rendo(:, :, 5));
verifyTrue(testCase, startsWith(details.Skipped, 'no valid stretch'));
end

function testWithoutAnLvTheStructureCentreIsUsed(testCase)
masks = fixture();
masks.Lendo(:) = false;
stack = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 5, [1, 1], ...
    right_side_on_slice_one(), 1, 3, 4);
[~, columns] = find(stack(:, :, 5) & ~masks.Rendo(:, :, 5));
verifyGreaterThanOrEqual(testCase, min(columns), 81);
end

function testCrescentStretchStaysOnTheFreeWall(testCase)
% The RV is a crescent hugging the right side of the LV: a ray from the LV
% centre crosses it twice. A free-wall stretch must stay on the outer side.
[rr, cc] = ndgrid(1:120, 1:160);
Lendo = false(120, 160, 3); Rendo = Lendo; Epi = Lendo;
for k = 1:3
    x0 = 60 + 3 * (k - 1);
    radius = hypot(rr - 60, cc - x0);
    Lendo(:, :, k) = radius <= 14;
    Rendo(:, :, k) = radius >= 20 & radius <= 32 & cc > x0 + 4;
    Epi(:, :, k) = radius <= 38;
end
masks = struct('Lendo', Lendo, 'Rendo', Rendo, 'Epi', Epi, 'lepi', []);
% Ends on the outer edge above and below, middle on the outer edge right.
points = [60 + 22, 60 - 23; 60 + 22, 60 + 23; 60 + 32, 60];
stack = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 1:3, [1, 1], points, 1, 3, 4);
for k = 1:3
    x0 = 60 + 3 * (k - 1);
    [rows, columns] = find(stack(:, :, k) & ~Rendo(:, :, k));
    verifyNotEmpty(testCase, rows, sprintf('slice %d grows', k));
    verifyGreaterThan(testCase, min(hypot(rows - 60, columns - x0)), 32, ...
        sprintf('slice %d grows outward from the free wall, not into the septum', k));
end
end
