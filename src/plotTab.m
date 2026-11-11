function api = plotTab(tab, fig)
%PLOTTAB  "Plot" tab: interactive viewer for the loaded test file.
%
%   api = plotTab(tab, fig)   builds the tab inside uitab TAB of figure FIG.
%   api.setData(d)            show dataset d (from loadBatteryCsv)
%
%   Mouse on the plot
%     left-drag          zoom into the dragged box (see the Drag drop-down)
%     middle-drag        pan (shift + left-drag does the same)
%     scroll wheel       zoom in/out around the mouse
%     double-click       fit all
%     right-click        zoom back
%   Keys: f = fit all, backspace = zoom back, esc = cancel a drag
%
%   Cursor: shows each curve's value where it crosses the mouse X position,
%   with a label next to every crossing point. When a twin signal and its
%   measured partner are both shown, a "Δ = twin - measured" label is added.
%
%   Y lists: "(none)" at the top shows nothing on that axis. Below the file's
%   columns come the digital-twin signals read from the MATLAB workspace
%   (twin_soc, twin_current, twin_voltage, twin_temp - see loadTwin).
%   Ctrl+click picks several signals for one axis.
%
%   Same units, same scale: when every curve on the left AND the right has
%   the same unit (e.g. measured voltage left, twin voltage right) both Y
%   axes get the SAME limits, so the curves sit on top of each other and
%   stay that way through every zoom / pan / fit. A twin signal counts as
%   having its measured partner's unit. Untick "Same units -> same Y scale"
%   to give each side its own scale again.

NONE = '(none)';
SEP  = char([9472 9472 32 'Twin (from workspace)' 32 9472 9472]);   % list separator, not selectable
TWIN = struct('var',  {'twin_soc','twin_current','twin_voltage','twin_temp'}, ...
              'label',{'Twin: SOC (-)','Twin: Current (A)','Twin: Voltage (V)','Twin: Temp (°C)'});

% ---------------- state shared by the nested functions ----------------------
d          = [];          % current dataset
twin       = struct('name',{},'t',{},'y',{},'pair',{},'note',{});   % loaded twin signals
series     = struct('h',{},'side',{},'x',{},'y',{},'mono',{},'name',{}, ...
                    'color',{},'marker',{},'label',{},'pair',{},'dlabel',{});
cursorOn   = false;
cursorX    = [];          % xline handle
zoomStack  = {};
drag       = struct('active',false,'p0',[0 0],'box',[]);
pan        = struct('active',false,'px0',[0 0],'lims0',{{}});
hasRight   = false;
locked     = false;       % left and right Y axes share their limits (same unit)
lockUnit   = '';
ax         = [];

% ---------------- layout -----------------------------------------------------
g = uigridlayout(tab,[1 2],'ColumnWidth',{240,'1x'},'Padding',[6 6 6 6]);
gCtl = uigridlayout(g,[15 2],'Padding',[0 0 0 0],'RowSpacing',4,'ColumnSpacing',4, ...
    'RowHeight',{'fit',24,'fit','1x','fit','1x',26,22,26,26,24,26,26,8,'fit'});
gCtl.Layout.Column = 1;
axHolder = uipanel(g,'BorderType','none','BackgroundColor','white');
axHolder.Layout.Column = 2;
gAx = uigridlayout(axHolder,[1 1],'Padding',[0 0 0 0]);

r = 1;
lbl('X axis',r); r = r+1;
ddX = uidropdown(gCtl,'Items',{'(open a file)'},'ValueChangedFcn',@(~,~) refreshPlot(false));
place(ddX,r,[1 2]); r = r+1;
lbl('Left Y axis (Ctrl+click = several)',r); r = r+1;
lbLeft = uilistbox(gCtl,'Multiselect','on','Items',{},'ValueChangedFcn',@onListChanged);
place(lbLeft,r,[1 2]); r = r+1;
lbl('Right Y axis',r); r = r+1;
lbRight = uilistbox(gCtl,'Multiselect','on','Items',{},'ValueChangedFcn',@onListChanged);
place(lbRight,r,[1 2]); r = r+1;
btnTwin = uibutton(gCtl,'Text','Load twin from workspace','ButtonPushedFcn',@(~,~) loadTwin(false), ...
    'Tooltip',sprintf(['Reads twin_soc, twin_current, twin_voltage and twin_temp from the MATLAB\n' ...
    'workspace (or from "out" if the model saves a single simulation output)\n' ...
    'and adds them at the bottom of the Y lists. Press again after a new run.']));
place(btnTwin,r,[1 2]); r = r+1;
cbLock = uicheckbox(gCtl,'Text','Same units -> same Y scale','Value',true, ...
    'ValueChangedFcn',@(~,~) onLockChanged(), ...
    'Tooltip',sprintf(['When every curve on the left and right Y axes has the same unit\n' ...
    '(e.g. measured voltage left, twin voltage right), both axes get the same\n' ...
    'limits so the curves can be compared directly. A twin signal counts as\n' ...
    'having the unit of its measured partner.']));
place(cbLock,r,[1 2]); r = r+1;
btnFitAll = uibutton(gCtl,'Text','Fit all','FontWeight','bold','ButtonPushedFcn',@(~,~) fitView('all'));
place(btnFitAll,r,[1 2]); r = r+1;
btnFitX = uibutton(gCtl,'Text','Fit horizontal','ButtonPushedFcn',@(~,~) fitView('x'));
place(btnFitX,r,1);
btnFitY = uibutton(gCtl,'Text','Fit vertical','ButtonPushedFcn',@(~,~) fitView('y'));
place(btnFitY,r,2); r = r+1;
ddDrag = uidropdown(gCtl,'Items',{'Drag: box zoom','Drag: horizontal zoom', ...
    'Drag: vertical zoom','Drag: off'},'Value','Drag: box zoom');
place(ddDrag,r,[1 2]); r = r+1;
btnBack = uibutton(gCtl,'Text','Zoom back','ButtonPushedFcn',@(~,~) zoomBack());
place(btnBack,r,1);
btnCursor = uibutton(gCtl,'state','Text','Cursor: off','ValueChangedFcn',@(s,~) setCursor(s.Value));
place(btnCursor,r,2); r = r+1;
btnPop = uibutton(gCtl,'Text','Copy plot to a figure','ButtonPushedFcn',@(~,~) onPopOut());
place(btnPop,r,[1 2]); r = r+2;
hint = uilabel(gCtl,'WordWrap','on','FontColor',[0.35 0.35 0.4],'FontSize',11, ...
    'Text',['Left-drag = zoom to box.  Middle-drag (or Shift+drag) = pan.  ' ...
            'Scroll = zoom at the mouse.  Double-click = fit all.  Right-click = zoom back.']);
place(hint,r,[1 2]);
createAxes();
title(ax,'Open a CSV file to start');

% ---------------- figure-level mouse handlers (only act on this tab) --------------
fig.WindowButtonDownFcn   = @onMouseDown;
fig.WindowButtonMotionFcn = @onMouseMove;
fig.WindowButtonUpFcn     = @onMouseUp;
fig.WindowScrollWheelFcn  = @onScroll;
fig.KeyPressFcn           = @onKey;

% ---------------- API ------------------------------------------------------------------
api.setData    = @setData;
api.setColumns = @setColumns;
api.cursorAt   = @(x,y) updateCursor([x y]);
api.setCursor  = @setCursor;
api.zoomBox    = @(xl,yl) applyZoom(xl,yl);
api.fit        = @fitView;
api.zoomBack   = @zoomBack;
api.panBy      = @panBy;
api.getState   = @getState;
api.loadTwin   = @loadTwin;

    function st = getState()     % nested (not anonymous) so it sees the live values
        st = struct('series',series,'ax',ax,'zoomDepth',numel(zoomStack),'twin',twin, ...
            'leftItems',{lbLeft.Items},'rightItems',{lbRight.Items},'locked',locked, ...
            'lockUnit',lockUnit);
    end

% =========================================================================
%  Data
% =========================================================================
    function setData(newD)
        firstTime = isempty(d) || ~isequal(d.file, newD.file);
        d = newD;
        if firstTime, loadTwin(true); end      % pick up twin_* if they already exist
        refreshColumnLists(firstTime);
        refreshPlot(~firstTime);
        if firstTime, zoomStack = {}; fitView('all', false); end
    end

    function refreshColumnLists(setDefaults)
        cols = numericColumns(d.tbl);
        items = [{NONE}, cols];
        if ~isempty(twin), items = [items, {SEP}, {twin.name}]; end
        oldX = ddX.Value; oldL = lbLeft.Value; oldR = lbRight.Value;
        ddX.Items = cols; lbLeft.Items = items; lbRight.Items = items;
        if setDefaults || ~any(strcmp(cols, oldX))
            ddX.Value = pickCol(cols, {'Test Time (h)','TestTime'});
        else
            ddX.Value = oldX;
        end
        keepL = intersect(oldL, items, 'stable'); keepR = intersect(oldR, items, 'stable');
        if setDefaults || isempty(keepL)
            keepL = {pickCol(cols, {'Voltage'})};
            keepR = {pickCol(cols, {'Current, +charge','Current'})};
        end
        if isempty(keepR), keepR = {NONE}; end
        lbLeft.Value = keepL; lbRight.Value = keepR;
    end

    function onListChanged(lb, evt)
        % "(none)" clears that axis; picking anything else drops "(none)".
        % The separator line is not a signal and is ignored.
        v = lb.Value; prev = {};
        if isobject(evt) || isstruct(evt), prev = evt.PreviousValue; end
        v(strcmp(v, SEP)) = [];
        if any(strcmp(v, NONE))
            if ~any(strcmp(prev, NONE)) || numel(v) == 1
                v = {NONE};
            else
                v(strcmp(v, NONE)) = [];
            end
        end
        if isempty(v), v = {NONE}; end
        lb.Value = v;
        refreshPlot(false);
    end

    function setColumns(xName, leftNames, rightNames)
        ddX.Value = xName;
        if isempty(leftNames), lbLeft.Value = {NONE}; else, lbLeft.Value = cellstr(leftNames); end
        if isempty(rightNames), lbRight.Value = {NONE}; else, lbRight.Value = cellstr(rightNames); end
        refreshPlot(false); fitView('all');
    end

% =========================================================================
%  Digital twin signals from the workspace
% =========================================================================
    function loadTwin(silent)
        % Reads twin_soc / twin_current / twin_voltage / twin_temp from the base
        % workspace, or from a Simulink.SimulationOutput called "out" (what a
        % model saves when "Single simulation output" is on). Accepted To
        % Workspace formats: Timeseries, Structure With Time, or Array /
        % Structure together with "tout".
        if nargin < 1, silent = false; end
        old = {twin.name};
        twin = twin([]);
        notes = {};
        for k = 1:numel(TWIN)
            [t, y, how] = readTwinVar(TWIN(k).var);
            if isempty(t)
                if ~isempty(how), notes{end+1} = sprintf('%s: %s', TWIN(k).var, how); end %#ok<AGROW>
                continue
            end
            s.name = TWIN(k).label; s.t = t; s.y = y; s.note = how;
            s.pair = '';
            switch TWIN(k).var
                case 'twin_soc'
                    if max(y) > 1.5 && max(y) <= 100.5, s.y = y/100; s.note = [how ', % -> fraction']; end
                    s.pair = 'SOC (-)';
                case 'twin_current'
                    s.pair = 'Current, +charge (A)';
                case 'twin_voltage'
                    if ~isempty(d), s.pair = d.colNames.voltage; end
                case 'twin_temp'
                    if median(y, 'omitnan') > 150, s.y = y - 273.15; s.note = [how ', K -> °C']; end
                    if ~isempty(d), s.pair = d.colNames.tcell; end
            end
            twin(end+1) = s; %#ok<AGROW>
        end
        if ~isempty(d) && ~isequal(old, {twin.name})
            refreshColumnLists(false);
            refreshPlot(true);
        elseif ~isempty(d) && ~silent
            refreshPlot(true);              % same names, new data from a new run
        end
        btnTwin.Text = sprintf('Load twin from workspace (%d found)', numel(twin));
        if silent, return; end
        if isempty(twin)
            msg = ['No twin signals found. The plot looks for these variables in the ' ...
                   'base workspace (or inside "out"):' newline newline ...
                   '  twin_soc, twin_current, twin_voltage, twin_temp' newline newline ...
                   'Save them with To Workspace blocks (format Timeseries or Structure With Time).'];
            if ~isempty(notes), msg = [msg newline newline strjoin(notes, newline)]; end
            uialert(fig, msg, 'Twin signals', 'Icon','warning');
        elseif isempty(d)
            uialert(fig, 'Twin signals loaded. Open the test CSV to plot them against it.', 'Twin signals', 'Icon','info');
        end
    end

% =========================================================================
%  Plotting
% =========================================================================
    function createAxes()
        % ONE axes for the life of the tab, with both Y axes created up front.
        % (Deleting and re-creating a uiaxes on every change - what this tab used
        % to do - sometimes left the right-axis lines undrawn until the next
        % click forced a repaint.) The right ruler is just hidden when unused.
        ax = uiaxes(gAx);
        styleAxes(ax);
        ax.Interactions = [];               % this tab does its own mouse handling
        disableDefaultInteractivity(ax);
        ax.Toolbar.Visible = 'off';
        yyaxis(ax,'right'); ax.YAxis(2).Color = [0.25 0.25 0.25];
        yyaxis(ax,'left');  ax.YAxis(1).Color = [0.25 0.25 0.25];
        ax.YAxis(2).Visible = 'off';
        cursorX = [];
    end

    function refreshPlot(keepLimits)
        % Redraw the selected columns. keepLimits = true keeps the current zoom;
        % otherwise the view is fitted to the new curves - so changing ANY axis
        % selection always shows every curve straight away.
        lims = [];
        if keepLimits && ~isempty(series), lims = currentLimits(); end
        clearPlot();
        if isempty(d), title(ax,'Open a CSV file to start'); return; end
        xName = ddX.Value;
        leftNames  = setdiff(lbLeft.Value, {NONE, SEP}, 'stable');
        rightNames = setdiff(lbRight.Value, [leftNames, {NONE, SEP}], 'stable');
        hasRight = ~isempty(rightNames);
        pal = seriesColors(numel(leftNames) + numel(rightNames));

        % ---- left Y axis ----
        yyaxis(ax,'left'); hold(ax,'on');
        for k = 1:numel(leftNames)
            addSeries(xName, leftNames{k}, 'left', pal(k,:));
        end
        hold(ax,'off');
        ax.YAxis(1).Label.String = strjoin(leftNames, ', ');
        ax.YAxis(1).Label.Interpreter = 'none';

        % ---- right Y axis (hidden when nothing is picked) ----
        yyaxis(ax,'right'); hold(ax,'on');
        for k = 1:numel(rightNames)
            addSeries(xName, rightNames{k}, 'right', pal(numel(leftNames)+k,:));
        end
        hold(ax,'off');
        ax.YAxis(2).Label.String = strjoin(rightNames, ', ');
        ax.YAxis(2).Label.Interpreter = 'none';
        ax.YAxis(2).Visible = onOff(hasRight);
        yyaxis(ax,'left');                  % mouse / zoom code works in left-axis units
        updateLock();

        xlabel(ax, xName, 'Interpreter','none');
        title(ax, d.name, 'Interpreter','none');
        if ~isempty(series)
            legend(ax, [series.h], {series.name}, 'Interpreter','none', ...
                'Location','southwest', 'AutoUpdate','off');
        end

        if ~isempty(lims), setLimits(lims{:}); else, fitView('all', false); end
        if cursorOn, buildCursor(); end
        repaintSoon();
    end

    function updateLock()
        % lock when the curves on both sides all share one unit
        locked = false; lockUnit = '';
        if ~hasRight || ~cbLock.Value || isempty(series), cbLock.Text = 'Same units -> same Y scale'; return; end
        u = arrayfun(@(s) unitKey(s.name), series, 'UniformOutput', false);
        if all(~cellfun(@isempty, u)) && numel(unique(u)) == 1
            locked = true; lockUnit = u{1};
            cbLock.Text = sprintf('Same units -> same Y scale (locked: %s)', unitLabel(lockUnit));
        else
            cbLock.Text = 'Same units -> same Y scale (units differ)';
        end
    end

    function k = unitKey(name)
        % the unit of a curve: the text in its last (...) - "Voltage (V)" -> V.
        % Temperature columns count as °C. A twin signal takes its measured
        % partner's unit; a column without a unit is only "the same unit" as
        % itself and its own twin.
        t = find(strcmp({twin.name}, name), 1);
        if ~isempty(t) && ~isempty(twin(t).pair), name = twin(t).pair; end
        k = '';
        if ~isempty(d) && any(strcmp(name, {d.colNames.tcell, d.colNames.tch})), k = 'degC'; return; end
        tok = regexp(name, '\(([^()]*)\)\s*$', 'tokens', 'once');
        if ~isempty(tok), k = strtrim(tok{1}); else, k = ['col:' name]; end
        if any(strcmpi(k, {'C','°C','degC','deg C'})), k = 'degC'; end
    end

    function s = unitLabel(k)
        if strcmp(k, 'degC'), s = '°C';
        elseif startsWith(k, 'col:'), s = k(5:end);
        else, s = k;
        end
    end

    function onLockChanged()
        if isempty(series), updateLock(); return; end
        updateLock();
        pushZoom();
        fitView('y', false);
        if cursorOn, refreshCursorAtLast(); end
    end

    function clearPlot()
        deleteCursor();
        for k = 1:numel(series)
            if isvalid(series(k).h), delete(series(k).h); end
        end
        series = series([]);
        legend(ax,'off');
        hasRight = false;
        ax.YAxis(2).Visible = 'off';
        yyaxis(ax,'left');
    end

    function repaintSoon()
        % Belt and braces: re-apply the limits once the window has actually
        % painted the new lines (the same thing clicking "Fit all" did by hand).
        drawnow limitrate
        lims = currentLimits();
        tmr = timer('StartDelay',0.25,'ExecutionMode','singleShot', ...
            'TimerFcn',@(tm,~) reapply(tm, lims));
        start(tmr);
        function reapply(tm, L)
            stop(tm); delete(tm);
            if isempty(ax) || ~isvalid(ax) || isempty(series), return; end
            if ~isequal(currentLimits(), L), return; end    % user already zoomed: leave it
            setLimits(L{:});
            % adding + removing an invisible object forces a full repaint
            % (this is what a click on the plot used to do by accident)
            hold(ax,'on');
            h = plot(ax, NaN, NaN, 'HandleVisibility','off', 'PickableParts','none');
            hold(ax,'off');
            drawnow limitrate
            delete(h);
        end
    end

    function addSeries(xName, yName, side, color)
        T = d.tbl;
        if ~ismember(xName, T.Properties.VariableNames), return; end
        pair = ''; style = '-';
        k = find(strcmp({twin.name}, yName), 1);
        if ~isempty(k)
            % twin signal: its own time base (s from 0, like batt_load) is put
            % on the chosen X column through the test's time
            x = twinX(xName, twin(k).t);
            y = twin(k).y;
            style = '--';
            if ismember(twin(k).pair, T.Properties.VariableNames), pair = twin(k).pair; end
        elseif ismember(yName, T.Properties.VariableNames)
            x = double(T.(xName)); y = double(T.(yName));
        else
            return
        end
        h = plot(ax, x, y, style, 'Color', color, 'LineWidth', 1.3, 'DisplayName', yName);
        h.PickableParts = 'none';
        xv = x(~isnan(x));
        s.h = h; s.side = side; s.x = x; s.y = y;
        s.mono = all(diff(xv) >= 0);           % X never goes back (e.g. time)
        s.name = yName; s.color = color; s.marker = []; s.label = [];
        s.pair = pair; s.dlabel = [];
        series(end+1) = s;
    end

    function x = twinX(xName, tq)
        % value of X column xName at test times tq (s). Time-like columns
        % (rising) are extended past the end; others are NaN outside the test.
        [tu, iu] = unique(d.t, 'last');
        xc = double(d.tbl.(xName)); xc = xc(iu);
        ok = isfinite(xc);
        if nnz(ok) < 2, x = nan(size(tq)); return; end
        if all(diff(xc(ok)) >= 0)
            x = interp1(tu(ok), xc(ok), tq, 'linear', 'extrap');
        else
            x = interp1(tu(ok), xc(ok), tq, 'linear', NaN);
        end
    end

    function lims = currentLimits()
        if hasRight
            lims = {ax.XLim, ax.YAxis(1).Limits, ax.YAxis(2).Limits};
        else
            lims = {ax.XLim, ax.YLim, []};
        end
    end

    function setLimits(xl, yl, yr)
        if any(~isfinite(xl)) || diff(xl) <= 0, xl = xl(1) + [-0.5 0.5]; end
        ax.XLim = xl;
        if locked, yr = yl; end             % one scale for both sides
        if hasRight
            if isfinite(diff(yl)) && diff(yl) > 0, ax.YAxis(1).Limits = yl; end
            if ~isempty(yr) && isfinite(diff(yr)) && diff(yr) > 0, ax.YAxis(2).Limits = yr; end
        else
            if isfinite(diff(yl)) && diff(yl) > 0, ax.YLim = yl; end
        end
        if cursorOn, refreshCursorAtLast(); end
    end

    function [lo, hi] = extentOf(side, xr)
        % min / max of every curve on one side (optionally only inside X range xr)
        lo = inf; hi = -inf;
        for k = 1:numel(series)
            if ~strcmp(series(k).side, side), continue; end
            y = series(k).y;
            if ~isempty(xr), y = y(series(k).x >= xr(1) & series(k).x <= xr(2)); end
            y = y(isfinite(y));
            if isempty(y), continue; end
            lo = min(lo, min(y)); hi = max(hi, max(y));
        end
        if ~isfinite(lo), lo = 0; hi = 1; end
        if hi - lo < eps(max(abs([lo hi]))+1)*100
            pad = max(abs(hi)*0.05, 0.5);
        else
            pad = 0.04*(hi - lo);
        end
        lo = lo - pad; hi = hi + pad;
    end

    function fitView(mode, push)
        % mode 'all' | 'x' (horizontal) | 'y' (vertical, for the X range shown)
        if nargin < 2, push = true; end
        if isempty(series), return; end
        if push, pushZoom(); end
        lims = currentLimits();
        xl = lims{1}; yl = lims{2}; yr = lims{3};
        if any(strcmp(mode, {'all','x'}))
            xs = cellfun(@finiteRange, {series.x}, 'UniformOutput', false);
            xs = vertcat(xs{:});
            xl = [min(xs(:,1),[],'omitnan') max(xs(:,2),[],'omitnan')];
            if ~all(isfinite(xl)), xl = lims{1}; end
        end
        if any(strcmp(mode, {'all','y'}))
            if strcmp(mode,'all'), xr = []; else, xr = xl; end
            [a,b] = extentOf('left', xr); yl = [a b];
            if hasRight, [a,b] = extentOf('right', xr); yr = [a b]; end
            if locked, yl = [min(yl(1), yr(1)), max(yl(2), yr(2))]; yr = yl; end
        end
        setLimits(xl, yl, yr);
    end

    function pushZoom()
        if isempty(series), return; end
        zoomStack{end+1} = currentLimits();
        if numel(zoomStack) > 50, zoomStack(1) = []; end
    end

    function zoomBack()
        if isempty(zoomStack), fitView('all', false); return; end
        lims = zoomStack{end}; zoomStack(end) = [];
        setLimits(lims{:});
    end

    function applyZoom(xl, yl)
        % xl / yl in LEFT-axis units; [] keeps that direction as it is
        pushZoom();
        lims = currentLimits();
        newX = lims{1}; newL = lims{2}; newR = lims{3};
        if ~isempty(xl), newX = sort(xl); end
        if ~isempty(yl)
            yl = sort(yl);
            if hasRight && ~locked              % right axis zooms by the same fraction

                f = (yl - lims{2}(1)) / diff(lims{2});
                newR = lims{3}(1) + f*diff(lims{3});
            end
            newL = yl;
        end
        setLimits(newX, newL, newR);
    end

    function panBy(fx, fy)
        % shift the view by a fraction of the visible range (positive = right / up)
        lims = currentLimits();
        yr = lims{3};
        if hasRight, yr = yr + fy*diff(yr); end
        setLimits(lims{1} + fx*diff(lims{1}), lims{2} + fy*diff(lims{2}), yr);
    end

    function onPopOut()
        if isempty(series), return; end
        f2 = figure('Name','Battery plot','Color','w');
        a2 = axes(f2);
        a2.FontName = 'Century Gothic';
        a2.FontSize = 16;
        a2.Title.FontName = 'Century Gothic';
        a2.XLabel.FontName = 'Century Gothic';
        a2.YLabel.FontName = 'Century Gothic';
        lims = currentLimits();
        if hasRight
            yyaxis(a2,'right'); hold(a2,'on');
            for k = find(strcmp({series.side},'right'))
                plot(a2, series(k).x, series(k).y, 'Color', series(k).color, 'LineStyle', series(k).h.LineStyle, 'DisplayName', series(k).name);
            end
            ylim(a2, lims{3}); ylabel(a2, ax.YAxis(2).Label.String, 'Interpreter','none');
            yyaxis(a2,'left');
        end
        hold(a2,'on');
        for k = find(strcmp({series.side},'left'))
            plot(a2, series(k).x, series(k).y, 'Color', series(k).color, 'LineStyle', series(k).h.LineStyle, 'DisplayName', series(k).name);
        end
        xlim(a2, lims{1}); ylim(a2, lims{2});
        xlabel(a2, ax.XLabel.String, 'Interpreter','none');
        ylabel(a2, ax.YAxis(1).Label.String, 'Interpreter','none');
        legend(a2, 'Interpreter','none', 'Location','southwest');   % bottom-left
        grid(a2,'on');
    end

% =========================================================================
%  Mouse: drag-zoom, middle-drag pan, scroll-zoom, cursor
% =========================================================================
    function on = tabVisible()
        on = isvalid(tab) && tab.Parent.SelectedTab == tab;
    end

    function [inside, p] = mouseInAxes()
        inside = false; p = [NaN NaN];
        if isempty(series) || isempty(ax) || ~isvalid(ax) || ~tabVisible(), return; end
        cp = ax.CurrentPoint;            % left-axis data units
        p = cp(1,1:2);
        lims = currentLimits();
        inside = p(1) >= lims{1}(1) && p(1) <= lims{1}(2) && p(2) >= lims{2}(1) && p(2) <= lims{2}(2);
    end

    function onMouseDown(~,~)
        [inside, p] = mouseInAxes();
        if ~inside, return; end
        switch fig.SelectionType
            case 'open'                       % double-click
                drag.active = false; deleteBox();
                fitView('all');
            case 'alt'                        % right-click
                zoomBack();
            case 'extend'                     % middle button (or shift + left)
                pan.active = true;
                pan.px0 = fig.CurrentPoint;
                pan.lims0 = currentLimits();
                fig.Pointer = 'fleur';
            case 'normal'
                if strcmp(ddDrag.Value,'Drag: off'), return; end
                drag.active = true; drag.p0 = p;
                deleteBox();
                hold(ax,'on');
                if hasRight, yyaxis(ax,'left'); end
                drag.box = plot(ax, NaN, NaN, '-', 'Color',[0.1 0.3 0.8], 'LineWidth',1, ...
                    'HandleVisibility','off','PickableParts','none');
                hold(ax,'off');
        end
    end

    function onMouseMove(~,~)
        if pan.active
            % pixels moved -> data units, using the axes' plot-box size in pixels
            dp = fig.CurrentPoint - pan.px0;
            pos = ax.InnerPosition;
            L = pan.lims0;
            fx = -dp(1)/pos(3); fy = -dp(2)/pos(4);
            yr = L{3};
            if hasRight, yr = yr + fy*diff(yr); end
            setLimits(L{1} + fx*diff(L{1}), L{2} + fy*diff(L{2}), yr);
            return
        end
        if drag.active
            cp = ax.CurrentPoint;
            [xr, yr] = dragRect(drag.p0, clampToAxes(cp(1,1:2)));
            set(drag.box, 'XData', xr([1 2 2 1 1]), 'YData', yr([1 1 2 2 1]));
            return
        end
        if ~cursorOn, return; end
        [inside, p] = mouseInAxes();
        if inside, updateCursor(p); end
    end

    function onMouseUp(~,~)
        if pan.active
            pan.active = false;
            fig.Pointer = 'arrow';
            zoomStack{end+1} = pan.lims0;       % "Zoom back" undoes the pan
            return
        end
        if ~drag.active, return; end
        drag.active = false;
        cp = ax.CurrentPoint; p = clampToAxes(cp(1,1:2));
        deleteBox();
        [xr, yr] = dragRect(drag.p0, p);
        lims = currentLimits();
        fx = abs(diff(xr))/diff(lims{1}); fy = abs(diff(yr))/diff(lims{2});
        mode = ddDrag.Value;
        if contains(mode,'horizontal')
            if fx > 0.005, applyZoom(xr, []); end
        elseif contains(mode,'vertical')
            if fy > 0.005, applyZoom([], yr); end
        elseif fx > 0.005 && fy > 0.005
            applyZoom(xr, yr);
        end
    end

    function [xr, yr] = dragRect(p0, p1)
        lims = currentLimits();
        xr = sort([p0(1) p1(1)]); yr = sort([p0(2) p1(2)]);
        if contains(ddDrag.Value,'horizontal'), yr = lims{2}; end
        if contains(ddDrag.Value,'vertical'),   xr = lims{1}; end
    end

    function p = clampToAxes(p)
        lims = currentLimits();
        p(1) = min(max(p(1), lims{1}(1)), lims{1}(2));
        p(2) = min(max(p(2), lims{2}(1)), lims{2}(2));
    end

    function deleteBox()
        if ~isempty(drag.box) && isvalid(drag.box), delete(drag.box); end
        drag.box = [];
    end

    function onScroll(~,evt)
        [inside, p] = mouseInAxes();
        if ~inside, return; end
        f = 1.25^evt.VerticalScrollCount;     % >1 zoom out, <1 zoom in
        lims = currentLimits();
        mode = ddDrag.Value;
        newX = []; newY = [];
        if ~contains(mode,'vertical'), newX = p(1) + (lims{1} - p(1))*f; end
        if contains(mode,'vertical') || contains(mode,'box'), newY = p(2) + (lims{2} - p(2))*f; end
        applyZoom(newX, newY);
    end

    function onKey(~,evt)
        if ~tabVisible(), return; end
        switch evt.Key
            case 'escape',    drag.active = false; deleteBox();
            case 'f',         fitView('all');
            case 'backspace', zoomBack();
        end
    end

    function setCursor(on)
        cursorOn = logical(on);
        btnCursor.Value = cursorOn;
        if cursorOn
            btnCursor.Text = 'Cursor: on';
            buildCursor();
            if ~isempty(series)
                lims = currentLimits();
                updateCursor([mean(lims{1}) mean(lims{2})]);
            end
        else
            btnCursor.Text = 'Cursor: off';
            deleteCursor();
        end
    end

    function buildCursor()
        deleteCursor();
        if isempty(series), return; end
        hold(ax,'on');
        for k = 1:numel(series)
            if hasRight, yyaxis(ax, series(k).side); end
            series(k).marker = plot(ax, NaN, NaN, 'o', 'MarkerSize',7, 'LineWidth',1.5, ...
                'MarkerEdgeColor', series(k).color, 'MarkerFaceColor','w', ...
                'HandleVisibility','off','PickableParts','none');
            series(k).label = text(ax, NaN, NaN, '', 'Color', series(k).color*0.8, ...
                'FontSize',11,'FontWeight','bold','BackgroundColor',[1 1 1 0.85], ...
                'EdgeColor', series(k).color, 'Margin',2, 'Interpreter','none', ...
                'Clipping','on','PickableParts','none','VerticalAlignment','middle');
            if partnerOf(k) > 0            % twin + measured both shown -> a delta label
                series(k).dlabel = text(ax, NaN, NaN, '', 'Color',[0.1 0.1 0.1], ...
                    'FontSize',11,'FontWeight','bold','FontAngle','italic', ...
                    'BackgroundColor',[1 0.97 0.80 0.92],'EdgeColor',[0.45 0.45 0.45], ...
                    'LineStyle','--','Margin',2,'Interpreter','none','Clipping','on', ...
                    'PickableParts','none','VerticalAlignment','middle');
            end
        end
        if hasRight, yyaxis(ax,'left'); end
        cursorX = xline(ax, mean(ax.XLim), '-', '', 'Color',[0.15 0.15 0.15], ...
            'LineWidth',1, 'LabelOrientation','horizontal', ...
            'LabelVerticalAlignment','bottom','FontSize',11,'FontWeight','bold', ...
            'HandleVisibility','off','PickableParts','none','Interpreter','none');
        hold(ax,'off');
    end

    function deleteCursor()
        for k = 1:numel(series)
            if ~isempty(series(k).marker) && isvalid(series(k).marker), delete(series(k).marker); end
            if ~isempty(series(k).label) && isvalid(series(k).label), delete(series(k).label); end
            if ~isempty(series(k).dlabel) && isvalid(series(k).dlabel), delete(series(k).dlabel); end
            series(k).marker = []; series(k).label = []; series(k).dlabel = [];
        end
        if ~isempty(cursorX) && isvalid(cursorX), delete(cursorX); end
        cursorX = [];
    end

    function refreshCursorAtLast()
        if isempty(cursorX) || ~isvalid(cursorX), return; end
        lims = currentLimits();
        x = cursorX.Value;
        if x < lims{1}(1) || x > lims{1}(2), x = mean(lims{1}); end
        updateCursor([x mean(lims{2})]);
    end

    function updateCursor(p)
        if isempty(series) || isempty(cursorX) || ~isvalid(cursorX), return; end
        lims = currentLimits();
        xl = lims{1};
        xc = snapX(p(1), xl);          % snap to the nearest actually-measured X sample
        cursorX.Value = xc;
        cursorX.Label = [' ' ddX.Value ' = ' fmtFull(xc) ' '];
        if (xc - xl(1))/diff(xl) > 0.6
            cursorX.LabelHorizontalAlignment = 'left';
        else
            cursorX.LabelHorizontalAlignment = 'right';
        end
        fracY = (p(2) - lims{2}(1)) / diff(lims{2});
        n = numel(series);
        yFrac = nan(n,1); yVal = nan(n,1); xVal = nan(n,1);
        for k = 1:n
            s = series(k);
            yl = lims{2}; if strcmp(s.side,'right'), yl = lims{3}; end
            if s.mono
                [xv, yv] = interpMono(s.x, s.y, xc);
            else
                % X goes back and forth (e.g. V vs SOC): nearest point on screen
                yc = yl(1) + fracY*diff(yl);
                dd = ((s.x - xc)/diff(xl)).^2 + ((s.y - yc)/diff(yl)).^2;
                [~, j] = min(dd);
                xv = s.x(j); yv = s.y(j);
            end
            xVal(k) = xv; yVal(k) = yv;
            yFrac(k) = (yv - yl(1)) / diff(yl);
        end
        % push labels apart when they would overlap (screen-fraction units)
        labFrac = yFrac;
        [~, order] = sort(labFrac);
        order = order(isfinite(labFrac(order)));
        for j = 2:numel(order)
            if labFrac(order(j)) - labFrac(order(j-1)) < 0.055
                labFrac(order(j)) = labFrac(order(j-1)) + 0.055;
            end
        end
        rightSide = (xc - xl(1))/diff(xl) > 0.72;     % labels flip to the left near the edge
        dx = 0.012*diff(xl);
        for k = 1:n
            s = series(k);
            if isempty(s.marker) || ~isvalid(s.marker), continue; end
            yl = lims{2}; if strcmp(s.side,'right'), yl = lims{3}; end
            if ~(isfinite(yVal(k)) && yFrac(k) >= 0 && yFrac(k) <= 1)
                set(s.marker,'XData',NaN,'YData',NaN);
                set(s.label,'Position',[NaN NaN 0],'String','');
                continue
            end
            set(s.marker,'XData',xVal(k),'YData',yVal(k));
            ly = yl(1) + min(max(labFrac(k),0.03),0.97)*diff(yl);
            str = sprintf('%s: %s', s.name, fmtNum(yVal(k)));
            if rightSide
                set(s.label,'Position',[xVal(k)-dx ly 0],'HorizontalAlignment','right','String',str);
            else
                set(s.label,'Position',[xVal(k)+dx ly 0],'HorizontalAlignment','left','String',str);
            end
        end

        % ---- delta labels: twin - measured, on the OTHER side of the cursor
        dk = find(arrayfun(@(s) ~isempty(s.dlabel) && isvalid(s.dlabel), series));
        dFrac = nan(numel(dk),1);
        for j = 1:numel(dk)
            k = dk(j); m = partnerOf(k);
            if m > 0 && isfinite(yVal(k)) && isfinite(yVal(m)), dFrac(j) = yFrac(k); end
        end
        [~, order] = sort(dFrac); order = order(isfinite(dFrac(order)));
        for j = 2:numel(order)
            if dFrac(order(j)) - dFrac(order(j-1)) < 0.055
                dFrac(order(j)) = dFrac(order(j-1)) + 0.055;
            end
        end
        for j = 1:numel(dk)
            k = dk(j); s = series(k);
            if ~isfinite(dFrac(j)) || yFrac(k) < 0 || yFrac(k) > 1
                set(s.dlabel,'Position',[NaN NaN 0],'String',''); continue
            end
            m = partnerOf(k);
            yl = lims{2}; if strcmp(s.side,'right'), yl = lims{3}; end
            ly = yl(1) + min(max(dFrac(j),0.03),0.97)*diff(yl);
            str = sprintf('%s = %s (twin - measured)', ...
                deltaName(s.name), fmtDelta(yVal(k) - yVal(m)));
            if rightSide
                set(s.dlabel,'Position',[xc+dx ly 0],'HorizontalAlignment','left','String',str);
            else
                set(s.dlabel,'Position',[xc-dx ly 0],'HorizontalAlignment','right','String',str);
            end
            % no room on that side (cursor near the edge): put it on the
            % value-label side instead, below all the value labels
            e = s.dlabel.Extent;
            if numel(e) >= 3 && (e(1) < xl(1) || e(1) + e(3) > xl(2))
                below = min(labFrac(isfinite(labFrac))) - 0.06*find(order == j, 1);
                ly = yl(1) + min(max(below, 0.03), 0.97)*diff(yl);
                if rightSide
                    set(s.dlabel,'Position',[xc-dx ly 0],'HorizontalAlignment','right');
                else
                    set(s.dlabel,'Position',[xc+dx ly 0],'HorizontalAlignment','left');
                end
            end
        end
    end

    function xs = snapX(x0, xl)
        % nearest X sample (over all plotted series) to x0, so the cursor sits on
        % a point that was really measured. Falls back to x0 if nothing is finite.
        xs = x0; best = inf;
        for q = 1:numel(series)
            sx = series(q).x;
            if isempty(sx), continue; end
            [d, j] = min(abs(sx - x0));
            if isfinite(d) && d < best, best = d; xs = sx(j); end
        end
        xs = min(max(xs, xl(1)), xl(2));
    end

    function m = partnerOf(k)
        % index of the measured series a twin series is paired with (0 = none shown)
        m = 0;
        if isempty(series(k).pair), return; end
        j = find(strcmp({series.name}, series(k).pair), 1);
        if ~isempty(j), m = j; end
    end

% ---------------- layout helpers -------------------------------------------------
    function lbl(txt,row)
        h = uilabel(gCtl,'Text',txt,'FontWeight','bold');
        h.Layout.Row = row; h.Layout.Column = [1 2];
    end
end

% =========================================================================
%  Small helpers (not nested)
% =========================================================================
function place(h,row,col)
h.Layout.Row = row; h.Layout.Column = col;
end

function styleAxes(a)
a.FontName = 'Segoe UI'; a.FontSize = 11; a.Box = 'on';
grid(a,'on'); a.GridAlpha = 0.12;
a.Title.FontWeight = 'bold';
end

function s = deltaName(twinName)
% 'Twin: Voltage (V)' -> 'ΔVoltage (V)'
s = [char(916) strtrim(regexprep(twinName, '^Twin:\s*', ''))];
end

function s = fmtDelta(v)
s = fmtNum(v);
if isfinite(v) && v > 0, s = ['+' s]; end
end

function r = finiteRange(v)
v = v(isfinite(v));
if isempty(v), r = [NaN NaN]; else, r = [min(v) max(v)]; end
end

function [t, y, how] = readTwinVar(name)
% One twin signal from the base workspace (or from "out"). Returns [] if absent.
t = []; y = []; how = '';
[v, src] = fetchBase(name);
if isempty(src), return; end
how = ['read from ' src];
try
    if isa(v, 'Simulink.SimulationData.Dataset'), v = v{1}; end
    if isa(v, 'Simulink.SimulationData.Signal'),  v = v.Values; end
    if isa(v, 'timeseries')
        t = double(v.Time(:)); y = double(squeeze(v.Data));
    elseif istimetable(v)
        t = seconds(v.Properties.RowTimes - v.Properties.RowTimes(1)); y = double(v{:,1});
    elseif isstruct(v) && isfield(v, 'signals')
        y = double(v.signals(1).values);
        if isfield(v, 'time') && ~isempty(v.time)
            t = double(v.time(:));
        else
            t = double(fetchBase('tout')); t = t(:); how = [how ' + tout'];
        end
    elseif isnumeric(v)
        tt = double(fetchBase('tout'));
        if numel(tt) == size(v,1)
            t = tt(:); y = double(v); how = [how ' + tout'];
        elseif size(v,2) == 2
            t = double(v(:,1)); y = double(v(:,2)); how = [how ' as [t y]'];
        end
    end
catch ME
    t = []; y = []; how = ['could not read (' ME.message ')']; return
end
if isempty(y), t = []; how = 'format not recognised (use Timeseries or Structure With Time)'; return; end
if ~isvector(y), y = y(:,1); end
y = y(:);
if numel(t) ~= numel(y)
    t = []; y = []; how = 'time and data lengths differ'; return
end
end

function [v, src] = fetchBase(name)
v = []; src = '';
if evalin('base', sprintf('exist(''%s'',''var'')', name))
    v = evalin('base', name); src = 'the workspace';
elseif evalin('base', 'exist(''out'',''var'') && isa(out,''Simulink.SimulationOutput'')')
    out = evalin('base', 'out');
    if any(strcmp(out.who, name)), v = out.get(name); src = 'out'; end
end
end

function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function c = seriesColors(n)
base = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56;
        0.93 0.69 0.13; 0.30 0.75 0.93; 0.64 0.08 0.18; 0.25 0.25 0.25];
c = base(mod(0:max(n,1)-1, size(base,1)) + 1, :);
end

function s = fmtNum(v)
if ~isfinite(v), s = 'NaN'; return; end
a = abs(v);
if a == 0, s = '0';
elseif a >= 1e5 || a < 1e-3, s = sprintf('%.4g', v);
elseif a >= 100, s = sprintf('%.1f', v);
elseif a >= 1, s = sprintf('%.4f', v);
else, s = sprintf('%.4g', v);
end
end

function s = fmtFull(v)
% Full typed-out number: never an exponent / axis multiplier (e.g. 12345.678, not 1.2346e4).
if ~isfinite(v), s = 'NaN'; return; end
s = sprintf('%.10g', v);
if any(s == 'e')
    s = sprintf('%.10f', v);
    s = regexprep(s, '(\.\d*?)0+$', '$1');
    s = regexprep(s, '\.$', '');
end
end

function c = pickCol(cols, prefs)
c = cols{1};
for k = 1:numel(prefs)
    j = find(strncmpi(cols, prefs{k}, numel(prefs{k})), 1);
    if ~isempty(j), c = cols{j}; return; end
end
end

function cols = numericColumns(T)
v = T.Properties.VariableNames;
keep = false(size(v));
for k = 1:numel(v)
    x = T.(v{k});
    keep(k) = (isnumeric(x) || islogical(x)) && isvector(x) && any(isfinite(double(x)));
end
cols = v(keep);
pri = {'Test Time (h)','TestTime (s)','Voltage (V)','Current, +charge (A)','Current (A)', ...
       'SOC (-)','Temp 1','Chamber Temperature (C)'};
[tf, loc] = ismember(pri, cols);
first = cols(loc(tf));
cols = [first, setdiff(cols, first, 'stable')];
end

function [xv, yv] = interpMono(x, y, xc)
% value of a curve whose X never decreases, at xc (linear between samples)
n = numel(x);
k = find(x <= xc, 1, 'last');
if isempty(k), k = 1; end
if k >= n || x(k+1) <= x(k)
    xv = x(k); yv = y(k);
    if k < n && abs(x(k+1) - xc) < abs(x(k) - xc), xv = x(k+1); yv = y(k+1); end
    return
end
f = (xc - x(k)) / (x(k+1) - x(k));
xv = xc;
yv = y(k) + f*(y(k+1) - y(k));
if ~isfinite(yv)
    if f < 0.5, yv = y(k); xv = x(k); else, yv = y(k+1); xv = x(k+1); end
end
end
