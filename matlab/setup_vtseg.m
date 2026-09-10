function status = setup_vtseg(varargin)
%SETUP_VTSEG Add maintained vtseg MATLAB code and verify external dependencies.

parser = inputParser;
addParameter(parser, 'Iso2meshPath', getenv('VTSEG_ISO2MESH'), @(value) ischar(value) || isstring(value));
parse(parser, varargin{:});

matlab_root = fileparts(mfilename('fullpath'));
addpath(matlab_root);
iso2mesh_path = char(parser.Results.Iso2meshPath);
if isempty(iso2mesh_path)
    % Keep optional third-party dependencies next to the repository without
    % placing their source or binaries under version control.
    repo_local_iso2mesh = fullfile(fileparts(matlab_root), '.external', 'iso2mesh');
    if isfolder(repo_local_iso2mesh)
        iso2mesh_path = repo_local_iso2mesh;
    end
end
if isempty(iso2mesh_path)
    % A preceding explicit setup call has already added iso2mesh to MATLAB's
    % path. Reuse it when workflow functions perform their own setup check.
    existing_surf2mesh = which('surf2mesh');
    if ~isempty(existing_surf2mesh)
        iso2mesh_path = fileparts(existing_surf2mesh);
    end
end
if isempty(iso2mesh_path) || ~isfolder(iso2mesh_path)
    error('vtseg:Iso2meshMissing', ['iso2mesh is required for mesh generation. Set VTSEG_ISO2MESH or call ', ...
        'setup_vtseg(''Iso2meshPath'', ''/authorized/path/to/iso2mesh''), or install it at ', ...
        '<repo>/.external/iso2mesh.']);
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
