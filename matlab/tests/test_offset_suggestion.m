function tests = test_offset_suggestion
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

% Five slices; LV left, RV right, both shifting 4 px right per slice.
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

function request = whole(structure, offset, covered)
request = struct('Structure', structure, 'Mode', 'whole', 'OffsetMm', offset, ...
    'FadeMm', NaN, 'StretchPoints', [], 'SourceSlice', covered(1), 'Covered', covered);
end

function request = stretch(offset, covered)
request = struct('Structure', 'Rendo', 'Mode', 'stretch', 'OffsetMm', offset, ...
    'FadeMm', 4, 'StretchPoints', [65, 38; 65, 62; 77, 50], 'SourceSlice', 1, 'Covered', covered);
end

function testWholeSuggestionMatchesTheMultiSliceOffset(testCase)
masks = fixture();
[after, details] = vtseg.apply_offset_suggestion(masks, whole('Rendo', 2, 1), 2, [1, 1]);
expected = vtseg.offset_mask_slices(masks, 'Rendo', 2, [1, 1], 2);
verifyEqual(testCase, after.Rendo, expected);
verifyTrue(testCase, details.Changed);
verifyEqual(testCase, details.Structure, 'Rendo');
end

function testStretchSuggestionMatchesTheCarriedStretch(testCase)
masks = fixture();
after = vtseg.apply_offset_suggestion(masks, stretch(3, 1), 2, [1, 1]);
expected = vtseg.offset_mask_stretch_slices(masks, 'Rendo', 2, [1, 1], ...
    [65, 38; 65, 62; 77, 50], 1, 3, 4);
verifyEqual(testCase, after.Rendo, expected);
end

function testOnlyTheSuggestedSliceChanges(testCase)
masks = fixture();
after = vtseg.apply_offset_suggestion(masks, whole('Rendo', 2, 1), 2, [1, 1]);
verifyEqual(testCase, after.Rendo(:, :, [1, 3, 4, 5]), masks.Rendo(:, :, [1, 3, 4, 5]));
verifyEqual(testCase, after.Lendo, masks.Lendo);
end

function testCoveredSliceIsSkipped(testCase)
masks = fixture();
[after, details] = vtseg.apply_offset_suggestion(masks, whole('Rendo', 2, [1, 2]), 2, [1, 1]);
verifyEqual(testCase, after.Rendo, masks.Rendo);
verifyFalse(testCase, details.Changed);
verifyEqual(testCase, details.Skipped, 'this slice already has this change');
end

function testLaterStructureSeesTheEarlierChange(testCase)
masks = fixture();
requests = [whole('Rendo', 3, 1); whole('Lendo', 5, 1)];
after = vtseg.apply_offset_suggestion(masks, requests, 2, [1, 1]);
verifyFalse(testCase, any(any(after.Lendo(:, :, 2) & after.Rendo(:, :, 2))), ...
    'The LV grows only up to the RV as the RV is after its own suggestion.');
end

function testAppliesOnlyNextToACoveredSlice(testCase)
requests = whole('Rendo', 2, 3);
verifyTrue(testCase, vtseg.offset_suggestion_applies(requests, 2, []));
verifyTrue(testCase, vtseg.offset_suggestion_applies(requests, 4, []));
verifyFalse(testCase, vtseg.offset_suggestion_applies(requests, 3, []), 'Not on its own slice.');
verifyFalse(testCase, vtseg.offset_suggestion_applies(requests, 5, []), 'Not two slices away.');
end

function testDeclinedSliceGetsNoSuggestion(testCase)
verifyFalse(testCase, vtseg.offset_suggestion_applies(whole('Rendo', 2, 3), 4, 4));
end

function testNoRequestsMeansNoSuggestion(testCase)
verifyFalse(testCase, vtseg.offset_suggestion_applies(struct('Covered', {}), 2, []));
end

function testEachRequestIsCheckedOnItsOwn(testCase)
% The RV change already reached slice 4 through Scope; the LV change did not.
requests = [whole('Rendo', 2, [3, 4]); whole('Lendo', 1, 3)];
verifyTrue(testCase, vtseg.offset_suggestion_applies(requests, 4, []));
end

function testChainedAcceptanceMovesOneSliceAtATime(testCase)
requests = whole('Rendo', 2, 3);
requests.Covered(end + 1) = 4;   % accepted on slice 4
verifyTrue(testCase, vtseg.offset_suggestion_applies(requests, 5, []));
verifyFalse(testCase, vtseg.offset_suggestion_applies(requests, 1, []));
end
