function [y, stopCondition, sigma, t] ...
    = cons_smacof_pip(dx, y, bnd, w, con, smacof_opts, scip_opts)
% CONS_SMACOF_PIP  SMACOF algorithm with polynomial constraints (PIP file
% format)
%
% Scaling by MAjorizing a COnvex Function (SMACOF) is an iterative solution
% to the Multidimensional Scaling (MDS) problem (see de Leeuw and Mair [1]
% for an up to date review).
%
% The classic implementation of SMACOF uses an iterative algorithm that
% relies on the Guttman transform update. Our function here implements a
% different approach, where the Guttman transform update is replaced by
% solving a Quadratic Program (QP) (as proposed by Dwyer et al [2]) with
% polynomial constraints.
%
% In this implementation, we use the SCIP binary to solve the constrained
% QP. This binary can be downloaded for Linux, MacOS X and Windows from the
% Zuse Institute Berlin (ZIB) website
%
%   http://scip.zib.de/#download
%
% The objective function is
%
%   min_y 1/2 y' * H * y + f' * y
%
% subject to the constraints and bounds provided by the user.
%
% We use the PIP file format to formulate the constrained QP and pass it to
% SCIP.
%
%   http://polip.zib.de/pipformat.php
%
%
% Y = cons_smacof_pip(D, Y0, BND, [], CON)
%
%   D is an (N, N)-distance matrix, with distances between the points in an
%   N-point configuration. D can be full or sparse. D(i,j)=0 means that
%   vertices i and j are not directly connected.
%
%   Y0 is an initial guess of the solution, given as an (N, P)-matrix,
%   where P is the dimensionality of the output points. Y0 can be generated
%   randomly.
%
%   BND is a cell array with the variable bounds in PIP format, and cannot
%   be empty (otherwise SCIP doesn't return a solution). E.g.
%
%      BND = {'Bounds', ' -1 <= x1 <= 4', ' -1 <= y1 <= 2.5', ...
%             ' -1 <= x2 <= 4', ' -1 <= y2 <= 2.5'};
%
%   CON is a cell array with the problem constraints in PIP format, and
%   cannot be empty (otherwise SCIP doesn't return a solution). E.g.
%
%      CON = {'Subject to', ...
%            ' c1: -0.5 x6 y7 +0.5 x3 y7 +0.5 x7 y6 -0.5 x3 y6 -0.5 x7 y3 +0.5 x6 y3 >= 0.1'};
%
%   Y is the solution computed by SMACOF. Y is a point configuration with
%   the same size as Y0.
%
% Y = cons_smacof_pip(..., SMACOF_OPTS, SCIP_OPTS)
%
%   SMACOF_OPTS is a struct with tweaking parameters for the SMACOF
%   algorithm.
%
%     'MaxIter': (default = 0) Maximum number of majorization iterations we
%                allow the optimisation algorithm.
%
%     'Epsilon': (default = Inf) The algorithm will stop if
%                (SIGMA(I+1)-SIGMA(I))/SIGMA(I) < OPTS.Epsilon.
%
%     'Display': (default = 'off') Do not display any internal information.
%                'iter': display internal information at every iteration.
%
%     'TolFun':  (default = 1e-12) Termination tolerance of the stress
%                value.
%
%   SCIP_OPTS is a struct with tweaking parameters for the SCIP algorithm.
%
%     'scipbin': (defaults = 'scip-3.0.2.linux.x86_64.gnu.opt.spx' (Linux),
%                            'scip-3.0.2.darwin.x86_64.gnu.opt.spx' (Mac),
%                            'scip-3.0.2.mingw.x86_64.intel.opt.spx.exe' (Win))
%                Name of the SCIP binary/executable. This binary should be
%                available in the system path. E.g. place it in
%                gerardus/programs. The binaries/executable can be
%                downloaded from http://scip.zib.de/#download.
%
%     'limits_absgap': (default 0.0) solving stops, if the absolute 
%                gap = |primalbound - dualbound| is below the given value.
%
%     'limits_gap': (default 0.0) solving stops, if the relative 
%                gap = |primal - dual|/MIN(|dual|,|primal|) is below the
%                given value.
%
%     'limits_time': (default 1e+20) maximal time in seconds to run.
%
%     'limits_solutions': (default -1) solving stops, if the given number
%                of solutions were found (-1: no limit).
%
%     'display_verblevel': (default 4) verbosity level of output (0: SCIP
%                quiet mode).
%
%
% [1] J de Leeuw, P Mair, "Multidimensional scaling using majorization:
% SMACOF in R", Journal of Statistical Software, 31(3), 2009.
%
% [2] T. Dwyer, Y. Koren, and K. Marriott, "Drawing directed graphs using
% quadratic programming," IEEE Transactions on Visualization and Computer
% Graphics, vol. 12, no. 4, pp. 536-548, 2006.
%
% See also: cmdscale, qcqp_smacof.

% Author: Ramon Casero <rcasero@gmail.com>
% Copyright © 2014 University of Oxford
% Version: 0.0.1
% $Rev$
% $Date$
%
% University of Oxford means the Chancellor, Masters and Scholars of
% the University of Oxford, having an administrative office at
% Wellington Square, Oxford OX1 2JD, UK. 
%
% This file is part of Gerardus.
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details. The offer of this
% program under the terms of the License is subject to the License
% being interpreted in accordance with English Law and subject to any
% action against the University of Oxford being under the jurisdiction
% of the English Courts.
%
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see
% <http://www.gnu.org/licenses/>.

%% Input arguments

% check arguments
narginchk(5, 7);
nargoutchk(0, 4);

% number of points
N = size(dx, 1);

% dimensionality of the points
D = size(y, 2);
if (D ~= 2)
    error('Only implemented for 2D output')
end
        

% check inputs
if (N ~= size(dx, 2))
    error('D must be a square matrix')
end
if (N ~= size(y, 1))
    error('Y0 must have the same number of rows as D')
end

% defaults
if (nargin < 4 || isempty(w))
    % if the user doesn't provide a weight matrix, we simply assign 1 if
    % two vertices are connected, and 0 if not
    w = double(dx ~= 0);
    if (any(diag(w)) ~= 0)
        error('Assertion error: W matrix has diagonal elements that are non-zero')
    end
end
if (any(size(w) ~= [N N]))
    error('W must be a square matrix with the same size as D')
end

% SMACOF_OPTS defaults
if (nargin < 6 || isempty(smacof_opts) || ~isfield(smacof_opts, 'MaxIter'))
    smacof_opts.MaxIter = 100;
end
if (nargin < 6 || isempty(smacof_opts) || ~isfield(smacof_opts, 'Epsilon'))
    smacof_opts.Epsilon = 0;
end
if (nargin < 6 || isempty(smacof_opts) || ~isfield(smacof_opts, 'Display'))
    smacof_opts.Display = 'off';
end
if (nargin < 6 || isempty(smacof_opts) || ~isfield(smacof_opts, 'TolFun'))
    smacof_opts.TolFun = 1e-12;
end

% SCIP_OPTS
if (nargin < 7 || isempty(scip_opts) || ~isfield(scip_opts, 'scipbin'))
    
    % default name of the SCIP binary depending on the architecture
    if (isunix)
        SCIPBIN = 'scip-3.0.2.linux.x86_64.gnu.opt.spx';
    elseif (ismac)
        SCIPBIN = 'scip-3.0.2.darwin.x86_64.gnu.opt.spx';
    elseif (ispc)
        SCIPBIN = 'scip-3.0.2.mingw.x86_64.intel.opt.spx.exe';
    else
        error('Operating system not recognized: I do not know what is the default name for the SCIP binary')
    end
end

scip_opts_comm = {};
if (nargin >= 7 && ~isempty(scip_opts))
    
    % SCIP binary
    if (isfield(scip_opts, 'scipbin'))
        SCIPBIN = scip_opts.scipbin;
    end
    
    % limits options
    
    % solving stops, if the absolute gap = |primalbound - dualbound| is below the given value [0.0]
    if (isfield(scip_opts, 'limits_absgap'))
        scip_opts_comm{end+1} = [' -c "set limits absgap ' num2str(scip_opts.limits_absgap) '"'];
    end
    
    % solving stops, if the relative gap = |primal - dual|/MIN(|dual|,|primal|) is below the given value [0.0]
    if (isfield(scip_opts, 'limits_gap'))
        scip_opts_comm{end+1} = [' -c "set limits gap ' num2str(scip_opts.limits_gap) '"'];
    end
    
    % maximal time in seconds to run [1e+20]
    if (isfield(scip_opts, 'limits_time'))
        scip_opts_comm{end+1} = [' -c "set limits time ' num2str(scip_opts.limits_time) '"'];
    end
    
    % solving stops, if the given number of solutions were found (-1: no limit) [-1]
    if (isfield(scip_opts, 'limits_solutions'))
        scip_opts_comm{end+1} = [' -c "set limits solutions ' num2str(scip_opts.limits_solutions) '"'];
    end
    
    % display options
    QUIETFLAG = [];
    if isfield(scip_opts, 'display_verblevel')
        if (scip_opts.display_verblevel == 0)
            QUIETFLAG = ' -q ';
        end
        scip_opts_comm{end+1} = [' -c "set display verblevel ' num2str(scip_opts.display_verblevel) '"'];
    end
    
    
end

%% Objective function: 1/2 nu' * H * nu + f' * nu

% pre-compute the weighted Laplacian matrix
V = -w;
V(1:N+1:end) = sum(w, 2);

% quadratic terms of the objective function
objfunq = cell(1, N);

% main diagonal terms
for I = 1:N
    
    objfunq{I} = sprintf(...
        '+%.6g x%d x%d + %.6g y%d y%d', ...
        full(V(I, I)), I, I, full(V(I, I)), I, I);
        
end
objfunq{1} = [' obj: ' objfunq{1}];

% upper triangular matrix terms
for I = 1:N
    for J = I+1:N
        
        % V is sparse, so we don't add terms that are going to be
        % multiplied by 0 anyway
        if (V(I, J))
            
            % main diagonal terms
            objfunq{end+1} = sprintf(...
                '+%.6g x%d x%d + %.6g y%d y%d', ...
                2*full(V(I, J)), I, J, 2*full(V(I, J)), I, J);
            
        end
        
    end
end

% the linear term of the objective function (f) has to be computed at each
% iteration of the QPQC-SMACOF algorithm. Thus, it is not computed here

%% SMACOF algorithm

% file name and path to save PIP model and solutions
pipfilename = [tempdir 'model.pip'];
solfilename = [tempdir 'model-sol.txt'];

% init stopCondition
stopCondition = [];

% Euclidean distances between vertices in the current solution
dy = dmatrix_con(dx, y);

% initial stress
sigma = zeros(1, smacof_opts.MaxIter+1);
sigma(1) = sum(sum(w .* (dx - dy).^2));

% display algorithm's evolution
t = zeros(1, smacof_opts.MaxIter+1); % time past from 0th iteration
tic
if (strcmp(smacof_opts.Display, 'iter'))
    fprintf('Iter\tSigma\t\t\tTime (sec)\n')
    fprintf('===================================================\n')
    fprintf('%d\t\t%.4e\t\t%.4e\n', 0, sigma(1), 0.0)
end

% auxiliary intermediate result
mwdx = -w .* dx;

% majorization loop
for I = 1:smacof_opts.MaxIter

    % auxiliary matrix B: non-main-diagonal elements
    B = mwdx ./ dy;
    B(isnan(B)) = 0;

    % auxiliary matrix B: main diagonal elements
    B(1:N+1:end) = -sum(B, 2);
    
    % the linear term (f) of the quadratic objective function 
    % 1/2 nu' * H * nu + f' * nu
    % has to be recomputed at every iteration
    f = -2 * B * y;
    
    % convert linear term to PIP format
    objfunl = cell(1, N);
    for J = 1:N
        objfunl{J} = sprintf(...
            '+%.6g x%d +%.6g y%d', ...
            f(J, 1), J, f(J, 2), J);
    end
    
    % create PIP file to describe problem
    fid = fopen(pipfilename, 'w');
    if (fid == -1)
        error(['Cannot open file ' pipfilename ' to save PIP model'])
    end
    fprintf(fid, '%s\n%s\n%s\n%s\n%s\n%s\n', ...
        'Minimize', objfunq{:}, objfunl{:}, bnd{:}, con{:}, 'End');
    if (fclose(fid) == -1)
        error(['Cannot close file ' pipfilename ' to save PIP model'])
    end
    
    % solve the quadratic problem
    system([...
        SCIPBIN...
        QUIETFLAG ...
        ' -c "read ' pipfilename '"'...
        strcat(scip_opts_comm{:}) ...
        ' -c "optimize"'...
        ' -c "write solution ' solfilename '"'...
        ' -c "quit"']);
    
    % read solution
    aux = read_solution(solfilename, size(y));
    if (isscalar(aux) && isnan(aux))
        % maybe we were already at the optimum or something else happened.
        % But for some reason, SCIP did not return a solution. Thus, we
        % keep the solution from the previous step
        stopCondition{end+1} = 'SCIPDidNotUpdateSolution';
    else
        y = aux;
    end
    
    % recompute distances between vertices in the current solution
    dy = dmatrix_con(dx, y);

    % compute stress with the current solution
    sigma(I+1) = sum(sum(w .* (dx - dy).^2));
    
    % display algorithm's evolution
    t(I+1) = toc;
    if (strcmp(smacof_opts.Display, 'iter'))
        fprintf('%d\t\t%.4e\t\t%.4e\n', I, sigma(I+1), t(I+1))
    end
    
    % check whether the stress is under the tolerance level requested by
    % the user
    if (sigma(I+1) < smacof_opts.TolFun)
        stopCondition{end+1} = 'TolFun';
    end
    
    % check whether the improvement in stress is below the user's request,
    % and it's positive (don't stop if the error gets worse)
    if ((sigma(I)-sigma(I+1))/sigma(I) < smacof_opts.Epsilon ...
        && (sigma(I)-sigma(I+1))/sigma(I) >= 0)
        stopCondition{end+1} = 'Epsilon';
    end

    % stop if any stop condition has been met
    if (~isempty(stopCondition))
        break;
    end
    
end

% check whether the "maximum number of iterations" stop condition has been
% met
if (I == smacof_opts.MaxIter)
    stopCondition{end+1} = 'MaxIter';
end

% prune stress and time vectors if convergence was reached before the
% maximum number of iterations
sigma(I+2:end) = [];
t(I+2:end) = [];

end

% read SCIP solution from a text file created by SCIP
%
% file: path and file name of the solution file.
%
% sz: size of the output matrix with the solution. This parameter makes the
%     code easier to write, and it also allows to detect missing variables
%     in the solution
%
% y: matrix with the solution as a point configuration (each row is a
%    point)
function y = read_solution(file, sz)

if (sz ~= 2)
    error('We only know how to read solutions that are sets of 2D points')
end

fid = fopen(file, 'r');
if (fid == -1)
    error(['Cannot open file ' file ' to read solution'])
end

% read contents of the file. Example result:
%
% solution status: optimal solution found
% objective value:                     468.345678663118
% x1                                                 -4 	(obj:0)
% y1                                                  2 	(obj:0)
% x2                                  0.613516669331233 	(obj:0)
% y2                                                 -4 	(obj:0)
% x3                                   1.24777861008035 	(obj:0)
% y3                                  -3.43327058768579 	(obj:0)
% x4                                                 -4 	(obj:0)
% y4                                 -0.804343353251697 	(obj:0)
% x5                                                  2 	(obj:0)
% y5                                                 -4 	(obj:0)
% x6                                  -3.31069797707353 	(obj:0)
% y6                                   1.21192102496956 	(obj:0)
% x7                                     1.643412276563 	(obj:0)
% y7                                  -3.72674560989634 	(obj:0)
% quadobjvar                           468.345678663118 	(obj:1)
c = textscan(fid, '%s%f%s', 'Headerlines', 2, 'Delimiter', ' ', 'MultipleDelimsAsOne', true);
fclose(fid);

% if our initial guess was the optimum, then SCIP is going to create a
% solution file with only the two header lines. This means
if isempty(c{1})
    y = nan;
    return;
end

% if SCIP has found a solution, read it from the file into the output
% matrix
y = nan(sz);
for I = 1:length(c{1})-1
    
    % variable name
    varname = c{1}{I};
    
    % vertex index
    idx = str2double(varname(2:end));
    
    if (c{1}{I}(1) == 'x') % this is an x-coordinate
        y(idx, 1) = c{2}(I);
    elseif (c{1}{I}(1) == 'y') % this is a y-coordinate
        y(idx, 2) = c{2}(I);
    end
    
end

end