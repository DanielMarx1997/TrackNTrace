function RunTrackNTrace()
    %% Add required folders and subfolders to path
    fullPathToThisFile = mfilename('fullpath');
    [path,~,~] = fileparts(fullPathToThisFile);
    addpath(genpath([path,filesep,'external']));
    addpath(genpath([path,filesep,'helper']));
    addpath(genpath([path,filesep,'plugins']));
    addpath(genpath([path,filesep,'subfun']));
    addpath(genpath([path,filesep,'analysis']));    

    %% Load and adjust the default settings for this batch
    GUIinputs.titleText = 'Please select a list of movies to process.';
    GUIinputs.fileText  = 'Default settings for this batch';
    GUIinputs.singleFileMode = false;
    [generalOptions_def] = setDefaultOptions();
    [generalOptions_def, candidateOptions_def,fittingOptions_def,trackingOptions_def, GUIreturns] = settingsGUI(generalOptions_def, [],[],[], GUIinputs);
    if GUIreturns.userExit; error('User abort. Stopping TrackNTrace.'); end;

    %% Adjust options for each movie and test settings if desired
    GUIinputs.singleFileMode = true; % No editing of movie list possible

    % [movie_list,dark_stack] = getMovieFilenames(generalOptions.filename_movies, generalOptions.filename_dark_movie);
    movie_list = generalOptions_def.filename_movies;
    % Calculate default dark image if given
    dark_img_def = [];
    if(~isempty(generalOptions_def.filename_dark_movie))
        dark_img_def = CalculateDark(read_tiff(generalOptions_def.filename_dark_movie));
    end

    % Get timestamp for output files
    time = clock;
    timestamp = sprintf('%i-m%02i-d%02i-%ih%i',time(1),time(2),time(3),time(4),time(5));

    posFit_list = cell(0);
    for i=1:numel(movie_list)
        filename_movie = movie_list{i};
        [path,filename,~] = fileparts(filename_movie);
        filename_fitData = [path,filesep,filename,'_',timestamp,'_TNT.mat'];
        
        
        % Skip nonsensical input
        if ~isempty(filename_movie)
            [~,movie] = evalc(['read_tiff(''',filename_movie,''',false,[1,2])']); % Read 2 frames. note: evalc suppresses output
            if size(movie,3)<=1
                continue;
            end
        else
            continue;
        end

        % Set options to default for this batch
        generalOptions = generalOptions_def;
        candidateOptions = candidateOptions_def;
        fittingOptions = fittingOptions_def;
        trackingOptions = trackingOptions_def;
        dark_img = dark_img_def;

        % Does the user want to adjust the settings per movie?
        if not(  GUIreturns.useSettingsForAll )
            % Show filename in GUI
            GUIinputs.fileText = filename_movie;

            GUIinputs.titleText = 'Adjust movie specific options.';
            [generalOptions, candidateOptions,fittingOptions,trackingOptions, GUIreturns] = settingsGUI(generalOptions, candidateOptions,fittingOptions,trackingOptions, GUIinputs);
            if GUIreturns.userExit; error(sprintf('User abort. Stopping TrackNTrace.\nDelete unwanted settings files that might have been saved already.')); end; %#ok<SPERR>

            % Check if different dark movie was given
            if(~strcmp(generalOptions_def.filename_dark_movie, generalOptions.filename_dark_movie))
                if(~isempty(generalOptions.filename_dark_movie))
                    dark_img = CalculateDark(read_tiff(generalOptions.filename_dark_movie));
                end
            end
            
            % Set same settings for all remaining movies if user said so
            if GUIreturns.useSettingsForAll; generalOptions.previewMode = false; end;

            % If test mode is enabled, analyze first X frames and show GUI
            if generalOptions.previewMode
                run_again = true;
                first_run = true;
                filename_dark_movie = generalOptions.filename_dark_movie;
                while run_again
                    if not(first_run)
                        [generalOptions, candidateOptions,fittingOptions,trackingOptions, GUIreturns] = settingsGUI(generalOptions, candidateOptions,fittingOptions,trackingOptions, GUIinputs);
                        if GUIreturns.userExit; error(sprintf('User abort. Stopping TrackNTrace.\nDelete unwanted settings files that might have been saved already.')); end; %#ok<SPERR>
                        if GUIreturns.useSettingsForAll; generalOptions.previewMode = false; end; %dont go through other movies anymore
                    end

                    if not(generalOptions.previewMode); break; end; % If test mode was disabled by user in the settingsGUI
                    % Check if requested frame interval has changed -> re-read movie if neccessary
                    if first_run || GUIreturns.testWindowChanged
                        try
                            movie = read_tiff(filename_movie, false, [generalOptions.firstFrameTesting, generalOptions.lastFrameTesting]);
                        catch
                            warning('Movie could not be read, check settings again before continuing!');
                            continue;
                        end
                    end
                    % Check if different dark movie was given
                    if(~strcmp(filename_dark_movie, generalOptions.filename_dark_movie))
                        if(~isempty(generalOptions.filename_dark_movie))
                            dark_img   = CalculateDark(read_tiff(generalOptions.filename_dark_movie));
                        end
                        filename_dark_movie = generalOptions.filename_dark_movie;
                    end
                    % IF: this is the first run, the preview window changed or the fitting/candidate options changed locate and
                    % track particles and save fitData. ELSE: reuse fitData acquired in the last run without re-fitting
                    if  first_run || GUIreturns.testWindowChanged || GUIreturns.fittingOptionsChanged || GUIreturns.candidateOptionsChanged
                        [run_again, fitData_test] = testTrackerSettings(movie,dark_img,generalOptions,candidateOptions,fittingOptions,trackingOptions);
                    else
                        [run_again] = testTrackerSettings(movie,dark_img,generalOptions,candidateOptions,fittingOptions,trackingOptions, fitData_test);
                    end
                    first_run = false;
                end
            end

        end %not(  GUIreturns_def.useSettingsForAll || (exist('GUIreturns','var') && GUIreturns.useSettingsForAll)  )
        
        if GUIreturns.useSettingsForAll
            generalOptions_def = generalOptions;
            candidateOptions_def = candidateOptions;
            fittingOptions_def = fittingOptions;
            trackingOptions_def = trackingOptions;
            dark_img_def = dark_img;
        end
        
        % Save options
        generalOptions.filename_movies = {filename_movie}; % Save only name of this file in its settings (important when loading options)
        save(filename_fitData,'filename_movie','generalOptions','candidateOptions','fittingOptions','trackingOptions','dark_img');
        posFit_list = [posFit_list;{filename_fitData}]; %#ok<AGROW>
    end

    %% Compute positions
    clearvars -except posFit_list
    for i=1:numel(posFit_list)
        filename_fitData = posFit_list{i};
        load(filename_fitData,'-mat');

        % Read movie
        movie = read_tiff(filename_movie, false, [generalOptions.firstFrame,generalOptions.lastFrame]);        
        % Compute the positions
        fprintf('######\nLocating particles in movie %s.\n',filename_movie);
        fitData = locateParticles(movie, dark_img, generalOptions, candidateOptions, fittingOptions);

        % Save positions and movieSize, update generalOptions.lastFrame
        generalOptions.lastFrame = generalOptions.firstFrame + size(movie,3)-1; % lastFrame could have been set to 'inf', now we synchronize with the correct number
        movieSize = size(movie); %#ok<NASGU> % Save size of movie (nice to have)
        save(filename_fitData,'fitData','generalOptions','movieSize','-append');
    end

    clear fitData movie
    %% TODO
    % correct for half pixel shift?
    % keep amplitude even if tracker cant manage
    % replace Ptest by something better? --> amp>mean+k*std, k by user
    % automatically determine if memory large enough

    %% Compute trajectories
    for i=1:numel(posFit_list)
        load(posFit_list{i},'generalOptions','trackingOptions','fitData','filename_movie');

        % If no tracking is desired for this movie, continue
        if (~generalOptions.enableTracking)
            continue
        end

        % Compute trajectories
        fprintf('######\nTracking particles in movie %s.\n',filename_movie);
        trajectoryData = trackParticles(fitData,trackingOptions); %#ok<NASGU>

        %Save trajectories
        save(posFit_list{i},'trajectoryData','-append');
    end
end

