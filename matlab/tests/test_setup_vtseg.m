function tests = test_setup_vtseg
tests = functiontests(localfunctions);
end

function testMissingIso2meshFailsClearly(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
verifyError(testCase, @() setup_vtseg('Iso2meshPath', fullfile(tempdir, 'missing-iso2mesh')), ...
    'vtseg:Iso2meshMissing');
end
