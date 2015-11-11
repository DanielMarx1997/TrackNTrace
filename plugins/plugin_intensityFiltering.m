function [plugin_name, plugin_type] = plugin_intensityFiltering(h_panel, inputOptions)
    if nargin < 2
        inputOptions = [];
    end

    % Name of the component these options are for
    plugin_name = 'Intensity filtering';

    % Type of plugin.
    % 1: Candidate detection
    % 2: Spot fitting
    % 3: Tracking
    plugin_type = 1;
    
    % Enter names of the parameters
    % These translate to the names of variables inside options struct this plugin
    % outputs by removing all white spaces.
    par_name  = {'particle_radius','threshold_relative','pval_min','iteration_count'};

    % Enter type of the parameters
    % possible: 'float', 'int', 'bool','list'
    par_type  = {'int','float','float','int'};

    % Default value for parameters
    % Should be a number for 'float'/'int', true/false for 'bool'
    % or a cell array string list of possible choices for 'list' (first entry is default)
    par_defaultValue = {3,5,0.05,10};

    % Tooltip for the parameters
    par_tooltip = {'Approxiate spot radius in [pixels]',...
        'Relative intensity threshold in percent [0,100). Example: 4 means only spots with intensity in the top 4% count.',...
        'P value for significance test of signal against background [0,1]. Lower means higher quality spots.',...
        'Background is estimated every N times in the main loop. Set to higher number to speed up function.'};
    
    % Calling the plugin function without arguments just returns its name and type
    if (nargin == 0); return; end

    createOptionsPanel(h_panel, plugin_name, par_name, par_type, par_defaultValue, par_tooltip,inputOptions);

    % Save handle of the plugins function
    options = getappdata(h_panel,'options');
    options.functionHandle = @findCandidates_intensityFiltering;
    setappdata(h_panel,'options',options);
end



function [candidatePos] = findCandidates_intensityFiltering(img,options)
% Find particle candidates in fluorescence images based on intensity, local
% background and size.
%
% INPUT:
%     img - 2D matrix of pixel intensities, data type and normalisation
%     arbitrary
%
%     W0 - 1D positive integer, search window size used for filtering image
%     and detecting local maximas
%
%     INTENS_THRSH - 1D positive double percentage [0,100), used to
%     consider only the top INTENS_THRSH percent highest pixel intensities.
%     Lower means less candidates.
%
%     PVAL_MIN - 1D positive double [0,1], used to reject candidates whose
%     intensities fail a P-test against their local background (assumed to
%     be Gaussian). Lower means less candidates.
% 
%     N_ITER - 1D positive integer, background is calculated every time
%     main loop variable every time mod(loop_var,N_ITER) is 0
%
%
% OUTPUT:
%     candidatePos - Nx2 matrix of particle candidate positions [column
%     pixel, row pixel] without subpixel position. Middle of upper left pixel would be [1,1].

global iLocF;

% parse options
W0 = options.particle_radius;
INTENS_THRSH = options.threshold_relative;
PVAL_MIN = options.pval_min;
N_ITER = options.iteration_count;

calc_bck = mod(iLocF,N_ITER)==0;

% find candidates
cands_w0 = detectSpots(img,W0,INTENS_THRSH,PVAL_MIN,calc_bck);
% n_cands = numel(cands_w0);

[pos_y,pos_x] = ind2sub(size(img),cands_w0);
candidatePos = [pos_x,pos_y]; %save candidates in [column pixels, row pixels] format
% neighbours = zeros(n_cands,1);
%if no smaller features can exist or the search range is too low, don't
%bother
% if W0<=1 || MIN_DIST<=sqrt(2)
%     return
% end

% %find smaller candidates
% cands_w = detectSpots(img,W0-1,INTENS_THRSH,PVAL_MIN,false);
% [pos_y,pos_x] = ind2sub(size(img),cands_w);
% %now find number of smaller neighbours within a a circle of radius MIN_DIST around
% %every candidate (expensive in Matlab!)
% for i=1:n_cands
%     neigh_list = repmat(candidatePos(i,:),numel(cands_w),1)-[pos_x,pos_y];
%     neighbours(i) = numel(sqrt(neigh_list(:,1).^2+neigh_list(:,2))<=MIN_DIST)-1; %subtract 1 for original pos
% end


    function [max_indices] = detectSpots(img,w,INTENS_THRSH,PVAL_MIN,calc_bck)
        global img_bck_mean img_bck_std
        %convolution with Gaussian blur (sigma = 1px, camera discretization) and moving
        %average, kernel window length is 2*w+1
        lambda_k = 1;
        [x_k,y_k] = meshgrid(-w:w,-w:w);
        b_0 = sum(exp(-(-w:w).^2/(4*lambda_k^2)))^2;
        k_0 = 1/b_0*sum(exp(-(-w:w).^2/(2*lambda_k^2)))^2 + b_0/(2*w+1)^2; %normalization constant
        kernel = 1/k_0*(1/b_0*exp(-(x_k.^2+y_k.^2)/(4*lambda_k^2))+1/(2*w+1)^2);
        img_conv = conv2(img,kernel,'same'); %filtered image
        
        %find maximums by image dilation
        neigh = ones(2*w+1);
        img_dilated = imdilate(img_conv, neigh);
        max_indices = find(img_conv == img_dilated);
        
        %calculate local background with twice bigger window by
        %LeastMedianSquares method
        if calc_bck || isempty(img_bck_mean)
            [img_bck_mean,img_bck_std] = calcBG(img_conv,size(img_conv,1),size(img_conv,2),2*w+1);
        end
        
        %calculate intensity threshold
        img_sort = sort(img_conv(:));
        intens_cut = img_sort(round((1-INTENS_THRSH/100)*size(img_sort,1))); %cutoff intensity, anything smaller will be rejected
        pvals = 1-normcdf(img_conv(max_indices),img_bck_mean(max_indices),img_bck_std(max_indices)); %compare background to gaussian
        
        %give pixel positions
        max_indices = max_indices(img_conv(max_indices)>=intens_cut & pvals<=PVAL_MIN);
    end %END SUBFUN


end %END intensity filtering
