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
%   with a label next to every crossing point.

% ---------------- state shared by the nested functions ----------------------
d          = [];          % current dataset
series     = struct('h',{},'side',{},'x',{},'y',{},'mono',{},'name',{}, ...
                    'color',{},'marker',{},'label',{});
cursorOn   = false;
cursorX    = [];          % xline handle
zoomStack  = {};
drag       = struct('active',false,'p0',[0 0],'box',[]);
pan        = struct('active',false,'px0',[0 0],'lims0',{{}});
hasRight   = false;
ax         = [];

% ---------------- layout -----------------------------------------------------
g = uigridlayout(tab,[1 2],'ColumnWidth',{240,'1x'},'Padding',[6 6 6 6]);
gCtl = uigridlayout(g,[14 2],'Padding',[0 0 0 0],'RowSpacing',4,'ColumnSpacing',4, ...
    'RowHeight',{'fit',24,'fit','1x','fit','1x',8,26,26,24,26,26,8,'fit'});
gCtl.Layout.Column = 1;
axHolder = uipanel(g,'BorderType','none','BackgroundColor','white');
axHolder.Layout.Column = 2;
gAx = uigridlayout(axHolder,[1 1],'Padding',[0 0 0 0]);

r = 1;
lbl('X axis',r); r = r+1;
ddX = uidropdown(gCtl,'Items',{'(open a file)'},'ValueChangedFcn',@(~,~) refreshPlot(false));
place(ddX,r,[1 2]); r = r+1;
lbl('Left Y axis (Ctrl+click = several)',r); r = r+1;
lbLeft = uilistbox(gCtl,'Multiselect','on','Items',{},'ValueChangedFcn',@(~,~) refreshPlot(false));
place(lbLeft,r,[1 2]); r = r+1;
lbl('Right Y axis',r); r = r+1;
lbRight = uilistbox(gCtl,'Multiselect','on','Items',{},'ValueChangedFcn',@(~,~) refreshPlot(false));
place(lbRight,r,[1 2]); r = r+2;
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

    function st = getState()     % nested (not anonymous) so it sees the live values
        st = struct('series',series,'ax',ax,'zoomDepth',numel(zoomStack));
    end

% =========================================================================
%  Data
% =========================================================================
    function setData(newD)
        firstTime = isempty(d) || ~isequal(d.file, newD.file);
        d = newD;
        refreshColumnLists(firstTime);
        refreshPlot(~firstTime);
        if firstTime, zoomStack = {}; fitView('all', false); end
    end

    function refreshColumnLists(setDefaults)
        cols = numericColumns(d.tbl);
        oldX = ddX.Value; oldL = lbLeft.Value; oldR = lbRight.Value;
        ddX.Items = cols; lbLeft.Items = cols; lbRight.Items = cols;
        if setDefaults || ~any(strcmp(cols, oldX))
            ddX.Value = pickCol(cols, {'Test Time (h)','TestTime'});
        else
            ddX.Value = oldX;
        end
        keepL = intersect(oldL, cols, 'stable'); keepR = intersect(oldR, cols, 'stable');
        if setDefaults || isempty(keepL)
            keepL = {pickCol(cols, {'Voltage'})};
            keepR = {pickCol(cols, {'Current, +charge','Current'})};
        end
        lbLeft.Value = keepL; lbRight.Value = keepR;
    end

    function setColumns(xName, leftNames, rightNames)
        ddX.Value = xName;
        lbLeft.Value = cellstr(leftNames);
        if isempty(rightNames), lbRight.Value = {}; else, lbRight.Value = cellstr(rightNames); end
        refreshPlot(false); fitView('all');
    end

% =========================================================================
%  Plotting
% =========================================================================
    function createAxes()
        if ~isempty(ax) && isvalid(ax), delete(ax); end
        ax = uiaxes(gAx);
        styleAxes(ax);
        ax.Interactions = [];               % this tab does its own mouse handling
        disableDefaultInteractivity(ax);
        ax.Toolbar.Visible = 'off';
        cursorX = [];
    end

    function refreshPlot(keepLimits)
        lims = [];
        if keepLimits && ~isempty(series), lims = currentLimits(); end
        createAxes();
        series = series([]);
        if isempty(d), title(ax,'Open a CSV file to start'); return; end
        xName = ddX.Value;
        leftNames = lbLeft.Value;
        rightNames = setdiff(lbRight.Value, leftNames, 'stable');
        hasRight = ~isempty(rightNames);
        pal = seriesColors(numel(leftNames) + numel(rightNames));
        c = 0;
        if hasRight
            yyaxis(ax,'right'); hold(ax,'on');
            for k = 1:numel(rightNames)
                c = c+1; addSeries(xName, rightNames{k}, 'right', pal(c,:));
            end
            ylabel(ax, strjoin(rightNames, ', '), 'Interpreter','none');
            ax.YAxis(2).Color = [0.25 0.25 0.25];
            yyaxis(ax,'left');
        end
        hold(ax,'on');
        for k = 1:numel(leftNames)
            c = c+1; addSeries(xName, leftNames{k}, 'left', pal(c,:));
        end
        ylabel(ax, strjoin(leftNames, ', '), 'Interpreter','none');
        if hasRight, ax.YAxis(1).Color = [0.25 0.25 0.25]; end
        xlabel(ax, xName, 'Interpreter','none');
        title(ax, d.name, 'Interpreter','none');
        if ~isempty(series)
            legend(ax, [series.h], {series.name}, 'Interpreter','none', ...
                'Location','best','AutoUpdate','off');
        end
        hold(ax,'off');
        if ~isempty(lims), setLimits(lims{:}); else, fitView('all', false); end
        if cursorOn, buildCursor(); end
    end

    function addSeries(xName, yName, side, color)
        T = d.tbl;
        if ~all(ismember({xName, yName}, T.Properties.VariableNames)), return; end
        x = double(T.(xName)); y = double(T.(yName));
        h = plot(ax, x, y, '-', 'Color', color, 'LineWidth', 1.3, 'DisplayName', yName);
        h.PickableParts = 'none';
        xv = x(~isnan(x));
        s.h = h; s.side = side; s.x = x; s.y = y;
        s.mono = all(diff(xv) >= 0);           % X never goes back (e.g. time)
        s.name = yName; s.color = color; s.marker = []; s.label = [];
        series(end+1) = s;
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
            xs = cellfun(@(v) [min(v(isfinite(v))) max(v(isfinite(v)))], {series.x}, 'UniformOutput', false);
            xs = vertcat(xs{:});
            xl = [min(xs(:,1)) max(xs(:,2))];
        end
        if any(strcmp(mode, {'all','y'}))
            if strcmp(mode,'all'), xr = []; else, xr = xl; end
            [a,b] = extentOf('left', xr); yl = [a b];
            if hasRight, [a,b] = extentOf('right', xr); yr = [a b]; end
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
            if hasRight                         % right axis zooms by the same fraction
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
        lims = currentLimits();
        if hasRight
            yyaxis(a2,'right'); hold(a2,'on');
            for k = find(strcmp({series.side},'right'))
                plot(a2, series(k).x, series(k).y, 'Color', series(k).color, 'DisplayName', series(k).name);
            end
            ylim(a2, lims{3}); ylabel(a2, ax.YAxis(2).Label.String); yyaxis(a2,'left');
        end
        hold(a2,'on');
        for k = find(strcmp({series.side},'left'))
            plot(a2, series(k).x, series(k).y, 'Color', series(k).color, 'DisplayName', series(k).name);
        end
        xlim(a2, lims{1}); ylim(a2, lims{2});
        xlabel(a2, ax.XLabel.String); ylabel(a2, ax.YAxis(1).Label.String);
        legend(a2,'Interpreter','none'); grid(a2,'on');
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
            series(k).marker = []; series(k).label = [];
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
        xc = p(1);
        cursorX.Value = xc;
        cursorX.Label = [' ' ddX.Value ' = ' fmtNum(xc) ' '];
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
