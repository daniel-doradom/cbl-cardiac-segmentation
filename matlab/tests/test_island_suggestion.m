function tests = test_island_suggestion
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

% Three slices. The RV is a disk with a small island to its right and an
% enclosed hole; everything moves 4 px right per slice.
function masks = fixture()
[rr, cc] = ndgrid(1:100, 1:140);
Lendo = false(100, 140, 3); Rendo = Lendo; Epi = Lendo;
for k = 1:3
    x = 4 * (k - 1);
    Lendo(:, :, k) = hypot(rr - 50, cc - (30 + x)) <= 10;
    rv = hypot(rr - 50, cc - (65 + x)) <= 15 & ~(hypot(rr - 50, cc - (65 + x)) <= 3);
    rv = rv | hypot(rr - 50, cc - (90 + x)) <= 2;      % island to the right
    rv = rv | hypot(rr - 20, cc - (65 + x)) <= 2;      % island above
    Rendo(:, :, k) = rv;
    Epi(:, :, k) = hypot(rr - 50, cc - (50 + x)) <= 45;
end
masks = struct('Lendo', Lendo, 'Rendo', Rendo, 'Epi', Epi, 'lepi', []);
end

function request = islands(keep_largest, fill_all, removed, filled)
request = struct('Structure', 'Rendo', 'SourceSlice', 1, 'Islands', struct( ...
    'KeepLargest', keep_largest, 'FillAllHoles', fill_all, 'RemovedPoints', removed, ...
    'FilledPoints', filled, 'Connectivity', 4));
end

function testKeepLargestRemovesEveryIsland(testCase)
masks = fixture();
[after, detail] = vtseg.apply_island_suggestion(masks, islands(true, false, zeros(0, 2), zeros(0, 2)), 2, [1, 1]);
verifyEqual(testCase, detail.RemovedCount, 2);
verifyEqual(testCase, detail.FinalComponentCount, 1);
verifyFalse(testCase, after.Rendo(50, 94, 2));
verifyTrue(testCase, after.Rendo(50, 69 + 10, 2), 'The main piece stays.');
end

function testRemovedIslandIsMatchedAfterTheHeartMoves(testCase)
masks = fixture();
% On slice 1 the right island was centred at x = 90, y = 50.
[after, detail] = vtseg.apply_island_suggestion(masks, islands(false, false, [90, 50], zeros(0, 2)), 3, [1, 1]);
verifyEqual(testCase, detail.RemovedCount, 1);
verifyFalse(testCase, after.Rendo(50, 98, 3), 'The right island moved to x = 98 and is removed.');
verifyTrue(testCase, after.Rendo(20, 73, 3), 'The island above stays.');
end

function testPointWithNothingCloseRemovesNothing(testCase)
masks = fixture();
[after, detail] = vtseg.apply_island_suggestion(masks, islands(false, false, [10, 90], zeros(0, 2)), 2, [1, 1]);
verifyEqual(testCase, after.Rendo, masks.Rendo);
verifyFalse(testCase, detail.Changed);
verifyEqual(testCase, detail.Skipped, 'no matching island or hole on this slice');
end

function testTheLargestPieceIsNeverRemoved(testCase)
masks = fixture();
[after, ~] = vtseg.apply_island_suggestion(masks, islands(false, false, [65, 50], zeros(0, 2)), 2, [1, 1]);
verifyTrue(testCase, after.Rendo(50, 69 + 8, 2));
end

function testFilledHoleIsMatched(testCase)
masks = fixture();
[after, detail] = vtseg.apply_island_suggestion(masks, islands(false, false, zeros(0, 2), [65, 50]), 2, [1, 1]);
verifyEqual(testCase, detail.FilledCount, 1);
verifyTrue(testCase, after.Rendo(50, 69, 2), 'The hole moved to x = 69 and is filled.');
end

function testFillAllHoles(testCase)
masks = fixture();
[after, detail] = vtseg.apply_island_suggestion(masks, islands(false, true, zeros(0, 2), zeros(0, 2)), 3, [1, 1]);
verifyEqual(testCase, detail.FilledCount, 1);
verifyTrue(testCase, after.Rendo(50, 73, 3));
end

function testOnlyTheSuggestedSliceChanges(testCase)
masks = fixture();
after = vtseg.apply_island_suggestion(masks, islands(true, true, zeros(0, 2), zeros(0, 2)), 2, [1, 1]);
verifyEqual(testCase, after.Rendo(:, :, [1, 3]), masks.Rendo(:, :, [1, 3]));
end

function testEmptySliceIsSkipped(testCase)
masks = fixture();
masks.Rendo(:, :, 2) = false;
[~, detail] = vtseg.apply_island_suggestion(masks, islands(true, false, zeros(0, 2), zeros(0, 2)), 2, [1, 1]);
verifyEqual(testCase, detail.Skipped, 'no mask on this slice');
end
