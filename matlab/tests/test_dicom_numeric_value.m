function tests = test_dicom_numeric_value
tests = functiontests(localfunctions);
end

function setupOnce(~)
matlab_root = fileparts(fileparts(mfilename('fullpath')));
addpath(matlab_root);
end

function testNumericAndTextDicomFields(testCase)
info = struct('RescaleSlope', 2, 'RescaleIntercept', '-1024', ...
    'WindowCenter', '40\80', 'WindowWidth', [400 800]);
verifyEqual(testCase, vtseg.dicom_numeric_value(info, 'RescaleSlope', 1), 2);
verifyEqual(testCase, vtseg.dicom_numeric_value(info, 'RescaleIntercept', 0), -1024);
verifyEqual(testCase, vtseg.dicom_numeric_value(info, 'WindowCenter', NaN), 40);
verifyEqual(testCase, vtseg.dicom_numeric_value(info, 'WindowWidth', NaN), 400);
end

function testMissingFieldUsesFallback(testCase)
verifyEqual(testCase, vtseg.dicom_numeric_value(struct(), 'RescaleSlope', 1), 1);
end

function testInvalidFieldFailsClearly(testCase)
verifyError(testCase, @() vtseg.dicom_numeric_value( ...
    struct('WindowCenter', 'invalid'), 'WindowCenter', NaN), ...
    'vtseg:InvalidDicomNumber');
end
