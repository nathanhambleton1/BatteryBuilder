function f = explainParameter(key, R, row)
%EXPLAINPARAMETER  Pop-up window: how one parameter was calculated.
%
%   explainParameter(key, R, row)
%     key  parameter key (e.g. 'R0_vec')
%     R    result of extractCellParameters
%     row  the matching entry of blockParameterList (for names / units)
%
%   Left: a step-by-step explanation - what the parameter means, the
%   equations (rendered with LaTeX), the actual numbers from this file worked
%   through, and the final table. Right: plots of the data behind it.

d  = R.d;
th = d.t/3600;
val = R.value.(key);

f = uifigure('Name', ['How was ' row.label ' calculated?'], 'Color','w');
f.Position(3:4) = [1320 800];
movegui(f,'center');
g = uigridlayout(f,[1 2],'ColumnWidth',{560,'1x'},'Padding',[0 0 0 0],'ColumnSpacing',0, ...
    'BackgroundColor','w');
gR = uigridlayout(g,[2 1],'Padding',[6 10 10 10],'BackgroundColor','w');
gR.Layout.Row = 1; gR.Layout.Column = 2;
ax1 = uiaxes(gR); styleAxes(ax1);
ax2 = uiaxes(gR); styleAxes(ax2);
one = false;                      % true -> only the top axes is used

B = {};                           % explanation blocks: {kind, content}
H(row.label, 'title');
P(sprintf('Workspace variable:  %s', row.var), 'meta');
P(sprintf('Goes in:  %s', row.where), 'meta');

% Symbols used everywhere
SYM = ['I = current (A), positive = charge.  V = terminal voltage.  ' ...
       'Q_in = net Ah that has gone INTO the cell since the start of the file.  ' ...
       'SOC = state of charge, 0 (empty) .. 1 (full).'];

switch key
    % ------------------------------------------------------------------
    case 'SOC_vec'
        H('What it is');
        P(['The SOC breakpoints: the x-axis of every table in the block. V0, R0, R1, tau1 ... ' ...
           'are each given as one number per breakpoint, and the block draws straight lines ' ...
           'between them. These points are YOUR CHOICE, not a measurement.']);
        H('How the block uses them');
        P('Between two breakpoints s_j and s_(j+1) the block interpolates linearly, e.g. for the OCV:');
        EQ('V_0(\mathrm{SOC}) = V_{0,j} + \frac{V_{0,j+1}-V_{0,j}}{s_{j+1}-s_j}\,\left(\mathrm{SOC}-s_j\right)');
        P(['Points close together near 0 and 1 follow the steep ends of the OCV curve; the ' ...
           'middle of the curve is flat so fewer points are needed there. Outside 0..1 the ' ...
           'block holds the end value (extrapolation = nearest).']);
        H('Value');
        M({vecStr(val)});
        if ~isempty(d.soc)
            plot(ax1, th, d.soc, 'LineWidth',1.2); hold(ax1,'on');
            yline(ax1, val, ':', 'Color',[0.5 0.5 0.5]); hold(ax1,'off');
            xlabel(ax1,'Test time (h)'); ylabel(ax1,'SOC (-)'); title(ax1,'SOC of the test with the breakpoints');
        end
        one = true;

    % ------------------------------------------------------------------
    case 'AH'
        c = R.diag.capacity;
        ah = d.tbl.('Net Ah in (Ah)');
        H('What it is');
        P(['The usable capacity: how many amp-hours the cell gives from FULL down to EMPTY. ' ...
           'The block uses it to turn current into SOC. Here FULL and EMPTY are defined by ' ...
           'this test''s own charge voltage and cut-off voltage.']);
        P(SYM, 'small');
        H('Step 1 - count the charge (coulomb counting)');
        P(['Every logged current is held until the next sample (that is how the cycler ' ...
           'applies it) and added up:']);
        EQ('Q_{in}(t_n) = \frac{1}{3600}\sum_{i=1}^{n-1} I_i\,\left(t_{i+1}-t_i\right)\quad[\mathrm{Ah}]');
        P('Q_in rises while charging and falls while discharging (the "Net Ah in" column on the Plot tab).');
        H('Step 2 - find FULL');
        P(sprintf(['FULL = the end of a CC-CV charge: the current tapered to below 35 %% of its ' ...
           'maximum while the voltage stayed flat (within 15 mV) at the highest CV voltage of ' ...
           'the test, V_cv = %.3f V.  Found %d full point(s).'], c.VmaxCV, numel(c.fullIdx)));
        H('Step 3 - find EMPTY');
        P(sprintf(['EMPTY = the end of a discharge that lasted at least 5 min and stopped at the ' ...
           'cut-off, V_cut = %.3f V (the lowest END voltage of all long discharges - short ' ...
           'pulses are ignored). It must also end on the "knee", where the voltage drops much ' ...
           'faster per Ah than in the middle of the discharge:'], c.Vmin));
        EQ('\left|\frac{dV}{dQ}\right|_{\mathrm{last\ 3\%}} > 3\,\left|\frac{dV}{dQ}\right|_{\mathrm{middle\ half}}');
        P(sprintf(['This stops a partial discharge (e.g. one HPPC step) being taken as empty. ' ...
           'Found %d empty point(s).'], numel(c.emptyIdx)));
        H('Step 4 - capacity');
        EQ('AH = Q_{in}(t_{\mathrm{full}}) - Q_{in}(t_{\mathrm{empty}})');
        if ~isempty(c.a)
            EQ(sprintf('AH = %s - %s = \\mathbf{%s}\\ \\mathrm{Ah}', n4(ah(c.a)), p4(ah(c.b)), n4(val)));
            P(sprintf(['Full at %.2f h, empty at %.2f h, discharged at %.3g A (%.2fC). If there are ' ...
               'several full-to-empty discharges, the slowest one is used (closest to the true ' ...
               'capacity).'], th(c.a), th(c.b), c.rateA, c.rateA/val));
            if isfinite(c.fileAh)
                H('Cross-check');
                P(sprintf(['The cycler''s own "Capacity (Ah)" column for the same discharge gives ' ...
                   '%.4f Ah (%+.2f %%). The two should agree within about 1 %%; if they do not, the ' ...
                   'time or current column is not what it seems.'], c.fileAh, 100*(c.fileAh/val - 1)), ...
                   warnIf(abs(c.fileAh/val - 1) > 0.02));
            end
        end
        if size(c.candidates,1) >= 2
            H('Rate capability (every full-to-empty discharge in the file)');
            P(['Each discharge from FULL to the cut-off gives its own capacity. Faster discharges ' ...
               'reach the cut-off voltage sooner (more voltage is lost over the resistance), so ' ...
               'they deliver less. The slowest one is the closest to the cell''s real capacity and ' ...
               'is the one used; the rest show how the usable capacity falls with rate.']);
            cc = sortrows(c.candidates, 2);
            L = {sprintf('   %8s  %8s  %10s  %8s', 'current', 'C-rate', 'Ah out', 'vs AH')};
            for r = 1:size(cc,1)
                L{end+1,1} = sprintf('   %7.3g A  %7.2fC  %8.4f Ah  %+6.1f %%', cc(r,2), cc(r,2)/val, ...
                    cc(r,1), 100*(cc(r,1)/val - 1)); %#ok<AGROW>
            end
            M(L);
            P(['Note: after a fast discharge the cell is NOT empty - it only hit the cut-off early. ' ...
               'SOC keeps counting with the slow-rate AH, so it shows the charge that is still in it.'], 'small');
        end
        H('Good to know');
        P(['The capacity depends on the discharge rate and the cut-off voltage. A datasheet ' ...
           'rating at a lower rate or a lower cut-off will be larger.']);
        plot(ax1, th, d.V, 'Color',[0.3 0.3 0.3]); hold(ax1,'on');
        plot(ax1, th(c.fullIdx), d.V(c.fullIdx), '^', 'MarkerFaceColor',[0.2 0.6 0.3], ...
            'MarkerEdgeColor','none','MarkerSize',9);
        plot(ax1, th(c.emptyIdx), d.V(c.emptyIdx), 'v', 'MarkerFaceColor',[0.85 0.2 0.1], ...
            'MarkerEdgeColor','none','MarkerSize',9);
        hold(ax1,'off');
        legend(ax1, {'voltage','FULL (end of CC-CV)','EMPTY (cut-off + knee)'}, 'Location','southwest');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Voltage (V)'); title(ax1,'Full and empty points');
        plot(ax2, th, ah, 'LineWidth',1.2); hold(ax2,'on');
        if ~isempty(c.a)
            plot(ax2, th([c.a c.b]), ah([c.a c.b]), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerSize',8);
            plot(ax2, th([c.b c.b]), ah([c.a c.b]), '-', 'Color',[0.85 0.33 0.1], 'LineWidth',2);
            plot(ax2, th([c.a c.b]), ah([c.a c.a]), ':', 'Color',[0.85 0.33 0.1]);
            text(ax2, th(c.b), mean(ah([c.a c.b])), sprintf('  AH = %.4f Ah', val), 'FontWeight','bold');
        end
        hold(ax2,'off');
        xlabel(ax2,'Test time (h)'); ylabel(ax2,'Q_{in} (Ah)'); title(ax2,'Coulomb count: net Ah into the cell');

    % ------------------------------------------------------------------
    case 'SOC0'
        s = R.diag.soc; ck = s.check;
        ah = d.tbl.('Net Ah in (Ah)');
        H('What it is');
        P(['The state of charge at the FIRST sample of the file. Put it in the block''s initial ' ...
           'SOC so a simulation driven by batt_load starts where the test started.']);
        H('How SOC is defined');
        P(['SOC is coulomb counted (see AH) and pinned to 1 at the end of every full CC-CV ' ...
           'charge. In between it follows the charge that went in or out:']);
        EQ('\mathrm{SOC}(t) = 1 + \frac{Q_{in}(t) - Q_{in}(t_{\mathrm{full}})}{AH}');
        P('So SOC = 1 at FULL and SOC = 0 after AH amp-hours have come out (the cut-off).');
        H('Worked through for this file');
        if strcmp(s.anchor, 'full')
            P(sprintf(['The first FULL point is at %.2f h. From the start of the file to that point ' ...
               'the net charge that went in was'], th(s.anchorIdx)));
            EQ(sprintf('Q_{in}(t_{\\mathrm{full}}) - Q_{in}(0) = %s - %s = %s\\ \\mathrm{Ah}', ...
                n4(s.ahAnchor), p4(s.ah0), n4(s.ahAnchor - s.ah0)));
            EQ(sprintf('\\mathrm{SOC}_0 = 1 - \\frac{%s}{%s} = \\mathbf{%s}', n4(s.ahAnchor - s.ah0), ...
                n4(s.cap), n4(s.raw0)));
            P(sprintf(['In words: filling the cell from where the file starts took %.4g Ah of its ' ...
               '%.4g Ah, so %.1f %% of the capacity was already in it at the start. (A result ' ...
               'below 0 or above 1 would be clipped to 0..1.)'], s.ahAnchor - s.ah0, s.cap, 100*s.raw0));
        else
            P(sprintf('There is no full charge, so SOC is counted from the first EMPTY point (%.2f h):', th(s.anchorIdx)));
            EQ(sprintf('\\mathrm{SOC}_0 = \\frac{Q_{in}(0) - Q_{in}(t_{\\mathrm{empty}})}{AH} = \\frac{%s - %s}{%s} = \\mathbf{%s}', ...
                n4(s.ah0), p4(s.ahAnchor), n4(s.cap), n4(s.raw0)));
        end
        if ~isempty(ck)
            H('Check against the voltage');
            P(sprintf(['A resting cell''s voltage is its OCV, so the OCV table (built from this ' ...
               'same file) can be read backwards. The cell rests at %.3f V at %.2f h:'], ck.V, ck.t/3600));
            EQ(sprintf('V_0^{-1}(%s\\ \\mathrm{V}) = %s \\qquad \\mathrm{coulomb\\ count:}\\ %s', ...
                n4(ck.V), n3(ck.socOcv), n3(ck.socCC)));
            P(sprintf(['How sharp this check is depends on the OCV slope there, %.3f V per 100 %% SOC: ' ...
               'a 5 mV error in the voltage moves the answer by'], ck.slope));
            EQ(sprintf('\\Delta\\mathrm{SOC} \\approx \\frac{\\Delta V}{dV_0/d\\mathrm{SOC}} = \\frac{0.005}{%s} = %s', ...
                n3(ck.slope), n3(ck.unc)));
            if isfinite(ck.Vempty)
                P(sprintf(['For comparison: after the discharge to the %.3f V cut-off (SOC 0 by ' ...
                   'definition) this cell relaxed to %.3f V. A start voltage close to that means ' ...
                   'the file really does start near empty.'], R.diag.capacity.Vmin, ck.Vempty));
            end
            P(['Note: on most lithium-ion cells a RESTING voltage around 3.1-3.3 V is close to ' ...
               'empty - the voltage only drops to the cut-off while current flows, then recovers ' ...
               'when it stops.'], 'small');
            if abs(ck.socOcv - ck.socCC) > max(0.08, ck.unc)
                P(['The two disagree by more than the check''s uncertainty. Possible causes: the ' ...
                   'rest was too short to settle, the current sign or time column is wrong, or the ' ...
                   'cell was changed between tests.'], 'warn');
            end
        end
        plot(ax1, th, d.soc, 'LineWidth',1.2); hold(ax1,'on');
        plot(ax1, th(1), min(max(d.soc(1),0),1), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerSize',9);
        if ~isempty(s.anchorIdx)
            plot(ax1, th(s.anchorIdx), d.soc(s.anchorIdx), '^', 'MarkerFaceColor',[0.2 0.6 0.3], ...
                'MarkerEdgeColor','none','MarkerSize',9);
        end
        hold(ax1,'off');
        legend(ax1, {'SOC','SOC_0 (first sample)', ['first ' upper(s.anchor) ' point']}, 'Location','southwest');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'SOC (-)'); title(ax1,'Coulomb-counted SOC');
        if R.found.V0_vec
            plot(ax2, R.value.SOC_vec, R.value.V0_vec, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.5);
            hold(ax2,'on');
            if ~isempty(ck)
                yline(ax2, ck.V, '--', sprintf('rest voltage %.3f V', ck.V), 'Color',[0.85 0.33 0.1], ...
                    'HandleVisibility','off', 'LabelHorizontalAlignment','left');
                plot(ax2, ck.socOcv, ck.V, 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerSize',9);
                plot(ax2, ck.socCC, ck.V, 'd', 'MarkerFaceColor',[0.2 0.6 0.3], 'MarkerEdgeColor','none', 'MarkerSize',9);
                legend(ax2, {'OCV table','read from voltage','coulomb count'}, 'Location','southeast');
            end
            hold(ax2,'off');
            xlabel(ax2,'SOC (-)'); ylabel(ax2,'OCV (V)'); title(ax2,'Voltage check on the OCV table');
        else
            one = true;
        end

    % ------------------------------------------------------------------
    case 'V_range'
        H('What it is');
        P(['The lowest and highest terminal voltage the cell is allowed to reach. The block ' ...
           'only uses it to warn when a simulation leaves this window.']);
        H('How it is found');
        EQ('V_{min} = \min_t V(t), \qquad V_{max} = \max_t V(t)');
        EQ(sprintf('V_{min} = %s\\ \\mathrm{V}, \\qquad V_{max} = %s\\ \\mathrm{V}', n4(val(1)), n4(val(2))));
        P(['These are simply what the real cell did in this test. Replace them with the ' ...
           'datasheet limits if you prefer the official operating window.']);
        plot(ax1, th, d.V); hold(ax1,'on');
        yline(ax1, val(1), '--r', sprintf('min %.3f V', val(1)));
        yline(ax1, val(2), '--r', sprintf('max %.3f V', val(2)));
        hold(ax1,'off');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Voltage (V)'); title(ax1,'Measured voltage');
        one = true;

    % ------------------------------------------------------------------
    case 'V0_vec'
      p = R.diag.points; ex = R.diag.ocvExample;
      if isfield(R.diag, 'multiRate') && R.diag.multiRate.ok
        explainOcvMultiRate();
      else
        H('What it is');
        P(['The open-circuit voltage (OCV): the voltage the cell settles to with no current, ' ...
           'as a function of SOC. It is the "fuel gauge" curve of the cell.']);
        H('The model it belongs to');
        P(['The block''s terminal voltage is the OCV plus the drop over R0 plus the voltage ' ...
           'over each RC pair (x_k = current through the resistor of RC pair k):']);
        EQ('V = V_0(\mathrm{SOC}) + I\,R_0 + \sum_k R_k\,x_k');
        P('So the OCV can never be measured directly while current flows - two ways are used:');
        H('Source 1 - relaxed rests (sets the LEVEL)');
        P(['After a current pulse the voltage creeps towards the OCV. Each rest of at least ' ...
           '5 min is fitted (see R1 / tau1) with']);
        EQ('V(t) = V_\infty + \sum_k R_k\,x_k(0)\,e^{-t/\tau_k}');
        P(sprintf(['V_inf, the voltage it would reach after infinite time, is one OCV point. ' ...
           '%d rest(s) gave points (orange dots on the plot).'], size(p.ocv,1)));
        H('Source 2 - slow charge / discharge (sets the SHAPE)');
        P(sprintf(['During constant-current steps at or below %.2gC the model above is turned ' ...
           'round to estimate the OCV at every sample:'], R.constants.ocvMaxCrate));
        EQ('\hat V_0 = V - I\,R_0(\mathrm{SOC}) - \sum_k R_k(\mathrm{SOC})\,x_k');
        P('with each RC current x_k following the real current history:');
        EQ('x_k[n] = a_k\,x_k[n-1] + (1-a_k)\,I[n-1], \qquad a_k = e^{-\Delta t/\tau_k}');
        if ~isempty(ex)
            P(sprintf('Worked example (sample at %.2f h, SOC %.3f):', ex.t/3600, ex.soc), 'small');
            rx = sum(ex.Rx);
            EQ(sprintf('\\hat V_0 = %s - (%s)(%s) - %s = %s\\ \\mathrm{V}', n4(ex.V), n4(ex.I), ...
                n5(ex.R0), n4(rx), n4(ex.est)));
        end
        P(['Charge and discharge estimates are averaged in 1 % SOC bins; that cancels most of ' ...
           'the hysteresis and what is left of the model error:']);
        EQ('\hat V_0 = \tfrac{1}{2}\left(\hat V_{0,\mathrm{chg}} + \hat V_{0,\mathrm{dis}}\right)');
        H('Putting them together');
        P(['The dense curve gives the shape between rests, the rest points fix its level: the ' ...
           'offset c between the two is measured at each rest and interpolated in between.']);
        EQ('V_0(s_j) = \hat V_0(s_j) - c(s_j), \qquad c = \hat V_0 - V_\infty \ \mathrm{at\ each\ rest}');
        P(['Finally the table is forced to rise with SOC. Where neither source reaches the ' ...
           'box is left empty rather than guessed.']);
        H('Table');
        P('M = measured near this SOC, I = interpolated between measurements, E = short extension past the data.', 'small');
        M(tableLines(R.value.SOC_vec, val, R.diag.prov.V0_vec, '%.4f V'));
        hold(ax1,'on');
        if ~isempty(p.ocvDense)
            plot(ax1, p.ocvDense(:,1), p.ocvDense(:,2), '.', 'Color',[0.6 0.6 0.6], 'DisplayName','corrected slow curve');
        end
        if ~isempty(p.ocv)
            plot(ax1, p.ocv(:,1), p.ocv(:,2), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], ...
                'MarkerEdgeColor','none','DisplayName','relaxed rest voltage V_\infty');
        end
        plot(ax1, R.value.SOC_vec, val, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6, 'DisplayName','V0 table');
        hold(ax1,'off'); legend(ax1,'Location','southeast'); xlim(ax1, [-0.02 1.02]);
        xlabel(ax1,'SOC (-)'); ylabel(ax1,'OCV (V)'); title(ax1,'Open-circuit voltage');
        plotExampleRelaxation(ax2, R, 1, true);
      end

    % ------------------------------------------------------------------
    case 'R0_vec'
        p = R.diag.points.R0;
        e = exampleEdge(R);
        H('What it is');
        P(['The series (ohmic) resistance: the part of the voltage drop that appears the ' ...
           'instant current flows - electrolyte, contacts, tabs.']);
        H('Why a current step measures it');
        P(['The voltage over an RC pair cannot jump - its capacitor needs time to charge. So ' ...
           'when the current steps from one value to another between two samples, only R0 ' ...
           'responds in that instant:']);
        EQ('\Delta V = R_0\,\Delta I \quad\Rightarrow\quad R_0 = \frac{V_{n+1}-V_n}{I_{n+1}-I_n}');
        P(sprintf(['What counts is how soon AFTER the step the first sample was taken: within ' ...
           '%g s, otherwise the RC pairs have already started to move and R0 would come out too ' ...
           'high. The StepTime column gives that time exactly (a rest logged every 10 s is fine, ' ...
           'as long as the new step''s first sample comes straight away). Steps smaller than ' ...
           '%.2gC are left out (too little voltage change to measure). %d steps were used.'], ...
           R.constants.maxEdgeDt, R.constants.minStepC, size(p,1)));
        hotP();
        if ~isempty(e)
            H('Worked example');
            P(sprintf('The step closest to SOC 0.5 (at %.2f h, SOC %.3f):', e.t/3600, e.soc), 'small');
            EQ(sprintf('R_0 = \\frac{%s\\ \\mathrm{V}}{%s\\ \\mathrm{A}} = %s\\ \\mathrm{m\\Omega}', ...
                n4(e.dV), n4(e.dI), n3(1000*e.R0)));
        end
        H('From points to the table');
        P(['Each SOC breakpoint takes the MEDIAN of the steps nearest to it (robust against ' ...
           'the odd bad step).']);
        rdcP();
        M(tableLines(R.value.SOC_vec, val*1000, R.diag.prov.R0_vec, '%.3f mOhm'));
        scatter(ax1, p(:,1), p(:,2)*1000, 16, [0.6 0.6 0.6], 'filled', 'MarkerFaceAlpha',0.5); hold(ax1,'on');
        plot(ax1, R.value.SOC_vec, val*1000, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6);
        lg = {'each current step','R0 table'};
        [rs, rsLab] = rSum();
        if isfield(R.diag,'multiRate') && R.diag.multiRate.ok
            plot(ax1, R.diag.multiRate.RdcPts(:,1), R.diag.multiRate.RdcPts(:,2)*1000, '-', ...
                'Color',[0.85 0.33 0.1], 'LineWidth',1.2);
            plot(ax1, R.value.SOC_vec, rs*1000, '--', 'Color',[0.47 0.67 0.19], 'LineWidth',1.2);
            lg = [lg, {'R_{dc} from the multi-rate fit', rsLab}];
        end
        hold(ax1,'off'); legend(ax1, lg, 'Location','best');
        xlim(ax1,[-0.02 1.02]); xlabel(ax1,'SOC (-)'); ylabel(ax1,'R0 (m\Omega)'); title(ax1,'R0 vs SOC');
        plotExampleEdge(ax2, R, e);

    % ------------------------------------------------------------------
    case {'R1_vec','R2_vec','R3_vec','tau1_vec','tau2_vec','tau3_vec'}
        q = str2double(key(regexp(key,'\d','once')));
        isTau = startsWith(key,'tau');
        p = R.diag.points.(regexprep(key,'_vec',''));
        fx = exampleFit(R);
        H('What it is');
        P(sprintf(['RC pair %d models a slow voltage change - diffusion and charge transfer ' ...
           'inside the cell. R%d is how big the change is per amp, tau%d = R%d*C%d is how fast ' ...
           'it happens (in seconds). Pairs are numbered fastest first: tau1 < tau2 < tau3.'], q, q, q, q, q));
        H('The model');
        P(sprintf('The current through the resistor of pair k, x_k, lags the cell current I with time constant tau_k:'));
        EQ('\frac{dx_k}{dt} = \frac{I - x_k}{\tau_k}, \qquad v_k = R_k\,x_k');
        H('Step 1 - pick the rests');
        P(sprintf(['Every rest of at least %d min that follows a charge or discharge. During ' ...
           'a rest I = 0, so each x_k decays and the voltage relaxes:'], round(R.constants.minRestS/60)));
        EQ('V(t) = V_\infty + \sum_k R_k\,x_k(0)\,e^{-t/\tau_k}');
        H('Step 2 - where the RC pairs start');
        P(['x_k(0), the current in each pair when the current stopped, is worked out from the ' ...
           'REAL current history (exact for a cycler''s piecewise-constant current):']);
        EQ('x_k[n] = a_k\,x_k[n-1] + (1-a_k)\,I[n-1], \qquad a_k = e^{-\Delta t/\tau_k}');
        P('So a 10 s pulse and a 2 h charge are both handled correctly.');
        H('Step 3 - fit');
        P(['For a given set of time constants the equation is LINEAR in V_inf and the R_k, so ' ...
           'they come from least squares (with R_k >= 0):']);
        EQ('\min_{V_\infty,\;R_k \ge 0}\ \sum_i \Big(V_i - V_\infty - \sum_k R_k\,x_k(0)\,e^{-t_i/\tau_k}\Big)^2');
        P(sprintf(['The time constants are searched on a log grid between %g s and the rest ' ...
           'length, then refined (Nelder-Mead). Fits with an rms error above %g mV are thrown ' ...
           'away. %d rest(s) gave usable fits.'], R.constants.tauMin, 1000*R.constants.maxFitRmse, ...
           numel(R.diag.fits)));
        if ~isempty(fx) && numel(fx.R) >= q && isfinite(fx.R(q))
            H('Worked example');
            P(sprintf('The rest closest to SOC 0.5 (SOC %.3f, rms error %.2f mV):', fx.soc, 1000*fx.rmse), 'small');
            EQ(sprintf('x_%d(0) = %s\\ \\mathrm{A},\\quad R_%d = %s\\ \\mathrm{m\\Omega},\\quad \\tau_%d = %s\\ \\mathrm{s}', ...
                q, n4(fx.x0(q)), q, n3(1000*fx.R(q)), q, n3(fx.tau(q))));
            EQ(sprintf('C_%d = \\frac{\\tau_%d}{R_%d} = %s\\ \\mathrm{F} \\quad (\\mathrm{if\\ you\\ need\\ a\\ capacitance})', ...
                q, q, q, n3(fx.tau(q)/fx.R(q))));
        end
        hotP();
        H('From fits to the table');
        P(['Each breakpoint takes the median of the fits nearest to it. A rest only happens ' ...
           'where the current stops, so in a rate test (full charge -> discharge to cut-off) ' ...
           'the fits sit near SOC 1 and near the end of each discharge.']);
        if ~isTau, rdcP(); else
            P(['Time constants cannot be seen at SOCs where the current never stops, so they are ' ...
               'interpolated there (I) and held past the ends (E).']);
        end
        if isTau
            M(tableLines(R.value.SOC_vec, val, R.diag.prov.(key), '%.1f s'));
            scale = 1; unit = sprintf('\\tau_%d (s)', q);
        else
            M(tableLines(R.value.SOC_vec, val*1000, R.diag.prov.(key), '%.3f mOhm'));
            scale = 1000; unit = sprintf('R_%d (m\\Omega)', q);
        end
        scatter(ax1, p(:,1), p(:,2)*scale, 22, [0.6 0.6 0.6], 'filled'); hold(ax1,'on');
        plot(ax1, R.value.SOC_vec, val*scale, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6);
        hold(ax1,'off'); legend(ax1, {'each relaxation fit','table'}, 'Location','best');
        xlim(ax1,[-0.02 1.02]); xlabel(ax1,'SOC (-)'); ylabel(ax1,unit); title(ax1,[unit ' vs SOC']);
        plotExampleRelaxation(ax2, R, q, false);

    % ------------------------------------------------------------------
    case {'thermal_mass','hA'}
        t2 = R.diag.thermal;
        H('What it is');
        P(['thermal_mass = m*cp, the energy needed to warm the cell by 1 K (J/K). h*A is how ' ...
           'well the cell sheds heat to the chamber air (W/K). h*A is NOT a battery block ' ...
           'parameter: it goes in a Convective Heat Transfer block between the battery''s ' ...
           'thermal port and the ambient.']);
        H('The model');
        P('One lumped temperature for the whole cell, heated by its own losses and cooled by the chamber:');
        EQ('m c_p\,\frac{dT}{dt} = Q - hA\,\left(T - T_{ch}\right)');
        P(['Q is the heat the cell generates. It is worked out from the MEASURED voltage: the ' ...
           'electrical power lost inside the cell is the current times the gap between the ' ...
           'terminal voltage and the OCV (Bernardi''s energy balance, irreversible part):']);
        EQ('Q = I\,\big(V - V_0(\mathrm{SOC})\big)\;-\;\sum_k R_k\,x_k\,(I - x_k)');
        P(['The second term takes out the power that is only being stored in the RC capacitors ' ...
           '(it comes back as heat in the rest that follows). With the block''s own voltage ' ...
           'equation this is exactly the block''s heat:']);
        EQ('Q = I^2 R_0 + \sum_k R_k\,x_k^2');
        P(['Why not compute I^2 R from the tables directly? The tables hold the resistance at ' ...
           'the test temperature. During a fast discharge the cell warms up and its real ' ...
           'resistance drops (lithium-ion resistance falls as the temperature rises - that is why ' ...
           'the block can take R0(SOC,T) tables), so I^2 R from the tables would invent heat that was never made. The measured voltage already carries the real resistance.'], 'small');
        P(['Left out: the reversible (entropic) heat I*T*dV0/dT - it needs the OCV at several ' ...
           'temperatures, and the block does not model it either.'], 'small');
        H('Step 1 - linear least squares');
        P('Divided by m*cp the model is linear in two unknowns, so it is fitted to dT/dt on a 10 s grid:');
        EQ('\frac{dT}{dt} = \theta_1\,Q - \theta_2\,\left(T - T_{ch}\right), \qquad m c_p = \frac{1}{\theta_1},\quad hA = \frac{\theta_2}{\theta_1}');
        if isfield(t2,'mcp0')
            EQ(sprintf('m c_p \\approx %s\\ \\mathrm{J/K}, \\qquad hA \\approx %s\\ \\mathrm{W/K}', n4(t2.mcp0), n4(t2.hA0)));
        end
        H('Step 2 - refine on the temperature curve');
        P(['dT/dt is noisy, so both values are then adjusted until the SIMULATED temperature ' ...
           'matches the measured one as closely as possible (smallest rms error):']);
        EQ(sprintf('m c_p = \\mathbf{%s}\\ \\mathrm{J/K}, \\qquad hA = \\mathbf{%s}\\ \\mathrm{W/K}, \\qquad \\mathrm{rms} = %s\\ \\mathrm{K}', ...
            n4(t2.mcp), n4(t2.hA), n3(t2.rmse)));
        P('The cell''s thermal time constant follows from the two:');
        EQ(sprintf('\\tau_{th} = \\frac{m c_p}{hA} = %s\\ \\mathrm{s} \\approx %s\\ \\mathrm{min}', n3(t2.mcp/t2.hA), n3(t2.mcp/t2.hA/60)));
        H('Using h*A in Simulink');
        P(['Convective Heat Transfer block: Area = 1 m^2, heat transfer coefficient = batt_hA. ' ...
           'Connect it between the battery port H and a Controlled/Ideal Temperature Source set ' ...
           'to the chamber temperature.']);
        plot(ax1, t2.t/3600, t2.Tmeas, 'Color',[0.3 0.3 0.3]); hold(ax1,'on');
        plot(ax1, t2.t/3600, t2.Tmodel, '--', 'Color',[0.85 0.33 0.1], 'LineWidth',1.4);
        plot(ax1, t2.t/3600, t2.Tamb, ':', 'Color',[0 0.45 0.74]);
        hold(ax1,'off'); legend(ax1, {'measured cell T','model','chamber'}, 'Location','southwest');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Temperature (°C)'); title(ax1,'Measured vs model temperature');
        plot(ax2, t2.t/3600, t2.Q, 'Color',[0.49 0.18 0.56]);
        xlabel(ax2,'Test time (h)'); ylabel(ax2,'Heat Q (W)'); title(ax2,'Heat generated in the cell');

    % ------------------------------------------------------------------
    case 'T0'
        H('What it is');
        P('The cell temperature at the first sample of the file - the block''s initial cell temperature, in kelvin.');
        EQ(sprintf('T_0 = T_{cell}(t_0) + 273.15 = %s + 273.15 = \\mathbf{%s}\\ \\mathrm{K}', n3(val - 273.15), n3(val)));
        plot(ax1, th, d.Tcell); hold(ax1,'on');
        if any(isfinite(d.Tch)), plot(ax1, th, d.Tch, ':'); end
        k = find(isfinite(d.Tcell), 1);
        if ~isempty(k), plot(ax1, th(k), d.Tcell(k), 'o', 'MarkerFaceColor',[0.85 0.33 0.1]); end
        hold(ax1,'off');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Temperature (°C)'); title(ax1,'Cell temperature');
        one = true;
end

addSources();
render();
if one
    delete(ax2);
    ax1.Layout.Row = [1 2];
end

% =========================================================================
%  explanation blocks
% =========================================================================
    function H(s, kind)
        if nargin < 2, kind = 'h'; end
        B(end+1,:) = {kind, s};
    end
    function P(s, kind)
        if nargin < 2, kind = 'p'; end
        B(end+1,:) = {kind, s};
    end
    function EQ(s)
        B(end+1,:) = {'eq', s};
    end
    function M(lines)
        B(end+1,:) = {'mono', lines};
    end
    function LINK(txt, url)
        B(end+1,:) = {'link', {txt, url}};
    end

    function addSources()
        [S, use] = batterySources(key);
        if isempty(S), return; end
        H('Sources');
        P(['Where the method comes from - click a title to open it. Each line says what that ' ...
           'source shows that is used here. (free) = readable without a subscription.'], 'small');
        for k = 1:numel(S)
            fr = ''; if S(k).free, fr = '  (free)'; end
            LINK([S(k).cite fr], S(k).url);
            P(['   ' char(8594) ' ' use{k}], 'small');
        end
    end

    function hotP()
        h = R.diag.hot;
        if ~isfield(R.diag,'Tref') || ~isfinite(R.diag.Tref), return; end
        P(sprintf(['Temperature: these tables are for %.3g °C (the chamber). A step or rest where ' ...
           'the cell was more than %g K away from that (e.g. right after the fast discharge heated ' ...
           'it) belongs to a different temperature and is left out - the resistances change with ' ...
           'temperature (the reason the block has R(SOC,T) tables). Left out here: %d step(s), %d rest(s).'], R.diag.Tref, R.constants.maxDT, ...
           h.edges, h.fits), warnIf(false));
    end

    function rdcP()
        % how the SOC range between the measured points is filled
        pr = R.diag.prov.(key);
        if any(pr == 'S')
            mr = R.diag.multiRate;
            P(['Between the measured SOC points (where the current never steps or stops) R0 and ' ...
               'the RC resistances cannot be told apart - but their SUM can be measured: once ' ...
               'the RC pairs have settled, a constant-current discharge sits at']);
            EQ('V = V_0(\mathrm{SOC}) - |I|\,R_{dc}(\mathrm{SOC}), \qquad R_{dc} = R_0 + \sum_k R_k');
            P(sprintf(['and the multi-rate fit (see the OCV window) measures R_dc at every SOC from ' ...
               'the %d discharge rates. At the breakpoints marked S the interpolated R0, R1 ... ' ...
               'are scaled by ONE common factor so that they add up to the measured R_dc:'], numel(mr.use)));
            EQ('R_x(s_j) \leftarrow R_x(s_j)\cdot\frac{R_{dc}(s_j)}{R_0(s_j) + \sum_k R_k(s_j)}');
            P(['So the total (what a constant current feels) is measured; only the split between ' ...
               'R0 and the RC pairs is interpolated from the nearest measured points.'], 'small');
            ck = R.diag.rdcCheck;
            if ~isempty(ck)
                P(sprintf(['Cross-check where both exist (measured breakpoints): R0 + sum R_k = %s mOhm ' ...
                    'vs R_dc = %s mOhm.'], strjoin(compose('%.3g', 1000*ck(:,2)), ' / '), ...
                    strjoin(compose('%.3g', 1000*ck(:,3)), ' / ')), 'small');
            end
        else
            P(['Breakpoints with no measurement are interpolated (I); past the last measured ' ...
               'point the end value is held (E).']);
        end
        P('M = measured near this SOC, I = interpolated, E = end value held, S = scaled to the measured R_dc.', 'small');
    end

    function [rs, lab] = rSum()
        rs = R.value.R0_vec; lab = 'R0';
        for q2 = 1:R.nRC
            k2 = sprintf('R%d_vec', q2);
            if R.found.(k2), rs = rs + R.value.(k2); lab = sprintf('%s+R%d', lab, q2); end
        end
        lab = [lab ' (table sum)'];
    end

    function explainOcvMultiRate()
        mr = R.diag.multiRate;
        H('What it is');
        P(['The open-circuit voltage (OCV): the voltage the cell settles to with no current, ' ...
           'as a function of SOC. It is the "fuel gauge" curve of the cell.']);
        H('The model it belongs to');
        P(['The block''s terminal voltage is the OCV minus the drop over R0 minus the voltage ' ...
           'over each RC pair (written here with i = discharge current, positive):']);
        EQ('V = V_0(\mathrm{SOC}) - i\,R_0 - \sum_k R_k\,x_k');
        P(['So the OCV can never be read directly while current flows. This test discharges the ' ...
           'cell from FULL to the cut-off at several rates - which is exactly what is needed to ' ...
           'take the current out of the equation:']);
        H('Step 1 - wait until the RC pairs have settled');
        P(['Right after the current starts, the RC voltages are still building up. Each one ' ...
           'reaches R_k*i with time constant tau_k (from the rest fits), so a sample is used ' ...
           'once what is left of every transient is below 1 mV:']);
        EQ('t \;\ge\; \max_k\ \tau_k\,\ln\!\frac{R_k\,i}{1\ \mathrm{mV}}');
        P(sprintf('Here: %s s for the %s C discharges.', strjoin(compose('%.0f', mr.settle(mr.use)), ' / '), ...
            strjoin(compose('%.2g', mr.crate(mr.use)), ' / ')), 'small');
        P('From then on every branch current equals i, and the model becomes a straight line in i:');
        EQ('V(\mathrm{SOC}, i) = V_0(\mathrm{SOC}) - i\,R_{dc}(\mathrm{SOC}), \qquad R_{dc} = R_0 + \sum_k R_k');
        H('Step 2 - one straight-line fit per 1 % of SOC');
        P(sprintf(['SOC comes from coulomb counting from FULL (see AH), so every discharge can be ' ...
           'lined up on the same SOC axis. At each SOC the average voltage of each discharge ' ...
           '(1 %% SOC bin) is plotted against its current and a straight line is fitted ' ...
           '(least squares). Used: discharges at or below %gC, with the cell within %g K of ' ...
           '%.3g °C (faster ones heat the cell and stop being linear).'], mr.maxCrate, mr.maxDT, mr.Tref));
        EQ('\mathrm{intercept}\ (i = 0) = V_{0,\mathrm{dis}}(\mathrm{SOC}), \qquad \mathrm{slope} = -R_{dc}(\mathrm{SOC})');
        [~, j] = min(abs(mr.sf - 0.5) + 10*~isfinite(mr.ocvD));
        u = mr.use(isfinite(mr.Vd(mr.use, j)));
        if numel(u) >= 2
            P(sprintf('Worked example at SOC %.2f:', mr.sf(j)), 'small');
            L = {sprintf('   %8s  %10s', 'current', 'voltage')};
            for r = u, L{end+1,1} = sprintf('   %7.3g A  %9.4f V', mr.rates(r), mr.Vd(r,j)); end %#ok<AGROW>
            M(L);
            EQ(sprintf('V_{0,\\mathrm{dis}} = %s\\ \\mathrm{V}, \\qquad R_{dc} = %s\\ \\mathrm{m\\Omega}', ...
                n4(mr.ocvD(j)), n3(1000*mr.Rdc(j))));
            if isfinite(mr.rms(j))
                P(sprintf(['The points sit %.2f mV (rms) from the straight line - the linear model ' ...
                   'holds.'], 1000*mr.rms(j)), warnIf(mr.rms(j) > 0.005));
            end
        end
        H('Step 3 - the charge side, then average');
        P(sprintf(['The discharge-side value still carries hysteresis (a cell rests slightly lower ' ...
           'after a discharge than after a charge). The charges give the other side: %s. The ' ...
           'block uses one resistance for both directions, so the same R_dc is used:'], mr.chargeHow));
        EQ('V_{0,\mathrm{chg}} = V_{chg} - i_{chg}\,R_{dc}, \qquad V_0 = \tfrac{1}{2}\left(V_{0,\mathrm{chg}} + V_{0,\mathrm{dis}}\right)');
        if isfinite(mr.hyst)
            P(sprintf(['Half the charge-discharge gap is %.1f mV here. Where only one side exists it ' ...
               'is shifted by that amount.'], 1000*mr.hyst), 'small');
        end
        H('Step 4 - the two ends');
        P(['The first minutes of every discharge are not settled yet, so the very top of the ' ...
           'curve has no multi-rate point; neither does the end of the discharge. There the ' ...
           'relaxed rest voltages are used: after a full charge the cell rests at its SOC 1 ' ...
           'OCV, after the discharge to cut-off at its SOC 0 OCV (see the RC fits). A smooth ' ...
           '(pchip) curve joins them to the multi-rate curve.']);
        P(sprintf('%d rest point(s) were available; inside the multi-rate range they are a check only.', size(p.ocv,1)), 'small');
        H('Table');
        P('M = measured (multi-rate fit or a rest), I = joined between them, E = short extension past the data.', 'small');
        M(tableLines(R.value.SOC_vec, val, R.diag.prov.V0_vec, '%.4f V'));
        % plots
        hold(ax1,'on');
        cols = lines(numel(mr.rates));
        lg = {};
        for r = mr.use
            fm = isfinite(mr.Vd(r,:));
            plot(ax1, mr.sf(fm), mr.Vd(r,fm), '-', 'Color',[cols(r,:) 0.8], 'LineWidth',1);
            lg{end+1} = sprintf('discharge %.2gC (settled)', mr.crate(r)); %#ok<AGROW>
        end
        for q2 = 1:size(mr.Vc,1)
            fm = isfinite(mr.Vc(q2,:));
            plot(ax1, mr.sf(fm), mr.Vc(q2,fm), '-', 'Color',[0.47 0.67 0.19], 'LineWidth',1);
            lg{end+1} = sprintf('charge %.2gC', mr.Ic(q2)/R.value.AH); %#ok<AGROW>
        end
        plot(ax1, mr.sf, mr.ocvD, ':', 'Color',[0.3 0.3 0.3], 'LineWidth',1.4); lg{end+1} = 'V_{0,dis} (i = 0)';
        if ~isempty(p.ocv)
            plot(ax1, p.ocv(:,1), p.ocv(:,2), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerEdgeColor','none');
            lg{end+1} = 'relaxed rest voltage';
        end
        plot(ax1, R.value.SOC_vec, val, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6); lg{end+1} = 'V0 table';
        hold(ax1,'off'); legend(ax1, lg, 'Location','southeast'); xlim(ax1, [-0.02 1.02]);
        xlabel(ax1,'SOC (-)'); ylabel(ax1,'Voltage (V)'); title(ax1,'Every rate on one SOC axis');
        if numel(u) >= 2
            ii = linspace(0, max(mr.rates(u))*1.05, 20);
            plot(ax2, mr.rates(u), mr.Vd(u,j), 'o', 'MarkerFaceColor',[0 0.45 0.74], 'MarkerSize',8); hold(ax2,'on');
            plot(ax2, ii, mr.ocvD(j) - mr.Rdc(j)*ii, '--', 'Color',[0.85 0.33 0.1], 'LineWidth',1.3);
            plot(ax2, 0, mr.ocvD(j), 'p', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerSize',14, 'MarkerEdgeColor','none');
            hold(ax2,'off');
            legend(ax2, {'each discharge at this SOC','straight-line fit','V_{0,dis}: zero current'}, 'Location','northeast');
            xlabel(ax2,'Discharge current (A)'); ylabel(ax2,'Voltage (V)');
            title(ax2, {sprintf('At SOC %.2f: V against current', mr.sf(j)), ...
                sprintf('intercept %.4f V, slope R_{dc} = %.2f m\\Omega', mr.ocvD(j), 1000*mr.Rdc(j))});
        end
    end

    function render()
        n = size(B,1);
        gL = uigridlayout(g, [n 1], 'RowHeight', repmat({'fit'},1,n), 'Scrollable','on', ...
            'Padding',[18 14 14 14], 'RowSpacing',7, 'BackgroundColor',[0.985 0.985 0.99]);
        gL.Layout.Row = 1; gL.Layout.Column = 1;
        for k = 1:n
            s = B{k,2};
            switch B{k,1}
                case 'title'
                    uilabel(gL,'Text',s,'FontSize',20,'FontWeight','bold','FontColor',[0.1 0.15 0.3]);
                case 'meta'
                    uilabel(gL,'Text',s,'FontSize',12,'FontColor',[0.35 0.35 0.4],'WordWrap','on');
                case 'h'
                    uilabel(gL,'Text',s,'FontSize',14,'FontWeight','bold','FontColor',[0 0.33 0.6]);
                case 'p'
                    uilabel(gL,'Text',s,'FontSize',13,'WordWrap','on');
                case 'small'
                    uilabel(gL,'Text',s,'FontSize',12,'FontColor',[0.35 0.35 0.4],'WordWrap','on', ...
                        'FontAngle','italic');
                case 'warn'
                    uilabel(gL,'Text',[char(9888) ' ' s],'FontSize',13,'FontColor',[0.75 0.35 0], ...
                        'FontWeight','bold','WordWrap','on');
                case 'eq'
                    uilabel(gL,'Text',['$$' s '$$'],'Interpreter','latex','FontSize',15, ...
                        'HorizontalAlignment','center');
                case 'mono'
                    uilabel(gL,'Text',s,'FontName','Consolas','FontSize',12, ...
                        'BackgroundColor','w');
                case 'link'
                    uihyperlink(gL,'Text',s{1},'URL',s{2},'FontSize',12,'WordWrap','on', ...
                        'Tooltip',s{2});

            end
        end
    end
end

% =========================================================================
function e = exampleEdge(R)
% the current step closest to SOC 0.5
e = [];
d = R.d; k = R.diag.edgeIdx;
if isempty(k), return; end
[~, j] = min(abs(d.soc(k) - 0.5));
k = k(j);
e.k = k; e.t = d.t(k); e.soc = d.soc(k);
e.dV = d.V(k+1) - d.V(k); e.dI = d.I(k+1) - d.I(k); e.R0 = e.dV/e.dI;
end

function f = exampleFit(R)
% the relaxation fit closest to SOC 0.5
f = [];
fits = R.diag.fits;
if isempty(fits), return; end
[~, k] = min(abs([fits.soc] - 0.5));
f = fits(k);
end

function plotExampleRelaxation(ax, R, q, showVinf)
f = exampleFit(R);
if isempty(f), title(ax,'No relaxation fits'); return; end
plot(ax, f.tr/60, f.v, '.', 'Color',[0.4 0.4 0.4]); hold(ax,'on');
plot(ax, f.tr/60, f.vfit, '-', 'Color',[0.85 0.33 0.1], 'LineWidth',1.5);
yline(ax, f.Vinf, '--', sprintf('V_\\infty = %.4f V', f.Vinf));
hold(ax,'off');
legend(ax, {'measured','fit'}, 'Location','best');
xlabel(ax,'Time since current stopped (min)'); ylabel(ax,'Voltage (V)');
if showVinf
    title(ax, sprintf('Example rest at SOC %.2f: it settles to V_\\infty (an OCV point)', f.soc));
else
    s = sprintf('R_%d = %.3f m\\Omega, \\tau_%d = %.1f s', q, 1000*f.R(min(q,end)), q, f.tau(min(q,end)));
    title(ax, {sprintf('Example relaxation at SOC %.2f', f.soc), ...
        sprintf('%s, fit rms %.2f mV', s, 1000*f.rmse)});
end
end

function plotExampleEdge(ax, R, e)
d = R.d;
if isempty(e), title(ax,'No current steps'); return; end
k = e.k;
w = abs(d.t - d.t(k+1)) <= 30;
tt = d.t(w) - d.t(k+1);
yyaxis(ax,'left');
plot(ax, tt, d.V(w), '.-'); ylabel(ax,'Voltage (V)');
yyaxis(ax,'right');
stairs(ax, tt, d.I(w)); ylabel(ax,'Current (A, + = charge)');
xlabel(ax,'Time from the first sample after the step (s)');
title(ax, sprintf('Example step: \\DeltaV = %.1f mV, \\DeltaI = %.3f A  \\rightarrow  R_0 = %.3f m\\Omega', ...
    1000*e.dV, e.dI, 1000*e.R0));
end

function L = tableLines(g, v, prov, fmt)
L = {sprintf('   %6s   %-14s %s', 'SOC', 'value', 'source')};
for j = 1:numel(g)
    pj = ' '; if numel(prov) >= j, pj = prov(j); end
    L{end+1,1} = sprintf(['   %6.3f   ' fmt '     %c'], g(j), v(j), pj); %#ok<AGROW>
end
end

function k = warnIf(tf)
if tf, k = 'warn'; else, k = 'p'; end
end

function s = n3(x), s = sprintf('%.3g', x); end
function s = n4(x), s = sprintf('%.4g', x); end
function s = n5(x), s = sprintf('%.5g', x); end
function s = p4(x)           % for after a minus sign: (-1.23)
if x < 0, s = ['(' n4(x) ')']; else, s = n4(x); end
end

function s = vecStr(v)
s = ['[' strjoin(arrayfun(@(x) sprintf('%.4g', x), v, 'UniformOutput', false), ' ') ']'];
end

function styleAxes(a)
a.FontName = 'Segoe UI'; a.FontSize = 11; a.Box = 'on';
grid(a,'on'); a.GridAlpha = 0.12;
a.Title.FontWeight = 'bold';
end
