% The CMU IDM format contains a structure named "meta" which keeps the information
% about a dataset that is not directly related to the experimental design. The format
% assumes the data is a matrix with <n> examples (or time points) by <m> voxels.
% and generally only a subset of the voxels in the volume is present. Hence, it's
% necessary to keep a mapping between columns of the data matrix and position in 3D.
%
% This is done with the following fields of meta:
%
% dimx,dimy,dimz - the dimensions of the imaging volume
%
% colToCoord - m x 3 matrix 
%
%	   vector = coordToCol(i,:) places the 3D coordinates of voxel i in vector
%
% coordToCol - <dimx> x <dimy> x <dimz> matrix
%
%	   i = colToCoord(x,y,z) gives the column of voxel with 3D coordinates x, y and z
%	   If i = 0 then the voxel is not in the data matrix.
%
% indicesIn3D - m element vector
%
%	   these are just the linear indices into a <dimx> x <dimy> x <dimz> matrix
%	   of the voxels in the data matrix, i.e.
%
%	   volume(meta.indicesIn3D) should return 1 through m
%
%	   This is useful in order to load a vector of m elements
%	   (e.g. the p-values of some test over each data matrix column
%	   into a volume, for instance
%
%	   volume = repmat(NaN,[dimx,dimy,dimz]); % creates a 3D volume with NaN values
%	   volume(meta.indicesIn3D) = vector;     % places vector in that 3D volume
%
%
% The easiest way to create the structure is from a 3D matrix with a binary mask
% of the voxels you are interested in, "mask" (can be created easily by reading in
% an AFNI mask with afni_matlab, say).
%
% Input:
% - mask - a binary 3D matrix where the voxels of interest are 1 and the others are 0
%
% Output:
% - meta - the meta structure relating voxel 3D positions to indices in a vectorized
% representation, as well as neighbourhood relationships
%
% History:
%
% 2011 September 21 - fpereira@princeton.edu - added the mex options
% 2009 April 2 - fpereira@princeton.edu - created from existing code
%

function [meta] = createMetaFromMask( varargin )

mask = varargin{1};

radius         = 1; % radius for searchlight
buildAdjacency = 0; % create a sparse adjacency matrix

if exist('findNeighbours.mexglx') | exist('findNeighbours.mexa64') | exist('findNeighbours.mexmac') | exist('findNeighbours.mexmaci') | exist('findNeighbours.mexmaci64') | exist('findNeighbours.mexwin32') | exist('findNeighbours.mexwin64')
  useMEX = 1;
else
  % no mex compiled findNeighbours
  useMEX = 0;

  if exist('findNeighbours.c')
     % try making it
     fail = mex('findNeighbours.c');
     if fail
        % done
     else
        % now we can use it!
        useMEX = 1;
     end
   edn
end

idx = 2;
while idx <= nargin
  argval = varargin{idx}; idx = idx + 1;
  switch argval
   case {'adjacency'}
    % enable construction of the adjacency matrix
    buildAdjacency = 1;
   case {'radius'}
    radius = varargin{idx}; idx = idx + 1;
   case {'useMEX'}
    if useMEX == 0
      % we already know it can't be used
      fprintf('warning: there is no MEX file on the path, useMEX has no effect\n');
    else
      % has no effect, it's already on
      useMEX = 1;
    end
    idx = idx + 1;
   
   otherwise
    fprintf('unrecognized parameter %s\n',argval);return;
  end
end
if radius > 1;
  fprintf('warning: radius > 1, turning off construction of adjacency matrix\n');
  buildAdjacency = 0;
end

% 1) create the mappings between 3D and columns in a data array

[dimx,dimy,dimz] = size(mask);
meta.dimx = dimx; meta.dimy = dimy; meta.dimz = dimz; meta.dimensions = [dimx dimy dimz];

meta.indicesIn3D = find( mask(:)>0 );
m = length(meta.indicesIn3D);
[cx,cy,cz] = ind2sub(meta.dimensions,meta.indicesIn3D);
meta.colToCoord = [cx,cy,cz];
meta.coordToCol = zeros(meta.dimensions);
meta.coordToCol(meta.indicesIn3D) = 1:m;

% 2) find the neighbours of each voxel (immediately adjacent in 3D)

if useMEX
  [meta.voxelsToNeighbours,meta.numberOfNeighbours] = computeNeighboursWithinRadius(meta.colToCoord,radius,'useMEX');
else
  [meta.voxelsToNeighbours,meta.numberOfNeighbours] = computeNeighboursWithinRadius(meta.colToCoord,radius);
end

% 3) find ROIs

tmp    = mask(meta.indicesIn3D);
roiIDs = unique(tmp);
meta.roiIDs = roiIDs;
meta.nrois  = length(roiIDs);
for r = 1:meta.nrois
  roiID = roiIDs(r);
  indices = find(tmp==roiID);
  meta.roiColumns{r} = indices;
%  meta.roiIndicesIn3D{r} = meta.indicesIn3D(indices);
end

% 4) compute adjacency matrix (if requested)

meta.nVoxels = m; meta.nvoxels = m;

if buildAdjacency
  meta.neighbourAdjacency = sparse(m,m);
  for v = 1:m
    meta.neighbourAdjacency(v,meta.voxelsToNeighbours(v,1:meta.numberOfNeighbours(v))) = 1;
  end
end
