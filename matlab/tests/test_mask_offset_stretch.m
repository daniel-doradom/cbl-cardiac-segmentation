function tests = test_mask_offset_stretch
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

% A disk of radius 20 centred at (x=60, y=60). Top and bottom points are the
% ends; a right or left point picks the side.
function points = side(which)
top = [60, 40]; bottom = [60, 80];
if strcmp(which, 'right'), points = [top; bottom; 80, 60]; else, points = [top; bottom; 40, 60]; end
end

function testZeroOffsetChangesNothing(testCase)
mask = disk();
offset = vtseg.offset_mask_stretch(mask, [1, 1], side('right'), 0, 5);
verifyEqual(testCase, offset, mask);
end

function testGrowOnlyMovesTheChosenSide(testCase)
mask = disk();
offset = vtseg.offset_mask_stretch(mask, [1, 1], side('right'), 4, 5);
added = offset & ~mask;
[~, columns] = find(added);
verifyNotEmpty(testCase, columns);
verifyGreaterThanOrEqual(testCase, min(columns), 60, 'Nothing may grow on the left side.');
end

function testThirdPointPicksTheOtherSide(testCase)
mask = disk();
offset = vtseg.offset_mask_stretch(mask, [1, 1], side('left'), 4, 5);
[~, columns] = find(offset & ~mask);
verifyLessThanOrEqual(testCase, max(columns), 60, 'Nothing may grow on the right side.');
end

function testFullOffsetInTheMiddleAndFadeAtTheEnds(testCase)
mask = disk();
offset = vtseg.offset_mask_stretch(mask, [1, 1], side('right'), 4, 8);
verifyEqual(testCase, nnz(offset(60, 81:90)), 4, 'The middle moves the full 4 mm.');
verifyEqual(testCase, nnz(offset(:, 60) & ~mask(:, 60)), 0, 'The ends do not move.');
end

function testShrinkOnlyTheChosenSide(testCase)
mask = disk();
offset = vtseg.offset_mask_stretch(mask, [1, 1], side('right'), -4, 5);
verifyFalse(testCase, any(offset(~mask)), 'Shrinking never adds a pixel.');
[~, columns] = find(mask & ~offset);
verifyGreaterThanOrEqual(testCase, min(columns), 60, 'Nothing may shrink on the left side.');
verifyEqual(testCase, nnz(mask(60, :) & ~offset(60, :)), 4, 'The middle shrinks the full 4 mm.');
end

function testClicksOffTheOutlineSnapToIt(testCase)
mask = disk();
exact = vtseg.offset_mask_stretch(mask, [1, 1], side('right'), 3, 5);
rough = vtseg.offset_mask_stretch(mask, [1, 1], [60, 33; 60, 88; 97, 60], 3, 5);
verifyEqual(testCase, rough, exact);
end

function testGrowStopsAtBlockedNeighbour(testCase)
mask = disk();
neighbour = false(120); neighbour(:, 83:120) = true;
[offset, details] = vtseg.offset_mask_stretch(mask, [1, 1], side('right'), 5, 5, ...
    struct('blocked', neighbour));
verifyFalse(testCase, any(offset(neighbour & ~mask)));
verifyGreaterThan(testCase, details.BlockedPixels, 0);
end

function testShrinkKeepsProtectedPixels(testCase)
mask = disk();
inner = disk(); inner(:, 1:78) = false; inner = inner & disk(18);
offset = vtseg.offset_mask_stretch(mask, [1, 1], side('right'), -4, 5, ...
    struct('protected', inner));
verifyTrue(testCase, all(offset(inner)));
end

function testMillimetreScaling(testCase)
mask = disk();
offset = vtseg.offset_mask_stretch(mask, [0.5, 0.5], side('right'), 2, 2);
verifyEqual(testCase, nnz(offset(60, 81:95)), 4, '2 mm at 0.5 mm pixels is 4 pixels.');
end

function testReportsTheStretch(testCase)
[~, details, stretch] = vtseg.offset_mask_stretch(disk(), [1, 1], side('right'), 3, 5);
verifyEqual(testCase, stretch.LengthMm, pi * 20, 'RelTol', 0.15);
verifyEqual(testCase, details.StretchLengthMm, stretch.LengthMm);
verifyEqual(testCase, size(stretch.Points, 1), numel(stretch.Weights));
verifyEqual(testCase, max(stretch.Weights), 1, 'AbsTol', 1e-9);
verifyEqual(testCase, stretch.Weights([1, end]), [0; 0], 'AbsTol', 1e-9);
end

function testOnlyTheClickedPieceMoves(testCase)
mask = disk();
[rr, cc] = ndgrid(1:120, 1:120);
other = hypot(rr - 15, cc - 15) <= 6;
offset = vtseg.offset_mask_stretch(mask | other, [1, 1], side('right'), 4, 5);
verifyEqual(testCase, offset(1:30, 1:30), other(1:30, 1:30), 'The far piece is untouched.');
end

function testEndsThatSnapTogetherAreRejected(testCase)
verifyError(testCase, @() vtseg.offset_mask_stretch(disk(), [1, 1], ...
    [60, 40; 60.2, 40.1; 80, 60], 3, 5), 'vtseg:StretchEnds');
end

function mask = disk(radius)
if nargin < 1, radius = 20; end
[rr, cc] = ndgrid(1:120, 1:120);
mask = hypot(rr - 60, cc - 60) <= radius;
end
