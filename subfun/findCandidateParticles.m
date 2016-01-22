function [ candidateData, candidateOptions ] = findCandidateParticles( movieStack, darkImage, globalOptions, candidateOptions)
% [ candidateData, candidateOptions ] = findCandidateParticles( movieStack, darkImage, globalOptions, candidateOptions)
% Find rough estimate of locations of bright spots in an image, in this
% case a movie of fluorescent molecules, for later refinement.
%
% INPUT:
%     movieStack: 3D array of intensity values (y,x,N) where N is the
%     number of frames. All images are treated piecewise and only converted
%     to double when needed to avoid memory overflow.
%
%     darkImage: 2D array of intensity correction values which is added
%     to each movie image to correct for non-isotropic camera readout.
%     Leave empty [] if no correction is needed.
%
%     globalOptions: struct of input options for this function, se
%     setDefaultOptions or TrackNTrace manual for details.
%
%     candidateOptions: struct of input options used to find localization
%     candidates. See respective plugin function for details.
%
%
% OUTPUT:
%     candidateData: 1D cell array of xy position estimates (2D row array)
%     used in later fitParticles routine.
%
%     candidateOptions: see above

global imgCorrection;
global parallelProcessingAvailable

% Parse inputs
if ~isempty(darkImage) %if correction image is provided, do it
    imgCorrection = darkImage;
    
    %if image is converted to photons, correction image has to be converted too
    %but the bias is already included. Add the bias again to avoid later
    %confusion
    if globalOptions.usePhotonConversion
        imgCorrection = (imgCorrection+globalOptions.photonBias)*(globalOptions.photonSensitivity/globalOptions.photonGain);
    end
end

nrFrames = size(movieStack,3);
candidateData = cell(nrFrames,1);

%Call plugins init function
if ~isempty(candidateOptions.initFunc)
    candidateOptions = candidateOptions.initFunc(candidateOptions);
end

% Try parallel processing of plugins main function
parallelProcessing_Failed = false;
if parallelProcessingAvailable && candidateOptions.useParallelProcessing
    try       
        imgCorrectionLocal = imgCorrection; % Need a copy for parallel processing
        
        fprintf('TNT: Locating candidates using parallel processing (Frame by Frame).\n');
        startTime = tic;
        parfor iFrame = 1:nrFrames
            img = correctMovie_Parallel(movieStack(:,:,iFrame), globalOptions, imgCorrectionLocal);
            candidateData(iFrame) = {candidateOptions.mainFunc(img,candidateOptions,iFrame)};
        end
        totalTime = toc(startTime);
        fprintf('TNT: Time elapsed %im %is.\n',floor(totalTime/60), floor(mod(totalTime,60)));
    catch err
        warning off backtrace
        warning('Parallel execution failed. Switching to serial execution.\n Error: %s.',err.message);
        warning on backtrace
        parallelProcessing_Failed = true;
    end
end

% Standard serial processing of plugins main function
if not(parallelProcessingAvailable) || not(candidateOptions.useParallelProcessing) || parallelProcessing_Failed
    if parallelProcessingAvailable && not(candidateOptions.useParallelProcessing)
        fprintf('TNT: Locating candidates (parallel processing disabled by plugin).\n');
    else
        fprintf('TNT: Locating candidates.\n');
    end    
    
    msgAccumulator = ''; % Needed for rewindable command line printing (rewPrintf subfunction)
    startTime = tic;
    elapsedTime = [];
    lastElapsedTime = 0;
    
    for iLocF = 1:nrFrames %first frame has already been dealt with
        elapsedTime = toc(startTime);
        
        % Output process every 0.5 seconds
        if( (elapsedTime-lastElapsedTime) > 0.5)
            rewindMessages();
            rewPrintf('TNT: Time elapsed %im %is - to go: %im %is\n', floor(elapsedTime/60), floor(mod(elapsedTime,60)),  floor(elapsedTime/iLocF*(nrFrames-iLocF)/60),  floor(mod(elapsedTime/iLocF*(nrFrames-iLocF),60)))
            rewPrintf('TNT: Locating candidates in frame %i/%i\n',iLocF,nrFrames)
            
            lastElapsedTime = elapsedTime;
        end
        
        img = correctMovie(movieStack(:,:,iLocF));
        
        candidateData(iLocF) = {candidateOptions.mainFunc(img,candidateOptions,iLocF)};
    end
    rewindMessages();
    rewPrintf('TNT: Time elapsed %im %is - to go: %im %is\n', floor(elapsedTime/60), floor(mod(elapsedTime,60)),  floor(elapsedTime/iLocF*(nrFrames-iLocF)/60),  floor(mod(elapsedTime/iLocF*(nrFrames-iLocF),60)))
end

% Call plugins post-processing function
if ~isempty(candidateOptions.postFunc)
    [candidateData,candidateOptions] = candidateOptions.postFunc(candidateData,candidateOptions);
end

fprintf('TNT: Candidate search done.\n');

% Verify the outParamDescription, make it fit to the data if neccessary
candidateOptions = verifyOutParamDescription(candidateData, candidateOptions);


    function rewPrintf(msg, varargin)
        % Rewindable message printing: Print msg and cache it.
        % Usage is analogous to sprintf.
        msg = sprintf(msg, varargin{:});
        msgAccumulator = [msgAccumulator, msg];
        fprintf(msg);
    end

    function rewindMessages()
        % Remove cached messages from command line, reset cache
        reverseStr = repmat(sprintf('\b'), 1, length(msgAccumulator));
        fprintf(reverseStr);
        
        msgAccumulator = '';
    end

end

