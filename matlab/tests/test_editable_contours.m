function tests = test_editable_contours
tests = functiontests(localfunctions);
end

function setupOnce(~)
matlab_root = fileparts(fileparts(mfilename('fullpath')));
addpath(matlab_root);
end

function testMultipleComponentsAndHoleArePreserved(testCase)
mask = false(100, 100);
mask(10:35, 10:35) = true;
mask(18:25, 18:25) = false;
mask(20:22, 20:22) = true;
mask(60:80, 65:90) = true;
mask(90, 90) = true;

contours = vtseg.mask_to_editable_contours(mask, 2, 200);
verifyEqual(testCase, sum(~[contours.IsHole]), 4);
verifyEqual(testCase, sum([contours.IsHole]), 1);

rebuilt = vtseg.editable_contours_to_mask(contours, size(mask));
verifyTrue(testCase, rebuilt(12, 12));
verifyFalse(testCase, rebuilt(24, 24));
verifyTrue(testCase, rebuilt(20, 20));
verifyTrue(testCase, rebuilt(70, 75));
verifyTrue(testCase, rebuilt(90, 90));
components = bwconncomp(rebuilt);
verifyEqual(testCase, components.NumObjects, 4);
end

function testVertexCountIsBounded(testCase)
[columns, rows] = meshgrid(1:200, 1:200);
mask = (columns - 100) .^ 2 + (rows - 100) .^ 2 <= 70 ^ 2;

contours = vtseg.mask_to_editable_contours(mask, 1, 24);
verifyEqual(testCase, numel(contours), 1);
verifyLessThanOrEqual(testCase, size(contours(1).Position, 1), 24);
verifyGreaterThanOrEqual(testCase, size(contours(1).Position, 1), 3);
end

function testPhysicalSpacingProducesComparableControlDensity(testCase)
[x_mri, y_mri] = meshgrid(1:120, 1:120);
mri_mask = (x_mri - 60) .^ 2 + (y_mri - 60) .^ 2 <= 30 ^ 2;
[x_ct, y_ct] = meshgrid(1:240, 1:240);
ct_mask = (x_ct - 120) .^ 2 + (y_ct - 120) .^ 2 <= 60 ^ 2;

% Both circles have a 30 mm radius. CT has twice the pixel resolution.
mri = vtseg.mask_to_editable_contours(mri_mask, 8, 96, [1, 1]);
ct = vtseg.mask_to_editable_contours(ct_mask, 8, 96, [0.5, 0.5]);

verifyEqual(testCase, numel(mri), 1);
verifyEqual(testCase, numel(ct), 1);
verifyLessThanOrEqual(testCase, ...
    abs(size(mri.Position, 1) - size(ct.Position, 1)), 1);
end

function testUnmovedControlsKeepDenseBoundary(testCase)
[columns, rows] = meshgrid(1:100, 1:100);
mask = (columns - 50) .^ 2 + (rows - 50) .^ 2 <= 32 ^ 2;
controls = vtseg.mask_to_editable_contours(mask, 8, 64, [0.5, 0.5]);

[deformed, changed] = vtseg.deform_editable_contours(controls, controls);

verifyFalse(testCase, changed);
verifyEqual(testCase, deformed.Position, controls.DensePosition);
end

function testMovedControlDeformsDenseBoundary(testCase)
[columns, rows] = meshgrid(1:100, 1:100);
mask = (columns - 50) .^ 2 + (rows - 50) .^ 2 <= 32 ^ 2;
controls = vtseg.mask_to_editable_contours(mask, 8, 64, [1, 1]);
edited = controls;
edited.Position(1, :) = edited.Position(1, :) + [6, -2];

[deformed, changed] = vtseg.deform_editable_contours(controls, edited);

verifyTrue(testCase, changed);
verifyEqual(testCase, size(deformed.Position), size(controls.DensePosition));
verifyGreaterThan(testCase, max(abs(deformed.Position(:) - controls.DensePosition(:))), 0);
end

function testSmallComponentRetainsNativeBoundary(testCase)
mask = false(40, 40);
mask(20:22, 20:22) = true;

contours = vtseg.mask_to_editable_contours(mask, 8, 64, [0.5, 0.5]);

verifyEqual(testCase, numel(contours), 1);
verifyEqual(testCase, size(contours.Position, 1), size(contours.DensePosition, 1));
rebuilt = vtseg.editable_contours_to_mask(contours, size(mask));
verifyTrue(testCase, rebuilt(20, 20));
end
