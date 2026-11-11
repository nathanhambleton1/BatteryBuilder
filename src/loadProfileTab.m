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
%     batt_ambient     [t T]  chamber temperature (K) on the same time base
%     batt_ambient_ts  the same as a timeseries
%                      (only when the file has a chamber temperature column)
%
%   In Simulink:
%     From Workspace (Data = batt_load, Interpolate data = on,
%                     Form output after final data value = Holding final value)
%       -> Simulink-PS Converter (unit A)
%       -> Controlled Current Source (Simscape > Foundation > Electrical > Sources)
%     Wire the source "+" (arrow head) to battery "+" and "-" to battery "-":
%     a positive signal then pushes current INTO the battery = charging.
%
%   Thermal port (block "Thermal model" = Lumped thermal mass):
%     From Workspace (batt_ambient) -> Simulink-PS Converter (unit K)
%       -> Controlled Temperature Source (Foundation > Thermal > Sources;
%          port A to a Thermal Reference)
%       -> Convective Heat Transfer (Area 1 m^2, coefficient batt_hA)
%       -> battery port H

d = [];
prof = [];
capAh = NaN;
pulses = [];          % struct array, one per charge / discharge pulse
hLab = gobjects(0);   % one text label per pulse
labStr = {};          % ... and its text

g = uigridlayout(tab,[1 2],'ColumnWidth',{350,'1x'},'Padding',[6 6 6 6]);
gL = uigridlayout(g,[4 1],'RowHeight',{36,36,'fit','1x'},'Padding',[0 0 0 0]);
gL.Layout.Column = 1;
btnSave = uibutton(gL,'Text','Save load profile to workspace','FontWeight','bold','FontSize',13, ...
    'BackgroundColor',[0.20 0.45 0.80],'FontColor','white','Enable','off', ...
    'ButtonPushedFcn',@(~,~) onSave(), ...
    'Tooltip',sprintf(['Writes batt_load = [t I] (positive = charge), batt_load_ts (timeseries),\n' ...
                       'batt_stopTime (model Stop time), batt_Ts (sampling interval) and\n' ...
                       'batt_ambient / batt_ambient_ts (chamber temperature, K, for the thermal port)\n' ...
                       'to the base workspace.']));
btnCrate = uibutton(gL,'Text','Plot discharge C-rate curves','FontWeight','bold','FontSize',13, ...
    'Enable','off','ButtonPushedFcn',@(~,~) onCratePlot(), ...
    'Tooltip',sprintf(['Opens a figure: voltage vs discharged capacity (Ah), one colour per discharge\n' ...
                       'C-rate (legend: C-rate and Amps), with the cell temperature of each\n' ...
                       'discharge as a dotted line of the same colour on the right axis.']));
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
        btnCrate.Enable = 'on';
    end

    function setCapacity(ah)
        if isempty(ah) || ~isscalar(ah) || ~isfinite(ah) || ah <= 0, ah = NaN; end
        capAh = ah;
        if isempty(prof), return; end
        makeLabels(); updateInfo(); layoutLabels();
    end


    function onCratePlot()
        if isempty(prof), return; end
        D = dischargeCurves();
        if isempty(D)
            uialert(fig, ['No constant-current discharge long enough to plot was found in this test ' ...
                '(needs at least 5 minutes at one current).'], 'C-rate curves');
            return
        end
        col = seriesColors(numel(D));
        f2 = figure('Name','Discharge C-rate curves','Color','w');
        a2 = axes(f2); %#ok<LAXES>
        fn = 'Century Gothic';
        a2.FontName = fn; a2.FontSize = 16;
        hasT = any(arrayfun(@(q) any(isfinite(q.T)), D));
        yyaxis(a2,'left'); hold(a2,'on');
        hS = gobjects(numel(D),1); lab = cell(numel(D),1);
        for k = 1:numel(D)
            hS(k) = plot(a2, D(k).Ah, D(k).V, '-', 'Color', col(k,:), 'LineWidth', 1.6);
            if isfinite(capAh)
                lab{k} = sprintf('%sC  (%.3g A)', crStr(D(k).I/capAh), D(k).I);
            else
                lab{k} = sprintf('%.3g A', D(k).I);
            end
        end
        ylabel(a2, 'Voltage (V)', 'FontName', fn);
        a2.YAxis(1).Color = [0.15 0.15 0.15];
        if hasT
            yyaxis(a2,'right'); hold(a2,'on');
            for k = 1:numel(D)
                plot(a2, D(k).Ah, D(k).T, ':', 'Color', col(k,:), 'LineWidth', 1.8, 'HandleVisibility','off');
            end
            ylabel(a2, ['Cell temperature (' char(176) 'C)'], 'FontName', fn);
            a2.YAxis(2).Color = [0.15 0.15 0.15];
            yyaxis(a2,'left');
        end
        xlabel(a2, 'Discharged capacity (Ah)', 'FontName', fn);
        if isfinite(d.T_C), tt = sprintf('%.3g %cC', d.T_C, char(176)); else, tt = 'temperature unknown'; end
        title(a2, sprintf('Discharge curves at %s', tt), 'FontName', fn, 'Interpreter','none');
        lg = legend(a2, hS, lab, 'Interpreter','none', 'Location','southwest', 'FontName', fn);
        lg.Title.String = sprintf('Test temperature: %s', tt);
        grid(a2,'on');
        if ~hasT
            text(a2, 0.98, 0.98, 'no cell temperature column in the file', 'Units','normalized', ...
                'HorizontalAlignment','right', 'VerticalAlignment','top', 'FontName', fn, 'FontSize', 11);
        end
    end

    function D = dischargeCurves()
        % one curve per discharge C-rate: the biggest constant-current discharge
        % at that rate (>= 5 min), as voltage / cell temperature vs Ah drawn out
        D = struct('I',{},'Ah',{},'V',{},'T',{});
        if isempty(pulses), return; end
        t = prof.tData; I = prof.IData; V = d.V(prof.iu); Tc = d.Tcell(prof.iu);
        cand = struct('I',{},'q',{},'v',{},'T',{},'tot',{});
        for k = 1:numel(pulses)
            p = pulses(k);
            if p.sign >= 0 || ~strcmp(p.kind,'CC') || (p.t2 - p.t1) < 300, continue; end
            idx = p.i1:p.i2;
            if numel(idx) < 3, continue; end
            q = [0; cumsum(abs(I(idx(1:end-1))).*diff(t(idx)))]/3600;
            cand(end+1) = struct('I',p.Ilev,'q',q,'v',V(idx),'T',Tc(idx),'tot',q(end)); %#ok<AGROW>
        end
        if isempty(cand), return; end
        if isfinite(capAh), unit = 0.02*capAh; else, unit = 0.02*max([cand.I]); end
        lev = round([cand.I]/unit);
        [u, ~, id] = unique(lev);
        for r = 1:numel(u)
            m = find(id == r);
            [~, j] = max([cand(m).tot]);
            c = cand(m(j));
            D(end+1) = struct('I',c.I,'Ah',c.q,'V',c.v,'T',c.T); %#ok<AGROW>
        end
        [~, ord] = sort([D.I]); D = D(ord);
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
                          '               AH = %.4g Ah (from the test,\n' ...
                          '               or typed on the Modeling tab)'], capAh);
        else
            cr = sprintf(['C-rate labels  no full discharge found to\n' ...
                          '               get AH: type AH on the Modeling\n' ...
                          '               tab (labels show A)']);
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
            '                the file ranges %.3g .. %.4g s)\n%s'], ...
            d.name, prof.t(end)/3600, numel(prof.t), max(prof.I), min(prof.I), ahIn, ahOut, ...
            nC, nD, cr, numel(prof.t), prof.t(end), Ts, dtMin, dtMax, ambientInfo());
    end

    function s = ambientInfo()
        if isempty(prof.Tamb)
            s = sprintf(['batt_ambient   NOT saved: %s\n' ...
                         '               (type the chamber temperature\n' ...
                         '                into a Constant block instead)'], prof.TambWhy);
        else
            s = sprintf(['batt_ambient   %d x 2  [t (s), T (K)]\n' ...
                         '               chamber %.1f .. %.1f °C\n' ...
                         '               -> Controlled Temperature Source\n' ...
                         'batt_ambient_ts timeseries of the same'], ...
                numel(prof.t), min(prof.Tamb) - 273.15, max(prof.Tamb) - 273.15);
        end
    end

    function onSave()
        if isempty(prof), return; end
        Ts = sampleTime(prof.tData);
        assignin('base', 'batt_load', [prof.t, prof.I]);
        assignin('base', 'batt_load_ts', timeseries(prof.I, prof.t, 'Name', 'Cell current, +charge (A)'));
        assignin('base', 'batt_stopTime', prof.t(end));
        assignin('base', 'batt_Ts', Ts);
        if isempty(prof.Tamb)
            amb = sprintf('  batt_ambient   NOT saved: %s', prof.TambWhy);
        else
            assignin('base', 'batt_ambient', [prof.t, prof.Tamb]);
            assignin('base', 'batt_ambient_ts', timeseries(prof.Tamb, prof.t, 'Name', 'Chamber temperature (K)'));
            amb = sprintf(['  batt_ambient   %d x 2  [t (s), T (K)]  (thermal port)\n' ...
                           '  batt_ambient_ts timeseries'], numel(prof.t));
        end
        uialert(fig, sprintf(['Saved to the base workspace:\n\n' ...
            '  batt_load      %d x 2  [t (s), I (A)]\n' ...
            '  batt_load_ts   timeseries\n' ...
            '  batt_stopTime  %.6g s   (model Stop time)\n' ...
            '  batt_Ts        %.4g s   (sampling interval)\n%s\n\nPositive current = charge.'], ...
            numel(prof.t), prof.t(end), Ts, amb), 'Load profile saved', 'Icon','success');
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
prof.tData = t; prof.IData = I; prof.iu = iu;
% chamber temperature = the ambient for the thermal port, in K on the same
% time points (missing readings are bridged linearly between their neighbours)
prof.Tamb = []; prof.TambWhy = '';
Tc = d.Tch(iu);
if nnz(isfinite(Tc)) < 2
    prof.TambWhy = 'no chamber temperature column in the file';
else
    ok = isfinite(Tc);
    Tc = interp1(t(ok), Tc(ok), t, 'linear');
    if any(~isfinite(Tc)), Tc = fillmissing(Tc, 'nearest'); end   % before the first / after the last reading
    TT = [Tc; interp1(t, Tc, tb, 'linear')];
    prof.Tamb = TT(ord) + 273.15;
end
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

function c = seriesColors(n)
% distinct, readable line colours (cycles if there are more curves than colours)
base = [0.00 0.447 0.741; 0.850 0.325 0.098; 0.929 0.694 0.125; 0.494 0.184 0.556; ...
        0.466 0.674 0.188; 0.301 0.745 0.933; 0.635 0.078 0.184; 0.10 0.10 0.10];
c = base(mod((0:n-1), size(base,1)) + 1, :);
end
