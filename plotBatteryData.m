function plotBatteryData
% --------------------------------------------------------------
% Polished Battery‑Test Viewer – full‑screen, responsive layout
% --------------------------------------------------------------
% (All the original features are kept – only the tip‑box creation/
% positioning has been adjusted.)

% --------------------------------------------------------------
% 0️⃣  Shared variables (visible to *all* nested callbacks)
% --------------------------------------------------------------
dataTable   = [];          % CSV contents
legHandle   = [];          % Legend handle (so we can delete it)
cursorLine  = [];          % Handle to the draggable vertical line
txtValue    = [];          % Read‑only text box that shows the tip
plottedLines = {};         % Cell array of line handles (one per series)

% --------------------------------------------------------------
% 1️⃣  UI creation – a grid layout that automatically resizes
% --------------------------------------------------------------
fig = uifigure( ...
    'Name','Battery Test Viewer', ...
    'WindowState','maximized', ...
    'Color',[0.95 0.95 0.95]);       % Light‑gray background

% Main grid: 2 rows × 2 columns
gl = uigridlayout(fig,[2 2], ...
    'RowHeight', {40, '1x'}, ...
    'ColumnWidth', {250, '1x'}, ...
    'Padding',[10 10 10 10], ...
    'RowSpacing',10, ...
    'ColumnSpacing',10);

% -----------------------------------------------------------------
% Header (title + status bar)
% -----------------------------------------------------------------
lblTitle = uilabel(gl, ...
    'Text','Battery Test Viewer', ...
    'FontSize',20, ...
    'FontWeight','bold', ...
    'HorizontalAlignment','center');
lblTitle.Layout.Row    = 1;
lblTitle.Layout.Column = [1 2];   % Span both columns

lblStatus = uilabel(gl, ...
    'Text','Ready – load a CSV file', ...
    'FontColor',[0.4 0.4 0.4], ...
    'HorizontalAlignment','right');
lblStatus.Layout.Row    = 1;
lblStatus.Layout.Column = 2;     % Right‑aligned in the header row

% -----------------------------------------------------------------
% Left column – control panel
% -----------------------------------------------------------------
pnlControls = uipanel(gl, ...
    'Title','Controls', ...
    'FontWeight','bold', ...
    'BackgroundColor','white');
pnlControls.Layout.Row    = 2;
pnlControls.Layout.Column = 1;

% Nested grid inside the panel for tidy spacing
ctrlGrid = uigridlayout(pnlControls,[6 1], ...
    'RowHeight', {'fit','fit','fit','fit','fit','1x'}, ...
    'Padding',[10 10 10 10], ...
    'RowSpacing',8);

% Load‑CSV button
btnLoad = uibutton(ctrlGrid, ...
    'push', ...
    'Text','Load CSV', ...
    'FontWeight','bold', ...
    'ButtonPushedFcn',@loadCSV);
btnLoad.Layout.Row = 1;

% X‑axis drop‑down
uilabel(ctrlGrid,'Text','X‑Axis:','HorizontalAlignment','left');
ddX = uidropdown(ctrlGrid, ...
    'Items',{}, ...
    'Enable','off', ...
    'ValueChangedFcn',@updatePlot);
ddX.Layout.Row = 2;

% Y‑axis list‑box (multi‑select)
uilabel(ctrlGrid,'Text','Y‑Axis (multi‑select):','HorizontalAlignment','left');
lbY = uilistbox(ctrlGrid, ...
    'Multiselect','on', ...
    'Items',{}, ...
    'Enable','off', ...
    'ValueChangedFcn',@updatePlot);
lbY.Layout.Row = 3;

% Reset button
btnReset = uibutton(ctrlGrid, ...
    'push', ...
    'Text','Reset', ...
    'ButtonPushedFcn',@resetViewer);
btnReset.Layout.Row = 4;

% -----------------------------------------------------------------
% Right column – the plot area (fills the rest of the screen)
% -----------------------------------------------------------------
ax = uiaxes(gl, ...
    'BackgroundColor','white', ...
    'FontSize',12, ...
    'Box','on');
ax.Layout.Row    = 2;
ax.Layout.Column = 2;

% -----------------------------------------------------------------
% 2️⃣‑b  Read‑only text box that will display the tip (created **after**
%      the grid layout so it sits on top)
% -----------------------------------------------------------------
txtValue = uieditfield(fig, ...
    'Editable','off', ...
    'Visible','off', ...               % hidden until cursor is ON
    'Position',[10 40 300 22], ...    % placeholder – will be repositioned
    'FontSize',12, ...
    'BackgroundColor',[1 1 1]);        % white background

% -----------------------------------------------------------------
% 3️⃣  Add a toggle button **after** the axes have been created
% -----------------------------------------------------------------
btnCursor = uibutton(ctrlGrid, ...
    'state', ...                     % create a *state* (toggle) button
    'Text','Show Cursor', ...
    'FontWeight','bold', ...
    'Value',false, ...               % start OFF
    'ValueChangedFcn',@toggleCursor);
btnCursor.Layout.Row = 5;   % place it in the last row of ctrlGrid

% --------------------------------------------------------------
% 4️⃣  Callback definitions
% --------------------------------------------------------------

    function loadCSV(~,~)
        %--- Show a spinner while the file is being read -----------------
        spinner = uiprogressdlg(fig, ...
            'Message','Loading CSV…', ...
            'Indeterminate','on');
        drawnow;   % Force UI update

        %--- Default folder for the explorer ----------------------------
        defaultFolder = '\\Ssnx\ssn(x)\Documents\Non-Prop Electrical and Combat Systems\NP Electrical\5_Energy Storage\3_Analysis\NRL_Battery_Data';

        %--- Prompt for a CSV file ---------------------------------------
        [file, path] = uigetfile('*.csv', ...
            'Select battery data CSV', ...
            defaultFolder);
        if isequal(file,0)   % User cancelled
            close(spinner);
            return;
        end
        fullName = fullfile(path,file);

        %--- Read the file (preserve original column headers) ----------
        try
            dataTable = readtable(fullName, ...
                'VariableNamingRule','preserve');   % keep original names
        catch ME
            close(spinner);
            uialert(fig,ME.message,'File read error');
            return;
        end
        close(spinner);

        %--- Populate UI controls ----------------------------------------
        colNames = dataTable.Properties.VariableNames;   % already preserved
        ddX.Items = colNames;
        lbY.Items = colNames;

        % Sensible defaults (if they exist)
        idxX = find(contains(lower(colNames),'testtime'),1);
        idxY = find(contains(lower(colNames),'voltage'),1);
        if ~isempty(idxX), ddX.Value = colNames{idxX}; end
        if ~isempty(idxY), lbY.Value = colNames{idxY}; end

        % Enable the controls now that we have data
        ddX.Enable = 'on';
        lbY.Enable = 'on';
        lblStatus.Text = sprintf('Loaded "%s" – select axes',file);
        plotSelectedData();   % Initial plot
    end

    function updatePlot(~,~)
        if isempty(dataTable)
            uialert(fig,'Load a CSV first','Info');
            return;
        end
        plotSelectedData();
    end

    function resetViewer(~,~)
        %--- 1️⃣ Clear shared data ---------------------------------------
        dataTable = [];

        %--- 2️⃣ Reset UI controls ---------------------------------------
        ddX.Items = {};          % clear the list of items
        ddX.Value = {};          % must be an empty cell when Items is empty
        ddX.Enable = 'off';
        lbY.Items = {};          % clear the list of items
        lbY.Value = {};          % empty cell for a multi‑select list box
        lbY.Enable = 'off';

        %--- 3️⃣ Clean the plot area --------------------------------------
        cla(ax,'reset');                 % remove graphics and reset limits
        ax.Title.String    = '';
        ax.XLabel.String   = '';
        ax.YLabel.String   = '';
        ax.XLim = 'auto';  ax.YLim = 'auto';

        % Delete the legend if it exists
        if ~isempty(legHandle) && isvalid(legHandle)
            delete(legHandle);
            legHandle = [];
        end

        %--- 4️⃣ Reset cursor --------------------------------------------
        if ~isempty(cursorLine) && isvalid(cursorLine)
            delete(cursorLine);
        end
        cursorLine = [];      % clear the shared handle
        txtValue.Value = '';
        txtValue.Visible = 'off';

        %--- 5️⃣ Reset status text ---------------------------------------
        lblStatus.Text = 'Ready – load a CSV file';
        drawnow;                         % force UI refresh immediately
    end

% -----------------------------------------------------------------
% Callback: turn the cursor on/off
% -----------------------------------------------------------------
    function toggleCursor(src,~)
        if src.Value   % *** Turn ON ***
            % 1️⃣  Create a vertical line that can be dragged horizontally
            midX = mean(ax.XLim);
            cursorLine = drawline(ax, ...
                'Position',[midX ax.YLim(1); midX ax.YLim(2)], ...
                'Color','r','LineWidth',1.5, ...
                'InteractionsAllowed','translate');   % ← only translation

            % 2️⃣  Attach a listener that fires continuously while the line moves
            addlistener(cursorLine,'MovingROI',@cursorMoved);   % ← correct event

            % 3️⃣  Show the first data‑tip immediately
            cursorMoved();

            % 4️⃣  Make the tip box visible **and bring it to the front**
            txtValue.Visible = 'on';
            uistack(txtValue,'top');   % <-- ensures it isn't hidden by the layout
        else            % *** Turn OFF ***
            if ~isempty(cursorLine) && isvalid(cursorLine)
                delete(cursorLine);
            end
            cursorLine = [];      % clear the shared handle
            txtValue.Value = '';
            txtValue.Visible = 'off';
        end
    end

% -----------------------------------------------------------------
% Listener: update the read‑only text box whenever the cursor line moves
% -----------------------------------------------------------------
    function cursorMoved(~,~)
        if isempty(cursorLine) || ~isvalid(cursorLine)
            return;
        end

        % ----- 1️⃣  Current X‑position (clamped to the plotted X‑range) -----
        xPos = mean(cursorLine.Position(:,1));
        xPosClamped = max(min(xPos, max(ax.XLim)), min(ax.XLim));

        % ----- 2️⃣  Interpolate Y‑values for **every** plotted line -----
        yStrings = {};   % will hold "SeriesName = value"
        for i = 1:numel(plottedLines)
            hLine = plottedLines{i};
            if ~isvalid(hLine) || ~isa(hLine,'matlab.graphics.chart.primitive.Line')
                continue;
            end
            yVal = interp1(hLine.XData, hLine.YData, xPosClamped, 'linear', NaN);
            seriesName = hLine.DisplayName;
            if isempty(seriesName)
                seriesName = sprintf('Series%d',i);
            end
            yStrings{end+1} = sprintf('%s = %.4g', seriesName, yVal); %#ok<AGROW>
        end

        % ----- 3️⃣  Build the tip string (X + all Y values) -----
        tipStr = sprintf('X = %.4g',xPosClamped);
        if ~isempty(yStrings)
            tipStr = sprintf('%s   %s', tipStr, strjoin(yStrings,'   '));
        end
        txtValue.Value = tipStr;

        % ----- 4️⃣  Keep the line perfectly vertical -----
        cursorLine.Position = [xPos ax.YLim(1); xPos ax.YLim(2)];

        % ----- 5️⃣  Position the box so it **overlaps the top of the cursor** -----
        % All coordinates are in *pixels* relative to the figure.
        % Convert axes units to pixels temporarily.
        origAxUnits  = ax.Units;  ax.Units = 'pixels';
        origFigUnits = fig.Units; fig.Units = 'pixels';
        axPos   = ax.Position;                     % [left bottom width height] in figure pixels

        % Normalised position of the cursor inside the axes (0‑1)
        xNorm   = (xPosClamped - ax.XLim(1)) / diff(ax.XLim);
        % Pixel coordinate of the cursor (relative to the figure)
        pixelX  = axPos(1) + xNorm*axPos(3);

        % Desired size of the edit field (a bit wider for multiple Y‑values)
        boxW = 120;   % width (pixels)
        boxH = 22;    % height (pixels)

        % Bottom of the box aligns with the **top edge of the axes**
        pixelY = axPos(2) + axPos(4) - boxH - 40;   % small margin (6 px)

        % Clamp horizontally so the box never leaves the axes
        minX = axPos(1);                     % left edge of axes
        maxX = axPos(1) + axPos(3) - boxW;   % right edge of axes (minus box width)
        pixelX = max(minX, min(pixelX - boxW/2, maxX));

        txtValue.Position = [pixelX, pixelY, boxW, boxH];   % Updated positioning

        % Restore original units (good practice)
        ax.Units   = origAxUnits;
        fig.Units  = origFigUnits;
    end

% -----------------------------------------------------------------
% Plotting routine (called by loadCSV & updatePlot)
% -----------------------------------------------------------------
    function plotSelectedData()
        xCol  = ddX.Value;          % string
        yCols = lbY.Value;          % cell array

        % Guard clauses -------------------------------------------------
        if isempty(xCol) || isempty(yCols)
            cla(ax,'reset');
            ax.Title.String = 'Select X‑ and Y‑axis columns';
            drawnow;
            return;
        end

        % Limit to two Y‑columns (left/right axes) --------------------
        if numel(yCols) > 2
            yCols = yCols(1:2);
            uialert(fig,'Only the first two Y‑columns are used.','Info');
        end

        % ----- X data ------------------------------------------------
        xData = dataTable.(xCol);
        if ~isnumeric(xData)
            xData = str2double(string(xData));
        end

        % ----- Plot --------------------------------------------------
        cla(ax,'reset'); hold(ax,'on');
        plottedLines = {};   % reset the list of line handles

        % Left Y‑axis
        yyaxis(ax,'left');
        plottedLines{end+1} = plotSingleSeries(yCols{1},xData,'left');

        % Right Y‑axis (optional)
        if numel(yCols) == 2
            yyaxis(ax,'right');
            plottedLines{end+1} = plotSingleSeries(yCols{2},xData,'right');
        end

        hold(ax,'off');

        % Axis labels, legend, title ---------------------------------
        xlabel(ax,xCol,'Interpreter','none');

        % Create (or replace) the legend and keep its handle
        if ~isempty(legHandle) && isvalid(legHandle)
            delete(legHandle);
        end
        legHandle = legend(ax,yCols,'Location','best');

        title(ax,sprintf('Plot of %s vs %s',strjoin(yCols,', '),xCol),...
            'Interpreter','none');

        % Visual polish ------------------------------------------------
        ax.FontName = 'Segoe UI';
        ax.Title.FontWeight = 'bold';
        ax.Title.FontSize   = 14;
        ax.XLabel.FontSize  = 12;
        ax.YLabel.FontSize  = 12;
        ax.TickLabelInterpreter = 'none';
    end

% -----------------------------------------------------------------
% Helper: plot a single series (numeric or categorical "State")
% Returns the line handle that was created.
% -----------------------------------------------------------------
    function hLine = plotSingleSeries(colName,xData,axisSide)
        % Handles the special categorical "State" column, otherwise plots numeric data
        if strcmpi(colName,'State') && any(strcmpi(dataTable.Properties.VariableNames,'State'))
            % ----- Categorical State handling -------------------------
            stateRaw = dataTable.State;
            if iscell(stateRaw), stateRaw = string(stateRaw); end
            stateOrder = {'C','D','R','P'};
            [~,loc] = ismember(stateRaw,stateOrder);
            unknown = loc==0;
            if any(unknown)
                maxKnown = numel(stateOrder);
                loc(unknown) = maxKnown + (1:sum(unknown));
            end
            hLine = stairs(ax,xData,loc,'LineWidth',2,'Color','k', ...
                'Marker','o','MarkerFaceColor','k', ...
                'DisplayName',sprintf('State (%s axis)',axisSide));
            ylim(ax,[0.5 max(loc)+0.5]);
            yticks(ax,1:numel(stateOrder));
            yticklabels(ax,stateOrder);
            ylabel(ax,sprintf('State (C/D/R/P) – %s axis',axisSide));
        else
            % ----- Numeric (or convertible) column --------------------
            yData = dataTable.(colName);
            if ~isnumeric(yData)
                yData = str2double(string(yData));
            end
            hLine = plot(ax,xData,yData,'LineWidth',1.5,'DisplayName',colName);
            ylabel(ax,colName,'Interpreter','none');
        end
    end

end   % <-- end of plotBatteryData -------------------------------------------------
