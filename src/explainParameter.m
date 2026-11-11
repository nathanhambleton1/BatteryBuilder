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
    case 'T_vec'
        Tc = R.T_C;
        if isempty(R.byT)
            P(R.note.T_vec); one = true;
            title(ax1, 'One temperature in this file');
        else
        H('What it is');
        P(['The temperature breakpoints (K) of every SOC table. With "Tabulate parameters over ' ...
           'temperature" = Yes the block takes V0, R0, R1, tau1 ... as matrices: one ROW per SOC ' ...
           'breakpoint, one COLUMN per temperature, and interpolates linearly in both.']);
        H('Why this file has two');
        P(sprintf(['The chamber schedule runs every CHARGE at %.3g °C and every DISCHARGE at %.3g °C. ' ...
           'Resistances change a lot with temperature, so each column is built only from the data ' ...
           'taken with the cell within %g K of that temperature:'], R.byT{3-R.iPrim}.T_C, ...
           R.byT{R.iPrim}.T_C, R.constants.maxDT));
        P(sprintf(['%.3g °C (discharges): R0 and the RC pairs from the start of each discharge ' ...
           '(SOC 1, from a rest), OCV and R_dc from the discharges at several rates, capacity, thermal ' ...
           'values.'], R.byT{R.iPrim}.T_C), 'small');
        P(sprintf(['%.3g °C (charges): R0 and the RC pairs from the start of each charge (near SOC 0, ' ...
           'from a rest), R_dc = (V - V0)/I from the CC part of the charges. There are no discharges at ' ...
           'this temperature, so the OCV is taken from the other column (it changes only a few mV with ' ...
           'temperature); a table that cannot be measured here is copied from the other temperature ' ...
           '(its note says COPIED).'], R.byT{3-R.iPrim}.T_C), 'small');
        H('Value');
        M({sprintf('T_vec = %s K   (= %s °C)', mat2str(val, 5), mat2str(Tc, 3))});
        if any(isfinite(d.Tch)), plot(ax1, th, d.Tch, 'LineWidth',1.2, 'DisplayName','chamber'); hold(ax1,'on'); end
        if any(isfinite(d.Tcell)), plot(ax1, th, d.Tcell, 'LineWidth',1.0, 'DisplayName','cell'); hold(ax1,'on'); end
        for j = 1:numel(Tc)
            yline(ax1, Tc(j), '--', sprintf('%.3g °C', Tc(j)), 'HandleVisibility','off');
            yline(ax1, Tc(j) + R.constants.maxDT*[-1 1], ':', 'Color',[0.6 0.6 0.6], 'HandleVisibility','off');
        end
        hold(ax1,'off'); legend(ax1,'Location','best');
        xlabel(ax1,'Test time (h)'); ylabel(ax1,'Temperature (°C)'); title(ax1,'Chamber schedule and the two table temperatures');
        one = true;
        end

    % ------------------------------------------------------------------
    case 'V0_vec'
        explainOcv();

    % ------------------------------------------------------------------
    case 'R0_vec'
        dy = R.diag.dyn; on = dy.on;
        u = find([on.used]);
        H('What it is');
        P(['The series (ohmic) resistance: the part of the voltage change that appears the ' ...
           'instant the current changes - electrolyte, contacts, tabs.']);
        H('Where it is measured');
        P(sprintf(['At every charge or discharge that starts after a rest of at least %g min. The cell ' ...
           'was at rest, so its voltage V_rest is steady and every RC pair is empty. The cycler logs the ' ...
           'first sample a few hundredths of a second after the switch; in that time only R0 can ' ...
           'respond (an RC pair''s capacitor needs time to charge):'], R.constants.minRestS/60));
        EQ('R_0 = \frac{V_{first} - V_{rest}}{I}');
        P(sprintf(['I is the step''s constant current (the median of its first samples): a first ' ...
           'reading can spike - e.g. 0.34 A logged for a 0.265 A step - while the voltage follows the ' ...
           'real current. Used when the first sample is within %g s of the switch and the cell is ' ...
           'within %g K of %.3g °C.'], R.constants.maxEdgeDt, R.constants.maxDT, R.T_C));
        e = [];
        if ~isempty(u)
            [~, m] = min(abs([on(u).crate] - 0.5)); e = on(u(m));
            H('Worked example');
            P(sprintf('%.3g A step (%.2gC) at SOC %.3f, after a %.0f min rest; first sample %.3g s after the switch:', ...
                abs(e.I), e.crate, e.soc, e.restDur/60, e.dt1), 'small');
            EQ(sprintf('R_0 = \\frac{%s - %s}{%s} = %s\\ \\mathrm{m\\Omega}', n5(R.d.V(e.a)), n5(e.Vrest), ...
                p4(e.I), n3(1000*e.R0)));
        end
        H('Every step from rest');
        L = {sprintf('   %6s %8s %6s %8s %8s %6s %8s   %s', 'SOC', 'I (A)', 'C', 'rest', 'first', 'T °C', 'R0 mOhm', 'used?')};
        for i = 1:numel(on)
            if on(i).used, us = 'yes'; else, us = ['no: ' on(i).why]; end
            L{end+1} = sprintf('   %6.3f %8.4g %6.2f %5.0fmin %7.3gs %6.3g %8.2f   %s', on(i).soc, on(i).I, ...
                on(i).crate, on(i).restDur/60, on(i).dt1, on(i).T, 1000*on(i).R0, us); %#ok<AGROW>
        end
        M(L);
        if numel(u) >= 2 && max([on(u).R0]) > 1.15*min([on(u).R0])
            P(sprintf(['R0 is not the same at every current here (%.3g .. %.3g mOhm): at low ' ...
               'temperature the cell''s resistance falls as the current rises. The block has one R0 per ' ...
               'SOC, so the table takes the median.'], 1000*min([on(u).R0]), 1000*max([on(u).R0])), 'small');
        end
        H('The table');
        msoc = unique(round([on(u).soc]*20)/20);
        if numel(msoc) == 1
            P(sprintf(['A rate test only starts from rest at one SOC per temperature (here about %.2f), ' ...
               'so R0 is measured there only and that value is held at every SOC. Nothing else in the test ' ...
               'shows R0 on its own (the current never jumps in the middle of the SOC range); what a ' ...
               'constant current feels beyond R0 is put in the RC pairs (see R1).'], msoc));
        else
            P('Median per measured SOC, straight line between them, end values held.');
        end
        P('M = measured near this SOC, I = straight line between measured SOCs, E = end value held.', 'small');
        M(tableLines(R.value.SOC_vec, val*1000, R.diag.prov.R0_vec, '%.3f mOhm'));
        if ~isempty(u)
            scatter(ax1, [on(u).soc], 1000*[on(u).R0], 30, [0.85 0.33 0.1], 'filled'); hold(ax1,'on');
        end
        plot(ax1, R.value.SOC_vec, val*1000, '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6);
        hold(ax1,'off'); legend(ax1, {'each step from rest','R0 table'}, 'Location','best');
        xlim(ax1,[-0.02 1.02]); xlabel(ax1,'SOC (-)'); ylabel(ax1,'R0 (m\Omega)'); title(ax1,'R0 vs SOC');
        plotStep(ax2, R, e);

    % ------------------------------------------------------------------
    case {'R1_vec','R2_vec','R3_vec','tau1_vec','tau2_vec','tau3_vec'}
        q = str2double(key(regexp(key,'\d','once')));
        isTau = startsWith(key,'tau');
        cl = R.diag.dyn.clusters;
        H('What it is');
        P(sprintf(['RC pair %d models a voltage change that takes time - charge transfer and ' ...
           'diffusion inside the cell. R%d is how big it is per amp, tau%d how fast it builds up (s). ' ...
           'Pairs are numbered fastest first: tau1 < tau2 < tau3.'], q, q, q));
        H('Where it is measured: right after a step from rest');
        P(['After a rest every RC pair is empty. When a constant current I starts, R0 responds at once ' ...
           '(see R0) and each pair then fills up with its own time constant. The OCV also moves a ' ...
           'little as charge goes in or out (slope s, V per Ah). So the block''s voltage is']);
        EQ('V(t) = V_{rest} + I\left[R_0 + \sum_k R_k\left(1 - e^{-t/\tau_k}\right)\right] + s\,\frac{I\,t}{3600}');
        P(sprintf(['Dividing by I gives the resistance the cell shows t seconds after the step - the ' ...
           'top plot, straight from the data. Used: the first %g s (at most %g %% of SOC) after each ' ...
           'step from rest at %.3g °C, rates up to %gC.'], R.constants.onsetMaxS, 100*R.constants.onsetMaxDSOC, ...
           R.T_C, R.constants.mrMaxCrate));
        EQ('\frac{V(t) - V_{rest}}{I} = R_0 + \sum_k R_k\left(1 - e^{-t/\tau_k}\right) + s\,\frac{t}{3600}');
        H('The fit');
        P(['All steps at the same SOC are fitted together. They share the time constants tau_k and the ' ...
           'OCV slope s (same cell, same SOC); each step gets its own R_k, because the cell''s resistance ' ...
           'can depend on the current and the block''s cannot. For given tau_k the equation is linear in ' ...
           'R_k and s (all >= 0), so those come from least squares; the tau_k are searched on a log grid ' ...
           'and refined.']);
        if isempty(cl)
            P(R.note.(key), 'warn');
        else
            c = cl(end);
            H('How many RC pairs?');
            P('The same steps fitted with 1, 2 and 3 pairs (rms voltage error over all of them):', 'small');
            L = {sprintf('   %6s  %10s  %s', 'pairs', 'rms (mV)', 'tau (s)')};
            for n = 1:3
                L{end+1} = sprintf('   %6d  %10.2f  %s', n, 1000*c.rmsN(n), mat2str(round(c.fitsN{n}.tau, 3, 'significant'))); %#ok<AGROW>
            end
            M(L);
            P(['Each extra pair should cut the error clearly; when it hardly does, the data cannot ' ...
               'separate it from the others and fewer pairs is the better choice.'], 'small');
            H(sprintf('Result with %d pair(s), SOC %.2f', R.nRC, c.soc));
            L = {sprintf('   %8s %6s %8s', 'I (A)', 'C', 'R0')};
            for k2 = 1:R.nRC, L{1} = [L{1} sprintf(' %8s', sprintf('R%d', k2))]; end
            L{1} = [L{1} '  (mOhm)  rms mV'];
            for i = 1:numel(c.tr)
                Li = sprintf('   %8.4g %6.2f %8.2f', c.tr(i).I, abs(c.tr(i).I)/R.diag.soc.cap, 1000*c.tr(i).R0);
                for k2 = 1:R.nRC, Li = [Li sprintf(' %8.2f', 1000*c.tr(i).R(k2))]; end %#ok<AGROW>
                L{end+1} = [Li sprintf('          %6.2f', 1000*c.tr(i).rms)]; %#ok<AGROW>
            end
            M(L);
            EQ(sprintf('\\tau = %s\\ \\mathrm{s}, \\qquad s = %s\\ \\mathrm{V/Ah}', mat2str(round(c.tau, 3, 'significant')), n3(c.s)));
            P(sprintf('The table takes the median R_k of these steps: R%d = %.3g mOhm at SOC %.2f.', ...
                q, 1000*c.R(q), c.soc));
            tot = [c.tr.R0] + sum(vertcat(c.tr.R), 2)';
            if numel(c.tr) >= 2 && max(tot) > 1.3*min(tot)
                P(['The steps do not agree on R_k: the higher the current, the lower the resistance. ' ...
                   'That is the cell (strongest at low temperature), not the fit - a linear model such as ' ...
                   'this block can only match one current exactly, and the median sits in the middle.'], 'small');
            end
        end
        H('From one SOC to the whole table');
        rdcP();
        if isTau
            M(tableLines(R.value.SOC_vec, val, R.diag.prov.(key), '%.1f s'));
        else
            M(tableLines(R.value.SOC_vec, val*1000, R.diag.prov.(key), '%.3f mOhm'));
        end
        plotOnsets(ax1, R);
        plotRdc(ax2, R, key);

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

    function rdcP()
        % how the RC tables get from the step SOC to every SOC
        rd = R.diag.rdc;
        pr = R.diag.prov.(key);
        if any(pr == 'S')
            P(['A step from rest only happens at one SOC, but the TOTAL resistance a constant current ' ...
               'feels once the RC pairs have filled up is measured at almost every SOC:']);
            EQ('R_{dc}(\mathrm{SOC}) = R_0 + \sum_k R_k');
            P(sprintf('Here it comes from %s (median of the 1 %% SOC points nearest each breakpoint).', rd.src));
            if ~isempty(rd.charge)
                P(['At this temperature there are only charges, so R_dc = (V_charge - V0)/I. This R_dc ' ...
                   'also holds the gap between the charge and the discharge OCV (hysteresis), which the ' ...
                   'block does not have - with it the model charges at the measured voltage.'], 'small');
            end
            P(['At every breakpoint where R_dc is measured (S), all R_k are scaled by ONE factor f so the ' ...
               'sum comes out right; the time constants and the split between the pairs stay as the step fit ' ...
               'found them. Between the step SOC (f = 1) and the R_dc points f goes in a straight line.']);
            EQ('R_k(s_j) = f_j\,R_{k,\mathrm{step}}, \qquad f_j = \frac{R_{dc}(s_j) - R_0(s_j)}{\sum_k R_{k,\mathrm{step}}}');
            if isfield(rd, 'f')
                L = {sprintf('   %6s  %10s  %10s  %6s', 'SOC', 'R_dc mOhm', 'R0 mOhm', 'f')};
                for j = 1:numel(R.value.SOC_vec)
                    L{end+1} = sprintf('   %6.3f  %10.2f  %10.2f  %6.3f', R.value.SOC_vec(j), 1000*rd.grid(j), ...
                        1000*R.value.R0_vec(j), rd.f(j)); %#ok<AGROW>
                end
                M(L);
            end
        else
            P('No R_dc at this temperature: the step values are held at every SOC (E).');
        end
        P('M = measured at a step, S = scaled to R_dc, I = interpolated, E = end value held.', 'small');
    end

    function [rs, lab] = rSum()
        rs = R.value.R0_vec; lab = 'R0';
        for q2 = 1:R.nRC
            k2 = sprintf('R%d_vec', q2);
            if R.found.(k2), rs = rs + R.value.(k2); lab = sprintf('%s+R%d', lab, q2); end
        end
        lab = [lab ' (tables)'];
    end

    function plotRdc(ax, R, key)
        if startsWith(key, 'tau')
            plot(ax, R.value.SOC_vec, R.value.(key), '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6);
            xlim(ax,[-0.02 1.02]); xlabel(ax,'SOC (-)'); ylabel(ax,'\tau (s)'); title(ax, [strrep(key,'_vec','') ' table']);
            return
        end
        rd = R.diag.rdc; hs = []; lg = {};
        if ~isempty(rd.pts)
            hs(end+1) = plot(ax, rd.pts(:,1), 1000*rd.pts(:,2), '.', 'Color',[0.6 0.6 0.6]); hold(ax,'on');
            lg{end+1} = 'R_{dc} measured (1 % SOC)';
        end
        [rs, lab] = rSum();
        hs(end+1) = plot(ax, R.value.SOC_vec, 1000*rs, '-o', 'Color',[0.85 0.33 0.1], 'LineWidth',1.4); hold(ax,'on');
        lg{end+1} = lab;
        hs(end+1) = plot(ax, R.value.SOC_vec, 1000*R.value.(key), '-s', 'Color',[0 0.45 0.74], 'LineWidth',1.6);
        lg{end+1} = [strrep(key,'_vec','') ' table'];
        hold(ax,'off'); legend(ax, hs, lg, 'Location','best');
        xlim(ax,[-0.02 1.02]); xlabel(ax,'SOC (-)'); ylabel(ax,'Resistance (m\Omega)');
        title(ax, 'Tables vs the measured total R_{dc}');
    end

    function explainOcv()
        mr = R.diag.multiRate;
        H('What it is');
        P(['The open-circuit voltage (OCV): the voltage the cell settles to with no current, ' ...
           'as a function of SOC. It is the "fuel gauge" curve of the cell.']);
        if ~isfield(mr, 'rates') || isempty(mr.rates)
            P(R.note.V0_vec, 'warn'); one = true; return
        end
        H('The idea: the same discharge at several currents');
        P('Once the RC pairs have filled up after the step, a constant discharge current i sits at');
        EQ('V(\mathrm{SOC}, i) = V_0(\mathrm{SOC}) - i\,R_{dc}(\mathrm{SOC}), \qquad R_{dc} = R_0 + \sum_k R_k');
        P(['- a straight line in i. Every discharge starts from FULL, so SOC is known exactly and the ' ...
           'discharges can be lined up on one SOC axis. At each SOC the line through them gives']);
        EQ('\mathrm{intercept}\ (i = 0) = V_0(\mathrm{SOC}), \qquad \mathrm{slope} = -R_{dc}(\mathrm{SOC})');
        H('Step 1 - wait until the RC pairs have filled up');
        P(['The first minutes of each discharge are left out, until what is left of each pair''s ' ...
           'transient is below 1 mV (R_k, tau_k from the 3-pair fit of the steps at SOC 1 - always 3, ' ...
           'so the OCV does not change with the number of pairs you pick):']);
        EQ('t \;\ge\; \max_k\ \tau_k\,\ln\!\frac{R_k\,i}{1\ \mathrm{mV}}');
        L = {sprintf('   %8s %6s %10s %10s   %s', 'current', 'C', 'wait (s)', 'dur (s)', 'used?')};
        for r = 1:numel(mr.rates)
            if ismember(r, mr.use)
                us = 'yes';
                if r <= numel(mr.hot) && mr.hot(r) > 0
                    us = sprintf('yes, %.0f %% of it left out (cell > %g K from %.3g °C)', 100*mr.hot(r), mr.maxDT, mr.Tref);
                end
            elseif mr.crate(r) > mr.maxCrate
                us = sprintf('no: faster than %gC (V no longer linear in i, cell heats up)', mr.maxCrate);
            else
                us = 'no: never settled within the temperature window';
            end
            L{end+1} = sprintf('   %7.4g A %6.2f %10.0f %10.0f   %s', mr.rates(r), mr.crate(r), mr.settle(r), mr.dur(r), us); %#ok<AGROW>
        end
        M(L);
        H('Step 2 - a straight line per 1 % of SOC');
        if ~mr.ok
            P(R.note.V0_vec, 'warn'); one = true; return
        end
        [~, j] = min(abs(mr.sf - 0.5) + 10*~isfinite(mr.ocvD));
        u = mr.use(isfinite(mr.Vd(mr.use, j)));
        P(sprintf('Worked example at SOC %.2f (lower plot):', mr.sf(j)), 'small');
        L = {sprintf('   %8s  %10s', 'current', 'voltage')};
        for r = u, L{end+1,1} = sprintf('   %7.4g A  %9.4f V', mr.rates(r), mr.Vd(r,j)); end %#ok<AGROW>
        M(L);
        EQ(sprintf('V_0 = %s\\ \\mathrm{V}, \\qquad R_{dc} = %s\\ \\mathrm{m\\Omega}', n4(mr.ocvD(j)), n3(1000*mr.Rdc(j))));
        P(['This is the discharge-side OCV. A cell rests a little higher after a charge (hysteresis); ' ...
           'the block has one OCV, and this one makes the discharges come out right.'], 'small');
        H('Step 3 - the two ends');
        P(sprintf(['The very top (still settling) and the very bottom have no line. There the voltage at ' ...
           'the end of every rest of at least %g h is used - by then the cell has relaxed to its OCV ' ...
           '(orange dots: after a full charge at SOC 1, after a discharge near SOC 0). A smooth ' ...
           '(pchip) curve joins them to the line. The table is forced to rise with SOC.'], R.constants.ocvRestS/3600));
        rp = R.diag.ocvRest;
        if ~isempty(rp)
            L = {sprintf('   %6s  %9s  %7s', 'SOC', 'V (V)', 'T °C')};
            for i = 1:size(rp,1), L{end+1} = sprintf('   %6.3f  %9.4f  %7.3g', rp(i,1), rp(i,2), rp(i,3)); end %#ok<AGROW>
            M(L);
            P(['The rests after a discharge end at 25 °C (the chamber goes back for the next charge); the ' ...
               'OCV changes only a few mV with temperature.'], 'small');
        end
        H('Table');
        P('M = measured (line or rest), I = joined between them, E = short extension past the data.', 'small');
        M(tableLines(R.value.SOC_vec, val, R.diag.prov.V0_vec, '%.4f V'));
        % plots
        hold(ax1,'on'); cols = lines(numel(mr.rates)); lg = {};
        for r = mr.use
            fm = isfinite(mr.Vd(r,:));
            plot(ax1, mr.sf(fm), mr.Vd(r,fm), '-', 'Color',cols(r,:), 'LineWidth',1);
            lg{end+1} = sprintf('%.2gC discharge (settled)', mr.crate(r)); %#ok<AGROW>
        end
        plot(ax1, mr.sf, mr.ocvD, ':', 'Color',[0.3 0.3 0.3], 'LineWidth',1.4); lg{end+1} = 'line at i = 0';
        if ~isempty(rp)
            plot(ax1, rp(:,1), rp(:,2), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerEdgeColor','none');
            lg{end+1} = 'end of a long rest';
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
            legend(ax2, {'each discharge at this SOC','straight line','V_0: zero current'}, 'Location','northeast');
            xlabel(ax2,'Discharge current (A)'); ylabel(ax2,'Voltage (V)');
            title(ax2, {sprintf('At SOC %.2f: V against current', mr.sf(j)), ...
                sprintf('intercept %.4f V, slope R_{dc} = %.2f m\\Omega', mr.ocvD(j), 1000*mr.Rdc(j))});
        else
            one = true;
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
function plotStep(ax, R, e)
% the raw samples around one step from rest: the jump is R0*I
d = R.d;
if isempty(e), title(ax,'No usable step from rest'); return; end
w = d.t >= e.tsw - 65 & d.t <= e.tsw + 3;
tt = d.t(w) - e.tsw;
plot(ax, tt, d.V(w), '.-', 'Color',[0.3 0.3 0.3], 'MarkerSize',12); hold(ax,'on');
plot(ax, d.t(e.a) - e.tsw, d.V(e.a), 'o', 'MarkerFaceColor',[0.85 0.33 0.1], 'MarkerEdgeColor','none', 'MarkerSize',9);
plot(ax, d.t(e.a-1) - e.tsw, e.Vrest, 's', 'MarkerFaceColor',[0 0.45 0.74], 'MarkerEdgeColor','none', 'MarkerSize',9);
xline(ax, 0, ':', 'switch', 'HandleVisibility','off');
hold(ax,'off');
legend(ax, {'measured','first sample','last rest sample'}, 'Location','best');
xlabel(ax,'Time from the switch (s)'); ylabel(ax,'Voltage (V)');
title(ax, sprintf('Example step: %.1f mV at %.4g A  \\rightarrow  R_0 = %.2f m\\Omega', ...
    1000*(d.V(e.a) - e.Vrest), e.I, 1000*e.R0));
end

function plotOnsets(ax, R)
% (V - V_rest)/I after every step from rest: the resistance the cell shows
% t seconds after the step (dots) and the fit (lines)
cl = R.diag.dyn.clusters;
if isempty(cl), title(ax,'No usable step from rest'); return; end
c = cl(end);
cols = lines(numel(c.tr)); lg = {};
for i = 1:numel(c.tr)
    tr = c.tr(i);
    plot(ax, tr.t, 1000*tr.rMeas, '.', 'Color',cols(i,:), 'MarkerSize',10); hold(ax,'on');
    lg{end+1} = sprintf('%.3g A measured', tr.I); %#ok<AGROW>
end
for i = 1:numel(c.tr)
    tr = c.tr(i);
    plot(ax, tr.t, 1000*tr.rFit, '-', 'Color',cols(i,:), 'LineWidth',1.2, 'HandleVisibility','off');
end
hold(ax,'off'); ax.XScale = 'log';
legend(ax, lg, 'Location','northwest');
xlabel(ax,'Time after the step (s, log scale)'); ylabel(ax,'(V - V_{rest}) / I  (m\Omega)');
title(ax, {sprintf('Steps from rest at SOC %.2f: dots measured, lines fit (%d pair(s))', c.soc, R.nRC), ...
    sprintf('\\tau = %s s, rms %.2f mV', mat2str(round(c.tau, 3, 'significant')), 1000*c.rms)});
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
