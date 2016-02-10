function [filename_movies, globalOptions, candidateOptions,fittingOptions,trackingOptions, GUIreturns] = startupGUI()
%
% Author: Simon Christoph Stein
% E-Mail: scstein@phys.uni-goettingen.de
% Date: 2016
%

GUIreturns.userExit = false;

globalOptions = [];
candidateOptions = [];
fittingOptions = [];
trackingOptions = [];

filename_movies ={};

% -- Preparing the GUI --
h_main = openfig('startupGUI_Layout.fig');
set(h_main,'handleVisibility','on'); % Make figure visible to Matlab (might not be the case)
set(h_main,'CloseRequestFcn',@onAppClose); % For cleanup
movegui(h_main,'center');

h_all = guihandles(h_main);

% Setup GUI elements
set(h_all.button_addMovies, 'Callback', @callback_addMovies);
set(h_all.button_removeMovie, 'Callback', @callback_removeMovie);
set(h_all.button_load, 'Callback', @callback_loadSettings);
set(h_all.button_start, 'Callback',@callback_exit);


% % GUI main
uiwait(h_main);
drawnow; % makes figure disappear instantly (otherwise it looks like it is existing until script finishes)

% Load settings from a file
    function callback_loadSettings(hObj,event)        
        [infile, path] = uigetfile({'*.mat','TNT settings'});
        if isfloat(infile);
            return;
        end; % User clicked cancel
        % Note: Loading has to be done this way, as variables "can not be
        % added to a static workspace" (e.g. the one of this GUI).
        warning off
        allOptions = load([path,infile],'globalOptions', 'candidateOptions','fittingOptions','trackingOptions','filename_movie');
        warning on
        globalOptions   = allOptions.globalOptions;
        candidateOptions = allOptions.candidateOptions;
        fittingOptions   = allOptions.fittingOptions;
        if isfield(allOptions,'trackingOptions')
            trackingOptions  = allOptions.trackingOptions;
        end
        filename_movies = {allOptions.filename_movie};
        
        callback_exit();
    end

% Opens a file chooser dialog to choose multiple input (movie) files
% for processing. Note: filenames will be seperated by ';'
    function callback_addMovies(hObj,event)
        % Get current text field to set starting path of uigetfile
        filename_movies = get(h_all.listbox_movieList,'String');
        
        % We have to do this, since repopulating a listbox does not
        % automatically reset its value..
        if numel(filename_movies) == 0
            set(h_all.listbox_movieList,'Value',1);
        end
        
        path = [];
        if ~isempty(filename_movies)
            [path,~,~] = fileparts(filename_movies{end});
        end
        [movieList, path] = uigetfile([path,filesep,'*.tif'],'MultiSelect','on');
        if( isfloat(movieList) ); return; end; % User pressed cancel.
        
        % atach path to every entry in the list then add to listbox
        if iscell(movieList)
            for i=1:length(movieList)
                movieList{i} =  [path,movieList{i}];
            end
            % Add to listbox
            filename_movies = [filename_movies; movieList.'];
        elseif ischar(movieList)
            movieList = [path,movieList];
            % Add to listbox
            filename_movies = [filename_movies; {movieList}];
        end
        
        set(h_all.listbox_movieList,'String',filename_movies);
    end

% Remove a movie from the movie list
    function callback_removeMovie(hObj,event)
        selected_entry = get(h_all.listbox_movieList,'Value');
        filename_movies = get(h_all.listbox_movieList,'String');
        
        % When listbox is empty, do nothing
        if numel(filename_movies) == 0
           return; 
        end
        
        % When last selected item is deleted, select the one before it
        if selected_entry == numel(filename_movies)
            set(h_all.listbox_movieList,'Value',selected_entry-1);
        end
        
        filename_movies(selected_entry) = [];
        set(h_all.listbox_movieList,'String',filename_movies);
    end



    function callback_exit(hObj, event)
        delete(h_main);
    end

% Called when closing the application via the 'X' button (or via close)
    function onAppClose(hObj, event)
        GUIreturns.userExit = true;
        delete(h_main);
    end

end
