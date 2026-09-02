function corloc2Gol(path_seg,path_coarsemesh,path_global)
% input lc in 3*n

file = strcat(path_seg,'info.mat');
load(file);
IRO = IRC(:,1);
ICO = IRC(:,2);
IR = 'x';
IC = 'y';
if IR == 'x'
    A(1,:) = IRO;
    if IC == 'y'
        A(2,:) = ICO;
        A(3,:) = cross(A(1,:),A(2,:));
    else
        A(3,:) = ICO;
        A(2,:) = -cross(A(1,:),A(3,:));
    end
else if IR == 'y'
        A(2,:) = IRO;
        if IC == 'x'
            A(1,:) = ICO;
            A(3,:) = cross(A(1,:),A(2,:));
        else
            A(3,:) = ICO;
            A(1,:) = cross(A(2,:),A(3,:));
        end
    else
        A(3,:) = IRO;
        if IC == 'x'
            A(1,:) = ICO;
            A(2,:) = -cross(A(1,:),A(3,:));
        else
            A(2,:) = ICO;
            A(1,:) = cross(A(2,:),A(3,:));
        end
    end
end

t=Cor_start(1,:)';
input_filename = {'sur_heart.cor','sur_dense_heart.cor','tet_heart.cor','tet_dense_heart.cor'};
output_filename = {'sur_heart.cor','sur_dense_heart.cor','tet_heart.cor','tet_dense_heart.cor'};
for i = 1:numel(input_filename)
    % read input file, the local coordinates
    file_in = strcat(path_coarsemesh,input_filename{i});
    fid = fopen(file_in,'rb');
    lcor = fread(fid,[3,inf],'double');
    fclose(fid);
    % gcor=corLoc2Gol(lcor,IRC, Cor_start(1,:)');
    n = size(lcor,2);
    gcor = inv(A)*lcor+ t*ones(1,n);


    % write outfile, the global coordinates
    file_out = strcat(path_global,output_filename{i});
    fid = fopen(file_out,'wb');
    fwrite(fid,gcor,'double');
    fclose(fid);

    clear gcor;
    clear lcor;
    clear n;
end













end
