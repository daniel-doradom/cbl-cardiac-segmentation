function iso2meshEP(path_in,path_out,path_global,readLVepi)
%%demo script for surface repairing using surf2vol and remeshsurf
%readLVepi determine need to build LV mesh

%Read data from Gen_mesh
filename = 'heart_sur';
file = strcat(path_in,filename);
file = strcat(file,'.cor');
fid = fopen(file,'rb');
cor = fread(fid,[3,inf],'double');
fclose(fid);

file = strcat(path_in,filename);
file = strcat(file,'.tri');
fid = fopen(file,'rb');
tri = fread(fid,[3,inf],'double');
fclose(fid);

file = strcat(path_in,filename);
file = strcat(file,'.idx');
fid = fopen(file,'rb');
idx = fread(fid,'double');
fclose(fid);


%% perform mesh generation
node1 = cor';
face1 = tri';
node1=node1(:,1:3);
face1=face1(:,1:3);

mesh_comparison_figure = vtseg.ReviewStyle.newFigure('Mesh smoothing: input and smoothed');
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plotmesh(node1,face1);
axis equal
vtseg.ReviewStyle.axesTitle(gca, 'from Gen_mesh');
% smoothing
newno1=sms(node1,face1(:,1:3),3,0.5); %%smooth
figure(mesh_comparison_figure);
nexttile;
plotmesh(newno1,face1);
axis equal
vtseg.ReviewStyle.axesTitle(gca, 'after smoothing');
% remeshing to make free of self interesting element, can doth downsample
% and upsample the mesh

[newno,newfc]=remeshsurf(newno1,face1,4);
remesh_comparison_figure = vtseg.ReviewStyle.newFigure('Mesh smoothing: remeshed and smoothed');
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plotmesh(newno,newfc);
axis equal
vtseg.ReviewStyle.axesTitle(gca, 'after remesh');
%again smoothing
newno=sms(newno,newfc(:,1:3),3,0.5);
figure(remesh_comparison_figure);
nexttile;
plotmesh(newno,newfc(:,1:3));
vtseg.ReviewStyle.axesTitle(gca, 'smoothing after remesh');
axis equal

% remeshing, similar to remeshsurf, uses downsample
[newno2, newfc2] = meshresample( newno(:,1:3), newfc(:,1:3), 0.2 );

% create volumetric tetrahedron mesh from the triangular volumetric mesh
% [node,elem,face]=surf2mesh(newno,newfc,[1 1 1],[100 100 100],0.5,80);
% [node_dense,elem_dense]=surf2mesh(newno,newfc,[1 1 1],[100 100 100],1.0,20);

mesh_min = min(newno(:, 1:3), [], 1);
mesh_max = max(newno(:, 1:3), [], 1);
mesh_margin = max(1, 0.05 * max(mesh_max - mesh_min));
mesh_min = mesh_min - mesh_margin;
mesh_max = mesh_max + mesh_margin;

fprintf('surf2mesh bounding box:\n');
fprintf('  min = [%g %g %g]\n', mesh_min);
fprintf('  max = [%g %g %g]\n', mesh_max);

[node,elem,face]=surf2mesh(newno,newfc,mesh_min,mesh_max,0.5,80);
[node_dense,elem_dense]=surf2mesh(newno,newfc,mesh_min,mesh_max,1.0,20);
tet_comparison_figure = vtseg.ReviewStyle.newFigure('Tetrahedral mesh: elements and nodes');
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plotmesh(node,face(:,1:3));
axis equal
hold on
vtseg.ReviewStyle.axesTitle(gca, 'tetrahedron mesh');
plot3(cor(1,:),cor(2,:),cor(3,:),'r*');

[vol_sur_dist,vol_sur_pos] = vtseg.getDistance(newno2,cor');
[vol_sur_dense_dist,vol_sur_dense_pos] = vtseg.getDistance(newno,cor');

newlabel = zeros(size(newno2,1),1);
for i = 1:size(vol_sur_pos,2)
     newlabel(i) = idx(vol_sur_pos(i));
 end
newlabel_dense = zeros(size(newno,1),1);
for i = 1:size(vol_sur_dense_pos,2)
     newlabel_dense(i) = idx(vol_sur_dense_pos(i));
 end
temp = (newlabel(:)==2);
hold on
plot3(newno2(temp,1),newno2(temp,2),newno2(temp,3),'+')

% assign each node to a slice, slice 1 is the apex

z_cor = node(:,3);
inter = (max(z_cor)-min(z_cor))/(30);
slice = zeros(length(node),1);
z_base = zeros(length(node),1);
for i = 1:30;
    z_base2 = z_base;
    z_base = z_cor <(min(z_cor)+i*inter);
    NumSlice = logical(z_base-z_base2);
    slice(NumSlice) = i;
end
figure(tet_comparison_figure);
nexttile;
plot3(node(:,1),node(:,2),node(:,3),'b+')
vtseg.ReviewStyle.axesTitle(gca, 'nodes');
%% output the mesh information
% .tri files are the faces, .cor files are the coordinates, .tet files are
% the element for tetrahedron mesh

%% tetrahedron mesh
% coordinates of the tetrahedron mesh
fid_w = fopen(strcat(path_out,'tet_heart.cor'),'wb');
fwrite(fid_w,node','double');
fclose(fid_w);


% index of the tertahedron mesh
fid_w = fopen(strcat(path_out,'tet_heart.tet'),'wb');
elem4 = elem(:,1:4);
fwrite(fid_w,elem4','int');
fclose(fid_w);
copyfile(strcat(path_out,'tet_heart.tet'),fullfile(path_global,'tet_heart.tet'));

% denser tetrahedron mesh
fid_w = fopen(strcat(path_out,'tet_dense_heart.cor'),'wb');
fwrite(fid_w,node_dense','double');
fclose(fid_w);

fid_w = fopen(strcat(path_out,'tet_dense_heart.tet'),'wb');
elem_dense4 = elem_dense(:,1:4);
fwrite(fid_w,elem_dense4','int');
fclose(fid_w);
copyfile(strcat(path_out,'tet_dense_heart.tet'),fullfile(path_global,'tet_dense_heart.tet'));

% faces of the tetrahedron mesh
file_out = strcat(path_out,'tet_heart_sur.tri');
fid_w = fopen(file_out,'wb');
face3 = face(:,1:3);
fwrite(fid_w,face3','int');
fclose(fid_w);
copyfile(file_out,fullfile(path_global,'tet_heart_sur.tri'));

%% triangular mesh
% triangular volumetric mesh
% faces of triangular mesh
file_out = strcat(path_out,'sur_heart.tri');
fid_w = fopen(file_out,'wb');
newfc3 = newfc2(:,1:3);
fwrite(fid_w,newfc3','int');
fclose(fid_w);
copyfile(file_out,fullfile(path_global,'sur_heart.tri'));


% coordinate of the triangular mesh
file_out = strcat(path_out,'sur_heart.cor');
fid_w = fopen(file_out,'wb');
fwrite(fid_w,newno2','double');
fclose(fid_w);
copyfile(file_out,fullfile(path_global,'sur_heart.cor'));

% I enable this part
%-----------------------------------
 file_out = strcat(path_out,'sur_heart.idx');
 fid_w = fopen(file_out,'wb');
 fwrite(fid_w,newlabel,'int');
 fclose(fid_w);
copyfile(file_out,fullfile(path_global,'sur_heart.idx'));
 %----------------------------------

% denser triangular surface mesh
file_out = strcat(path_out,'sur_dense_heart.tri');
fid_w = fopen(file_out,'wb');
newfc_dense3 = newfc(:,1:3);
fwrite(fid_w,newfc_dense3','int');
fclose(fid_w);
copyfile(file_out,fullfile(path_global,'sur_dense_heart.tri'));

file_out = strcat(path_out,'sur_dense_heart.cor');
fid_w = fopen(file_out,'wb');
fwrite(fid_w,newno','double');
fclose(fid_w);
copyfile(file_out,fullfile(path_global,'sur_dense_heart.cor'));

file_out = strcat(path_out,'sur_dense_heart.idx');
fid_w = fopen(file_out,'wb');
fwrite(fid_w,newlabel_dense,'int');
fclose(fid_w);
copyfile(file_out,fullfile(path_global,'sur_dense_heart.idx'));


% slice information
file_out = strcat(path_out,'tet_heart.slice');
fid_w = fopen(file_out,'wb');
fwrite(fid_w,slice,'int');
fclose(fid_w);
copyfile(file_out,fullfile(path_global,'tet_heart.slice'));



if readLVepi == 1
    %read Lv information
    file = strcat(path_in,'lv_sur.cor');
    fid = fopen(file,'rb');
    lvcor = fread(fid,[3,inf],'double');
    fclose(fid);


    file = strcat(path_in,'lv_sur.tri');
    fid = fopen(file,'rb');
    lvtri = fread(fid,[3,inf],'double');
    fclose(fid);


    %Lv mesh generation
    lvnode1 = lvcor';
    lvface1 = lvtri';
    lvnode1=lvnode1(:,1:3);
    lvface1=lvface1(:,1:3);
    lvnewno1=sms(lvnode1,lvface1(:,1:3),3,0.4);
    [lvnewno,lvnewfc]=remeshsurf(lvnewno1,lvface1,4);
    lvnewno=sms(lvnewno,lvnewfc(:,1:3),3,0.2);
    [lvnewno, lvnewfc] = meshresample( lvnewno(:,1:3), lvnewfc(:,1:3), 0.25 );
    [lvnode,lvelem,lvface]=surf2mesh(lvnewno,lvnewfc,[1 1 1],[100 100 100],0.4,250);


    vtseg.ReviewStyle.newFigure('Tetrahedral mesh: LV');
    plotmesh(lvnode,lvface(:,1:3));
    axis equal


    file_out = strcat(path_out,'tet_lv_heart.tri');
    fid_w = fopen(file_out,'wb');
    lvface3 = lvface(:,1:3);
    fwrite(fid_w,lvface3','int');
    fclose(fid_w);
    file_out = strcat(path_out,'tet_lv_heart.cor');
    fid_w = fopen(file_out,'wb');
    fwrite(fid_w,lvnode','double');
    fclose(fid_w);
    file_out = strcat(path_out,'tet_lv_heart.tet');
    fid_w = fopen(file_out,'wb');
    lvelem4 = lvelem(:,1:4);
    fwrite(fid_w,lvelem4','int');  fclose(fid_w);




end
