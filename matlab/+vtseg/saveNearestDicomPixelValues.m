function saveNearestDicomPixelValues(global_path, SA_full_stack_path)
    % Sample, plot, and save nearest DICOM pixel values and locations.


    [dicoms_struct, dicoms_imgs] = vtseg.DicomUtils.readDicomFiles(SA_full_stack_path);


    tet_nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, 'tet_heart.cor'), 3, 'double');
    tet_nodes_dense = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, 'tet_dense_heart.cor'), 3, 'double');
    sur_nodes = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, 'sur_heart.cor'), 3, 'double');
    sur_nodes_dense = vtseg.DicomUtils.read_Geometry_heart(fullfile(global_path, 'sur_dense_heart.cor'), 3, 'double');


    [pixel_values, locations] = vtseg.DicomUtils.nearestDicomPixelValues(tet_nodes, dicoms_struct, dicoms_imgs);
    [pixel_values_dense, locations_dense] = vtseg.DicomUtils.nearestDicomPixelValues(tet_nodes_dense, dicoms_struct, dicoms_imgs);
    [pixel_values_sur, locations_sur] = vtseg.DicomUtils.nearestDicomPixelValues(sur_nodes, dicoms_struct, dicoms_imgs);
    [pixel_values_sur_dense, locations_sur_dense] = vtseg.DicomUtils.nearestDicomPixelValues(sur_nodes_dense, dicoms_struct, dicoms_imgs);


    fprintf('COARSE valid vertices: %.2f%%\n', 100 * nnz(~isnan(pixel_values)) / numel(pixel_values));
    fprintf('DENSE valid vertices: %.2f%%\n', 100 * nnz(~isnan(pixel_values_dense)) / numel(pixel_values_dense));
    fprintf('SURFACE valid vertices: %.2f%%\n', 100 * nnz(~isnan(pixel_values_sur)) / numel(pixel_values_sur));
    fprintf('DENSE SURFACE valid vertices: %.2f%%\n', 100 * nnz(~isnan(pixel_values_sur_dense)) / numel(pixel_values_sur_dense));


    figure();


    subplot(1,2,1);
    scatter3(tet_nodes(:,1), tet_nodes(:,2), tet_nodes(:,3), 10, pixel_values, 'filled');
    title('Coarse Mesh'); view(3); axis equal; xlabel('X'); ylabel('Y'); zlabel('Z'); colorbar; colormap("gray");


    subplot(1,2,2);
    scatter3(tet_nodes_dense(:,1), tet_nodes_dense(:,2), tet_nodes_dense(:,3), 10, pixel_values_dense, 'filled');
    title('Dense Mesh'); view(3); axis equal; xlabel('X'); ylabel('Y'); zlabel('Z'); colorbar; colormap("gray");


    sgtitle('Nearest DICOM Pixel Values');


    fid = fopen(fullfile(global_path, 'tet_node_values.val'), 'wb');
    fwrite(fid, pixel_values, 'double');
    fclose(fid);


    fid = fopen(fullfile(global_path, 'tet_dense_node_values.val'), 'wb');
    fwrite(fid, pixel_values_dense, 'double');
    fclose(fid);

    fid = fopen(fullfile(global_path, 'sur_node_values.val'), 'wb');
    fwrite(fid, pixel_values_sur, 'double');
    fclose(fid);

    fid = fopen(fullfile(global_path, 'sur_dense_node_values.val'), 'wb');
    fwrite(fid, pixel_values_sur_dense, 'double');
    fclose(fid);


    fid = fopen(fullfile(global_path, 'tet_node_locations.val'), 'wb');
    fwrite(fid, table2array(locations).', 'double');
    fclose(fid);


    fid = fopen(fullfile(global_path, 'tet_dense_node_locations.val'), 'wb');
    fwrite(fid, table2array(locations_dense).', 'double');
    fclose(fid);

    fid = fopen(fullfile(global_path, 'sur_node_locations.val'), 'wb');
    fwrite(fid, table2array(locations_sur).', 'double');
    fclose(fid);

    fid = fopen(fullfile(global_path, 'sur_dense_node_locations.val'), 'wb');
    fwrite(fid, table2array(locations_sur_dense).', 'double');
    fclose(fid);


    fprintf('Pixel values and locations saved to:\n%s\n', global_path);
end
