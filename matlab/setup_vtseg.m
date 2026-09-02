function status = setup_vtseg(varargin)
%SETUP_VTSEG Add maintained vtseg MATLAB code and verify external dependencies.

parser = inputParser;
addParameter(parser, 'Iso2meshPath', getenv('VTSEG_ISO2MESH'), @(value) ischar(value) || isstring(value));
parse(parser, varargin{:});

matlab_root = fileparts(mfilename('fullpath'));
addpath(matlab_root);
iso2mesh_path = char(parser.Results.Iso2meshPath);
if isempty(iso2mesh_path) || ~isfolder(iso2mesh_path)
    error('vtseg:Iso2meshMissing', ['iso2mesh is required for mesh generation. Set VTSEG_ISO2MESH or call ', ...
        'setup_vtseg(''Iso2meshPath'', ''/authorized/path/to/iso2mesh'').']);
end
addpath(iso2mesh_path);
if isempty(which('surf2mesh')) || isempty(which('plotmesh'))
    error('vtseg:Iso2meshInvalid', 'The configured iso2mesh path does not provide surf2mesh and plotmesh.');
end
if ~license('test', 'image_toolbox')
    error('vtseg:ImageToolboxMissing', 'Image Processing Toolbox is required for manual correction and mesh generation.');
end
status = struct('matlab_root', matlab_root, 'iso2mesh_path', iso2mesh_path);
end
