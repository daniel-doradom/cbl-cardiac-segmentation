function [distMat,distPos] = getDistance(mat1,mat2)
[row1,col1] = size(mat1);
[row2,col2] = size(mat2);
distMat  = zeros(row1,1);

for i=1:row1
    tt = mat1(i,:)';
    [distMat(i),distPos(i)] = min(dist(mat2,tt));
end
