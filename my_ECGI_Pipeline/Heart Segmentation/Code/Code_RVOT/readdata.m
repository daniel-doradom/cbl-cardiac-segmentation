function readdata(path_in,path_out)
%This script will read the dicom images to get information about the
%relationship between the global and local coordinate system.
%path_in  : the path for dicom images  (short axis for ventricles)
%path_out : path for output data (matrices)
%num      : the total number of slices.
%start    : file number of initial slice.
% Read the global coordinate value of top left corner of each image in Cor_start
%epi = zeros(imgH,imgW,num);


folder=dir(strcat(path_in,'*.dcm'));
num=length(folder);
Cor_start = zeros(num,3);
IRC = zeros(3,2);
i=1;
for file = folder'
    if ~file.isdir
     
        f = strcat(path_in,file.name);
        info = dicominfo(f);
         Cor_start(i,:) = info.ImagePositionPatient;
         
       
        if(i==1)% read data common to all files i.e. orientation, pixel spacing
              PixelSpace = info.PixelSpacing;
        imgH = info.Height;
        imgW = info.Width;
        IRC(:,1) = info.ImageOrientationPatient(1:3);
        IRC(:,2) = info.ImageOrientationPatient(4:6);
        end
         i=i+1;
        
    end
end

% Calculate local slice positions.  Older callers only use sliceSpacing, but
% Gen_mesh also consumes sliceLocationsLocal so selected DICOM subsets may have
% nonuniform inter-slice spacing while retaining exact physical geometry.
gcor_s =Cor_start(1,:)';
gcor_f =Cor_start(num,:)';
A(1,:) = IRC(:,1);
A(2,:) = IRC(:,2);
A(3,:) = cross(A(1,:),A(2,:));
t = Cor_start(1,:)';  
lcor_s=A*(gcor_s-t);
lcor_f=A*(gcor_f-t);
sliceSpacing = (lcor_f(3)-lcor_s(3))/(num-1);
localCoordinates = A * (Cor_start' - t * ones(1, num));
sliceLocationsLocal = localCoordinates(3, :)';
if num > 1 && any(abs(diff(sliceLocationsLocal)) < eps)
    error('DICOM slice positions must be distinct for meshing.');
end

% save file into folder
savefile4 = strcat(path_out,'info.mat');
save(savefile4,'Cor_start','PixelSpace','imgH','imgW','num','IRC','sliceSpacing','sliceLocationsLocal');
end
