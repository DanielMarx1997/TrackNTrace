function [h_main, run_again] = visualizeTracksGUI(movie, trajectoryData, FPS, traj_lifetime, n_colors, use_bw, traj_displayLength, is_blocking)
% USAGE: visualizeTracksGUI(movie, trajectoryData)
% [ Full USAGE: visualizeTracksGUI(movie, trajectoryData, FPS, traj_lifetime, n_colors, use_bw) ]
%
% Visualizer for tracks computed by the tracker.
%
% Input:
%   movie: 3D matrix (rows,cols,frames) of the analyzed movie
%   trajectoryData: 2D matrix with columns particleID|frame|x|y|...
%                   This is the output of the tracker
% Inputs also adjustable by GUI:
%   FPS: frames per second to play movie with | default: 30
%   traj_lifetime: trajectories are kept for #traj_lifetime frames after
%                  the particle has vanished. | default: 0
%   n_colors: number of colors used to display trajectories | default: 20
%             Colors are generated using distinguishable_colors.m by
%             Timothy E. Holy (Matlab File Exchange).
%   use_bw: black/white image, otherwise colormap hot | default: false
%   trajDisplayLength: Only the positions in the last trajDisplayLength
%                      frames of each trajectory are shown | default: inf
%   is_blocking: Blocks MATLAB execution while visualizer is open
%
%  Inputs (except movie) can be left empty [] for default values.
%
% Output:
%   h_main - Handle to the GUI figure
%   run_again - Used for preview mode. Returns if the user selected to
%               run to software again in the onAppClose dialog
%
% Author: Simon Christoph Stein
% E-Mail: scstein@phys.uni-goettingen.de
% Date: 2015
%

% Parse given inputs. For clarity we outsource this in a function.
if nargin<1 || isempty(movie)
    fprintf(' Need input movie!\n');
    return
end
parse_inputs(nargin);
run_again = false;


% -- Preparing the GUI --
h_main = openfig('visualizeTracksGUI_Layout.fig');
set(h_main,'handleVisibility','on');       % Make figure visible to Matlab (might not be the case)
set(h_main,'CloseRequestFcn',@onAppClose); % Executed on closing for cleanup
set(h_main,'Toolbar','figure');   % Add toolbar needed for zooming
set(h_main, 'DoubleBuffer', 'on') % Helps against flickering

h_all = guihandles(h_main); % Get handles of all GUI objects
axes(h_all.axes); % Select axis for drawing plots

% Text on top
set(h_all.toptext,'String',sprintf('frame = 1/%i',size(movie,3)));

% Buttons
set(h_all.but_play,'Callback',@playCallback);
set(h_all.but_contrast,'Callback',@contrastCallback);
set(h_all.but_autocontrast,'Callback',@autocontrastCallback);

% Slider
set(h_all.slider,'Value',1, 'Min',1,'Max',size(movie,3),'SliderStep',[1/size(movie,3) 1/size(movie,3)],'Callback', @sliderCallback);
hLstn = addlistener(h_all.slider,'ContinuousValueChange',@updateSlider); % Add event listener for continous update of the shown slider value

% Edit fields
set(h_all.edit_FPS,'String',sprintf('%i',FPS), 'Callback', @fpsCallback);
set(h_all.edit_lifetime,'String',sprintf('%i',traj_lifetime), 'Callback', @lifetimeCallback);
set(h_all.edit_colors,'String',sprintf('%i',n_colors), 'Callback', @colorCallback);
set(h_all.edit_trajDisplayLength,'String',sprintf('%i', traj_displayLength), 'Callback', @dispLengthCallback);

% Checkbox
set(h_all.cb_bw, 'Value', use_bw, 'Callback',@bwCallback);


% Timer -> this controls playing the movie
h_all.timer = timer(...
    'ExecutionMode', 'fixedDelay', ...    % Run timer repeatedly
    'Period', round(1/FPS*1000)/1000, ... % Initial period is 1 sec. Limit to millisecond precision
    'TimerFcn', @onTimerUpdate, ...
    'StartFcn', @onTimerStart, ...
    'StopFcn',  @onTimerStop); % Specify callback


% -- Preparation for plotting --
% Convert data into cell array which is better for plotting
% Each cell saves frame|x|y for one track
if isempty(trajectoryData)
    id_tracks = [];
    n_tracks = 0;
else
    id_tracks = unique(trajectoryData(:,1));
    n_tracks = numel(id_tracks);
end

cell_traj = cell(n_tracks ,1);
cnt = 1;
for iTrack = 1:n_tracks
    cell_traj{iTrack} = trajectoryData( trajectoryData(:,1)== id_tracks(cnt) , 2:4);
    cnt = cnt+1;
end



% Store lineseries handle for each track (faster to plot)
% For the same reason store handle to the image
% Handles are set on first use (mostly in plotFrame)
linehandles = -1*ones(n_tracks,1);
imagehandle = -1;

% Create the color pool
track_colors = [];
drawColors(n_colors);

% Plot first frame to get limits right
% Set x,y,color limits
xl = [0.5,size(movie,2)+0.5];
yl = [0.5,size(movie,1)+0.5];
firstImg = movie(:,:,1);
zl = [min(firstImg(:)), max(firstImg(:))];

plotFrame(1);

xlim(xl);
ylim(yl);
caxis(zl);


% Calling this creates handles for all tracks not plotted before.
% Although this takes some time, the visualizer will respond smoother
% afterwards. If you uncomment this function, the visualizer starts faster,
% but may show jerky behaviour during first play as handles for tracks that
% did not occur before are created on demand.
setUnitinializedTrackHandles();


% Variables for playback
timePerFrame = round(1/FPS*1000)/1000; % limit to millisecond precision
elapsed_time = 0;
frame = 1;

% In case the RunAgain dialog should be displayed, we stop scripts/functions
% calling the GUI until the figure is closed
if(is_blocking)
    uiwait(h_main);
    drawnow; % makes figure disappear instantly (otherwise it looks like it is existing until script finishes)
end


% --- Nested Functions ---

% The main function of the application. This plays the movie if the
% timer is running
    function onTimerUpdate(timer, event)
        % Progress frame counter, clip at length of movie and stop at last
        % frame.
        frame = frame+1;
        if(frame >= size(movie,3))
            frame = size(movie,3);
            updateTopText();
            
            stop(h_all.timer);
        end
        set(h_all.slider,'Value',frame);
        updateTopText()
        
        % Skip frame if computer is too slow drawing
        if elapsed_time > timePerFrame
            elapsed_time = elapsed_time - timePerFrame;
            return;
        end
        tic_start = tic;
        updateFrameDisplay();
        elapsed_time = elapsed_time + toc(tic_start)- timePerFrame;
    end

    function onTimerStart(timer, event)
        set(h_all.but_play,'String','Pause');
        elapsed_time = 0;
    end

    function onTimerStop(timer, event)
        set(h_all.but_play,'String','Play');
        elapsed_time = 0;
    end

% Used to display the current frame as selected by the 'frame' variable
% Also this sets and saves the axis states (e.g. for zooming);
    function updateFrameDisplay()
        % Needed to minimize interference with other figures the user
        % brings into focus. It can be that the images are not plotted to
        % the GUI then but to the selected figure window
        set(0,'CurrentFigure',h_main);
        
        xl = xlim;
        yl = ylim;
        
        plotFrame(frame);
        
        % save the axis limits in case the user zoomed
        xlim(xl);
        ylim(yl);
        caxis(zl);
        
        % Adjust contrast continously if shift key is pressed
        modifiers = get(gcf,'currentModifier');
        shiftIsPressed = ismember('shift',modifiers);
        if(shiftIsPressed)
           autocontrastCallback([],[]); 
        end
        
        drawnow; % Important! Or Matlab will skip drawing entirely for high FPS
    end

% Plots the frame with the input index
    function plotFrame(iF)
        % Plot the movie frame
        if imagehandle == -1
            imagehandle = imagesc(movie(:,:,iF)); axis image; colormap gray;
        else
            set(imagehandle,'CData',movie(:,:,iF));
        end
        if use_bw
            colormap gray;
        else
            colormap hot;
        end
        %     title(sprintf('Frame %i/%i',iF,size(movie,3)));
        
        % Draw the tracks of currently visible particles
        hold on;
        for iTr = 1:n_tracks
            % Don't draw tracks not yet visible (iF <...) or not visible any more
            % (iF > ...). If traj_lifetime>0 the tracks are displayed for
            % the given number of frames longer.
            if iF < cell_traj{iTr}(1,1) || iF > cell_traj{iTr}(end,1) + traj_lifetime
                mask_toPlot = false(size(cell_traj{iTr},1),1);
            else
                % Plot trajectories a) only the last traj_displayLength positoins AND  b) up to the current frame
                mask_toPlot = ((cell_traj{iTr}(:,1)>iF-traj_displayLength) & cell_traj{iTr}(:,1)<=iF);
            end            
            
            % If this trajectory was already plotted before, we just set
            % its data via its handle (which is fast!). If not, create a
            % new lineseries by using the plot command.
            if (linehandles(iTr) == -1)
                if( sum(mask_toPlot) ~= 0) % only plot the first time we have actual data to display
                    linehandles(iTr) = plot(cell_traj{iTr}(mask_toPlot, 2), cell_traj{iTr}(mask_toPlot, 3), '.--','Color',track_colors(iTr,:));
                end
            else
                set(linehandles(iTr),'xdata',cell_traj{iTr}(mask_toPlot, 2),'ydata', cell_traj{iTr}(mask_toPlot, 3));
            end
        end
        hold off;        
    end

    % Creates a line handle for every track that was not plotted before
    function setUnitinializedTrackHandles()
        hold on;
        for iTr = 1:n_tracks
            if(linehandles(iTr)==-1)
                linehandles(iTr) = plot(cell_traj{iTr}(1, 2), cell_traj{iTr}(1, 3), '.--','Color',track_colors(iTr,:));
                set(linehandles(iTr),'xdata',[],'ydata',[]);
            end
        end
        hold off;
    end

% Switch play/pause by button
    function playCallback(hObj, eventdata)
        % Replay movie if at end
        if frame == size(movie,3)
            frame = 1;
        end
        
        % switch the timer state
        if strcmp(get(h_all.timer, 'Running'), 'off')
            start(h_all.timer);
        else
            stop(h_all.timer);
        end
    end

    % Stop playing, adjust contrast, continue
    function contrastCallback(hObj, eventdata)
        isTimerOn = strcmp(get(h_all.timer, 'Running'), 'on');
        if isTimerOn
            stop(h_all.timer);
        end
        
        % We clip the visible display range before the contrast dialog
        % to prevent a warning dialog about display range outside data range
        axes(h_all.axes);
        currImg = movie(:,:,frame);
        zImg = [min(currImg(:)), max(currImg(:))];
        zl = [max(zImg(1),zl(1)), min(zImg(2),zl(2))];
        caxis(zl);
        
        % Show contrast dialog, update color axis
        him = imcontrast;
        uiwait(him);
        zl = caxis;
        
        if isTimerOn
            start(h_all.timer);
        end
    end

    % Stop playing, set contrast to match image min/max values, continue
    function autocontrastCallback(hObj, eventdata)
        axes(h_all.axes);        
        xl = xlim; % update the axis limits in case the user zoomed
        yl = ylim;
        
%         currImg = movie(:,:,frame); % Take whole frame for autocontrast
        % Take visible image cutout for autocontrast
        visibleXRange = max(1,floor(xl(1))):min(size(movie,2),ceil(xl(2)));
        visibleYRange = max(1,floor(yl(1))):min(size(movie,1),ceil(yl(2)));
        currImg = movie(visibleYRange,visibleXRange,frame);
        
        % Adjust contrast to match min/max intensity
        zl = [min(currImg(:)), max(currImg(:))];
        caxis(zl);
    end

    % Switch black-white and hot display mode
    function bwCallback(hObj, eventdata)
        isTimerOn = strcmp(get(h_all.timer, 'Running'), 'on');
        if isTimerOn
            stop(h_all.timer);
        end
        
        use_bw = ~use_bw;
        
        drawColors(n_colors); % Recompute colors
                
        if isTimerOn
            start(h_all.timer);
        else
            updateFrameDisplay()
        end
        
    end

    % Update the movie FPS
    function fpsCallback(hObj, eventdata)
        isTimerOn = strcmp(get(h_all.timer, 'Running'), 'on');
        if isTimerOn
            stop(h_all.timer);
        end
        
        FPS = str2num(get(h_all.edit_FPS, 'String'));
        if isempty(FPS) || FPS<=0
            FPS = 30;
        end
        
        % Timer is limited to 1ms precision
        if FPS>1000
            FPS = 1000;
            warning('Max FPS is 1000 due to timer precision');
        end
        timePerFrame = round(1/FPS*1000)/1000; % limit to millisecond precision
        set(h_all.timer,'Period', timePerFrame);
        set(h_all.edit_FPS,'String',sprintf('%.1f',FPS));
        
        if isTimerOn
            start(h_all.timer);
        end
    end

    % Update the lifetime of tracks
    function lifetimeCallback(hObj, eventdata)
        isTimerOn = strcmp(get(h_all.timer, 'Running'), 'on');
        if isTimerOn
            stop(h_all.timer);
        end
        
        traj_lifetime = round(str2num(get(h_all.edit_lifetime,'String')));
        if traj_lifetime<=0 || isempty(traj_lifetime)
            traj_lifetime = 0;
        end
        set(h_all.edit_lifetime,'String',sprintf('%i%',traj_lifetime));
        
        if isTimerOn
            start(h_all.timer);
        else
            updateFrameDisplay();
        end
    end

    % Update the displayed length of trajectories
    function dispLengthCallback(hObj, eventdata)
        isTimerOn = strcmp(get(h_all.timer, 'Running'), 'on');
        if isTimerOn
            stop(h_all.timer);
        end
        
        traj_displayLength = round(str2num(get(h_all.edit_trajDisplayLength,'String')));
        if traj_displayLength<=0 || isempty(traj_displayLength)
            traj_displayLength = 0;
        end
        set(h_all.edit_trajDisplayLength,'String',sprintf('%i%',traj_displayLength));
        
        if isTimerOn
            start(h_all.timer);
        else
            updateFrameDisplay();
        end
    end

    % The user entered a different number of colors -> update color pool
    function colorCallback(hObj, eventdata)
        isTimerOn = strcmp(get(h_all.timer, 'Running'), 'on');
        if isTimerOn
            stop(h_all.timer);
        end
        
        n_colors = round(str2num(get(h_all.edit_colors,'String')));
        if n_colors<=0 || isempty(n_colors)
            n_colors = 1;
        end
        set(h_all.edit_colors,'String',sprintf('%i%',n_colors));
        
        drawColors(n_colors);
        
        if isTimerOn
            start(h_all.timer);
        else
            updateFrameDisplay();
        end
    end

    % Recompute the colors based on the current background
    function drawColors(num_colors)
        % create colors
        if use_bw % background color
            bg = {'k'};
        else
            bg = {'r'};
        end
        
        track_colors = repmat( distinguishable_colors(num_colors, bg), ceil(n_tracks/num_colors) ,1);
        track_colors = track_colors(1:n_tracks,:);
        
       % Set the line color for each track
       for iH = 1:length(linehandles)
           if(linehandles(iH) ~= -1)
             set(linehandles(iH),'Color',track_colors(iH,:));
           end
       end
    end

    % This is called after letting the slider go. We update the frame display 
    % once more, otherwise synchronisation issues can occur.
    function sliderCallback(hObj, eventdata)
        updateFrameDisplay();
        elapsed_time = 0;
    end

% This is called continously when dragging the slider
    function updateSlider(hObj,eventdata)
        % Round slider value, sync text
        frame = round(get(h_all.slider,'Value'));
        set(h_all.slider,'Value',round(frame));
        updateTopText();
        
        % Stop timer
        if strcmp(get(h_all.timer, 'Running'), 'on')
            stop(h_all.timer);
        end
        
        % Skip frame if computer is too slow
        if elapsed_time >timePerFrame
            elapsed_time = elapsed_time - timePerFrame;
            return;
        end
        
        tic_start = tic;
        updateFrameDisplay();
        elapsed_time = elapsed_time + toc(tic_start)- timePerFrame;
    end

% Sets top text according to the current frame
    function updateTopText()
        set(h_all.toptext,'String',[sprintf('frame =  %i/%i',frame,size(movie,3))])
    end

% Parse input variables
    function parse_inputs(num_argin)
        % input parsing
        if num_argin <3 || isempty(FPS)
            FPS = 30;
        end
        
        if num_argin <4 || isempty(traj_lifetime)
            traj_lifetime = 0;
        else
            traj_lifetime = round(traj_lifetime);
        end
        
        if num_argin < 5 || isempty(n_colors) || n_colors<=1
            n_colors = 20;
        else
            n_colors = round(n_colors);
        end
        
        if num_argin <6 || isempty(use_bw)
            use_bw = false;
        end
        
        if num_argin < 7 || isempty(traj_displayLength)
            traj_displayLength = inf;
        end
        
        if num_argin < 8 || isempty(is_blocking)
            is_blocking = false;
        end
        
    end

% Cleanup function. This is neccessary to delete the timer!
    function onAppClose(hObj, event)
        if strcmp(get(h_all.timer, 'Running'), 'on')
            stop(h_all.timer);
        end
        delete(h_all.timer);
       
        delete(h_main);
    end

end
