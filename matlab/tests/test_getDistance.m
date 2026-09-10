function tests = test_getDistance
tests = functiontests(localfunctions);
end

function setupOnce(~)
matlab_root = fileparts(fileparts(mfilename('fullpath')));
addpath(matlab_root);
end

function testNearestReferencePoint(testCase)
queries = [0 0 0; 4 4 4; 10 10 10];
references = [1 0 0; 5 5 5; 12 10 10];

[distances, positions] = vtseg.getDistance(queries, references);

verifyEqual(testCase, distances, [1; sqrt(3); 2], 'AbsTol', 1e-12);
verifyEqual(testCase, positions, [1 2 3]);
end

function testRejectsMismatchedDimensions(testCase)
verifyError(testCase, @() vtseg.getDistance(zeros(2, 3), zeros(2, 2)), ...
    'vtseg:GetDistanceDimensions');
end
