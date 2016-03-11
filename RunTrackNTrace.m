function RunTrackNTrace()
clearGlobals(); % Clear global variables used by TNT

% Global variables accessible by plugins
global globalOptions;
global candidateOptions
global fittingOptions
global trackingOptions
global movie;
global filename_movie;
global imgCorrection; %#ok<NUSED>

addRequiredPathsTNT();

fprintf('Starting Track''N''Trace.\n')

%% Load default options
[globalOptions_def, TNToptions] = getDefaultOptions();

%% Check if parallel processing is available
global parallelProcessingAvailable
parallelProcessingAvailable = false;

if TNToptions.enableParallelProcessing
    try
        nrRunningWorkers = matlabpool('size');
        if(nrRunningWorkers == 0);
            matlabpool('open','local');
        end
        parallelProcessingAvailable = true;
        fprintf('TNT: Parallel processing available (%i workers).\n', matlabpool('size'))
    catch
        parallelProcessingAvailable = false;
        fprintf('TNT: Parallel processing unavailable.\n')
    end
end

%% Load and adjust the default settings for this batch
[movie_list, globalOptions, candidateOptions,fittingOptions,trackingOptions, GUIreturns] = startupGUI();
if(isempty(globalOptions))
    globalOptions = globalOptions_def;
end;
if GUIreturns.userExit;
    userExitFunc();
    return;
end;

%% Adjust options for each movie and test settings if desired
GUIinputs.TNToptions = TNToptions;
GUIinputs.showStartupInformation = true;
GUIinputs.outputFolderSameAsMovie = true;
GUIinputs.outputFolder = '';

% Calculate default dark image if given in default options
dark_img_def = [];
if(~isempty(globalOptions_def.filename_dark_movie))
    dark_img_def = CalculateDark(read_tiff(globalOptions_def.filename_dark_movie));
end

% Create timestamp for output files
time = clock;
timestamp = sprintf('%i-m%02i-d%02i-%02ih%02i',time (1),time(2),time(3),time(4),time(5));

% Iterate through all movies in the list
GUIreturns.useSettingsForAll = false;

list_filenames_TNTdata = cell(0);
for iMovie=1:numel(movie_list)
    % Is this movie the last one to analyze?
    if(iMovie == numel(movie_list))
       GUIinputs.lastMovieInList = true;
    else
       GUIinputs.lastMovieInList = false;
    end
    
    filename_movie = movie_list{iMovie};
    [pathToMovie,filename,~] = fileparts(filename_movie);
    
    % Check if movie can be read
    if(~isempty(filename_movie))
        try
            [~,movie] = evalc(['read_tiff(''',filename_movie,''',false,[1,2])']); % Read 2 frames. note: evalc suppresses output
        catch err
            warning('Could not read movie ''%s''.\n  Error: %s',filename_movie,err.message);
            continue;
        end
    else
        continue;
    end
    
    % Set dark image to default for this movie
    dark_img = dark_img_def;
    
    % Does the user want to adjust the settings per movie?
    if not(  GUIreturns.useSettingsForAll )
        % Give file to adjust settings for to GUI
        GUIinputs.filename_movie = filename_movie;
        
        [globalOptions, candidateOptions,fittingOptions,trackingOptions, GUIreturns] = settingsGUI(globalOptions, candidateOptions,fittingOptions,trackingOptions, GUIinputs);
        % Save output folder settings
        GUIinputs.outputFolderSameAsMovie = GUIreturns.outputFolderSameAsMovie;
        GUIinputs.outputFolder = GUIreturns.outputFolder;
        
        GUIinputs.showStartupInformation = false; % Only show this on first startup
        if GUIreturns.userExit;
            userExitFunc(); % Cleanup
            return;
        end;
        
        % Check if different dark movie was given
        if(~strcmp(globalOptions_def.filename_dark_movie, globalOptions.filename_dark_movie))
            if(~isempty(globalOptions.filename_dark_movie))
                try
                    dark_img = CalculateDark(read_tiff(globalOptions.filename_dark_movie));
                catch err
                    error('Error when calculating dark image from movie ''%s''.\n  Error: %s',globalOptions.filename_dark_movie,err.message);
                end
            end
        end
        
        % Set same settings for all remaining movies if user said so
        if GUIreturns.useSettingsForAll; GUIreturns.previewMode = false; end;
        
        % If preview mode is enabled, analyze first X frames and show GUI
        if GUIreturns.previewMode
            first_run = true;
            filename_dark_movie = globalOptions.filename_dark_movie;
            while true
                if not(first_run)
                    [globalOptions, candidateOptions,fittingOptions,trackingOptions, GUIreturns] = settingsGUI(globalOptions, candidateOptions,fittingOptions,trackingOptions, GUIinputs);
                    % Save output folder settings
                    GUIinputs.outputFolderSameAsMovie = GUIreturns.outputFolderSameAsMovie;
                    GUIinputs.outputFolder = GUIreturns.outputFolder;
                    
                    if GUIreturns.userExit;
                        userExitFunc();
                        return;
                    end;
                    if GUIreturns.useSettingsForAll; GUIreturns.previewMode = false; end; %dont go through other movies anymore
                end
                
                if not(GUIreturns.previewMode); break; end; % If preview mode was disabled by user in the settingsGUI
                % Check if requested frame interval has changed -> re-read movie if neccessary
                if first_run || GUIreturns.previewIntervalChanged
                    movie = read_tiff(filename_movie, false, [globalOptions.firstFrameTesting, globalOptions.lastFrameTesting]);
                end
                % Check if different dark movie was given
                if(~strcmp(filename_dark_movie, globalOptions.filename_dark_movie))
                    if(~isempty(globalOptions.filename_dark_movie))
                        try
                            dark_img = CalculateDark(read_tiff(globalOptions.filename_dark_movie));
                        catch err
                            error('Error when calculating dark image from movie ''%s''.\n  Error: %s',globalOptions.filename_dark_movie,err.message);
                        end
                    end
                    filename_dark_movie = globalOptions.filename_dark_movie;
                end
                
                % IF: this is the first run perform all steps. ELSE: Reuse unchanged data from the last run
                if first_run
                    [candidateData_preview,fittingData_preview, trackingData_preview, previewOptions] = runPreview(movie,dark_img);
                else
                    [candidateData_preview,fittingData_preview, trackingData_preview, previewOptions] = runPreview(movie,dark_img, candidateData_preview, fittingData_preview, trackingData_preview, previewOptions, GUIreturns);
                end
                first_run = false;
            end
        end
        
    end %not( GUIreturns.useSettingsForAll )
        
    
    % --  Save options   --
    
    % Build filename for TNT file
    if GUIreturns.outputFolderSameAsMovie
        TNToutputPath = [pathToMovie,filesep];
    else
        if isempty(GUIreturns.outputFolder)
            TNToutputPath = [];
        else            
            TNToutputPath = [GUIreturns.outputFolder,filesep];
        end
    end
    
    filename_TNTdata = [TNToutputPath,filename,'_',timestamp,'_TNT.mat'];
    % prevent overriding filenames, e.g. when one movie is chosen multiple times
    fileID = 1;
    while(true)
       if exist(filename_TNTdata,'file') % Test if output file already exists
           filename_TNTdata = [TNToutputPath,filename,'_',timestamp,'_',int2str(fileID),'_TNT.mat'];
           fileID = fileID+1;
       else
           break;
       end
    end
    list_filenames_TNTdata = [list_filenames_TNTdata; {filename_TNTdata}]; %#ok<AGROW> % Append name of datafile to list
    
    save(filename_TNTdata,'filename_movie','globalOptions','candidateOptions','fittingOptions','dark_img');
    if(globalOptions.enableTracking) % Save tracking options only if tracking is desired
        save(filename_TNTdata,'trackingOptions','-append');
    end    
    
    if not(GUIreturns.useSettingsForAll || TNToptions.rememberSettingsForNextMovie)
        globalOptions    = [];
        candidateOptions = [];
        fittingOptions   = [];
        trackingOptions  = [];
    else
        dark_img_def = dark_img;
    end
end
clearvars -except list_filenames_TNTdata parallelProcessingAvailable TNToptions

%% Candidate detection and fitting for every movie
for iMovie=1:numel(list_filenames_TNTdata)
    filename_TNTdata = list_filenames_TNTdata{iMovie};
    load(filename_TNTdata,'-mat');
    
    % Read movie
    if iMovie==1 || ~strcmp(filename_movie,filename_movie_last_loop)
        movie = read_tiff(filename_movie, false, [globalOptions.firstFrame,globalOptions.lastFrame]);
    end
    filename_movie_last_loop = filename_movie;
    
    % Compute the positions
    fprintf('######\nTNT: Locating particles in movie %s.\n',filename_movie);
    [candidateData, candidateOptions] = findCandidateParticles(movie, dark_img, globalOptions, candidateOptions);
    [fittingData, fittingOptions] = fitParticles(movie, dark_img, globalOptions, fittingOptions, candidateData);
    
    % Save positions, movieSize, and index of first and last frame processed
    firstFrame_lastFrame = [globalOptions.firstFrame,  globalOptions.firstFrame + size(movie,3)-1];  %#ok<NASGU> % Note: lastFrame could have been set to 'inf', now we synchronize with the correct number
    movieSize = size(movie); %#ok<NASGU> % Save size of movie (nice to have)
    save(filename_TNTdata,'candidateData','fittingData','globalOptions','candidateOptions','fittingOptions','movieSize','firstFrame_lastFrame','-append');
end
clearvars -except list_filenames_TNTdata parallelProcessingAvailable TNToptions globalOptions

%% Compute trajectories for every movie
for iMovie=1:numel(list_filenames_TNTdata)
    
    % Load global options to check if tracking is desired (skip movie if it is not)
    load(list_filenames_TNTdata{iMovie},'globalOptions');
    if (~globalOptions.enableTracking)
        continue
    end
    
    % Load options and data needed for processing
    load(list_filenames_TNTdata{iMovie},'trackingOptions','fittingData','filename_movie');
    
    % Compute trajectories
    fprintf('######\nTNT: Tracking particles in movie %s.\n',filename_movie);
    [trackingData, trackingOptions] = trackParticles(fittingData,trackingOptions); %#ok<ASGLU>
    
    %Save trajectories
    save(list_filenames_TNTdata{iMovie},'trackingData','trackingOptions','-append');
end

% Deactivate parallel processing if requested
if parallelProcessingAvailable && TNToptions.closeMatlabpoolOnExit
    matlabpool('close');
end

% Clear globals
clearGlobals();

%% Add required folders and subfolders to path
    function addRequiredPathsTNT()
        fullPathToThisFile = mfilename('fullpath');
        [path,~,~] = fileparts(fullPathToThisFile);
        addpath(genpath([path,filesep,'external']));
        addpath(genpath([path,filesep,'helper']));
        addpath(genpath([path,filesep,'plugins']));
        addpath(genpath([path,filesep,'subfun']));
        addpath(genpath([path,filesep,'analysis']));
    end

%% Cleanup function if something goes wrong
    function userExitFunc()
        % Remove TNTdata files
        if exist('list_filenames_TNTdata','var')
            fprintf('TNT: User exit.\n')
%             warning off backtrace
%             warning('User exit. Stopping TrackNTrace. Deleting settings files that have been saved already.');
%             warning on backtrace
            for iTNTfile = 1:numel(list_filenames_TNTdata)
                if exist(list_filenames_TNTdata{iTNTfile},'file')
                    delete(list_filenames_TNTdata{iTNTfile});
                end
            end
        end
        
        if parallelProcessingAvailable && TNToptions.closeMatlabpoolOnExit
            matlabpool('close');
        end
        clearGlobals();
    end

% Clear all global variables
    function clearGlobals()
        clear global globalOptions candidateOptions fittingOptions trackingOptions movie imgCorrection parallelProcessingAvailable filename_movie;
    end
end


