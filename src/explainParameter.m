function f = explainParameter(key, R, row)
%EXPLAINPARAMETER  Pop-up window: how one parameter was calculated.
%
%   explainParameter(key, R, row)
%     key  parameter key (e.g. 'R0_vec')
%     R    result of extractCellParameters
%     row  the matching entry of blockParameterList (for names / units)
%
%   Shows the method, the equation and the numbers on the left and one or two
%   plots of the data that produced the value on the right.

d = R.d;
f = uifigure('Name', ['How was ' row.label ' calculated?'], 'Color','w');
f.Position(3:4) = [1150 640];
movegui(f,'center');
g = uigridlayout(f,[2 2],'ColumnWidth',{380,'1x'},'RowHeight',{'1x','1x'},'Padding',[8 8 8 8]);
txt = uitextarea(g,'Editable','off','FontSize',12,'WordWrap','on');
txt.Layout.Row = [1 2]; txt.Layout.Column = 1;
ax1 = uiaxes(g); ax1.Layout.Row = 1; ax1.Layout.Column = 2; styleAxes(ax1);
ax2 = uiaxes(g); ax2.Layout.Row = 2; ax2.Layout.Column = 2; styleAxes(ax2);

th = d.t/3600;
head = {upper(row.label); ...
        sprintf('Workspace variable: %s', row.var); ...
        sprintf('Goes in: %s', row.where); ''};
val = R.value.(key);
L = {};
one = false;          % true -> only the top axes is used

switch key
    % ------------------------------------------------------------------
    case 'SOC_vec'
        L = {'These are the state-of-charge points every table is given at.'
             'They are a choice, not a measurement. Points close together near'
             '0 and 1 follow the steep ends of the OCV curve better.'
             ''
             sprintf('Value: %s', vecStr(val))
             ''
             'Plot: the coulomb-counted SOC of the test with the breakpoints.'};
        if ~isempty(d.soc)
            plot(ax1, th, d.soc, 'LineWidth',1.2); hold(ax1,'on');
            yline(ax1, val, ':', 'Color',[0.5 0.5 0.5]); hold(ax1,'off');
            xlabel(ax1,'Test time (h)'); ylabel(ax1,'SOC (-)'); title(ax1,'SOC and the breakpoints');
        end
        one = true;

    % ------------------------------------------------------------------
    case 'AH'
        c = R.diag.capacity;
        ah = d.tbl.('Net Ah in (Ah)');
        L = {'METHOD'
             'Capacity = charge taken out between a FULL point and the'
             'next EMPTY point:'
             ''
             '   AH = Ah_in(full) - Ah_in(empty)'
             '   Ah_in(t) = sum of I*dt / 3600   (I positive = charge)'
             ''
             sprintf('FULL  = end of a CC-CV charge (current tapered at a flat %.3f V).', c.VmaxCV)
             sprintf('EMPTY = end of a discharge that stopped at the test''s lowest voltage (%.3f V).', c.Vmin)
             'If there are several full->empty discharges the slowest one is used'
             '(lowest current = closest to the true capacity).'
             ''
             'RESULT'
             sprintf('   AH = %.4f Ah  (discharge at %.3g A)', val, c.rateA)
             sprintf('   full points found: %d, empty points found: %d', numel(c.fullIdx), numel(c.emptyIdx))
             ''
             'Note: the capacity is defined by the cut-off voltage the test used.'
             'A datasheet rating at a lower cut-off or rate will be larger.'};
        plot(ax1, th, d.V, 'Color',[0.3 0.3 0.3]); hold(ax1,'on');
        plot(ax1, th(c.fullIdx), d.V(c.fullIdx), '^', 'MarkerFaceColor',[0.2 0.6 0.3], ...
            'MarkerEdgeColor','none','MarkerSize',9);
        plot(ax1, th(c.emptyIdx), d.V(c.emptyIdx), 'v', 'MarkerFaceColor',[0.85 0.2 0.1], ...
            'MarkerEdgeColor','none','MarkerSize',9);
        hold(ax1,'off');
        legend(ax1, {'voltage','full','empty'}, 'Location','best');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Voltage (V)'); title(ax1,'Full and empty points');
        plot(ax2, th, ah, 'LineWidth',1.2); hold(ax2,'on');
        if ~isempty(c.a)
            plot(ax2, th([c.a c.b]), ah([c.a c.b]), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerSize',8);
            plot(ax2, th([c.a c.a]), ah([c.a c.b]), '-', 'Color',[0.85 0.33 0.1], 'LineWidth',2);
            text(ax2, th(c.a), mean(ah([c.a c.b])), sprintf('  AH = %.4f Ah', val), 'FontWeight','bold');
        end
        hold(ax2,'off');
        xlabel(ax2,'Test time (h)'); ylabel(ax2,'Net Ah into the cell'); title(ax2,'Coulomb count');

    % ------------------------------------------------------------------
    case 'V_range'
        L = {'The lowest and highest terminal voltage seen in the whole test.'
             'The block uses this range only to warn when the simulated voltage'
             'leaves it, so it is set to what the real cell actually did.'
             ''
             sprintf('   Min = %.4f V', val(1))
             sprintf('   Max = %.4f V', val(2))
             ''
             'Replace it with the datasheet limits if you prefer the official'
             'operating window.'};
        plot(ax1, th, d.V); hold(ax1,'on');
        yline(ax1, val(1), '--r', sprintf('min %.3f V', val(1)));
        yline(ax1, val(2), '--r', sprintf('max %.3f V', val(2)));
        hold(ax1,'off');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Voltage (V)'); title(ax1,'Measured voltage');
        one = true;

    % ------------------------------------------------------------------
    case 'V0_vec'
        p = R.diag.points;
        L = {'METHOD'
             '1. Every long rest after a current pulse is fitted with'
             '      V(t) = Vinf + sum_k R_k * x_k * exp(-t/tau_k)'
             '   Vinf (the voltage it would settle to) is an OCV point.'
             '2. Low-rate CC charge / discharge gives a dense curve:'
             '      OCV ~ V - I*R0(SOC) - sum_k R_k(SOC)*x_k   (I + = charge)'
             '   Charge and discharge are averaged (removes hysteresis).'
             '3. The dense curve gives the SHAPE between rests; the rest'
             '   points set its LEVEL. Where the dense curve does not reach,'
             '   the rest points are interpolated.'
             ''
             sprintf('Rest points: %d   dense points: %d', size(p.ocv,1), size(p.ocvDense,1))
             ''
             'TABLE  (M = measured near this SOC, I = interpolated,'
             '        E = short extension past the data)'};
        L = [L; tableLines(R.value.SOC_vec, val, R.diag.prov.V0_vec, '%.4f V')];
        hold(ax1,'on');
        if ~isempty(p.ocvDense)
            plot(ax1, p.ocvDense(:,1), p.ocvDense(:,2), '.', 'Color',[0.6 0.6 0.6], 'DisplayName','corrected low-rate curve');
        end
        if ~isempty(p.ocv)
            plot(ax1, p.ocv(:,1), p.ocv(:,2), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], ...
                'MarkerEdgeColor','none','DisplayName','relaxed rest voltage (Vinf)');
        end
        plot(ax1, R.value.SOC_vec, val, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6, 'DisplayName','V0 table');
        hold(ax1,'off'); legend(ax1,'Location','southeast');
        xlabel(ax1,'SOC (-)'); ylabel(ax1,'OCV (V)'); title(ax1,'Open-circuit voltage');
        plotExampleRelaxation(ax2, R, 1, true);

    % ------------------------------------------------------------------
    case 'R0_vec'
        p = R.diag.points.R0;
        L = {'METHOD'
             'At every sharp current step the voltage jumps instantly by'
             'the resistive drop before any RC branch can react:'
             ''
             '      R0 = dV / dI   (across one sample at the step)'
             ''
             sprintf('Steps used: %d (sampled at <= %g s so the jump is not', size(p,1), R.constants.maxEdgeDt)
             'smeared by the RC relaxation).'
             'Each SOC breakpoint takes the median of the steps closest to it.'
             ''
             'TABLE  (M = median of measured steps, I = interpolated,'
             '        E = end value held)'};
        L = [L; tableLines(R.value.SOC_vec, val*1000, R.diag.prov.R0_vec, '%.3f mOhm')];
        scatter(ax1, p(:,1), p(:,2)*1000, 16, [0.6 0.6 0.6], 'filled', 'MarkerFaceAlpha',0.5); hold(ax1,'on');
        plot(ax1, R.value.SOC_vec, val*1000, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6);
        hold(ax1,'off'); legend(ax1, {'each current step','R0 table'}, 'Location','best');
        xlabel(ax1,'SOC (-)'); ylabel(ax1,'R0 (mOhm)'); title(ax1,'R0 vs SOC');
        plotExampleEdge(ax2, R);

    % ------------------------------------------------------------------
    case {'R1_vec','R2_vec','R3_vec','tau1_vec','tau2_vec','tau3_vec'}
        q = str2double(key(regexp(key,'\d','once')));
        isTau = startsWith(key,'tau');
        p = R.diag.points.(regexprep(key,'_vec',''));
        L = {'METHOD'
             'Every rest of at least 5 min that follows a current pulse is'
             'fitted with'
             ''
             '   V(t) = Vinf + sum_k R_k * x_k(0) * exp(-t / tau_k)'
             ''
             'x_k(0) = current flowing in RC branch k when the current'
             'stopped. It is worked out from the REAL current history:'
             '   x_k(n) = a*x_k(n-1) + (1-a)*I(n-1),  a = exp(-dt/tau_k)'
             'so short pulses and long charges are both handled exactly.'
             'For each tau set the R_k come from linear least squares'
             '(R_k >= 0); the taus are searched on a grid then refined.'
             'Pairs are sorted so tau1 < tau2 < tau3.'
             ''
             sprintf('Relaxations fitted: %d', numel(R.diag.fits))
             ''
             'TABLE  (M = median of fits near this SOC, I = interpolated,'
             '        E = end value held)'};
        if isTau
            L = [L; tableLines(R.value.SOC_vec, val, R.diag.prov.(key), '%.1f s')];
            scale = 1; unit = sprintf('tau%d (s)', q);
        else
            L = [L; tableLines(R.value.SOC_vec, val*1000, R.diag.prov.(key), '%.3f mOhm')];
            scale = 1000; unit = sprintf('R%d (mOhm)', q);
        end
        scatter(ax1, p(:,1), p(:,2)*scale, 22, [0.6 0.6 0.6], 'filled'); hold(ax1,'on');
        plot(ax1, R.value.SOC_vec, val*scale, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6);
        hold(ax1,'off'); legend(ax1, {'each relaxation fit','table'}, 'Location','best');
        xlabel(ax1,'SOC (-)'); ylabel(ax1,unit); title(ax1,[unit ' vs SOC']);
        plotExampleRelaxation(ax2, R, q, false);

    % ------------------------------------------------------------------
    case {'thermal_mass','hA'}
        t2 = R.diag.thermal;
        L = {'METHOD'
             'Lumped thermal model of the cell in the chamber:'
             ''
             '   m*cp * dT/dt = Q - h*A * (T - T_chamber)'
             '   Q = I^2*R0(SOC) + sum_k R_k(SOC)*x_k^2'
             ''
             'Q is exactly the heat the Simscape block generates, using the'
             'R0 / R_k tables found above.'
             '1. Least squares on dT/dt (10 s grid) gives a first estimate.'
             '2. m*cp and h*A are then refined so the SIMULATED temperature'
             '   matches the measured one (removes smoothing bias).'
             ''
             'RESULT'
             sprintf('   thermal mass m*cp = %.4g J/K', t2.mcp)
             sprintf('   h*A               = %.4g W/K', t2.hA)
             sprintf('   rms temperature error = %.3f K', t2.rmse)
             ''
             'h*A is NOT a battery parameter: use it in a Convective Heat'
             'Transfer block (Area = 1 m^2, coefficient = h*A) between the'
             'battery port H and a Controlled Temperature Source.'};
        plot(ax1, t2.t/3600, t2.Tmeas, 'Color',[0.3 0.3 0.3]); hold(ax1,'on');
        plot(ax1, t2.t/3600, t2.Tmodel, '--', 'Color',[0.85 0.33 0.1], 'LineWidth',1.4);
        plot(ax1, t2.t/3600, t2.Tamb, ':', 'Color',[0 0.45 0.74]);
        hold(ax1,'off'); legend(ax1, {'measured cell T','model','chamber'}, 'Location','best');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Temperature (°C)'); title(ax1,'Measured vs model temperature');
        plot(ax2, t2.t/3600, t2.Q, 'Color',[0.49 0.18 0.56]);
        xlabel(ax2,'Test time (h)'); ylabel(ax2,'Heat Q (W)'); title(ax2,'Heat generated in the cell');

    % ------------------------------------------------------------------
    case 'SOC0'
        L = {'SOC at the first sample of the file.'
             ''
             'SOC is coulomb counted and reset to 1.0 at the end of every'
             'full CC-CV charge:'
             '   SOC(t) = 1 + (Ah_in(t) - Ah_in(full)) / AH'
             'Before the first full charge the same line is run backwards.'
             ''
             sprintf('   SOC0 = %.4f', val)
             ''
             'Use it as the block''s initial SOC to start the simulation in'
             'the same state as the test (together with batt_load).'};
        plot(ax1, th, d.soc, 'LineWidth',1.2); hold(ax1,'on');
        plot(ax1, th(1), d.soc(1), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerSize',9);
        hold(ax1,'off');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'SOC (-)'); title(ax1,'Coulomb-counted SOC');
        one = true;

    % ------------------------------------------------------------------
    case 'T0'
        L = {'Cell temperature at the first sample of the file, in kelvin'
             '(the block''s initial cell temperature).'
             ''
             sprintf('   T0 = %.2f K = %.2f °C', val, val - 273.15)};
        plot(ax1, th, d.Tcell); hold(ax1,'on');
        if any(isfinite(d.Tch)), plot(ax1, th, d.Tch, ':'); end
        k = find(isfinite(d.Tcell), 1);
        if ~isempty(k), plot(ax1, th(k), d.Tcell(k), 'o', 'MarkerFaceColor',[0.85 0.33 0.1]); end
        hold(ax1,'off');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Temperature (°C)'); title(ax1,'Cell temperature');
        one = true;
end
txt.Value = [head; L];
if one
    delete(ax2);
    ax1.Layout.Row = [1 2];
end
end

% =========================================================================
function plotExampleRelaxation(ax, R, q, showVinf)
% one measured rest with the fitted curve (the fit closest to SOC 0.5)
fits = R.diag.fits;
if isempty(fits), title(ax,'No relaxation fits'); return; end
[~, k] = min(abs([fits.soc] - 0.5));
f = fits(k);
plot(ax, f.tr/60, f.v, '.', 'Color',[0.4 0.4 0.4]); hold(ax,'on');
plot(ax, f.tr/60, f.vfit, '-', 'Color',[0.85 0.33 0.1], 'LineWidth',1.5);
yline(ax, f.Vinf, '--', sprintf('Vinf = %.4f V', f.Vinf));
hold(ax,'off');
legend(ax, {'measured','fit'}, 'Location','best');
xlabel(ax,'Time since current stopped (min)'); ylabel(ax,'Voltage (V)');
if showVinf
    title(ax, sprintf('Example rest at SOC %.2f: it settles to Vinf (an OCV point)', f.soc));
else
    s = sprintf('R%d = %.3f mOhm, tau%d = %.1f s', q, 1000*f.R(min(q,end)), q, f.tau(min(q,end)));
    title(ax, sprintf('Example relaxation at SOC %.2f (%s, fit rms %.2f mV)', f.soc, s, 1000*f.rmse));
end
end

function plotExampleEdge(ax, R)
% the current step closest to SOC 0.5, +-30 s around it
d = R.d;
k = R.diag.edgeIdx;
if isempty(k), title(ax,'No current steps'); return; end
[~, j] = min(abs(d.soc(k) - 0.5));
k = k(j);
w = abs(d.t - d.t(k)) <= 30;
tt = d.t(w) - d.t(k);
yyaxis(ax,'left');
plot(ax, tt, d.V(w), '.-'); ylabel(ax,'Voltage (V)');
yyaxis(ax,'right');
stairs(ax, tt, d.I(w)); ylabel(ax,'Current (A, + = charge)');
xlabel(ax,'Time around the step (s)');
dV = d.V(k+1) - d.V(k); dI = d.I(k+1) - d.I(k);
title(ax, sprintf('Example step: dV = %.1f mV, dI = %.3f A  ->  R0 = %.3f mOhm', ...
    1000*dV, dI, 1000*dV/dI));
end

function L = tableLines(g, v, prov, fmt)
L = {sprintf('   %6s   %s', 'SOC', 'value')};
for j = 1:numel(g)
    pj = ' '; if numel(prov) >= j, pj = prov(j); end
    L{end+1,1} = sprintf(['   %6.3f   ' fmt '   %c'], g(j), v(j), pj); %#ok<AGROW>
end
end

function s = vecStr(v)
s = ['[' strjoin(arrayfun(@(x) sprintf('%.4g', x), v, 'UniformOutput', false), ' ') ']'];
end

function styleAxes(a)
a.FontName = 'Segoe UI'; a.FontSize = 11; a.Box = 'on';
grid(a,'on'); a.GridAlpha = 0.12;
a.Title.FontWeight = 'bold';
end
