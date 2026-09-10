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
