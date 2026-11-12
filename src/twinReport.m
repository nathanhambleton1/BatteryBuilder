function [tbl, files] = twinReport(res, outDir, show)
%TWINREPORT  Twin vs measured: key-point table and the comparison graphs.
%
%   [tbl, files] = twinReport(res)               table only
%   [tbl, files] = twinReport(res, outDir)       + PNGs in outDir
%   [tbl, files] = twinReport(res, outDir, true) + leave the figures open
%
%   res  from runDigitalTwin: t, I, V (measured), Vtwin, Vtb, T, Ttwin, Ttb,
%        phases, AH, name
%
%   tbl  one row per charge / discharge / rest of the test. For each: the
%        measured voltage at its START, END, MIN and MAX, and the twin's error
%        at those same points (twin - measured, mV), plus the rms error over
%        the whole phase. The Table-Based baseline gets the same rms column.
%        These are the numbers that say "starts, ends, dips and recovers like
%        the cell".
%
%   Graphs (what each is good for):
%     _twin_overview.png    the whole test: current, voltage, twin error, temperature
%     _twin_discharges.png  every discharge + the first hour of rest after it:
%                           the dip, the curve, the knee to cut-off, the recovery
%     _twin_steps.png       the first 2 minutes of every discharge on a log time
%                           axis: R0 (the instant drop) and the RC pairs (the curve after)
%     _twin_charges.png     every CC-CV charge + its rest: the top of charge

if nargin < 2, outDir = ''; end
if nargin < 3, show = false; end
t = res.t; I = res.I; V = res.V; ph = res.phases;
C.meas = [0.04 0.04 0.04]; C.twin = [0.165 0.471 0.839]; C.tb = [0.922 0.408 0.204];
C.grid = [0.86 0.86 0.84];

% ------------------------------------------------------------------ table
n = size(ph,1);
kind = strings(n,1); rate = nan(n,1);
z = nan(n,1);
S = struct('Vstart',z,'Vend',z,'Vmin',z,'Vmax',z,'eStart',z,'eEnd',z,'eMin',z,'eMax',z, ...
    'rms',z,'rmsTB',z,'Tmax',z,'TmaxTwin',z,'dur_h',z);
for p = 1:n
    k = ph(p,1):ph(p,2);
    Im = median(I(k));
    if abs(Im) < 1e-3, kind(p) = "Rest";
    elseif Im > 0,     kind(p) = "Charge";
    else,              kind(p) = "Discharge"; end
    if kind(p) ~= "Rest", rate(p) = abs(Im)/res.AH; end
    [S.Vmin(p), ia] = min(V(k)); [S.Vmax(p), ib] = max(V(k));
    S.Vstart(p) = V(k(1)); S.Vend(p) = V(k(end));
    e = 1000*(res.Vtwin(k) - V(k));
    S.eStart(p) = e(1); S.eEnd(p) = e(end);
    S.eMin(p) = 1000*(min(res.Vtwin(k)) - S.Vmin(p));      % lowest vs lowest
    S.eMax(p) = 1000*(max(res.Vtwin(k)) - S.Vmax(p));      % highest vs highest
    S.rms(p) = rms(e);
    if ~isempty(res.Vtb), S.rmsTB(p) = 1000*rms(res.Vtb(k) - V(k)); end
    S.Tmax(p) = max(res.T(k)); S.TmaxTwin(p) = max(res.Ttwin(k));
    S.dur_h(p) = (t(k(end)) - t(k(1)))/3600;
    %#ok<*NASGU>
end
label = kind;
for p = 1:n
    if isfinite(rate(p)), label(p) = sprintf('%s %.2gC', kind(p), rate(p)); end
end
tbl = table((1:n)', label, round(S.dur_h,2), round(S.Vstart,4), round(S.Vend,4), round(S.Vmin,4), round(S.Vmax,4), ...
    round(S.eStart,1), round(S.eEnd,1), round(S.eMin,1), round(S.eMax,1), round(S.rms,1), round(S.rmsTB,0), ...
    round(S.Tmax,1), round(S.TmaxTwin,1), ...
    'VariableNames', {'n','Phase','Hours','Vstart','Vend','Vmin','Vmax', ...
    'err_start_mV','err_end_mV','err_min_mV','err_max_mV','rms_twin_mV','rms_TableBased_mV', ...
    'Tmax_meas_C','Tmax_twin_C'});

files = {};
if isempty(outDir) && ~show, return; end
if ~isempty(outDir) && ~isfolder(outDir), mkdir(outDir); end
[~, base] = fileparts(res.name);
vis = 'off'; if show, vis = 'on'; end
th = t/3600;

% ------------------------------------------------------------------ 1. overview
f = figure('Color','w','Visible',vis,'Position',[50 50 1400 900]);
tl = tiledlayout(f, 4, 1, 'TileSpacing','compact','Padding','compact');
title(tl, sprintf('Digital twin vs test  -  %s', res.name), 'FontWeight','bold','Interpreter','none');
a1 = nexttile(tl); plot(a1, th, I, 'Color', C.meas, 'LineWidth', 1); ylabel(a1,'Current (A)'); style(a1);
title(a1, 'Measured current (+ = charge) - the input to both models','FontWeight','normal');
a2 = nexttile(tl); hold(a2,'on');
if ~isempty(res.Vtb), plot(a2, th, res.Vtb, 'Color', C.tb, 'LineWidth', 1, 'DisplayName','Modeling tab, Battery (Table-Based)'); end
plot(a2, th, V, 'Color', C.meas, 'LineWidth', 1.6, 'DisplayName','Measured');
plot(a2, th, res.Vtwin, '--', 'Color', C.twin, 'LineWidth', 1.4, 'DisplayName','Digital twin (Simulink)');
ylim(a2, [max(0, min(V) - 0.3), max(V) + 0.1]); ylabel(a2,'Voltage (V)'); style(a2);
legend(a2,'Location','southwest','Box','off');
a3 = nexttile(tl);
plot(a3, th, 1000*(res.Vtwin - V), 'Color', C.twin, 'LineWidth', 1);
yline(a3, 0, 'Color', [0.5 0.5 0.5]);
ylabel(a3,'Twin - measured (mV)'); style(a3);
title(a3, sprintf('Twin error: %.1f mV rms over the whole test', 1000*rms(res.Vtwin - V)),'FontWeight','normal');
a4 = nexttile(tl); hold(a4,'on');
if ~isempty(res.Ttb), plot(a4, th, res.Ttb, 'Color', C.tb, 'LineWidth', 1, 'DisplayName','Table-Based'); end
plot(a4, th, res.T, 'Color', C.meas, 'LineWidth', 1.6, 'DisplayName','Measured (Temp 1)');
plot(a4, th, res.Ttwin, '--', 'Color', C.twin, 'LineWidth', 1.4, 'DisplayName','Digital twin');
if isfield(res,'Tch'), plot(a4, th, res.Tch, ':', 'Color', [0.55 0.55 0.55], 'LineWidth', 1, 'DisplayName','Chamber'); end
ylim(a4, [min(res.T) - 5, max(res.T) + 10]);   % the baseline can run far off: clip it, the table has its peak
ylabel(a4,'Cell temperature (°C)'); xlabel(a4,'Test time (h)'); style(a4);
legend(a4,'Location','northwest','Box','off');
linkaxes([a1 a2 a3 a4],'x'); xlim(a1, [0 th(end)]);
files{end+1} = save1(f, outDir, [base '_twin_overview.png']);

% ------------------------------------------------------------------ 2. discharges
dis = find(kind == "Discharge");
if ~isempty(dis)
    f = figure('Color','w','Visible',vis,'Position',[50 50 1500 520]);
    tl = tiledlayout(f, 1, numel(dis), 'TileSpacing','compact','Padding','compact');
    title(tl, 'Every discharge + the first hour of rest after it (time from the start of the discharge)','FontWeight','bold');
    for j = 1:numel(dis)
        p = dis(j); k1 = ph(p,1);
        k2 = ph(p,2); if p < n, k2 = find(t <= t(ph(p,2)) + 3600, 1, 'last'); end
        k = k1:k2; tm = (t(k) - t(k1))/60;
        a = nexttile(tl); hold(a,'on');
        if ~isempty(res.Vtb), plot(a, tm, res.Vtb(k), 'Color', C.tb, 'LineWidth', 1); end
        plot(a, tm, V(k), 'Color', C.meas, 'LineWidth', 1.6);
        plot(a, tm, res.Vtwin(k), '--', 'Color', C.twin, 'LineWidth', 1.4);
        ylim(a, [2.3 4.3]); style(a); xlabel(a,'min');
        if j == 1, ylabel(a,'Voltage (V)'); end
        title(a, sprintf('%s  (%.1f A)\nend %+.1f mV, min %+.1f mV', label(p), abs(median(I(ph(p,1):ph(p,2)))), ...
            S.eEnd(p), S.eMin(p)), 'FontWeight','normal','FontSize',9);
    end
    lg = legend(a, legNames(res), 'Orientation','horizontal','Box','off'); lg.Layout.Tile = 'south';
    files{end+1} = save1(f, outDir, [base '_twin_discharges.png']);

    % -------------------------------------------------------------- 3. steps (RC reaction)
    f = figure('Color','w','Visible',vis,'Position',[50 50 1500 480]);
    tl = tiledlayout(f, 1, numel(dis), 'TileSpacing','compact','Padding','compact');
    title(tl, 'First 2 minutes of every discharge (log time): the instant drop is R0, the curve after it is the RC pairs','FontWeight','bold');
    for j = 1:numel(dis)
        p = dis(j); k1 = ph(p,1);
        k = k1:min(ph(p,2), find(t <= t(k1) + 120, 1, 'last'));
        k = [k1-1, k]; %#ok<AGROW>   last rest sample (plotted at 0.01 s)
        ts = max(t(k) - t(k1), 0) + 0.02; ts(1) = 0.01;
        a = nexttile(tl); hold(a,'on');
        plot(a, ts, V(k), 'o-', 'Color', C.meas, 'LineWidth', 1.4, 'MarkerSize', 3);
        plot(a, ts, res.Vtwin(k), '--', 'Color', C.twin, 'LineWidth', 1.4);
        set(a, 'XScale', 'log'); style(a); xlabel(a,'s after the switch');
        if j == 1, ylabel(a,'Voltage (V)'); end
        e = 1000*(res.Vtwin(k(2:end)) - V(k(2:end)));
        title(a, sprintf('%s\nfirst sample %+.0f mV, rms %.1f mV', label(p), e(1), rms(e)), 'FontWeight','normal','FontSize',9);
    end
    lg = legend(a, {'Measured','Digital twin'}, 'Orientation','horizontal','Box','off'); lg.Layout.Tile = 'south';
    files{end+1} = save1(f, outDir, [base '_twin_steps.png']);
end

% ------------------------------------------------------------------ 4. charges
chg = find(kind == "Charge");
if ~isempty(chg)
    f = figure('Color','w','Visible',vis,'Position',[50 50 1500 480]);
    tl = tiledlayout(f, 1, numel(chg), 'TileSpacing','compact','Padding','compact');
    title(tl, 'Every CC-CV charge + the rest after it: the climb to the CV voltage and the settle back','FontWeight','bold');
    for j = 1:numel(chg)
        p = chg(j); k1 = ph(p,1);
        k2 = ph(p,2); if p < n, k2 = ph(p+1,2); end
        k = k1:k2; th2 = (t(k) - t(k1))/3600;
        a = nexttile(tl); hold(a,'on');
        if ~isempty(res.Vtb), plot(a, th2, res.Vtb(k), 'Color', C.tb, 'LineWidth', 1); end
        plot(a, th2, V(k), 'Color', C.meas, 'LineWidth', 1.6);
        plot(a, th2, res.Vtwin(k), '--', 'Color', C.twin, 'LineWidth', 1.4);
        style(a); xlabel(a,'h'); ylim(a, [2.9 4.3]);
        if j == 1, ylabel(a,'Voltage (V)'); end
        title(a, sprintf('Charge %d (%s)\nmax %+.1f mV, rest end %+.1f mV', j, label(p), S.eMax(p), S.eEnd(min(p+1,n))), ...
            'FontWeight','normal','FontSize',9);
    end
    lg = legend(a, legNames(res), 'Orientation','horizontal','Box','off'); lg.Layout.Tile = 'south';
    files{end+1} = save1(f, outDir, [base '_twin_charges.png']);
end
files = files(~cellfun(@isempty, files));
end

function c = legNames(res)
c = {'Measured','Digital twin'};
if ~isempty(res.Vtb), c = {'Modeling tab (Table-Based)','Measured','Digital twin'}; end
end

function style(a)
set(a, 'FontSize', 9, 'TickDir', 'out', 'Box', 'off', 'XColor', [0.32 0.32 0.31], 'YColor', [0.32 0.32 0.31], ...
    'GridColor', [0.86 0.86 0.84], 'GridAlpha', 1, 'YGrid', 'on', 'XGrid', 'off', 'LineWidth', 0.75);
end

function fn = save1(f, outDir, name)
fn = '';
if isempty(outDir), return; end
fn = fullfile(outDir, name);
exportgraphics(f, fn, 'Resolution', 150);
if strcmp(f.Visible, 'off'), close(f); end
end
