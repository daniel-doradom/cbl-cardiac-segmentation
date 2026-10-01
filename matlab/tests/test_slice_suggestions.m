function tests = test_slice_suggestions
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

function masks = fixture()
[rr, cc] = ndgrid(1:100, 1:140);
Lendo = false(100, 140, 3); Rendo = Lendo; Epi = Lendo;
for k = 1:3
    Lendo(:, :, k) = hypot(rr - 50, cc - 30) <= 10;
    Rendo(:, :, k) = hypot(rr - 50, cc - 65) <= 12 | hypot(rr - 50, cc - 95) <= 2;
    Epi(:, :, k) = hypot(rr - 50, cc - 55) <= 45;
end
masks = struct('Lendo', Lendo, 'Rendo', Rendo, 'Epi', Epi, 'lepi', []);
end

function request = base(kind, covered)
request = struct('Kind', kind, 'Structure', 'Rendo', 'Mode', 'whole', 'OffsetMm', 2, ...
    'FadeMm', NaN, 'StretchLengthMm', NaN, 'StretchPoints', [], 'SourceSlice', 1, ...
    'Covered', covered, 'Islands', struct('KeepLargest', true, 'FillAllHoles', false, ...
    'RemovedPoints', zeros(0, 2), 'FilledPoints', zeros(0, 2), 'Connectivity', 4));
end

function testOffsetAndIslandsBothApply(testCase)
masks = fixture();
requests = [base('islands', 1); base('offset', 1)];
[after, details] = vtseg.apply_slice_suggestions(masks, requests, 2, [1, 1]);
verifyEqual(testCase, {details.Kind}, {'islands', 'offset'}, 'Details keep the request order.');
verifyTrue(testCase, all([details.Changed]));
verifyFalse(testCase, after.Rendo(50, 95, 2), 'The island is gone.');
verifyTrue(testCase, after.Rendo(50, 78, 2), 'The main RV grew by 2 mm.');
end

function testOffsetRunsBeforeIslands(testCase)
% Growing first merges nothing here, so keep-largest still removes the
% island; if islands ran first the grown island would not exist at all.
% Either way the island must not survive the combined suggestion.
masks = fixture();
requests = [base('islands', 1); base('offset', 1)];
requests(2).OffsetMm = 5;
after = vtseg.apply_slice_suggestions(masks, requests, 2, [1, 1]);
components = bwconncomp(after.Rendo(:, :, 2), 4);
verifyEqual(testCase, components.NumObjects, 1);
end

function testCoveredRequestIsSkipped(testCase)
masks = fixture();
[after, details] = vtseg.apply_slice_suggestions(masks, base('islands', [1, 2]), 2, [1, 1]);
verifyEqual(testCase, after.Rendo, masks.Rendo);
verifyEqual(testCase, details.Skipped, 'this slice already has this change');
end
