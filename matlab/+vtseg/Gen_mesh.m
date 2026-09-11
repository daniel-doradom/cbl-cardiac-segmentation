function Gen_mesh(path_in,path_out)
% function to generate dense surface mesh of ventricles

% read input files
file1 = strcat(path_in,'Rendo.mat');
file2 = strcat(path_in,'Lendo.mat');
file3 = strcat(path_in,'Epi.mat');
file5 = strcat(path_in,'info.mat');
load (file1);
load (file2);
load (file3);
load (file5);
% file4 = strcat(path,'lepi.mat'); % to generate 17 segments of ventricles
% load (file4); % to generate 17 segments of ventricles

% Initalization
epi   = Epi;
lendo = Lendo;
rendo = Rendo;
f = num;
xint = PixelSpace(1);
yint = PixelSpace(2);
zint = sliceSpacing;
% a = Cor_start(1,:);   % global coordinate of first image, mesh grid start
% b = Cor_start(num,:); % global coordinate of last image, mesh grid end
a = Cor_start(1,:);   % global coordinate of first image, mesh grid start
b = Cor_start(num,:); % global coordinate of last image, mesh grid end
imgW = double(imgW);
imgH = double(imgH);

if exist('sliceLocationsLocal', 'var') && numel(sliceLocationsLocal) == f
    z_slices = double(sliceLocationsLocal(:)');
    if f < 2 || any(abs(diff(z_slices)) < eps)
        error('info.mat has invalid local DICOM slice positions.');
    end
    z_grid = [z_slices(1) - (z_slices(2) - z_slices(1)), z_slices, ...
        z_slices(end) + (z_slices(end) - z_slices(end - 1))];
else
    % Backward-compatible fallback for legacy info.mat files.
    z_grid = 0:zint:(f+1)*zint;
end

% initialize mesh
epi_total=ones(imgH,imgW,f+2)*(-100);
lendo_total=ones(imgH,imgW,f+2)*(-100);
rendo_total=ones(imgH,imgW,f+2)*(-100);
lwall = ones(imgH,imgW, f+2)*(-100); % to generate 17 segments of ventricles
epi_total(:,:,2:f+1) = epi(:,:,1:num);
lendo_total(:,:,2:f+1) = lendo(:,:,1:num);
rendo_total(:,:,2:f+1) = rendo(:,:,1:num);
%lwall(:,:,2:f+1) = lepi(:,:,1:num);% to generate 17 segments of ventricles

%generate binary images
lendo_total(:,:,f+2) = (logical(imerode(lendo_total(:,:,f+1),strel('square',5)))*100);
epi_total(:,:,f+2) = (logical(imerode(epi_total(:,:,f+1),strel('square',5)))*100);
vol_total = xor(xor(epi_total, lendo_total),rendo_total).*epi_total;

%  generate grid for the surface mesh, conversion from matlab's coordinate
%  system to local coordinate system done using pixel spacing
[X,Y,Z]=meshgrid(0:xint:xint*(imgW-1),0:yint:yint*(imgH-1),z_grid);
[X1,Y1]=meshgrid(0:xint:xint*(imgW-1),0:yint:yint*(imgH-1));
[X2,Y2,Z2]=meshgrid(0:xint:xint*(imgW-1),0:yint:yint*(imgH-1),z_grid);
i = 1:(f+2);
vol21(:,:,i) = vol_total(:,:,i);
epi2(:,:,i) = epi_total(:,:,i);
lendo2(:,:,i) = lendo_total(:,:,i);
rendo2(:,:,i) = rendo_total(:,:,i);
vol_total(:,:,f+2) = 0;

% generating epi, lendo, rendo surfaces separately
epi_sur = isosurface(X,Y,Z,epi2, 0); %%% it was X,Y,Z
lendo_sur = isosurface(X2,Y2,Z2,lendo2, 0);
rendo_sur = isosurface(X2,Y2,Z2,rendo2, 0);
lv_sur = isosurface(X2,Y2,Z2,lwall,0);
vol_sur = isosurface(X,Y,Z,vol21, 0);
vol2 = vol21;

% combine all three surface into a volume
gen_mesh_figure = vtseg.ReviewStyle.newFigure('Mesh generation: surfaces');
tiledlayout(1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
volobj = isosurface(X,Y,Z,vol2, 0);
p7 = patch(volobj, 'FaceColor', 'g', 'EdgeColor', 'r');
vtseg.ReviewStyle.axesTitle(gca, 'Combined surface');
% labeling the surface mesh nodes to differentiate epi , lendo and rendo
[epidist,eq] = vtseg.getDistance(vol_sur.vertices,epi_sur.vertices);
[lendodist,eq] = vtseg.getDistance(vol_sur.vertices,lendo_sur.vertices);
[rendodist,eq] = vtseg.getDistance(vol_sur.vertices,rendo_sur.vertices);
e=0;
l=0;
r=0;
label = [size(vol_sur.vertices,1),1];
for i = 1:size(epidist,1)
    if (epidist(i)<lendodist(i))
        if(epidist(i)<=rendodist(i))
            label(i) = 3;%epi point
            e = e+1;
        else
            label(i) = 2;%rendo point
            r=r+1;
        end
    else
        if(lendodist(i)<=rendodist(i))
            label(i) = 1;%lendo point
            l=l+1;
        else
            label(i) = 2;%rendo point
            r=r+1;
        end
    end
end
%% thhis is in case you want to ignore the RV
%[rendodist,eq] = vtseg.getDistance(vol_sur.vertices,rendo_sur.vertices);

% e=0;
% l=0;
% r=0;
% label = [size(vol_sur.vertices,1),1];
% for i = 1:size(epidist,1)
%     if (epidist(i)<lendodist(i))
% %         if(epidist(i)<=rendodist(i))
%             label(i) = 3;%epi point
%             e = e+1;
% %         else
% %             label(i) = 2;%rendo point
% %             r=r+1;
% %         end
%     else
% %         if(lendodist(i)<=rendodist(i))
% %             label(i) = 1;%lendo point
% %             l=l+1;
% %         else
%             label(i) = 2;%rendo point
%             r=r+1;
% %         end
%     end
% end
hold on
newlabel = label;
temp = (newlabel(:)==1);

figure(gen_mesh_figure);
nexttile;
plot3(volobj.vertices(temp,1),volobj.vertices(temp,2),volobj.vertices(temp,3),'g*')
vtseg.ReviewStyle.axesTitle(gca, 'LV endocardial surface nodes');
% write to output path
file1 = strcat(path_out,'heart_sur');
file1 = strcat(file1,'.tri');
fid1 = fopen(file1,'wb');
tri1 = volobj.faces' ; % to be compatible with linwei
fwrite(fid1,tri1,'double');
fclose(fid1);

file1 = strcat(path_out,'lv_sur');
file1 = strcat(file1,'.tri');
fid1 = fopen(file1,'wb');
tri2 = lv_sur.faces' ; % to be compatible with linwei
fwrite(fid1,tri2,'double');
fclose(fid1);

file = strcat(path_out,'heart_sur');
file = strcat(file,'.cor');
fid  = fopen(file,'wb');
cor = volobj.vertices';% to be compatible with linwei
fwrite(fid,cor,'double');
fclose(fid);

% uncomment for generating 17 segment information
%  file = strcat(path_out,'lv_total');
%  file = strcat(file,'.map');
%  fid  = fopen(file,'wb');
%  cor1 = vol2;% to be compatible with linwei
%  fwrite(fid,cor1,'double');
%  fclose(fid);

file = strcat(path_out,'heart_vol');
file = strcat(file,'.cor');
fid  = fopen(file,'wb');
vol = vol2;
fwrite(fid,vol,'double');
fclose(fid);

file = strcat(path_out,'lv_vol');
file = strcat(file,'.cor');
fid  = fopen(file,'wb');
fwrite(fid,lwall,'double');
fclose(fid);
file = strcat(path_out,'lendo_vol');
file = strcat(file,'.cor');
fid  = fopen(file,'wb');
fwrite(fid,lendo2,'double');
fclose(fid);

file = strcat(path_out,'heart_sur');
file = strcat(file,'.idx');
fid  = fopen(file,'wb');
fwrite(fid,newlabel,'double');
fclose(fid);
savefile3 = strcat(path_out,'Vol.mat');
save(savefile3,'vol');

% visualization
figure(gen_mesh_figure);
nexttile;
view(3);
axis vis3d;
%daspect([1 1 .4])
colormap(gray(100))
camva(9);
box on
camlight(40, 40);
camlight(-20,-10);
lighting gouraud
axis equal
alpha(0.3)
plot3(cor(1,:),cor(2,:),cor(3,:),'r*');
vtseg.ReviewStyle.axesTitle(gca, 'Dense surface mesh nodes');
view(3);
axis vis3d;
%daspect([1 1 .4])
colormap(gray(100))
camva(9);
box on
camlight(40, 40);
camlight(-20,-10);
lighting gouraud
axis equal
alpha(0.3)
