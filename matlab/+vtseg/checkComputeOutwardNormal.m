function [tri_n,nrm] = checkComputeOutwardNormal(cor,tri)
%input: cor: 3xn coordinates (nodes);
%       tri: 3xm triangle list (faces)
%output: tri_n: re-ordered 3xm triangle list --> the correct one to use for
%forward with SCIrun
%        nrm: outward normal.

% here
% iso2mesh is configured through setup_vtseg.
addpath('/Users/orenda/Documents/iso2mesh/');
%calculate current normal
nrm = surf_norm2(cor',tri','Normalize',1);
nrm = nrm';

%calculate cell center
center = zeros(3,size(tri,2));
for i=1:size(tri,2)
    center(:,i) = mean(cor(:,tri(:,i)),2);
end

trimesh(tri',cor(1,:),cor(2,:),cor(3,:));
hold on;
quiver3(center(1,:),center(2,:),center(3,:),nrm(1,:),nrm(2,:),nrm(3,:));
hold off;

key = input('Fix the mesh order? (y/n)  ', 's');

if key == 'y'
%    tri_n = meshreorient(cor',tri');tri_n = tri_n';
    m = mean(cor,2);
    radius = center - m*ones(1,size(tri,2));
    theta = radius.*nrm;
    theta = sum(theta);


    tri_n = tri;
    %reverse the order for elements with inward normal
    tri_n(:,theta<=0) = tri_n([3 2 1], theta<=0);


    nrm = surfnorm(cor',tri_n','Normalize',1);
    nrm = nrm';
    trimesh(tri_n',cor(1,:),cor(2,:),cor(3,:));
    hold on;
    plot3(m(1),m(2),m(3),'o');
    quiver3(center(1,:),center(2,:),center(3,:),nrm(1,:),nrm(2,:),nrm(3,:));
else
    tri_n = tri;
end
