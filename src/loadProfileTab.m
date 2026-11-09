function api = loadProfileTab(tab, fig)
%LOADPROFILETAB  "Load profile" tab: the test's current profile for Simulink.
%
%   api = loadProfileTab(tab, fig)
%   api.setData(d)    show the current of dataset d
%   api.save()        same as pressing "Save to workspace"
%
%   Sign convention: POSITIVE = CHARGE (current into the cell),
%                    NEGATIVE = DISCHARGE.
%
%   Saved to the base workspace
%     batt_load        [t I]  two columns: time (s) from 0, current (A)
%     batt_load_ts     the same data as a timeseries object
%     batt_load_tEnd   last time (s) -> use as the model Stop time
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

g = uigridlayout(tab,[1 2],'ColumnWidth',{330,'1x'},'Padding',[6 6 6 6]);
gL = uigridlayout(g,[3 1],'RowHeight',{36,'fit','1x'},'Padding',[0 0 0 0]);
gL.Layout.Column = 1;
btnSave = uibutton(gL,'Text','Save load profile to workspace','FontWeight','bold','FontSize',13, ...
    'BackgroundColor',[0.20 0.45 0.80],'FontColor','white','Enable','off', ...
    'ButtonPushedFcn',@(~,~) onSave(), ...
    'Tooltip',sprintf(['Writes batt_load = [t I] (positive = charge),\n' ...
                       'batt_load_ts (timeseries) and batt_load_tEnd to the base workspace.']));
lblInfo = uilabel(gL,'Text','Open a CSV file first.','WordWrap','on','VerticalAlignment','top', ...
    'FontName','Consolas','FontSize',12);
txtHelp = uitextarea(gL,'Editable','off','FontSize',12,'Value',{
    'HOW TO USE IT IN SIMULINK'
    ''
    '1. From Workspace block'
    '     Data: batt_load'
    '     Interpolate data: on'
    '     Form output after final data value: Holding final value'
    '2. Simulink-PS Converter, output unit A'
    '3. Controlled Current Source (Simscape > Foundation >'
    '   Electrical > Electrical Sources)'
    '     source + (arrow head)  ->  battery +'
    '     source -               ->  battery -'
    '   A positive signal then pushes current INTO the'
    '   battery (charging), negative = discharging.'
    '4. Model Stop time: batt_load_tEnd'
    ''
    'Extra points are added just before every current step so'
    'that the interpolated signal reproduces the steps exactly'
    '(no ramps between a rest and a pulse).'});

axI = uiaxes(g);
axI.Layout.Column = 2;
styleAxes(axI);
title(axI,'Current profile (positive = charge)');
xlabel(axI,'Test time (h)'); ylabel(axI,'Current (A)');

api.setData = @setData;
api.save = @onSave;
api.getProfile = @getProfile;

    function p = getProfile()    % nested (not anonymous) so it sees the live value
        p = prof;
    end

    function setData(newD)
        d = newD;
        prof = buildProfile(d);
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
        legend(axI,'Location','best');
        title(axI, sprintf('Current profile of %s (positive = charge)', d.name), 'Interpreter','none');
        % explicit limits (uiaxes may not have updated its automatic limits yet)
        lo = min(min(prof.I), 0); hi = max(max(prof.I), 0);
        pad = 0.06*max(hi - lo, 1e-3);
        axI.XLim = [0 max(th(end), 1e-6)];
        axI.YLim = [lo - pad, hi + pad];
        ahIn  = trapzZoh(prof.tData, max(prof.IData, 0))/3600;
        ahOut = trapzZoh(prof.tData, -min(prof.IData, 0))/3600;
        lblInfo.Text = sprintf(['File      %s\nDuration  %.2f h (%.0f s)\nPoints    %d\n' ...
            'Max charge     %+.3f A\nMax discharge  %+.3f A\n' ...
            'Ah charged     %.3f Ah\nAh discharged  %.3f Ah'], ...
            d.name, prof.t(end)/3600, prof.t(end), numel(prof.t), max(prof.I), min(prof.I), ahIn, ahOut);
        btnSave.Enable = 'on';
    end

    function onSave()
        if isempty(prof), return; end
        assignin('base', 'batt_load', [prof.t, prof.I]);
        assignin('base', 'batt_load_ts', timeseries(prof.I, prof.t, 'Name', 'Cell current, +charge (A)'));
        assignin('base', 'batt_load_tEnd', prof.t(end));
        uialert(fig, sprintf(['Saved to the base workspace:\n\n' ...
            '  batt_load       %d x 2  [t (s), I (A)]\n' ...
            '  batt_load_ts    timeseries\n' ...
            '  batt_load_tEnd  %.6g s\n\nPositive current = charge.'], numel(prof.t), prof.t(end)), ...
            'Load profile saved', 'Icon','success');
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

function q = trapzZoh(t, x)
q = sum(x(1:end-1).*diff(t));
end

function styleAxes(a)
a.FontName = 'Segoe UI'; a.FontSize = 11; a.Box = 'on';
grid(a,'on'); a.GridAlpha = 0.12;
a.Title.FontWeight = 'bold';
end
