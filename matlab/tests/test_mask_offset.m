function tests = test_mask_offset
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

function testZeroOffsetChangesNothing(testCase)
mask = disk(60, 30, 30, 10);
[offset, details] = vtseg.offset_mask(mask, [1, 1], 0);
verifyEqual(testCase, offset, mask);
verifyEqual(testCase, details.AddedPixels, 0);
verifyEqual(testCase, details.RemovedPixels, 0);
end

function testGrowCircleAddsExpectedArea(testCase)
mask = disk(120, 60, 60, 20);
offset = vtseg.offset_mask(mask, [1, 1], 5);
verifyEqual(testCase, nnz(offset), nnz(disk(120, 60, 60, 25)), 'RelTol', 0.03);
verifyTrue(testCase, all(offset(mask)), 'Growing must keep every original pixel.');
end

function testShrinkCircleRemovesExpectedArea(testCase)
mask = disk(120, 60, 60, 20);
offset = vtseg.offset_mask(mask, [1, 1], -5);
verifyEqual(testCase, nnz(offset), nnz(disk(120, 60, 60, 15)), 'RelTol', 0.05);
verifyFalse(testCase, any(offset(~mask)), 'Shrinking must never add a pixel.');
end

function testOffsetIsMeasuredInMillimetres(testCase)
mask = false(40, 40);
mask(:, 1:10) = true;
half_mm = vtseg.offset_mask(mask, [0.5, 0.5], 2);
one_mm = vtseg.offset_mask(mask, [1, 1], 2);
verifyEqual(testCase, nnz(any(half_mm, 1)), 14, '2 mm at 0.5 mm pixels is 4 columns.');
verifyEqual(testCase, nnz(any(one_mm, 1)), 12, '2 mm at 1 mm pixels is 2 columns.');
end

function testStepSmallerThanAPixelChangesNothing(testCase)
mask = disk(60, 30, 30, 10);
offset = vtseg.offset_mask(mask, [1.5, 1.5], 0.5);
verifyEqual(testCase, offset, mask);
end

function testGrowStopsAtBlockedNeighbour(testCase)
mask = false(40, 40); mask(:, 1:10) = true;
neighbour = false(40, 40); neighbour(:, 13:40) = true;
[offset, details] = vtseg.offset_mask(mask, [1, 1], 5, struct('blocked', neighbour));
verifyFalse(testCase, any(offset(neighbour)), 'Growth may not enter the neighbour.');
verifyTrue(testCase, all(all(offset(:, 1:12))), 'Growth fills up to the neighbour.');
verifyEqual(testCase, details.BlockedPixels, 40 * 3);
end

function testExistingOverlapIsNotRemovedByGrow(testCase)
mask = false(40, 40); mask(:, 1:15) = true;
neighbour = false(40, 40); neighbour(:, 13:40) = true;
offset = vtseg.offset_mask(mask, [1, 1], 3, struct('blocked', neighbour));
verifyTrue(testCase, all(offset(mask)), 'Pixels already in the mask stay.');
end

function testShrinkStopsAtProtectedInterior(testCase)
mask = disk(80, 40, 40, 30);
inner = disk(80, 40, 40, 27);
[offset, details] = vtseg.offset_mask(mask, [1, 1], -5, struct('protected', inner));
verifyTrue(testCase, all(offset(inner)), 'Shrinking may not remove a protected structure.');
verifyGreaterThan(testCase, details.RemovedPixels, 0);
end

function testShrinkingAThinBandCanSplitIt(testCase)
mask = false(40, 60);
mask(10:30, 5:20) = true; mask(10:30, 40:55) = true; mask(19:21, 20:40) = true;
[~, details] = vtseg.offset_mask(mask, [1, 1], -2);
verifyEqual(testCase, details.ComponentCount, 2);
end

function testShrinkingTooFarEmptiesTheMask(testCase)
mask = disk(40, 20, 20, 4);
offset = vtseg.offset_mask(mask, [1, 1], -5);
verifyFalse(testCase, any(offset(:)));
end

function testAnisotropicPixelsUseTheirOwnSpacing(testCase)
mask = false(41, 41); mask(21, 21) = true;
offset = vtseg.offset_mask(mask, [2, 1], 2);
verifyEqual(testCase, nnz(offset(:, 21)), 3, 'Rows are 2 mm apart: one row each way.');
verifyEqual(testCase, nnz(offset(21, :)), 5, 'Columns are 1 mm apart: two columns each way.');
end

function testLimitsFollowTheAcceptanceChecks(testCase)
L = false(20, 20); L(5:10, 5:10) = true;
R = false(20, 20); R(5:10, 12:16) = true;
E = false(20, 20); E(3:12, 3:18) = true;
lv = vtseg.mask_offset_limits('Lendo', L, R, E, []);
verifyEqual(testCase, lv.blocked, R | ~E);
rv = vtseg.mask_offset_limits('Rendo', L, R, E, []);
verifyEqual(testCase, rv.blocked, L | ~E);
epi = vtseg.mask_offset_limits('Epi', L, R, E, []);
verifyFalse(testCase, any(epi.blocked(:)));
verifyEqual(testCase, epi.protected, L | R);
end

function testEmptyEpiDoesNotBlockEverything(testCase)
L = false(20, 20); L(5:10, 5:10) = true;
limits = vtseg.mask_offset_limits('Lendo', L, false(20, 20), false(20, 20), []);
verifyFalse(testCase, any(limits.blocked(:)));
end

function mask = disk(n, row, column, radius)
[rr, cc] = ndgrid(1:n, 1:n);
mask = hypot(rr - row, cc - column) <= radius;
end
