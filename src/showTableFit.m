function fig = showTableFit(R, key)
%SHOWTABLEFIT  "Fit vs data": the saved Table-Based values against the test.
%
%   showTableFit(R)        R = Modeling tab result (after Extract)
%   showTableFit(R, key)   opened from a box's How? (key = 'V0_vec', 'R1_vec', ...)
%
%   Left: what the whole-test fit does and why (plain words), and every
%   charge / discharge / rest with the error at its start, end, lowest and
%   highest point. Right: the measured voltage with the model on top, the
%   difference in mV, and the cell temperature. The model is
%   simulateTableBased: the Table-Based block's own equations in MATLAB, with
%   the block's thermal mass and the Convective Heat Transfer block, i.e. what
%   your Simulink model computes with these batt_* values.

fig = [];
if nargin < 2, key = ''; end
if isempty(R) || ~isfield(R, 'fit'), return; end
F = R.fit; f = F.fit; sim = f.sim;
t = f.t/3600; V = f.V; Vs = sim.V; e = 1000*(Vs - V);
ph = f.phases; n = size(ph,1);

% ------------------------------------------------------------- key points
rows = cell(n, 8);
for p = 1:n
    k = ph(p,1):ph(p,2);
    Im = median(f.I(k));
    if abs(Im) < 1e-3, lab = 'Rest';
    elseif Im > 0, lab = sprintf('Charge %.2gC', Im/F.AH);
    else, lab = sprintf('Discharge %.2gC', -Im/F.AH); end
    rows(p,:) = {p, lab, V(k(end)), e(k(1)), e(k(end)), 1000*(min(Vs(k)) - min(V(k))), ...
        1000*(max(Vs(k)) - max(V(k))), rms(e(k))};
end

fig = uifigure('Name', ['Whole-test fit - ' R.d.name], 'Color', 'w');
fig.Position(3:4) = [1450 880]; movegui(fig, 'center');
g = uigridlayout(fig, [1 2], 'ColumnWidth', {520, '1x'}, 'Padding', [8 8 8 8]);
gl = uigridlayout(g, [2 1], 'RowHeight', {'1x', 330}, 'Padding', [0 0 0 0]);
h = uihtml(gl);
dis = find(contains(rows(:,2), 'Discharge'));
dend = cell2mat(rows(dis, 3)) + cell2mat(rows(dis, 5))/1000;
taus = arrayfun(@(q) F.(sprintf('tau%d',q))(1), 1:F.nRC);
focus = '';
if ~isempty(key), focus = sprintf('<p style="background:#eef4fb;padding:6px">You opened this from <b>%s</b>. Below this window you also get the step-by-step first estimate it started from.</p>', key); end
h.HTMLSource = ['<html><body style="font-family:Segoe UI,Arial;font-size:13px;line-height:1.45;margin:4px 10px">' ...
    sprintf('<h3 style="margin:2px 0">%s &ndash; the saved values against the test</h3>', esc(R.d.name)) focus ...
    sprintf(['<p><b>%.0f mV rms</b> over the whole test, temperature <b>%.1f K rms</b>.<br>Start of the test: <b>%+.0f mV</b>. ' ...
    'Every discharge ends at <b>%s V</b> (the cell: 2.50 V).</p>'], f.rmsSim_mV, f.rmsT_K, e(1), ...
    strjoin(compose('%.3f', dend'), ' / ')) ...
    '<p><b>What Extract does.</b> First every value is measured where the test shows it (the <i>How?</i> windows). ' ...
    'Put into Simulink as they are, those pieces miss in three places: the start (the OCV near empty came from rests that end ' ...
    'while the cell is still recovering), the slow recovery after every discharge, and the end of the fast discharge ' ...
    '(one resistance measured at low current is far too high at the max rate, so the model fell to ~0.5 V).</p>' ...
    '<p>So step 2 chooses every table number so that <b>the block''s own equations, driven by the measured current, give the ' ...
    'measured voltage over the whole test</b> (one least-squares solve; only the time constants are searched). Then m&middot;cp and ' ...
    'h&middot;A are fitted with the block''s own heat, and the tables are solved again at the temperature the block computes, so ' ...
    'tables and simulated temperature agree.</p>' ...
    sprintf(['<p><b>Shapes</b> (kept simple on purpose): V0 over SOC; R0 over SOC &times; T (%d temperatures, %s &deg;C) &ndash; the fast ' ...
    'discharge heats the cell to ~60 &deg;C and the hot cell''s lower R0 is what stops it at 2.5 V; %d RC pairs over SOC, ' ...
    'growing towards empty (&tau; = %s s); m&middot;cp = %.1f J/K, h&middot;A = %.4f W/K.</p>'], numel(F.T_vec), ...
    strjoin(compose('%g', F.T_vec - 273.15), ', '), F.nRC, strjoin(compose('%.3g', taus), ', '), F.thermal_mass, F.hA) ...
    '<p style="color:#555">Code: src/fitTableBased.m (the fit), src/simulateTableBased.m (the block''s equations). ' ...
    'Curves on the right: measured (black), these values through the block (blue dashed).</p></body></html>'];
tb = uitable(gl, 'Data', rows, 'ColumnName', {'#','Phase','V end (meas)','start mV','end mV','lowest mV','highest mV','rms mV'}, ...
    'ColumnFormat', {'numeric','char','short','bank','bank','bank','bank','bank'}, 'RowName', {});
tb.ColumnWidth = {28, 115, 70, 55, 55, 60, 65, 55};

gr = uigridlayout(g, [3 1], 'RowHeight', {'2x','1x','1x'}, 'Padding', [0 0 0 0]);
a1 = uiaxes(gr); hold(a1, 'on');
plot(a1, t, V, 'k', 'LineWidth', 1.4, 'DisplayName', 'Measured');
plot(a1, t, Vs, '--', 'Color', [0.165 0.471 0.839], 'LineWidth', 1.3, 'DisplayName', 'Table-Based block (these values)');
ylabel(a1, 'Voltage (V)'); legend(a1, 'Location', 'southwest'); grid(a1, 'on');
title(a1, 'Voltage: measured and the block with the saved values');
a2 = uiaxes(gr);
plot(a2, t, e, 'Color', [0.165 0.471 0.839]); yline(a2, 0, 'Color', [0.5 0.5 0.5]);
ylabel(a2, 'Model - measured (mV)'); grid(a2, 'on'); ylim(a2, [-1 1]*max(50, min(300, prctile(abs(e), 99.5))));
a3 = uiaxes(gr); hold(a3, 'on');
plot(a3, t, f.Tcell, 'k', 'LineWidth', 1.4, 'DisplayName', 'Measured');
plot(a3, t, sim.T_C, '--', 'Color', [0.165 0.471 0.839], 'LineWidth', 1.3, 'DisplayName', 'Block');
plot(a3, t, f.Tch, ':', 'Color', [0.55 0.55 0.55], 'DisplayName', 'Chamber');
ylabel(a3, 'Cell T (°C)'); xlabel(a3, 'Test time (h)'); legend(a3, 'Location', 'northwest'); grid(a3, 'on');
linkaxes([a1 a2 a3], 'x'); xlim(a1, [0 t(end)]);
end

function s = esc(s)
s = strrep(strrep(strrep(char(s), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
end
