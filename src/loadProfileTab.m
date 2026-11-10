function api = loadProfileTab(tab, fig)
%LOADPROFILETAB  "Load profile" tab: the test's current profile for Simulink.
%
%   api = loadProfileTab(tab, fig)
%   api.setData(d)        show the current of dataset d
%   api.setCapacity(AH)   capacity (Ah) for the C-rate labels (NaN = unknown);
%                         the Modeling tab sends it after "Extract" or when
%                         you type an AH
%   api.save()            same as pressing "Save to workspace"
%
%   Sign convention: POSITIVE = CHARGE (current into the cell),
%                    NEGATIVE = DISCHARGE.
%
%   Every charge / discharge pulse (a run of current with one sign) gets a
%   label with its C-rate (|I| / AH) and the Ah that went in (+) or out (-).
%   Labels that would overlap are hidden; zoom in to see them all.
%
%   Saved to the base workspace
%     batt_load        [t I]  two columns: time (s) from 0, current (A)
%     batt_load_ts     the same data as a timeseries object
%     batt_stopTime    length of the test (s)  -> model Stop time
%     batt_Ts          sampling interval of the test (s, median) -> To Workspace
%                      "Sample time", or a fixed-step solver's step size
%
%   In Simulink:
%     From Workspace (Data = batt_load, Interpolate data = on,
%                     Form output after final data value = Holding final value)
%       -> Simulink-PS Converter (unit A)
%       -> Controlled Current Source (Simscape > Foundation > Electrical > Sources)
%     Wire the source "+" (arrow head) to battery "+" and "-" to battery "-":
%     a positive signal then pushes current INTO the battery = charging.

d = [];
prof = [];
capAh = NaN;
pulses = [];          % struct array, one per charge / discharge pulse
hLab = gobjects(0);   % one text label per pulse
labStr = {};          % ... and its text

g = uigridlayout(tab,[1 2],'ColumnWidth',{350,'1x'},'Padding',[6 6 6 6]);
gL = uigridlayout(g,[3 1],'RowHeight',{36,'fit','1x'},'Padding',[0 0 0 0]);
gL.Layout.Column = 1;
btnSave = uibutton(gL,'Text','Save load profile to workspace','FontWeight','bold','FontSize',13, ...
    'BackgroundColor',[0.20 0.45 0.80],'FontColor','white','Enable','off', ...
    'ButtonPushedFcn',@(~,~) onSave(), ...
    'Tooltip',sprintf(['Writes batt_load = [t I] (positive = charge), batt_load_ts (timeseries),\n' ...
                       'batt_stopTime (model Stop time) and batt_Ts (sampling interval)\n' ...
                       'to the base workspace.']));
lblInfo = uilabel(gL,'Text','Open a CSV file first.','WordWrap','on','VerticalAlignment','top', ...
    'FontName','Consolas','FontSize',12);

axI = uiaxes(g);
axI.Layout.Column = 2;
styleAxes(axI);
title(axI,'Current profile (positive = charge)');
xlabel(axI,'Test time (h)'); ylabel(axI,'Current (A)');
axI.XAxis.LimitsChangedFcn = @(~,~) layoutLabels();
axI.YAxis.LimitsChangedFcn = @(~,~) layoutLabels();

api.setData = @setData;
api.setCapacity = @setCapacity;
api.save = @onSave;
api.getProfile = @getProfile;
api.getPulses = @getPulses;

    function p = getProfile()    % nested (not anonymous) so it sees the live value
        p = prof;
    end
    function p = getPulses()
        p = pulses;
        for k = 1:numel(p), p(k).visible = strcmp(hLab(k).Visible, 'on'); end
    end

    function setData(newD)
        if isempty(d) || ~strcmp(d.file, newD.file), capAh = NaN; end   % new file: capacity unknown
        d = newD;
        prof = buildProfile(d);
        pulses = findPulses(prof.tData, prof.IData);
        cla(axI);
        hold(axI,'on');
        th = prof.t/3600;
        Ip = prof.I; Ip(Ip < 0) = 0;
        In = prof.I; In(In > 0) = 0;
        patch(axI, [th; flipud(th)], [Ip; zeros(size(Ip))], [0.20 0.60 0.30], ...
            'FaceAlpha',0.35, 'EdgeColor','none', 'DisplayName','charge (+)');
        patch(axI, [th; flipud(th)], [In; zeros(size(In))], [0.85 0.33 0.10], ...
            'FaceAlpha',0.35, 'EdgeColor','none', 'DisplayName','discharge (-)');
        plot(axI, th, prof.I, '-', 'Color',[0.15 0.15 0.15], 'LineWidth',1, 'DisplayName','current');
        yline(axI, 0, ':', 'HandleVisibility','off');
        hold(axI,'off');
        legend(axI,'Location','southwest');
        title(axI, sprintf('Current profile of %s (positive = charge)', d.name), 'Interpreter','none');
        makeLabels();
        % explicit limits (uiaxes may not have updated its automatic limits yet),
        % with room above / below the curve for the pulse labels
        lo = min(min(prof.I), 0); hi = max(max(prof.I), 0);
        span = max(hi - lo, 1e-3);
        axI.XLim = [0 max(th(end), 1e-6)];
        axI.YLim = [lo - 0.20*span, hi + 0.20*span];
        updateInfo();
        layoutLabels();
        btnSave.Enable = 'on';
    end

    function setCapacity(ah)
        if isempty(ah) || ~isscalar(ah) || ~isfinite(ah) || ah <= 0, ah = NaN; end
        capAh = ah;
        if isempty(prof), return; end
        makeLabels(); updateInfo(); layoutLabels();
    end

% -------------------------------------------------------------------------
    function makeLabels()
        delete(hLab(isvalid(hLab)));
        hLab = gobjects(numel(pulses),1);
        labStr = cell(numel(pulses),1);
        hold(axI,'on');
        for k = 1:numel(pulses)
            p = pulses(k);
            labStr{k} = pulseText(p, capAh);
            if p.sign > 0
                col = [0.10 0.42 0.18]; va = 'bottom';
            else
                col = [0.62 0.22 0.05]; va = 'top';
            end
            hLab(k) = text(axI, p.tMid/3600, p.sign*p.Ipeak, labStr{k}, ...
                'Color',col, 'FontSize',10, 'FontWeight','bold', 'HorizontalAlignment','center', ...
                'VerticalAlignment',va, 'Interpreter','none', 'Clipping','on', ...
                'BackgroundColor',[1 1 1 0.75], 'Margin',1, 'PickableParts','none');
        end
        hold(axI,'off');
    end

    function layoutLabels()
        % show as many labels as fit without overlapping, biggest pulses first
        if ~isvalid(axI) || strcmp(axI.BeingDeleted,'on') || isempty(pulses) || ...
                numel(hLab) ~= numel(pulses) || numel(labStr) ~= numel(pulses) || ~all(isvalid(hLab))
            return
        end
        XL = axI.XLim; YL = axI.YLim;
        try
            pos = axI.InnerPosition;                % pixels
        catch
            pos = [0 0 800 500];                    % layout not ready yet
        end
        if pos(3) < 10 || pos(4) < 10, pos = [0 0 800 500]; end
        sx = diff(XL)/pos(3); sy = diff(YL)/pos(4); % data units per pixel
        [~, order] = sort([pulses.absAh], 'descend');
        boxes = zeros(0,4);
        for k = order
            p = pulses(k);
            x = p.tMid/3600; y = p.sign*p.Ipeak;
            str = labStr{k};             % (reading the text object here can fail mid-layout)
            if ~iscell(str), return; end % labels are being rebuilt / torn down
            w = (7*max(cellfun(@numel, str)) + 8)*sx;
            h = (15*numel(str) + 4)*sy;
            if p.sign > 0, b = [x-w/2, y, x+w/2, y+h]; else, b = [x-w/2, y-h, x+w/2, y]; end
            show = b(1) >= XL(1) && b(3) <= XL(2);     % whole label inside the view
            if show && ~isempty(boxes)
                show = ~any(b(1) < boxes(:,3) & b(3) > boxes(:,1) & b(2) < boxes(:,4) & b(4) > boxes(:,2));
            end
            if show, boxes(end+1,:) = b; end %#ok<AGROW>
            hLab(k).Visible = onOff(show);
        end
    end

    function updateInfo()
        ahIn  = trapzZoh(prof.tData, max(prof.IData, 0))/3600;
        ahOut = trapzZoh(prof.tData, -min(prof.IData, 0))/3600;
        [Ts, dtMin, dtMax] = sampleTime(prof.tData);
        nC = nnz([pulses.sign] > 0); nD = nnz([pulses.sign] < 0);
        if isfinite(capAh)
            cr = sprintf(['C-rate labels  |I| / AH,\n' ...
                          '               AH = %.4g Ah (Modeling tab)'], capAh);
        else
            cr = sprintf(['C-rate labels  need AH: press Extract on\n' ...
                          '               the Modeling tab (labels show A)']);
        end
        lblInfo.Text = sprintf([ ...
            'File      %s\nDuration  %.2f h\nPoints    %d\n\n' ...
            'Max charge     %+.3f A\nMax discharge  %+.3f A\n' ...
            'Ah charged     %.3f Ah\nAh discharged  %.3f Ah\n' ...
            'Pulses         %d charge, %d discharge\n%s\n\n' ...
            'SAVED BY THE BUTTON\n' ...
            'batt_load      %d x 2  [t (s), I (A)]\n' ...
            'batt_load_ts   timeseries of the same\n' ...
            'batt_stopTime  %.6g s\n' ...
            '               -> model Stop time\n' ...
            'batt_Ts        %.4g s\n' ...
            '               -> To Workspace Sample time\n' ...
            '               (median logging interval;\n' ...
            '                the file ranges %.3g .. %.4g s)'], ...
            d.name, prof.t(end)/3600, numel(prof.t), max(prof.I), min(prof.I), ahIn, ahOut, ...
            nC, nD, cr, numel(prof.t), prof.t(end), Ts, dtMin, dtMax);
    end

    function onSave()
        if isempty(prof), return; end
        Ts = sampleTime(prof.tData);
        assignin('base', 'batt_load', [prof.t, prof.I]);
        assignin('base', 'batt_load_ts', timeseries(prof.I, prof.t, 'Name', 'Cell current, +charge (A)'));
        assignin('base', 'batt_stopTime', prof.t(end));
        assignin('base', 'batt_Ts', Ts);
        uialert(fig, sprintf(['Saved to the base workspace:\n\n' ...
            '  batt_load      %d x 2  [t (s), I (A)]\n' ...
            '  batt_load_ts   timeseries\n' ...
            '  batt_stopTime  %.6g s   (model Stop time)\n' ...
            '  batt_Ts        %.4g s   (sampling interval)\n\nPositive current = charge.'], ...
            numel(prof.t), prof.t(end), Ts), 'Load profile saved', 'Icon','success');
    end
end

% =========================================================================
function prof = buildProfile(d)
% The cycler logs the NEW current on the first sample of a step. A point is
% inserted just before each step carrying the OLD current, so that linear
% interpolation (From Workspace) reproduces the step exactly.
[t, iu] = unique(d.t, 'last');
I = d.I(iu);
t = t - t(1);
thr = max(0.01, 0.02*max(abs(I)));
k = find(abs(diff(I)) > thr) + 1;
dtPos = diff(t);
epsT = min(1e-3, 0.1*min(dtPos(dtPos > 0)));
if isempty(epsT) || ~isfinite(epsT), epsT = 1e-3; end
tb = t(k) - epsT; Ib = I(k-1);
[tt, ord] = sort([t; tb]);
II = [I; Ib];
prof.t = tt;
prof.I = II(ord);
prof.tData = t; prof.IData = I;
end

function P = findPulses(t, I)
% One pulse = a run of samples with the same current sign (rests split them).
% Each logged current holds until the next sample (zero-order hold).
%   Ah     charge moved in this pulse (+ in, - out)
%   Ilev   the current the pulse spends most of its time at (A, magnitude)
%   kind   'CC' (mostly one level), 'CC-CV' (charge that tapers at the end),
%          'variable' (e.g. a drive cycle)
P = struct('i1',{},'i2',{},'sign',{},'t1',{},'t2',{},'tMid',{},'Ah',{},'absAh',{}, ...
    'Ilev',{},'Imean',{},'Ipeak',{},'kind',{});
n = numel(I);
s = sign(I);
brk = [true; s(2:end) ~= s(1:end-1)];
i1s = find(brk); i2s = [i1s(2:end)-1; n];
bw = max(0.01*max(abs(I)), 1e-3);              % 1 % of the largest current
for r = 1:numel(i1s)
    a = i1s(r); b = i2s(r);
    if s(a) == 0, continue; end
    if b < n, dts = t(a+1:b+1) - t(a:b); else, dts = [diff(t(a:b)); 0]; end
    if sum(dts) <= 0, continue; end
    Ia = abs(I(a:b));
    lev = round(Ia/bw);
    [u, ~, id] = unique(lev);
    w = accumarray(id, dts);
    [~, j] = max(w);
    near = abs(lev - u(j)) <= 2;
    frac = sum(dts(near))/sum(dts);
    p.i1 = a; p.i2 = b; p.sign = s(a);
    p.t1 = t(a); p.t2 = t(a) + sum(dts); p.tMid = (p.t1 + p.t2)/2;
    p.Ah = sum(I(a:b).*dts)/3600; p.absAh = abs(p.Ah);
    p.Imean = sum(Ia.*dts)/sum(dts);
    p.Ipeak = max(Ia);
    if p.sign > 0 && numel(Ia) >= 3 && Ia(end) < 0.35*max(Ia)
        hi = Ia >= 0.9*max(Ia);                 % the CC part of a CC-CV charge
        p.Ilev = median(Ia(hi)); p.kind = 'CC-CV';
    elseif frac >= 0.6
        p.Ilev = median(Ia(near)); p.kind = 'CC';
    else
        p.Ilev = p.Imean; p.kind = 'variable';
    end
    P(end+1) = p; %#ok<AGROW>
end
end

function str = pulseText(p, AH)
% two lines: C-rate (or A without a capacity) and the Ah moved
if isfinite(AH)
    switch p.kind
        case 'CC',    l1 = sprintf('%sC', crStr(p.Ilev/AH));
        case 'CC-CV', l1 = sprintf('%sC CC-CV', crStr(p.Ilev/AH));
        otherwise,    l1 = sprintf('avg %sC, max %sC', crStr(p.Imean/AH), crStr(p.Ipeak/AH));
    end
else
    switch p.kind
        case 'CC',    l1 = sprintf('%.3g A', p.Ilev);
        case 'CC-CV', l1 = sprintf('%.3g A CC-CV', p.Ilev);
        otherwise,    l1 = sprintf('avg %.3g A', p.Imean);
    end
end
str = {l1, sprintf('%+.3g Ah', p.Ah)};
end

function s = crStr(r)
if r >= 10, s = sprintf('%.0f', r); else, s = sprintf('%.2g', r); end
end

function [Ts, dtMin, dtMax] = sampleTime(t)
% the test's logging interval: median spacing of the (unique) time stamps
dt = diff(t); dt = dt(dt > 0);
if isempty(dt), Ts = NaN; dtMin = NaN; dtMax = NaN; return; end
Ts = median(dt); dtMin = min(dt); dtMax = max(dt);
end

function q = trapzZoh(t, x)
q = sum(x(1:end-1).*diff(t));
end

function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function styleAxes(a)
a.FontName = 'Segoe UI'; a.FontSize = 11; a.Box = 'on';
grid(a,'on'); a.GridAlpha = 0.12;
a.Title.FontWeight = 'bold';
end
