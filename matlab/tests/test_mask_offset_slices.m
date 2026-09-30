function tests = test_mask_offset_slices
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

function testOnlyTheRequestedSlicesChange(testCase)
masks = fixture();
[stack, details] = vtseg.offset_mask_slices(masks, 'Rendo', 2:3, [1, 1], 2);
verifyEqual(testCase, stack(:, :, [1, 4, 5]), masks.Rendo(:, :, [1, 4, 5]));
verifyGreaterThan(testCase, nnz(stack(:, :, 2)), nnz(masks.Rendo(:, :, 2)));
verifyEqual(testCase, [details.Slice], [2, 3]);
verifyTrue(testCase, all([details.Changed]));
end

function testEachSliceMatchesTheSingleSliceOffset(testCase)
masks = fixture();
stack = vtseg.offset_mask_slices(masks, 'Lendo', 1:5, [1, 1], 3);
for k = 1:5
    limits = vtseg.mask_offset_limits('Lendo', masks.Lendo(:, :, k), ...
        masks.Rendo(:, :, k), masks.Epi(:, :, k), []);
    verifyEqual(testCase, stack(:, :, k), vtseg.offset_mask( ...
        masks.Lendo(:, :, k), [1, 1], 3, limits), sprintf('slice %d', k));
end
end

function testGrowthStopsAtEachSlicesNeighbours(testCase)
masks = fixture();
[stack, details] = vtseg.offset_mask_slices(masks, 'Rendo', 1:5, [1, 1], 5);
verifyFalse(testCase, any(stack(:) & masks.Lendo(:)), 'RV may never grow into LV.');
verifyFalse(testCase, any(stack(:) & ~masks.Epi(:)), 'RV may never grow outside Epi.');
verifyGreaterThan(testCase, sum([details.BlockedPixels]), 0);
end

function testEmptySliceIsSkipped(testCase)
masks = fixture();
masks.Rendo(:, :, 5) = false;
[stack, details] = vtseg.offset_mask_slices(masks, 'Rendo', 4:5, [1, 1], 2);
verifyFalse(testCase, any(any(stack(:, :, 5))));
verifyEqual(testCase, details(2).Skipped, 'no mask on this slice');
verifyFalse(testCase, details(2).Changed);
end

function testShrinkThatWouldEraseIsSkipped(testCase)
masks = fixture();
masks.Rendo(:, :, 4) = false; masks.Rendo(30:31, 60:61, 4) = true;
[stack, details] = vtseg.offset_mask_slices(masks, 'Rendo', 4, [1, 1], -3);
verifyEqual(testCase, stack(:, :, 4), masks.Rendo(:, :, 4));
verifyEqual(testCase, details.Skipped, 'would remove the whole structure');
end

function testEpiShrinkKeepsBothCavities(testCase)
masks = fixture();
stack = vtseg.offset_mask_slices(masks, 'Epi', 1:5, [1, 1], -5);
verifyTrue(testCase, all(stack(masks.Lendo)) && all(stack(masks.Rendo)));
end

function testSlicesOutOfRangeAreRejected(testCase)
verifyError(testCase, @() vtseg.offset_mask_slices(fixture(), 'Lendo', 0:2, [1, 1], 1), ...
    'vtseg:OffsetSlices');
verifyError(testCase, @() vtseg.offset_mask_slices(fixture(), 'Lendo', 6, [1, 1], 1), ...
    'vtseg:OffsetSlices');
end

function testAuditAppendsUnderWorkOnly(testCase)
root = tempname;
cleanup = onCleanup(@() rmdir(root, 's'));
mkdir(fullfile(root, 'original', 'seg'));
mkdir(fullfile(root, 'work', 'seg'));
first = struct('slice_number', 3, 'structure', 'Rendo', 'mode', 'whole', ...
    'offset_mm', 1.5, 'set_on_slice', 3, 'added_pixels', 40);
second = struct('slice_number', 4, 'structure', 'Rendo', 'mode', 'whole', ...
    'offset_mm', 1.5, 'set_on_slice', 3, 'added_pixels', 35);
path = vtseg.save_mask_offset_audit(fullfile(root, 'work', 'seg'), first);
vtseg.save_mask_offset_audit(fullfile(root, 'work', 'seg'), second);
saved = jsondecode(fileread(path));
verifyEqual(testCase, [saved.records.slice_number], [3, 4]);
verifyEqual(testCase, [saved.records.set_on_slice], [3, 3]);
verifyEqual(testCase, saved.records(1).mode, 'whole');
verifyError(testCase, @() vtseg.save_mask_offset_audit( ...
    fullfile(root, 'original', 'seg'), first), 'vtseg:ReadOnlyOriginal');
clear cleanup
end

function masks = fixture()
% Five slices: LV disk on the left, RV disk to its right, Epi around both.
[rr, cc] = ndgrid(1:80, 1:100);
Lendo = false(80, 100, 5); Rendo = Lendo; Epi = Lendo;
for k = 1:5
    Lendo(:, :, k) = hypot(rr - 40, cc - 35) <= 12 - k;
    Rendo(:, :, k) = hypot(rr - 40, cc - 62) <= 11 - k;
    Epi(:, :, k) = hypot(rr - 40, cc - 35) <= 19 - k | hypot(rr - 40, cc - 62) <= 14 - k;
end
masks = struct('Lendo', Lendo, 'Rendo', Rendo, 'Epi', Epi, 'lepi', []);
end
