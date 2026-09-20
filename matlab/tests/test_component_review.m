function tests = test_component_review
tests = functiontests(localfunctions);
end

function setupOnce(~)
matlab_root = fileparts(fileparts(mfilename('fullpath')));
addpath(matlab_root);
end

function testSingleComponentRemainsUnchanged(testCase)
mask = false(30, 30);
mask(5:20, 7:24) = true;
[staged, details] = vtseg.stage_mask_component_action( ...
    mask, mask, 'keep_largest', 1, [0.5, 0.8]);
verifyEqual(testCase, staged, mask);
verifyEqual(testCase, details.OriginalComponentCount, 1);
verifyEqual(testCase, details.FinalComponentCount, 1);
end

function testKeepLargestRemovesIslands(testCase)
mask = component_fixture();
[staged, details] = vtseg.stage_mask_component_action( ...
    mask, mask, 'keep_largest', 1, [1, 1]);
verifyTrue(testCase, staged(10, 10));
verifyFalse(testCase, staged(42, 42));
verifyFalse(testCase, staged(55, 8));
verifyEqual(testCase, details.OriginalComponentCount, 3);
verifyEqual(testCase, details.FinalComponentCount, 1);
end

function testRemoveSelectedRemovesOnlyThatComponent(testCase)
mask = component_fixture();
analysis = vtseg.analyze_mask_components(mask, [1, 1]);
[~, selected] = min(analysis.AreasPixels);
[staged, details] = vtseg.stage_mask_component_action( ...
    mask, mask, 'remove_selected', selected, [1, 1]);
verifyTrue(testCase, staged(10, 10));
verifyTrue(testCase, staged(42, 42));
verifyFalse(testCase, staged(55, 8));
verifyEqual(testCase, details.FinalComponentCount, 2);
end

function testRestoreKeepAllAndCancelPreserveOriginal(testCase)
original = component_fixture();
analysis = vtseg.analyze_mask_components(original, [1, 1]);
[~, selected] = min(analysis.AreasPixels);
[staged, ~] = vtseg.stage_mask_component_action( ...
    original, original, 'remove_selected', selected, [1, 1]);
for action = {'restore', 'keep_all', 'cancel'}
    restored = vtseg.stage_mask_component_action( ...
        original, staged, action{1}, 1, [1, 1]);
    verifyEqual(testCase, restored, original);
end
end

function testStagingDoesNotMutateSource(testCase)
original = component_fixture();
source_copy = original;
staged = vtseg.stage_mask_component_action( ...
    original, original, 'keep_largest', 1, [1, 1]);
verifyEqual(testCase, original, source_copy);
verifyNotEqual(testCase, staged, original);
end

function testHoleIsNotAnIsland(testCase)
mask = false(50, 50);
mask(5:40, 5:40) = true;
mask(15:25, 15:25) = false;
analysis = vtseg.analyze_mask_components(mask, [0.7, 0.9]);
verifyEqual(testCase, analysis.Count, 1);
staged = vtseg.stage_mask_component_action( ...
    mask, mask, 'keep_largest', 1, [0.7, 0.9]);
verifyEqual(testCase, staged, mask);
verifyFalse(testCase, staged(20, 20));
end

function testEnclosedHolesAreDetectedSeparately(testCase)
mask = false(50, 50);
mask(5:40, 5:40) = true;
mask(15:25, 15:25) = false;
mask(30:31, 30:32) = false;
analysis = vtseg.analyze_mask_holes(mask, [0.5, 0.8], 4);
verifyEqual(testCase, analysis.Count, 2);
verifyEqual(testCase, sort(analysis.AreasPixels), [6, 121]);
verifyEqual(testCase, sort(analysis.AreasMm2), [2.4, 48.4], 'AbsTol', 1e-12);
end

function testFillSelectedHoleFillsOnlyThatHole(testCase)
mask = false(50, 50);
mask(5:40, 5:40) = true;
mask(15:25, 15:25) = false;
mask(30:31, 30:32) = false;
holes = vtseg.analyze_mask_holes(mask, [1, 1], 4);
[~, selected] = max(holes.AreasPixels);
[staged, details] = vtseg.stage_mask_component_action( ...
    mask, mask, 'fill_selected_hole', selected, [1, 1], 4);
verifyTrue(testCase, staged(20, 20));
verifyFalse(testCase, staged(30, 30));
verifyEqual(testCase, details.FilledHoleAreasPixels, 121);
verifyEmpty(testCase, details.RemovedAreasPixels);
end

function testFillAllHolesFillsEveryEnclosedRegionOnly(testCase)
mask = false(50, 50);
mask(5:40, 5:40) = true;
mask(15:25, 15:25) = false;
mask(30:31, 30:32) = false;
mask(45, 45) = true;                       % a separate island must survive
[staged, details] = vtseg.stage_mask_component_action( ...
    mask, mask, 'fill_all_holes', 1, [1, 1], 4);
verifyTrue(testCase, staged(20, 20));
verifyTrue(testCase, staged(30, 30));
verifyTrue(testCase, staged(45, 45));
verifyFalse(testCase, staged(2, 2));
verifyEqual(testCase, vtseg.analyze_mask_holes(staged, [1, 1], 4).Count, 0);
verifyEqual(testCase, sort(details.FilledHoleAreasPixels), [6, 121]);
verifyEqual(testCase, details.FinalComponentCount, 2);
end

function testExteriorBackgroundIsNotAHole(testCase)
mask = false(30, 30);
mask(5:20, 5:20) = true;
mask(10:12, 5:8) = false;
analysis = vtseg.analyze_mask_holes(mask, [1, 1], 4);
verifyEqual(testCase, analysis.Count, 0);
end

function testPhysicalAreaUsesPixelSpacing(testCase)
mask = false(10, 10);
mask(2:3, 2:4) = true;
analysis = vtseg.analyze_mask_components(mask, [0.5, 2]);
verifyEqual(testCase, analysis.AreasPixels, 6);
verifyEqual(testCase, analysis.AreasMm2, 6);
end

function testFourConnectivitySeparatesCornerTouchingIslands(testCase)
mask = false(10, 10);
mask(2:4, 2:4) = true;
mask(5:6, 5:6) = true;
eight_connected = vtseg.analyze_mask_components(mask, [1, 1], 8);
four_connected = vtseg.analyze_mask_components(mask, [1, 1], 4);
verifyEqual(testCase, eight_connected.Count, 1);
verifyEqual(testCase, four_connected.Count, 2);

staged = vtseg.stage_mask_component_action( ...
    mask, mask, 'keep_largest', 1, [1, 1], 4);
verifyTrue(testCase, staged(3, 3));
verifyFalse(testCase, staged(5, 5));
end

function testMyocardiumIsRecomputedAndDisjoint(testCase)
Epi = false(30, 30);
Epi(3:28, 3:28) = true;
Lendo = false(30, 30);
Lendo(8:14, 8:14) = true;
Rendo = false(30, 30);
Rendo(17:24, 17:25) = true;
myocardium = vtseg.recompute_myocardium(Lendo, Rendo, Epi);
verifyEqual(testCase, myocardium, Epi & ~Lendo & ~Rendo);
verifyFalse(testCase, any(myocardium(:) & Lendo(:)));
verifyFalse(testCase, any(myocardium(:) & Rendo(:)));
end

function testOriginalIsRejectedAndWorkRemainsEditable(testCase)
root = tempname;
cleanup = onCleanup(@() remove_test_tree(root));
mkdir(fullfile(root, 'original', 'raw'));
mkdir(fullfile(root, 'original', 'seg'));
mkdir(fullfile(root, 'work', 'raw'));
mkdir(fullfile(root, 'work', 'seg'));
baseline = component_fixture();
save(fullfile(root, 'original', 'seg', 'Lendo.mat'), 'baseline');
save(fullfile(root, 'work', 'seg', 'Lendo.mat'), 'baseline');

verifyEqual(testCase, vtseg.resolve_matlab_work_path(root), fullfile(root, 'work'));
verifyError(testCase, @() vtseg.resolve_matlab_work_path( ...
    fullfile(root, 'original')), 'vtseg:ReadOnlyOriginal');
verifyError(testCase, @() vtseg.assert_editable_matlab_path( ...
    fullfile(root, 'original', 'seg')), 'vtseg:ReadOnlyOriginal');

edited = vtseg.stage_mask_component_action( ...
    baseline, baseline, 'keep_largest', 1, [1, 1]);
save(fullfile(root, 'work', 'seg', 'Lendo.mat'), 'edited');
original_file = load(fullfile(root, 'original', 'seg', 'Lendo.mat'));
verifyEqual(testCase, original_file.baseline, baseline);
clear cleanup
end

function testAuditWritesOnlyUnderWork(testCase)
root = tempname;
cleanup = onCleanup(@() remove_test_tree(root));
mkdir(fullfile(root, 'original', 'seg'));
mkdir(fullfile(root, 'work', 'seg'));
action = struct( ...
    'slice_number', 3, ...
    'source_dicom_filename', 'slice_0003.dcm', ...
    'structure', 'Rendo', ...
    'original_component_count', 2, ...
    'action', 'remove_selected', ...
    'removed_component_areas_pixels', 7, ...
    'removed_component_areas_mm2', 1.75, ...
    'timestamp', '2026-09-19T00:00:00Z', ...
    'final_component_count', 1);
audit_path = vtseg.save_component_review_audit(fullfile(root, 'work', 'seg'), action);
verifyTrue(testCase, isfile(audit_path));
saved = jsondecode(fileread(audit_path));
verifyEqual(testCase, saved.actions.structure, 'Rendo');
verifyEmpty(testCase, saved.actions.filled_hole_areas_pixels);
verifyError(testCase, @() vtseg.save_component_review_audit( ...
    fullfile(root, 'original', 'seg'), action), 'vtseg:ReadOnlyOriginal');
verifyFalse(testCase, isfile(fullfile(root, 'original', 'component_review_audit.json')));
clear cleanup
end

function mask = component_fixture()
mask = false(60, 60);
mask(5:30, 5:30) = true;
mask(40:47, 40:49) = true;
mask(55, 8) = true;
end

function remove_test_tree(path)
if isfolder(path)
    rmdir(path, 's');
end
end
