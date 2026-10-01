function tests = test_island_suggestion
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

% Three slices. The RV is a disk with two small islands and an enclosed hole.
function masks = fixture()
[rr, cc] = ndgrid(1:100, 1:140);
Lendo = false(100, 140, 3); Rendo = Lendo; Epi = Lendo;
for k = 1:3
    rv = hypot(rr - 50, cc - 65) <= 15 & ~(hypot(rr - 50, cc - 65) <= 3);
    rv = rv | hypot(rr - 50, cc - 90) <= 2 | hypot(rr - 20, cc - 65) <= 2;
    Lendo(:, :, k) = hypot(rr - 50, cc - 30) <= 10;
    Rendo(:, :, k) = rv;
    Epi(:, :, k) = hypot(rr - 50, cc - 50) <= 45;
end
masks = struct('Lendo', Lendo, 'Rendo', Rendo, 'Epi', Epi, 'lepi', []);
end

function request = rules(keep_largest, fill_all)
request = struct('Structure', 'Rendo', 'Islands', struct( ...
    'KeepLargest', keep_largest, 'FillAllHoles', fill_all, 'Connectivity', 4));
end

function testKeepLargestRemovesEveryIsland(testCase)
masks = fixture();
[after, detail] = vtseg.apply_island_suggestion(masks, rules(true, false), 2, [1, 1]);
verifyEqual(testCase, detail.RemovedCount, 2);
verifyEqual(testCase, detail.FinalComponentCount, 1);
verifyFalse(testCase, after.Rendo(50, 90, 2));
verifyTrue(testCase, after.Rendo(50, 75, 2), 'The main piece stays.');
verifyFalse(testCase, after.Rendo(50, 65, 2), 'The hole stays when only Keep largest is suggested.');
end

function testFillAllHoles(testCase)
masks = fixture();
[after, detail] = vtseg.apply_island_suggestion(masks, rules(false, true), 3, [1, 1]);
verifyEqual(testCase, detail.FilledCount, 1);
verifyTrue(testCase, after.Rendo(50, 65, 3));
verifyTrue(testCase, after.Rendo(50, 90, 3), 'Islands stay when only Fill all holes is suggested.');
end

function testBothRules(testCase)
masks = fixture();
[after, detail] = vtseg.apply_island_suggestion(masks, rules(true, true), 2, [1, 1]);
verifyEqual(testCase, [detail.RemovedCount, detail.FilledCount], [2, 1]);
verifyEqual(testCase, bwconncomp(after.Rendo(:, :, 2), 4).NumObjects, 1);
end

function testCleanSliceGetsNoChange(testCase)
masks = fixture();
[rr, cc] = ndgrid(1:100, 1:140);
masks.Rendo(:, :, 2) = hypot(rr - 50, cc - 65) <= 15;
[after, detail] = vtseg.apply_island_suggestion(masks, rules(true, true), 2, [1, 1]);
verifyEqual(testCase, after.Rendo, masks.Rendo);
verifyFalse(testCase, detail.Changed);
verifyEqual(testCase, detail.Skipped, 'no island or hole on this slice');
end

function testOnlyTheSuggestedSliceChanges(testCase)
masks = fixture();
after = vtseg.apply_island_suggestion(masks, rules(true, true), 2, [1, 1]);
verifyEqual(testCase, after.Rendo(:, :, [1, 3]), masks.Rendo(:, :, [1, 3]));
end

function testEmptySliceIsSkipped(testCase)
masks = fixture();
masks.Rendo(:, :, 2) = false;
[~, detail] = vtseg.apply_island_suggestion(masks, rules(true, false), 2, [1, 1]);
verifyEqual(testCase, detail.Skipped, 'no mask on this slice');
end
