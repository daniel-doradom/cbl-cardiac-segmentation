function [distMat,distPos] = getDistance(mat1,mat2)
%GETDISTANCE Find each query point's nearest reference point.

if ~ismatrix(mat1) || ~ismatrix(mat2) || size(mat1, 2) ~= size(mat2, 2)
    error('vtseg:GetDistanceDimensions', ...
        'Query and reference points must have the same coordinate dimension.');
end
if isempty(mat2)
    error('vtseg:GetDistanceEmptyReference', 'Reference points cannot be empty.');
end

query_count = size(mat1, 1);
distMat = zeros(query_count, 1);
distPos = zeros(1, query_count);
for index = 1:query_count
    differences = double(mat2) - double(mat1(index, :));
    squared_distances = sum(differences .^ 2, 2);
    [minimum_squared_distance, distPos(index)] = min(squared_distances);
    distMat(index) = sqrt(minimum_squared_distance);
end
