function makeExplainerFrames(outDir)
%MAKEEXPLAINERFRAMES  Frames + narration for the "Modeling tab explained" video.
%
%   makeExplainerFrames(outDir)
%
%   Runs the real extraction (extractCellParameters, exactly what the Modeling
%   tab's Extract button does) on synthetic test files that follow the real
%   test: five 0.34C CC-CV charges at 25 °C, 0.1 / 0.2 / 0.5 / 1 / 5C
%   discharges at the file's test temperature, ~70 h. Every number in the
%   pictures and in the narration comes from that run.
%
%   Writes outDir/frames/NN_x.png (1920x1080) and outDir/narration.tsv
%   (frame id <TAB> narration). tools/video/build_video.py turns them into
%   the video (voice-over from Windows text-to-speech + ffmpeg).

here = fileparts(mfilename('fullpath'));
root = fullfile(here, '..', '..');
addpath(fullfile(root, 'src')); addpath(fullfile(root, 'tests'));
if nargin < 1, outDir = fullfile(here, 'build'); end
frDir = fullfile(outDir, 'frames');
if isfolder(frDir), delete(fullfile(frDir, '*.png')); else, mkdir(frDir); end
narr = {};
arrH = gobjects(0);                     % arrows of the current frame, in creation order

% ---------------------------------------------------------------- data
dataDir = fullfile(tempdir, 'bb_video');
[files, truth] = makeSyntheticCellData(dataDir, [10 25], 'chamber');
grid = [0 0.02 0.05 0.1:0.1:0.9 0.95 1];
d = loadBatteryCsv(files{1});            % the 10 °C file: the main example
R = extractCellParameters(d, 2, grid);
d25 = loadBatteryCsv(files{2});
R25 = extractCellParameters(d25, 2, grid);

D = R.d; soc = D.soc; t = D.t; th_ = t/3600; I = D.I; V = D.V;
AH = R.value.AH; Tref = R.diag.Tref; C = R.constants;
ph = R.diag.phases; isCV = R.diag.isCV;
mr = R.diag.multiRate; cap = R.diag.capacity; fits = R.diag.fits; thm = R.diag.thermal;
S = load(regexprep(files{1}, '\.csv$', '_truth.mat'));
mm = [ones(numel(soc),1), soc] \ S.trueSOC;           % extraction SOC -> true SOC
trueOcv = @(s) truth.ocv(mm(1) + mm(2)*s, Tref);
dis = find([ph.type] == 'D'); chg = find([ph.type] == 'C');
crate = arrayfun(@(k) median(abs(I(ph(k).i1:ph(k).i2)))/AH, dis);

% colours
cBlue = [0 0.447 0.741]; cOr = [0.85 0.325 0.098]; cGr = [0.30 0.65 0.20];
cRed = [0.80 0.10 0.10]; cGrey = [0.55 0.55 0.55]; cPur = [0.49 0.18 0.56];
rateCol = [0.00 0.45 0.74; 0.30 0.65 0.20; 0.93 0.69 0.13; 0.85 0.33 0.10; 0.49 0.18 0.56];

fprintf('extraction done: AH %.4g Ah, Tref %.3g C, %.1f h\n', AH, Tref, t(end)/3600);

%% ================================================================ 1 intro
f = frame('How the Modeling tab gets every number', 'Battery Builder  ·  battery\_data branch');
ax = axes(f, 'Position',[0.05 0.12 0.55 0.72]); circuit(ax);
panel(f, {'\bfWhat the block needs\rm', '', ...
    '\bullet V_0(SOC)   open-circuit voltage', '\bullet R_0(SOC)    series resistance', ...
    '\bullet R_1, \tau_1, R_2, \tau_2   two RC pairs', '\bullet AH          capacity', ...
    '\bullet m·c_p, h·A  thermal', '\bullet SOC_0, T_0   initial state', '', ...
    '\bfThe test\rm', '5 × 0.34C CC-CV charge', '5 discharges: 0.1, 0.2, 0.5, 1, 5C', ...
    sprintf('about %.0f hours', t(end)/3600)});
shot('01_a', ['This video walks through the Modeling tab of Battery Builder, one value at a time. ' ...
    'When you press Extract, the app fills the boxes of the Simscape Battery Table-Based block. ' ...
    'That block is an equivalent circuit: an open-circuit voltage source, a series resistance R0, ' ...
    'and two R C pairs, every one of them a table over state of charge, plus a capacity and a thermal mass. ' ...
    'Every number you will see here was calculated by the app''s own extraction code, on a test file that follows ' ...
    'your profile: five C C, C V charges at 0.34 C, and discharges at 0.1, 0.2, 0.5, 1 and 5 C, about seventy hours in total. ' ...
    'The file is synthetic, built from a cell whose values are known, so we can also check how close the app gets.']);

f = frame('The model the numbers go into', 'Simscape Battery (Table-Based), i = discharge current (+)');
ax = axes(f, 'Position',[0.05 0.40 0.55 0.45]); circuit(ax);
eqs(f, [0.05 0.06 0.9 0.30], { ...
    '$V = V_0(\mathrm{SOC}) - i\,R_0(\mathrm{SOC}) - R_1 x_1 - R_2 x_2$', ...
    '$\dot x_k = (i - x_k)/\tau_k \qquad \mathrm{SOC} = \mathrm{SOC}_0 - \int i\,dt\,/\,(3600\,AH)$', ...
    '$m c_p\,\dot T = i^2 R_0 + \sum R_k x_k^2 - hA\,(T - T_{\mathrm{chamber}})$'});
panel(f, {'\bfWhat the test can show\rm', '', '\bullet AH: full charge \rightarrow cut-off', ...
    '\bullet SOC: coulomb counting', '\bullet R_0: where the current \itsteps\rm', ...
    '\bullet R_k, \tau_k: where the current \itstops\rm', '\bullet V_0 + R_{dc}: same discharge at', '    several rates', ...
    '\bullet m c_p, h A: the 5C self-heating'}, [0.64 0.40 0.34 0.45]);
shot('01_b', ['Here are the equations of that block. The terminal voltage is the open-circuit voltage minus the drop across R0 ' ...
    'minus the voltage across each R C pair. x k is the current through the resistor of pair k; it follows the real current with time constant tau k. ' ...
    'S O C is coulomb counting, and the temperature is a lumped thermal mass heated by the losses and cooled by the chamber. ' ...
    'The key idea of the whole tab is on the right: each quantity can only be measured where the test actually shows it. ' ...
    'R0 shows up where the current steps, the R C pairs where the current stops, and the open-circuit voltage everywhere, ' ...
    'because the same discharge is repeated at several rates.']);

%% ================================================================ 2 the test
f = frame('Your test: 5 charges, 5 discharges, ~70 h', sprintf('%s', strrep(d.name,'_','\_')));
[a1, a2, a3] = threeAxes(f);
plot(a1, th_, I/AH, 'Color', cBlue); ylabel(a1, 'Current (C-rate)'); yline(a1, 0, ':');
plot(a2, th_, V, 'Color', cOr); ylabel(a2, 'Voltage (V)');
plot(a3, th_, D.Tch, 'Color', cGrey, 'LineWidth', 2); hold(a3,'on'); plot(a3, th_, D.Tcell, 'Color', cRed);
ylabel(a3, 'Temp (°C)'); xlabel(a3, 'Test time (h)'); legend(a3, {'chamber','cell'}, 'Location','northwest');
fixLims([a1 a2 a3]);
for j = 1:numel(dis)
    k = dis(j); tm = mean([ph(k).t1 ph(k).t2])/3600;
    txtAt(a1, tm, -crate(j) - 0.5, sprintf('%.2gC', crate(j)), rateCol(j,:));
end
k = chg(1); arrow(a1, mean([ph(k).t1 ph(k).t2])/3600, 0.34, '0.34C CC-CV charge', [0.10 -0.10], cGr);
panel(f, {'\bfThe pattern, 5 times\rm', '', '1. CC-CV charge at 0.34C', '2. rest', ...
    '3. discharge to cut-off', '    0.1C \rightarrow 0.2C \rightarrow 0.5C', '    \rightarrow 1C \rightarrow 5C', '4. rest', '', ...
    sprintf('%.0f h in total', t(end)/3600), sprintf('cut-off %.2f V, full %.2f V', cap.Vmin, cap.VmaxCV)});
shot('02_a', sprintf(['This is the whole test. Top: current in C-rate, positive is charge. Middle: voltage. Bottom: the chamber and cell temperature. ' ...
    'The same pattern repeats five times. @A constant-current, constant-voltage charge at 0.34 C, a rest, a discharge all the way to the ' ...
    '%.2f volt cut-off, and another rest. The discharges get faster each time: 0.1 C, 0.2 C, 0.5 C, 1 C, and finally 5 C. ' ...
    'That ladder of rates is what makes this a rate test, and it is what lets the app measure the open-circuit voltage over the whole S O C range.'], cap.Vmin));

f = frame('The chamber schedule', sprintf('this file''s test temperature: %.3g °C', Tref));
ax = axes(f, 'Position',[0.06 0.14 0.53 0.70]);
w = th_ <= ph(dis(2)).t2/3600 + 1;
yyaxis(ax,'left'); plot(ax, th_(w), I(w)/AH, '-', 'Color', [cBlue 0.5]); ylabel(ax,'Current (C-rate)'); ylim(ax, [-0.6 1.6]);
yyaxis(ax,'right'); plot(ax, th_(w), D.Tch(w), '-', 'Color', cGrey, 'LineWidth', 2.5); hold(ax,'on');
plot(ax, th_(w), D.Tcell(w), '-', 'Color', cRed, 'LineWidth', 1.2); ylabel(ax,'Temperature (°C)'); ylim(ax, [Tref-4 29]);
xlabel(ax,'Test time (h)'); ax.YAxis(1).Color = cBlue; ax.YAxis(2).Color = [0.3 0.3 0.3]; xlim(ax, [0 max(th_(w))]);
fixLims(ax);
k = chg(1); arrow(ax, mean([ph(k).t1 ph(k).t2])/3600, 25, 'charge at 25 °C', [0.02 0.06], cGr);
arrow(ax, ph(k).t2/3600 + 0.3, mean([25 Tref]), sprintf('right after the charge:\nchamber \\rightarrow %.3g °C', Tref), [0.07 0.03], cGrey);
k = dis(1); arrow(ax, mean([ph(k).t1 ph(k).t2])/3600, Tref, sprintf('rest + discharge at %.3g °C', Tref), [0.02 0.08], cOr);
arrow(ax, ph(k).t2/3600 + 0.4, mean([25 Tref]), 'back to 25 °C for the rest', [0.05 -0.05], cGrey);
panel(f, {'\bfEvery cycle\rm', '', '25 °C:  rest \rightarrow CC-CV charge', ...
    sprintf('%.3g °C:  rest \\rightarrow discharge', Tref), '25 °C:  rest  (and repeat)', '', ...
    'So the \bfdischarges\rm are at the', 'file''s temperature, the \bfcharges\rm', 'are always at 25 °C.', '', ...
    'Test temperature label =', 'chamber during the discharges', sprintf('= %.3g °C', Tref)});
shot('02_b', sprintf(['Now the chamber. @The chamber always starts at 25 degrees C, and the first charge happens at 25. ' ...
    '@Right after the charge finishes, the chamber moves to this file''s own temperature, here %.3g degrees, ' ...
    '@and holds it through the rest and the discharge. @When the discharge is done, it goes back to 25 for the rest, ' ...
    'and the next charge starts at 25 again. The red line is the cell; it follows the chamber with a lag of a few minutes. ' ...
    'So in every file, the discharges are at the file''s temperature and the charges are at 25. ' ...
    'Because of that, the app now takes the test temperature as the chamber temperature during the discharges, not the median of the whole file, ' ...
    'which could land on 25 for a cold test.'], Tref));

f = frame('Which samples belong to this temperature', sprintf('the ±%g K window around %.3g °C', C.maxDT, Tref));
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]);
patch(ax, [0 th_(end) th_(end) 0], Tref + C.maxDT*[-1 -1 1 1], cGr, 'FaceAlpha', 0.15, 'EdgeColor','none'); hold(ax,'on');
plot(ax, th_, D.Tch, 'Color', cGrey, 'LineWidth', 2); plot(ax, th_, D.Tcell, 'Color', cRed);
inW = abs(D.Tcell - Tref) <= C.maxDT;
plot(ax, th_(inW & I < 0), D.Tcell(inW & I < 0), '.', 'Color', cOr, 'MarkerSize', 6);
ylabel(ax, 'Temperature (°C)'); xlabel(ax, 'Test time (h)'); fixLims(ax);
k = chg(2); arrow(ax, mean([ph(k).t1 ph(k).t2])/3600, 25, sprintf('charges at 25 °C:\noutside the window'), [0.03 -0.13], cGr);
[~, j] = max(D.Tcell); arrow(ax, th_(j), D.Tcell(j), sprintf('5C heats the cell +%.0f K:\nleft out', max(D.Tcell) - Tref), [-0.12 -0.02], cRed);
panel(f, {'\bfUsed for the tables\rm', sprintf('cell within %g K of %.3g °C', C.maxDT, Tref), '', ...
    'In a 10 °C file:', '\bullet discharges: \bfused\rm', '\bullet steps / rests at the start and', '    end of each discharge: \bfused\rm', ...
    '\bullet charges (25 °C): left out', '\bullet the 5C end: left out (hot)', '', ...
    'In the 25 °C file everything is', 'at 25, so the charges are used', 'too (the OCV charge side).', '', ...
    sprintf('Here: %d step(s), %d rest(s) left out', R.diag.hot.edges, R.diag.hot.fits)});
shot('02_c', sprintf(['The resistances and time constants depend on temperature, so a table for %.3g degrees may only use samples where the cell really was at %.3g degrees. ' ...
    'The green band is plus or minus %g kelvin around the test temperature. The orange dots are the discharge samples inside it. ' ...
    'Two things fall outside. @First, the charges, because they run at 25. @Second, the end of the 5 C discharge, which heats the cell by about %.0f kelvin. ' ...
    'In this file that leaves out %d current steps and %d rests. In a 25 degree file nothing is outside except the 5 C end, so the charges are used as well.'], ...
    Tref, Tref, C.maxDT, max(D.Tcell) - Tref, R.diag.hot.edges, R.diag.hot.fits));

%% ================================================================ 3 phases / CC-CV
k = chg(2);
f = frame('Step 1 - split the test into phases', 'charge (I > 0) · discharge (I < 0) · rest (I = 0)');
ax = axes(f, 'Position',[0.06 0.14 0.53 0.70]);
w = t >= ph(k).t1 - 900 & t <= ph(k).t2 + 1800;
tt = (t(w) - ph(k).t1)/3600;
yyaxis(ax,'left'); plot(ax, tt, I(w), 'LineWidth', 2); ylabel(ax,'Current (A)'); ylim(ax, [-0.2 1.3]);
yyaxis(ax,'right'); plot(ax, tt, V(w), 'LineWidth', 2); ylabel(ax,'Voltage (V)'); ylim(ax, [3.0 4.35]);
xlabel(ax, 'Time from the start of the charge (h)'); fixLims(ax);
idx = ph(k).i1:ph(k).i2; jcv = idx(find(I(idx) < 0.9*ph(k).Imax, 1));
tcv = (t(jcv) - ph(k).t1)/3600; tend = (ph(k).t2 - ph(k).t1)/3600;
yyaxis(ax,'right');
arrow(ax, tcv*0.5, interp1(tt, V(w), tcv*0.5), 'CC: constant current', [-0.02 0.10], cOr);
arrow(ax, (tcv + tend)/2, R.diag.VmaxCV, sprintf('CV: voltage held at %.3f V\n(flat within 15 mV)', R.diag.VmaxCV), [-0.06 0.06], cOr);
yyaxis(ax,'left');
arrow(ax, tend, I(ph(k).i2), sprintf('current tapered to %.0f %%\nof its maximum \\rightarrow FULL', 100*I(ph(k).i2)/ph(k).Imax), [-0.02 0.22], cBlue);
panel(f, {'\bfPhases\rm', 'runs of one sign of current;', 'CC + CV steps merge into one', 'charge phase', '', ...
    '\bfCC-CV charge\rm =', 'current tapered below 35 %', 'of its max while the voltage', 'stayed within 15 mV', '', ...
    '\bfFULL\rm = end of a CC-CV charge', sprintf('at the top voltage (%.3f V)', R.diag.VmaxCV), '', ...
    sprintf('Here: %d charges, %d discharges,', numel(chg), numel(dis)), sprintf('%d rests, %d CC-CV', nnz([ph.type]=='R'), nnz(isCV))});
shot('03_a', sprintf(['The first thing the extraction does is cut the test into phases: charge, discharge and rest, by the sign of the current. ' ...
    'A charge phase is a C C, C V charge when its current tapered below 35 percent of its maximum while the voltage stayed flat, within 15 millivolts. ' ...
    'You can see it here: @constant current until the voltage reaches %.2f volts, @then the voltage is held and the current tapers away. ' ...
    '@The end of that taper is called FULL. It is the reference point for everything that follows. In this file the app finds %d charges, %d discharges and %d C C, C V charges.'], ...
    R.diag.VmaxCV, numel(chg), numel(dis), nnz(isCV)));

%% ================================================================ 4 AH
ahIn = D.tbl.('Net Ah in (Ah)');
[~, jbest] = min(cap.candidates(:,2));
a = cap.candidates(jbest,3); b = cap.candidates(jbest,4);
f = frame('Capacity  AH', 'batt\_AH  ·  Main › Cell capacity');
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]);
plot(ax, th_, ahIn, 'Color', cBlue, 'LineWidth', 1.8); hold(ax,'on');
plot(ax, th_(cap.fullIdx), ahIn(cap.fullIdx), 'o', 'MarkerFaceColor', cGr, 'MarkerEdgeColor','k', 'MarkerSize', 10);
plot(ax, th_(cap.emptyIdx), ahIn(cap.emptyIdx), 's', 'MarkerFaceColor', cRed, 'MarkerEdgeColor','k', 'MarkerSize', 10);
ylabel(ax, 'Net Ah in  =  \Sigma I·\Deltat / 3600  (Ah)'); xlabel(ax, 'Test time (h)'); fixLims(ax);
plot(ax, th_([a a]), [ahIn(b) ahIn(a)], '-', 'Color', cOr, 'LineWidth', 3);
plot(ax, [th_(a) th_(b)], ahIn([b b]), ':', 'Color', cOr, 'LineWidth', 1.5);
arrow(ax, th_(a), ahIn(a), 'FULL (end of CC-CV)', [0.07 -0.06], cGr);
arrow(ax, th_(b), ahIn(b), 'EMPTY (cut-off, on the knee)', [0.04 -0.07], cRed);
text(ax, th_(a) + 1, (ahIn(a) + ahIn(b))/2, sprintf('\\Delta = %.4f Ah', ahIn(a) - ahIn(b)), 'Color', cOr, 'FontSize', 18, 'FontWeight','bold', 'BackgroundColor','w');
panel(f, {'\bfAH = Ah_{in}(FULL) - Ah_{in}(EMPTY)\rm', '', sprintf('= %.4f - (%.4f)', ahIn(a), ahIn(b)), ...
    sprintf('= \\bf%.4f Ah\\rm', AH), '', 'from the \bfslowest\rm discharge', sprintf('(%.2gC = %.3g A)', cap.rateA/AH, cap.rateA), '', ...
    'Cross-check: cycler''s own', sprintf('Capacity column: %.4f Ah', cap.fileAh), sprintf('(%+.2f %%)', 100*(cap.fileAh/AH - 1)), '', ...
    sprintf('Known cell: %.3g Ah', truth.Q)});
shot('04_a', sprintf(['Capacity, A H. The app adds up the current over time; that is the blue line, net amp-hours in. It rises during charges and falls during discharges. ' ...
    '@The green circles are the FULL points at the end of each C C, C V charge. @The red squares are EMPTY points: the end of a discharge that stopped at the cut-off voltage. ' ...
    'The capacity is simply the drop between a FULL point and the next EMPTY point. For the 0.1 C discharge that is %.4f amp-hours. ' ...
    'As a cross-check, the cycler''s own capacity column gives %.4f, a difference of %.2f percent.'], AH, cap.fileAh, 100*(cap.fileAh/AH - 1)));

kd = find([ph.i2] == b, 1);
idx = (ph(kd).i1:ph(kd).i2)'; q = ahIn(idx(1)) - ahIn(idx); v = V(idx); Q = q(end);
mid = q >= 0.25*Q & q <= 0.75*Q; cfit = polyfit(q(mid), v(mid), 1);
j3 = find(q >= 0.97*Q, 1); sEnd = (v(j3) - v(end))/(q(end) - q(j3));
f = frame('Is it really EMPTY?  The knee check', 'a partial discharge must never count as empty');
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]);
plot(ax, q, v, 'Color', cOr, 'LineWidth', 2); hold(ax,'on');
plot(ax, q(mid), polyval(cfit, q(mid)), 'k--', 'LineWidth', 2);
plot(ax, q([j3 end]), v([j3 end]), '-', 'Color', cRed, 'LineWidth', 4);
xlabel(ax, 'Ah taken out in this discharge'); ylabel(ax, 'Voltage (V)'); fixLims(ax);
arrow(ax, q(find(mid,1) + round(nnz(mid)/2)), polyval(cfit, q(find(mid,1) + round(nnz(mid)/2))), sprintf('middle half: %.0f mV/Ah', -1000*cfit(1)), [-0.05 -0.15], [0 0 0]);
arrow(ax, q(end), v(end), sprintf('last 3 %%: %.0f mV/Ah', 1000*sEnd), [-0.14 0.05], cRed);
panel(f, {'\bfEMPTY needs all three\rm', '', '\bullet discharge \geq 5 min', '\bullet ended at the cut-off', '    (lowest end voltage of all', '    long discharges)', ...
    '\bullet ended on the knee:', '    slope over last 3 % >', '    3 × slope of middle half', '', sprintf('Here: %.0f / %.0f = %.0f×', 1000*sEnd, -1000*cfit(1), sEnd/-cfit(1)), '\rightarrow EMPTY'});
shot('04_b', sprintf(['Why trust that point as empty? The app checks three things. The discharge lasted at least five minutes, it ended at the cut-off, ' ...
    'and it ended on the knee. A lithium-ion cell''s voltage falls steeply when it is really empty. ' ...
    '@Over the middle half of this discharge the voltage falls %.0f millivolts per amp-hour; @over the last three percent it falls %.0f. ' ...
    'That is %.0f times steeper, more than the required three, so this is a true empty point, not a partial discharge.'], -1000*cfit(1), 1000*sEnd, sEnd/-cfit(1)));

f = frame('Why the slowest discharge sets AH', 'every FULL \rightarrow EMPTY discharge, as a rate-capability table');
ax = axes(f, 'Position',[0.08 0.16 0.52 0.66]);
cr = cap.candidates(:,2)/AH; qa = cap.candidates(:,1);
bh = bar(ax, 1:numel(qa), qa, 'FaceColor','flat'); bh.CData = rateCol(1:numel(qa),:);
set(ax, 'XTick', 1:numel(qa), 'XTickLabel', compose('%.2gC', cr)); ylabel(ax, 'Ah delivered to the cut-off'); xlabel(ax, 'discharge rate');
ylim(ax, [min(qa)*0.9 max(qa)*1.03]); fixLims(ax);
for j = 1:numel(qa), txtAt(ax, j, qa(j), sprintf('%.3f', qa(j)), [0 0 0], 'bottom'); end
arrow(ax, jbest, qa(jbest), 'used for AH', [0.06 0.08], cBlue);
panel(f, {'\bfFaster = fewer Ah to the cut-off\rm', '', 'More current \rightarrow more voltage', 'lost in R_{dc} \rightarrow the cut-off', 'comes sooner.', '', ...
    'The slowest one comes closest', 'to the charge really stored.', '', 'SOC keeps using this AH, so', 'after a fast discharge SOC', 'correctly stays above 0.'});
shot('04_c', sprintf(['The test has %d full-to-empty discharges, and each gives a different number. ' ...
    'A faster discharge loses more voltage across the internal resistance, so it reaches the cut-off sooner and delivers fewer amp-hours: ' ...
    'here from %.3f at 0.1 C down to %.3f at %.2g C. @The slowest discharge is the closest to the charge the cell really stores, so it becomes A H. ' ...
    'The A H How window shows this same table.'], numel(qa), qa(1), qa(end), cr(end)));

%% ================================================================ 5 SOC
f = frame('State of charge  SOC  and  SOC_0', 'batt\_SOC0  ·  coulomb counting, reset at every FULL');
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]);
plot(ax, th_, soc, 'Color', cPur, 'LineWidth', 2); hold(ax,'on');
plot(ax, th_(cap.fullIdx), soc(cap.fullIdx), 'o', 'MarkerFaceColor', cGr, 'MarkerEdgeColor','k', 'MarkerSize', 9);
ylabel(ax, 'SOC (-)'); xlabel(ax, 'Test time (h)'); ylim(ax, [-0.05 1.1]); fixLims(ax);
arrow(ax, th_(cap.fullIdx(1)), 1, 'SOC = 1 at FULL', [0.03 0.06], cGr);
arrow(ax, 0, soc(1), sprintf('SOC_0 = %.3f', R.value.SOC0), [0.06 0.10], cPur);
k = dis(end); arrow(ax, th_(ph(k).i2), soc(ph(k).i2), sprintf('after 5C: cut-off at\nSOC %.2f (not 0)', soc(ph(k).i2)), [-0.04 0.25], cRed);
panel(f, {'\bfSOC = 1 + (Ah_{in} - Ah_{in}(FULL)) / AH\rm', '', 'reset to 1 at every FULL point', '', ...
    '\bfSOC_0\rm (before the first FULL,', 'run backwards):', sprintf('1 - %.4f / %.4f', ahIn(cap.fullIdx(1)) - ahIn(1), AH), sprintf('= \\bf%.3f\\rm', R.value.SOC0), '', ...
    '\bfVoltage check\rm', sprintf('first rest %.3f V \\rightarrow OCV', R.diag.soc.check.V), sprintf('table reads SOC %.3f', R.diag.soc.check.socOcv), ...
    sprintf('(coulomb count %.3f)', R.diag.soc.check.socCC)});
shot('05_a', sprintf(['State of charge. With A H known, S O C is coulomb counting: one plus the amp-hours put in since the last FULL point, divided by A H. ' ...
    '@It is reset to exactly one at every FULL point, so errors never build up from cycle to cycle. ' ...
    '@Before the first full charge, the same line is run backwards. It took %.3f amp-hours to fill the cell the first time, ' ...
    'so the file started at S O C %.3f, almost empty, which matches a test that starts on a cell left at its cut-off. ' ...
    '@Notice that after the 5 C discharge, S O C stops at %.2f, not zero: the cell hit the cut-off with charge still in it. ' ...
    'As a check, the first rest voltage, %.3f volts, read backwards through the O C V table, gives S O C %.3f. That agrees.'], ...
    ahIn(cap.fullIdx(1)) - ahIn(1), R.value.SOC0, soc(ph(dis(end)).i2), R.diag.soc.check.V, R.diag.soc.check.socOcv));

%% ================================================================ 6 R0
ek = R.diag.edgeIdx;
k0 = ek(find(I(ek) == 0 & I(ek+1) < 0 & soc(ek) > 0.9, 1));
f = frame('Series resistance  R_0', 'batt\_R0\_vec  ·  the instant voltage jump at a current step');
ax = axes(f, 'Position',[0.06 0.14 0.53 0.70]);
w = t >= t(k0) - 40 & t <= t(k0) + 30; tt = t(w) - t(k0+1);
yyaxis(ax,'left'); stairs(ax, tt, I(w), 'LineWidth', 2); ylabel(ax,'Current (A)'); ylim(ax, [I(k0+1)*1.6 0.15]);
yyaxis(ax,'right'); plot(ax, tt, V(w), '-o', 'LineWidth', 1.5, 'MarkerSize', 6); ylabel(ax,'Voltage (V)');
xlabel(ax, 'Time from the step (s)'); fixLims(ax);
dV = V(k0+1) - V(k0); dI = I(k0+1) - I(k0); r0x = dV/dI;
arrow(ax, t(k0) - t(k0+1), V(k0), sprintf('last sample before\n%.4f V', V(k0)), [-0.14 0.05], cOr);
arrow(ax, 0, V(k0+1), sprintf('first sample after\n%.4f V', V(k0+1)), [0.06 -0.12], cOr);
panel(f, {'\bfR_0 = \DeltaV / \DeltaI\rm', '', sprintf('\\DeltaV = %.4f - %.4f', V(k0+1), V(k0)), sprintf('      = %.1f mV', 1000*dV), ...
    sprintf('\\DeltaI = %.3f A', dI), '', sprintf('R_0 = \\bf%.2f m\\Omega\\rm', 1000*r0x), sprintf('at SOC %.2f', soc(k0)), '', ...
    'Rules:', '\bullet first sample \leq 5 s after', '    the step (StepTime column)', '\bullet step \geq 0.08C', sprintf('\\bullet cell within %g K of %.3g °C', C.maxDT, Tref)});
shot('06_a', sprintf(['R0, the series resistance. Look at the start of a discharge. The voltage over an R C pair cannot jump, because its capacitor needs time to charge. ' ...
    'So the instant jump in voltage when the current steps is the series resistance alone. ' ...
    '@The last sample before the step is %.4f volts, @the first one after it is %.4f. ' ...
    'That is a change of %.1f millivolts for a current change of %.3f amps, so R0 is %.2f milliohms at S O C %.2f. ' ...
    'The step only counts if the first sample came within five seconds of the step, the step is at least 0.08 C, ' ...
    'and the cell was within %g kelvin of the test temperature.'], V(k0), V(k0+1), 1000*dV, dI, 1000*r0x, soc(k0), C.maxDT));

% all steps, with the ones that were left out
[stS, stR, stHot] = allSteps(D, soc, C, AH, Tref);
pr = R.diag.prov.R0_vec;
f = frame('R_0 at every step, and the table', 'M = measured  ·  S = scaled to R_{dc}  ·  E = end value held');
ax = axes(f, 'Position',[0.07 0.14 0.55 0.70]);
plot(ax, stS(~stHot), 1000*stR(~stHot), 'o', 'MarkerFaceColor', cBlue, 'MarkerEdgeColor','k', 'MarkerSize', 10); hold(ax,'on');
plot(ax, stS(stHot), 1000*stR(stHot), 'x', 'Color', cRed, 'MarkerSize', 14, 'LineWidth', 3);
plot(ax, grid, 1000*R.value.R0_vec, '-s', 'Color', cOr, 'LineWidth', 2, 'MarkerFaceColor', cOr);
plot(ax, grid, 1000*truth.R0(mm(1) + mm(2)*grid, Tref), 'k:', 'LineWidth', 1.5);
for j = 1:numel(grid), txtAt(ax, grid(j), 1000*R.value.R0_vec(j), pr(j), [0 0 0], 'bottom'); end
xlabel(ax, 'SOC (-)'); ylabel(ax, 'R_0 (m\Omega)'); xlim(ax, [-0.05 1.05]); fixLims(ax);
legend(ax, {'step used', 'step left out (charge at 25 °C / hot)', 'R_0 table', 'known cell'}, 'Location','north');
panel(f, {'\bfWhere R_0 is measured\rm', '\bullet start of each discharge', '    (SOC \approx 1)', '\bullet end of each discharge', '    (SOC \approx 0 ... 0.1)', '', ...
    'Each breakpoint = median of', 'the steps nearest to it (M).', '', 'In between: no steps at all,', 'so R_0 + R_1 + R_2 is scaled', 'to the measured R_{dc} (S).', '', ...
    sprintf('%d steps used, %d left out', nnz(~stHot), nnz(stHot))});
shot('06_b', sprintf(['Here is every current step in the test. The blue circles are the steps that were used; they sit at the two ends of the S O C range, ' ...
    'at the start and the end of each discharge, because that is the only place the current steps. ' ...
    'The red crosses were left out: the steps at the start of each charge, which happen at 25 degrees, and the end of the 5 C discharge, where the cell is hot. ' ...
    'Each S O C breakpoint takes the median of the steps nearest it; those are marked M. ' ...
    'In the middle of the range there are no steps, so those entries, marked S, come from the multi-rate fit you will see in a moment. ' ...
    'The dotted line is the known cell. %d steps used, %d left out.'], nnz(~stHot), nnz(stHot)));

%% ================================================================ 7 RC pairs
okF = arrayfun(@(q) all(isfinite(q.R)) && all(isfinite(q.tau)), fits);
amp = arrayfun(@(q) sum(abs(q.R .* q.x0)), fits); amp(~okF | [fits.after] ~= 'D') = -inf;
[~, fi] = max(amp);                       % clearest relaxation after a discharge
F = fits(fi);
f = frame('RC pairs  R_1, \tau_1, R_2, \tau_2', 'batt\_R1\_vec, batt\_tau1\_vec ...  ·  fitted to the voltage relaxation in a rest');
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]);
tm = F.tr/60;
plot(ax, tm, F.v, '.', 'Color', cGrey, 'MarkerSize', 10); hold(ax,'on');
plot(ax, tm, F.vfit, '-', 'Color', cBlue, 'LineWidth', 2.5);
yline(ax, F.Vinf, '--', 'Color', cGr, 'LineWidth', 2);
p1 = F.Vinf + F.R(2)*F.x0(2)*exp(-F.tr/F.tau(2));
plot(ax, tm, p1, ':', 'Color', cOr, 'LineWidth', 2);
xlabel(ax, 'Time since the current stopped (min)'); ylabel(ax, 'Voltage (V)'); xlim(ax, [0 min(max(tm), max(15, 6*F.tau(2)/60))]); fixLims(ax);
legend(ax, {'measured', 'fit', 'V_\infty', 'slow pair only'}, 'Location','southeast');
j1 = find(F.tr >= 2*F.tau(1), 1); j2 = find(F.tr >= F.tau(2), 1);
arrow(ax, 0.9*ax.XLim(2), F.Vinf, sprintf('V_\\infty = %.4f V\n= an OCV point', F.Vinf), [-0.05 -0.12], cGr);
arrow(ax, tm(j1), F.vfit(j1), sprintf('fast pair: \\tau_1 = %.0f s', F.tau(1)), [0.06 -0.12], cBlue);
arrow(ax, tm(j2), p1(j2), sprintf('slow pair: \\tau_2 = %.0f s', F.tau(2)), [0.06 -0.10], cOr);
panel(f, {'\bfV(t) = V_\infty + \Sigma R_k x_k(0) e^{-t/\tau_k}\rm', '', sprintf('rest at SOC %.2f, after a discharge', F.soc), '', ...
    sprintf('x_1(0) = %.3f A,  x_2(0) = %.3f A', F.x0), '(branch currents when the', 'current stopped, from the real', 'current history)', '', ...
    sprintf('R_1 = %.2f m\\Omega,  \\tau_1 = %.1f s', 1000*F.R(1), F.tau(1)), sprintf('R_2 = %.2f m\\Omega,  \\tau_2 = %.0f s', 1000*F.R(2), F.tau(2)), ...
    sprintf('rms error %.2f mV', 1000*F.rmse), '', sprintf('known: \\tau_1 = %.0f s, \\tau_2 = %.0f s', truth.tau1(0,Tref), truth.tau2(0,Tref))});
shot('07_a', sprintf(['The R C pairs come from the rests. When the current stops, the R0 drop disappears at once, and what is left is the R C voltages dying away. ' ...
    'That relaxation is a sum of exponentials, one per pair, settling to @V infinity, the fully relaxed voltage, which is also an open-circuit voltage point. ' ...
    'The branch currents at the moment the current stopped are computed from the real current history, here %.2f and %.2f amps. ' ...
    'For given time constants, the resistances are a linear least-squares problem; the time constants are found by a grid search and then refined. ' ...
    '@This rest, after a discharge at S O C %.2f, gives a fast pair with tau 1 of %.1f seconds @and a slow pair with tau 2 of %.0f seconds. ' ...
    'R1 is %.2f and R2 is %.2f milliohms, with a fit error of %.2f millivolts.'], F.x0(1), F.x0(2), F.soc, F.tau(1), F.tau(2), 1000*F.R(1), 1000*F.R(2), 1000*F.rmse));

%% ================================================================ 8 settle wait (and the 25 °C fix)
f = frame('Before the multi-rate fit: wait until the RC pairs settle', 't \geq max_k \tau_k ln(R_k i / 1 mV)');
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]); hold(ax,'on');
for r = 1:numel(mr.rates)
    if mr.crate(r) > C.mrMaxCrate, continue; end
    p = ph(mr.phase(r)); idx = p.i1:p.i2;
    tm = (t(idx) - p.t1)/60;
    plot(ax, tm, V(idx), '-', 'Color', [rateCol(r,:) 0.35], 'LineWidth', 1.2);
    ok = tm*60 >= mr.settle(r);
    plot(ax, tm(ok), V(idx(ok)), '-', 'Color', rateCol(r,:), 'LineWidth', 2.5);
end
xlim(ax, [0 60]); ylim(ax, [3.7 4.25]); xlabel(ax, 'Minutes from the start of each discharge'); ylabel(ax, 'Voltage (V)'); fixLims(ax);
for r = mr.use
    xs = mr.settle(r)/60; p = ph(mr.phase(r));
    vv = interp1((t(p.i1:p.i2) - p.t1)/60, V(p.i1:p.i2), xs);
    offs = {[0.25 -0.03], [0.20 -0.10], [0.08 0.05], [0.10 0.08]};
    arrow(ax, xs, vv, sprintf('%.2gC: %.0f min', mr.crate(r), xs), offs{min(r,4)}, rateCol(r,:));
end
panel(f, {'\bfFaint = not settled yet (unused)\rm', '', 'R_k, \tau_k from the rests', '\bfafter a discharge\rm only', sprintf('(%s)', mr.rc.from), '', ...
    '\bfThe 25 °C bug\rm', 'Rests after a CC-CV charge', 'start with almost no branch', 'current (CV taper) \rightarrow poorly', 'defined, long \tau / big R.', ...
    'In 25 °C files they were kept', '(not too warm), the wait grew', 'longer than the 0.5C and 1C', 'discharges, and the OCV came', 'out empty. Fixed.'});
shot('08_a', sprintf(['Next is the heart of the tab, the multi-rate fit, but it needs one preparation. ' ...
    'Right after a discharge starts, the R C voltages are still building up. A sample is only used once what is left of every transient is below one millivolt, ' ...
    'using the R and tau values from the rests. @4That wait is %s minutes for the %s C discharges; the faint parts of each curve are not used. ' ...
    'This is also where the 25 degree problem you saw came from. In a 25 degree file the rests after the C C, C V charges are not too warm, so they were included. ' ...
    'But a rest after a constant-voltage taper starts with almost no current in the R C branches, so its R and tau are poorly defined, and on real data they can come out large. ' ...
    'That made the wait longer than the 0.5 C and 1 C discharges themselves, those rates dropped out, and the O C V could not cover the full S O C range. ' ...
    'In the other files those rests were left out because the chamber had already changed, which is why only 25 degrees failed. ' ...
    'The wait now uses only rests that follow a discharge, and if a rate is still dropped, the O C V note tells you which one and why.'], ...
    strjoin(compose('%.0f', mr.settle(mr.use)/60), ', '), strjoin(compose('%.2g', mr.crate(mr.use)), ', ')));

%% ================================================================ 9 multi-rate
js = find(abs(mr.sf - 0.5) < 1e-9);
f = frame('OCV + R_{dc}: the multi-rate fit  (1/3)', 'every discharge on one SOC axis');
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]); hold(ax,'on');
lg = {};
for r = 1:numel(mr.rates)
    fm = isfinite(mr.Vd(r,:));
    if ~any(fm), continue; end
    lw = 2.2; if ~ismember(r, mr.use), lw = 0.8; end
    plot(ax, mr.sf(fm), mr.Vd(r,fm), '-', 'Color', rateCol(r,:), 'LineWidth', lw); lg{end+1} = sprintf('%.2gC', mr.crate(r)); %#ok<AGROW>
end
xline(ax, 0.5, '--k', 'LineWidth', 1.5); lg{end+1} = 'SOC 0.5';
xlabel(ax, 'SOC (-)'); ylabel(ax, 'Voltage, settled part (V)'); xlim(ax, [0 1]); fixLims(ax);
legend(ax, lg, 'Location','southeast');
r = mr.use(end); arrow(ax, 0.5, mr.Vd(r,js), sprintf('at SOC 0.5 the four\nrates give four voltages'), [0.08 -0.12], [0 0 0]);
panel(f, {'\bfOnce settled, the block is a\rm', '\bfstraight line in i:\rm', '', 'V(SOC, i) = V_0(SOC) - i·R_{dc}(SOC)', 'R_{dc} = R_0 + R_1 + R_2', '', ...
    'SOC is exact (every discharge', 'starts from FULL), so the rates', 'line up on one axis.', '', ...
    'Voltage averaged in 1 % SOC bins,', sprintf('cell within %g K, rates \\leq %gC', C.maxDT, C.mrMaxCrate), '(5C left out: too hot, not linear)'});
shot('09_a', ['Here is the multi-rate fit. Once the R C pairs have settled, every branch current equals the discharge current, and the block''s equation becomes a straight line in current: ' ...
    'the voltage equals the open-circuit voltage minus the current times R D C, where R D C is R0 plus R1 plus R2. ' ...
    'Every discharge starts from FULL, so its S O C is exact, and all the discharges can be drawn on one S O C axis. ' ...
    'The slower the discharge, the higher its curve. The 5 C discharge is left out: it heats the cell far outside the window and stops being linear. ' ...
    '@Now pick one S O C, say 0.5. The four rates give four voltages.']);

u = mr.use(isfinite(mr.Vd(mr.use, js)));
ii = mr.rates(u); vv = mr.Vd(u, js)';
f = frame('OCV + R_{dc}: the multi-rate fit  (2/3)', 'at SOC 0.5: voltage against current, extrapolated to zero current');
ax = axes(f, 'Position',[0.08 0.14 0.54 0.70]); hold(ax,'on');
xx = linspace(0, max(ii)*1.1, 50);
plot(ax, xx, mr.ocvD(js) - mr.Rdc(js)*xx, '--', 'Color', cGrey, 'LineWidth', 2);
for q2 = 1:numel(u), plot(ax, ii(q2), vv(q2), 'o', 'MarkerSize', 14, 'MarkerFaceColor', rateCol(u(q2),:), 'MarkerEdgeColor','k'); end
plot(ax, 0, mr.ocvD(js), 'p', 'MarkerSize', 22, 'MarkerFaceColor', cGr, 'MarkerEdgeColor','k');
xlabel(ax, 'Discharge current i (A)'); ylabel(ax, 'Voltage at SOC 0.5 (V)'); xlim(ax, [-0.1 max(ii)*1.15]); fixLims(ax);
arrow(ax, 0, mr.ocvD(js), sprintf('intercept (i = 0)\nV_{0,dis} = %.4f V', mr.ocvD(js)), [0.10 0.03], cGr);
arrow(ax, mean(xx), mr.ocvD(js) - mr.Rdc(js)*mean(xx), sprintf('slope = -R_{dc}\n= %.1f m\\Omega', 1000*mr.Rdc(js)), [0.04 -0.12], cGrey);
L = {'\bfThe four points\rm'};
for q2 = 1:numel(u), L{end+1} = sprintf('%.2gC: %.3f A, %.4f V', mr.crate(u(q2)), ii(q2), vv(q2)); end %#ok<AGROW>
L = [L, {'', '\bfLeast-squares line\rm', sprintf('V_{0,dis} = \\bf%.4f V\\rm', mr.ocvD(js)), sprintf('R_{dc} = \\bf%.2f m\\Omega\\rm', 1000*mr.Rdc(js))}];
if isfinite(mr.rms(js)), L{end+1} = sprintf('scatter %.2f mV rms', 1000*mr.rms(js)); end
Rt5 = truth.R0(mm(1)+mm(2)*0.5,Tref) + truth.R1(mm(1)+mm(2)*0.5,Tref) + truth.R2(mm(1)+mm(2)*0.5,Tref);
L = [L, {'', sprintf('known cell: %.4f V, %.2f m\\Omega', trueOcv(0.5), 1000*Rt5), '', 'Repeated at every 1 % of SOC'}];
panel(f, L);
shot('09_b', sprintf(['Plot those four voltages against their current and they fall on a straight line. ' ...
    '@Extend the line back to zero current, and the intercept is the voltage the cell would have with no current at all: the open-circuit voltage on the discharge side, %.4f volts. ' ...
    '@The slope is the total D C resistance, %.2f milliohms. The points sit %.2f millivolts from the line, so the straight-line model holds. ' ...
    'The known cell has %.4f volts and %.2f milliohms here. This is repeated at every one percent of S O C.'], ...
    mr.ocvD(js), 1000*mr.Rdc(js), 1000*mr.rms(js), trueOcv(0.5), 1000*Rt5));

f = frame('OCV + R_{dc}: the multi-rate fit  (3/3)', 'one line per 1 % SOC \rightarrow two whole curves');
ax = axes(f, 'Position',[0.06 0.14 0.26 0.70]);
plot(ax, mr.sf, mr.ocvD, '-', 'Color', cGr, 'LineWidth', 2.5); xlabel(ax, 'SOC (-)'); ylabel(ax, 'V_{0,dis} (V)'); title(ax, 'intercepts'); xlim(ax,[0 1]);
ax2 = axes(f, 'Position',[0.38 0.14 0.24 0.70]);
plot(ax2, mr.sf, 1000*mr.Rdc, '-', 'Color', cGrey, 'LineWidth', 2.5); hold(ax2,'on');
sg = linspace(0,1,101);
plot(ax2, sg, 1000*(truth.R0(mm(1)+mm(2)*sg,Tref) + truth.R1(mm(1)+mm(2)*sg,Tref) + truth.R2(mm(1)+mm(2)*sg,Tref)), 'k:', 'LineWidth', 1.5);
xlabel(ax2, 'SOC (-)'); ylabel(ax2, 'R_{dc} (m\Omega)'); title(ax2, 'slopes'); xlim(ax2,[0 1]); legend(ax2, {'fit','known'}, 'Location','north');
fixLims([ax ax2]);
fm = find(isfinite(mr.ocvD));
panel(f, {'\bfResult of the fit\rm', sprintf('covers SOC %.2f ... %.2f', mr.sf(fm(1)), mr.sf(fm(end))), '', ...
    'Not covered:', '\bullet very top: the first minutes', '    of each discharge never settle', '\bullet very bottom: the knee', '', ...
    'Those two ends come from the', 'relaxed rest voltages (next).', '', 'R_{dc}(SOC) fixes the sum', 'R_0 + R_1 + R_2 in the middle.'});
shot('09_c', sprintf(['Do that at every percent and you get two whole curves: the intercepts give the discharge-side open-circuit voltage, and the slopes give R D C against S O C. ' ...
    'The dotted line is the known cell''s total resistance. The fit covers S O C %.2f to %.2f. ' ...
    'It cannot reach the very top, because the first minutes of every discharge are never settled, or the very bottom, at the knee. Those ends come from the rests.'], ...
    mr.sf(fm(1)), mr.sf(fm(end))));

%% ================================================================ 10 charge side + ends + OCV table
mr25 = R25.diag.multiRate;
f = frame('Charge side, hysteresis, and the two ends', 'V_0 = ½ (V_{0,chg} + V_{0,dis});  ends from the rests');
ax = axes(f, 'Position',[0.06 0.14 0.27 0.70]); hold(ax,'on');
plot(ax, mr25.sf, mr25.ocvD, '-', 'Color', cOr, 'LineWidth', 2);
if ~isempty(mr25.Vc), plot(ax, mr25.sf, mr25.Vc(1,:), '-', 'Color', [cGr 0.5], 'LineWidth', 1.2); plot(ax, mr25.sf, mr25.ocvC, '-', 'Color', cGr, 'LineWidth', 2); end
plot(ax, mr25.sf, mr25.ocv, 'k-', 'LineWidth', 1.2);
xlabel(ax, 'SOC (-)'); ylabel(ax, 'Voltage (V)'); title(ax, '25 °C file'); xlim(ax, [0 1]);
legend(ax, {'V_{0,dis}', 'charge 0.34C', 'V_{chg} - i·R_{dc}', 'average'}, 'Location','southeast');
ax2 = axes(f, 'Position',[0.40 0.14 0.24 0.70]); hold(ax2,'on');
po = R.diag.points.ocv;
plot(ax2, grid, R.value.V0_vec, '-s', 'Color', cBlue, 'LineWidth', 2, 'MarkerFaceColor', cBlue);
plot(ax2, po(:,1), po(:,2), 'o', 'MarkerSize', 11, 'MarkerFaceColor', cRed, 'MarkerEdgeColor','k');
plot(ax2, sg, trueOcv(sg), 'k:', 'LineWidth', 1.5);
for j = 1:numel(grid), txtAt(ax2, grid(j), R.value.V0_vec(j), R.diag.prov.V0_vec(j), [0 0 0], 'bottom'); end
xlabel(ax2, 'SOC (-)'); ylabel(ax2, 'V_0 (V)'); title(ax2, sprintf('%.3g °C file: the V_0 table', Tref)); xlim(ax2, [-0.03 1.03]);
legend(ax2, {'V_0 table', 'relaxed rest V_\infty', 'known cell'}, 'Location','southeast'); fixLims([ax ax2]);
err = 1000*max(abs(R.value.V0_vec - trueOcv(grid)));
panel(f, {'\bfCharge side\rm', 'only where charges are inside', 'the temperature window:', '\bullet 25 °C file: yes', sprintf('    half-gap %.1f mV', 1000*mr25.hyst), ...
    sprintf('\\bullet %.3g °C file: no (25 °C', Tref), '    charges) \rightarrow discharge side', '', '\bfEnds\rm: rest after the discharge', '(SOC 0) and after the charge', '(SOC 1, 25 °C file), pchip join', '', ...
    sprintf('max error vs known: %.1f mV', err), 'M measured, I joined, E extended'}, [0.66 0.10 0.32 0.78]);
shot('10_a', sprintf(['Two more pieces finish the open-circuit voltage. First, the charge side. A cell rests slightly higher after a charge than after a discharge; that is hysteresis. ' ...
    'In the 25 degree file, on the left, the 0.34 C charges are inside the temperature window, so the app corrects them by i times R D C and averages the two sides. Half the gap is %.1f millivolts there. ' ...
    'In a %.3g degree file the charges ran at 25 degrees, so they are not used, and the table is the discharge side alone. ' ...
    'Second, the ends. The rest after each discharge to cut-off relaxes to the S O C zero open-circuit voltage, the red circles at the bottom, and a smooth curve joins them to the fit. ' ...
    'On the right is the final V0 table for this file, with its flags: M measured, I joined, E extended. Against the known cell, the largest error is %.1f millivolts.'], ...
    1000*mr25.hyst, Tref, err));

%% ================================================================ 11 R tables scaled to Rdc
f = frame('R_0, R_1, R_2 tables: the sum is measured', 'S = interpolated R_0 / R_1 / R_2 scaled by one factor so the sum = R_{dc}');
ax = axes(f, 'Position',[0.07 0.14 0.55 0.70]);
Rm = 1000*[R.value.R0_vec; R.value.R1_vec; R.value.R2_vec]';
bh = bar(ax, 1:numel(grid), Rm, 'stacked'); bh(1).FaceColor = cOr; bh(2).FaceColor = cBlue; bh(3).FaceColor = cGr; hold(ax,'on');
rdcG = interp1(mr.sf, mr.Rdc, grid);
plot(ax, 1:numel(grid), 1000*rdcG, 'k-o', 'LineWidth', 2, 'MarkerFaceColor', 'k');
set(ax, 'XTick', 1:numel(grid), 'XTickLabel', compose('%.2g', grid)); xlabel(ax, 'SOC breakpoint'); ylabel(ax, 'Resistance (m\Omega)');
fixLims(ax);
for j = 1:numel(grid), txtAt(ax, j, sum(Rm(j,:)), R.diag.prov.R0_vec(j), [0 0 0], 'bottom'); end
legend(ax, {'R_0', 'R_1', 'R_2', 'R_{dc} from the multi-rate fit'}, 'Location','northeast');
panel(f, {'\bfWhat each part means\rm', '', 'M: measured at steps / rests', '    (the two ends)', '', 'S: no step or rest there.', '    R_0, R_1, R_2 interpolated,', ...
    '    then × one factor so that', '    R_0 + R_1 + R_2 = R_{dc}', '', 'So the total a constant current', 'feels is always measured; only', 'the split is interpolated.', '', ...
    '\tau_1, \tau_2: interpolated', '(only seen where current stops)'});
shot('11_a', ['Now the resistance tables. Each bar is one S O C breakpoint: R0 in orange, R1 in blue, R2 in green, stacked. The black line is R D C from the multi-rate fit. ' ...
    'At the two ends, marked M, all three were measured directly, at the steps and in the rests. In between, the current never steps or stops, so R0, R1 and R2 cannot be told apart there. ' ...
    'But their sum can be measured. So the app interpolates them from the measured ends, then multiplies all three by one common factor so their sum equals R D C exactly. Those are the S entries. ' ...
    'The total resistance a constant current feels is always measured; only the split between the three is interpolated. The time constants are interpolated too.']);

%% ================================================================ 12 thermal
f = frame('Thermal mass  m·c_p  and  h·A', 'batt\_thermal\_mass, batt\_hA  ·  fitted to the measured cell temperature');
ax = axes(f, 'Position',[0.06 0.50 0.56 0.33]);
tt = thm.t/3600 + th_(find(isfinite(D.Tcell), 1));
plot(ax, tt, thm.Q, 'Color', cOr, 'LineWidth', 1.5); ylabel(ax, 'Heat Q (W)'); xlim(ax, [0 tt(end)]);
ax2 = axes(f, 'Position',[0.06 0.12 0.56 0.33]);
plot(ax2, tt, thm.Tamb, 'Color', cGrey, 'LineWidth', 2); hold(ax2,'on');
plot(ax2, tt, thm.Tmeas, '.', 'Color', cRed, 'MarkerSize', 4); plot(ax2, tt, thm.Tmodel, '-', 'Color', cBlue, 'LineWidth', 1.5);
ylabel(ax2, 'Temp (°C)'); xlabel(ax2, 'Test time (h)'); xlim(ax2, [0 tt(end)]); legend(ax2, {'chamber (ambient)','cell measured','cell simulated'}, 'Location','northwest');
fixLims([ax ax2]);
[~, jq] = max(thm.Q); arrow(ax, tt(jq), thm.Q(jq), 'the 5C discharge', [-0.10 -0.03], cOr);
[~, jt] = max(thm.Tmeas); arrow(ax2, tt(jt), thm.Tmeas(jt), sprintf('+%.0f K self-heating', max(thm.Tmeas) - Tref), [-0.12 0.0], cRed);
panel(f, {'\bfm c_p dT/dt = Q - hA (T - T_{chamber})\rm', '', 'Q = I·(V - V_0(SOC))', '    - \Sigma R_k x_k (I - x_k)', '(measured voltage minus OCV:', 'the electrical loss)', '', ...
    'T_{chamber} = the real chamber', 'column, steps 25 \leftrightarrow T included', '', sprintf('m·c_p = \\bf%.1f J/K\\rm  (known %g)', thm.mcp, truth.mcp), ...
    sprintf('h·A = \\bf%.3f W/K\\rm  (known %g)', thm.hA, truth.hA), sprintf('rms error %.2f K', thm.rmse), '', 'check: m·c_p \approx cell mass ×', '~1 J/(g·K)'});
shot('12_a', sprintf(['The thermal values. The cell is treated as one lump: its heat capacity times the rate of temperature change equals the heat generated minus what convects to the chamber. ' ...
    'The heat comes from the measured voltage: current times the gap between the terminal voltage and the open-circuit voltage, minus the energy stored in the R C capacitors. ' ...
    'The top plot shows it; @by far the biggest spike is the 5 C discharge. The ambient is the real chamber column, including its steps between 25 degrees and the test temperature, ' ...
    'so the chamber schedule is fully accounted for. The two unknowns, m c p and h A, are fitted @so that the simulated temperature, in blue, follows the measured one, in red. ' ...
    'Result: a thermal mass of %.1f joules per kelvin and h A of %.3f watts per kelvin, against %g and %g for the known cell, with %.2f kelvin rms error. ' ...
    'A sanity check for real cells: m c p should be close to the cell mass in grams times about one joule per gram kelvin.'], thm.mcp, thm.hA, truth.mcp, truth.hA, thm.rmse));

%% ================================================================ 13 the rest + summary
f = frame('The remaining boxes, and the summary', 'what goes into the workspace');
ax = axes(f, 'Position',[0 0 1 1], 'Visible','off'); %#ok<NASGU>
L = {sprintf('%-19s %-22s %s', 'variable', 'value', 'from')
     sprintf('%-19s %-22s %s', 'batt_AH', sprintf('%.4f Ah', AH), 'slowest FULL->EMPTY discharge')
     sprintf('%-19s %-22s %s', 'batt_SOC0', sprintf('%.3f', R.value.SOC0), 'Ah to the first FULL point')
     sprintf('%-19s %-22s %s', 'batt_V0_vec', sprintf('%.3f..%.3f V', R.value.V0_vec([1 end])), 'multi-rate fit + rest ends')
     sprintf('%-19s %-22s %s', 'batt_R0_vec', sprintf('%.1f..%.1f mOhm', 1000*[min(R.value.R0_vec) max(R.value.R0_vec)]), 'steps; middle scaled to R_dc')
     sprintf('%-19s %-22s %s', 'batt_R1/R2_vec', sprintf('%.1f / %.1f mOhm', 1000*median(R.value.R1_vec), 1000*median(R.value.R2_vec)), 'rests; middle scaled to R_dc')
     sprintf('%-19s %-22s %s', 'batt_tau1/2', sprintf('%.0f / %.0f s', median(R.value.tau1_vec), median(R.value.tau2_vec)), 'rest relaxation fits')
     sprintf('%-19s %-22s %s', 'batt_V_range', sprintf('%.3f..%.3f V', R.value.V_range), 'lowest / highest measured')
     sprintf('%-19s %-22s %s', 'batt_thermal_mass', sprintf('%.1f J/K', thm.mcp), 'temperature fit')
     sprintf('%-19s %-22s %s', 'batt_hA', sprintf('%.3f W/K', thm.hA), 'temperature fit')
     sprintf('%-19s %-22s %s', 'batt_T0', sprintf('%.2f K (%.1f C)', R.value.T0, R.value.T0 - 273.15), 'first cell temperature')
     sprintf('%-19s %-22s %s', 'batt_ambient', '[t  T_chamber(K)]', 'Load profile tab, real chamber')};
annotation(f, 'textbox', [0.05 0.10 0.90 0.72], 'String', L, 'FontName', 'Consolas', 'FontSize', 21, ...
    'Interpreter','none', 'EdgeColor', [0.8 0.8 0.8], 'BackgroundColor', [0.98 0.98 1], 'VerticalAlignment','middle', 'Margin', 24);
shot('13_a', sprintf(['Three small ones. The voltage range is just the lowest and highest voltage measured. ' ...
    'The initial cell temperature is the first cell reading, %.1f degrees, because the chamber always starts at 25. ' ...
    'That is the right start for the simulation, because batt ambient from the load profile tab carries the real chamber column, steps and all, to the thermal port. ' ...
    'And here is everything together, with the workspace name of each value. Capacity %.4f amp-hours, starting S O C %.3f, the open-circuit voltage table, ' ...
    'the resistances and time constants, and the thermal values. Every one of them came from the charge and discharge cycles exactly as you just saw.'], R.value.T0 - 273.15, AH, R.value.SOC0));

f = frame('Where each value is measured in your test', 'and where to see it in the app');
ax = axes(f, 'Position',[0.06 0.14 0.56 0.70]);
plot(ax, th_, V, 'Color', [0.6 0.6 0.6]); hold(ax,'on'); ylabel(ax, 'Voltage (V)'); xlabel(ax, 'Test time (h)'); fixLims(ax);
k = dis(1); arrow(ax, ph(k).t1/3600, V(ph(k).i1), 'R_0 (step), SOC \approx 1', [0.04 0.07], cOr);
arrow(ax, ph(k).t2/3600 + 1, V(ph(k).i2 + 30), 'R_k, \tau_k, V_0 end (rest)', [0.10 0.10], cBlue);
k = dis(1); arrow(ax, ph(k).t2/3600, V(ph(k).i2), 'AH: FULL \rightarrow EMPTY at 0.1C', [0.02 0.22], cRed);
k = dis(3); arrow(ax, mean([ph(k).t1 ph(k).t2])/3600, V(round(mean([ph(k).i1 ph(k).i2]))), 'V_0 + R_{dc}: all rates together', [0.02 0.13], cGr);
k = dis(end); arrow(ax, ph(k).t2/3600, V(ph(k).i2), 'm·c_p, h·A: 5C heating', [-0.10 0.10], cPur);
panel(f, {'\bfIn the app\rm', '', '1. Open CSV', '2. Modeling \rightarrow Extract', '3. green box = from data', '4. \bfHow?\rm = this walk-through', '    with your own numbers', '5. Save to workspace', '', ...
    '\bfThe 25 °C files\rm', 'now get an OCV too: the RC', 'wait only uses rests after', 'a discharge, and the note', 'names any rate it drops.'});
shot('14_a', ['To finish, here is where each value lives in your test. @R0 at the current steps, at the start and end of each discharge. ' ...
    '@The R C pairs, and the two ends of the open-circuit voltage curve, in the rests. @The capacity from the slowest full-to-empty discharge. ' ...
    '@The open-circuit voltage and the total resistance from all the discharge rates together. @And the thermal values from the self-heating of the 5 C discharge. ' ...
    'In the app, press Extract, and every green box has a How button that walks through the same steps with the numbers from your own file. ' ...
    'And the 25 degree files should now produce an open-circuit voltage as well. If one still does not, the note on the O C V box will say which discharge rate was dropped and why.']);

% ---------------------------------------------------------------- narration file
fid = fopen(fullfile(outDir, 'narration.tsv'), 'w', 'n', 'UTF-8');
for k = 1:size(narr,1), fprintf(fid, '%s\t%s\t%d\n', narr{k,1}, narr{k,2}, narr{k,3}); end
fclose(fid);
fprintf('%d frames written to %s\n', size(narr,1), frDir);

% =====================================================================
%  helpers (nested: they share frDir / narr / f)
% =====================================================================
    function fig = frame(ttl, sub)
        fig = figure('Visible','off', 'Units','pixels', 'Position',[0 0 1920 1080], 'Color','w', ...
            'DefaultAxesFontSize', 16, 'DefaultAxesLineWidth', 1.1, 'DefaultLineLineWidth', 1.2, ...
            'DefaultAxesBox', 'on', 'DefaultAxesXGrid','on', 'DefaultAxesYGrid','on', 'DefaultLegendFontSize', 14);
        annotation(fig, 'rectangle', [0 0.90 1 0.10], 'FaceColor', [0.10 0.20 0.38], 'EdgeColor','none');
        annotation(fig, 'textbox', [0.03 0.935 0.80 0.06], 'String', ttl, 'Color','w', 'FontSize', 34, ...
            'FontWeight','bold', 'EdgeColor','none', 'VerticalAlignment','middle', 'Interpreter','tex');
        annotation(fig, 'textbox', [0.03 0.900 0.80 0.04], 'String', sub, 'Color',[0.80 0.87 1], 'FontSize', 18, ...
            'EdgeColor','none', 'VerticalAlignment','middle', 'Interpreter','tex');
        annotation(fig, 'textbox', [0.80 0.91 0.18 0.08], 'String', 'Battery Builder · Modeling tab', 'Color',[0.80 0.87 1], ...
            'FontSize', 15, 'EdgeColor','none', 'HorizontalAlignment','right', 'VerticalAlignment','middle');
        f = fig;
        arrH = gobjects(0);
    end
    function panel(fig, L, pos)
        if nargin < 3, pos = [0.66 0.10 0.32 0.78]; end
        annotation(fig, 'textbox', pos, 'String', L, 'FontSize', 19, 'Interpreter','tex', ...
            'EdgeColor', [0.75 0.80 0.90], 'BackgroundColor', [0.96 0.97 1], 'VerticalAlignment','top', ...
            'Margin', 14, 'LineWidth', 1.5);
    end
    function eqs(fig, pos, L)
        annotation(fig, 'textbox', pos, 'String', L, 'FontSize', 24, 'Interpreter','latex', ...
            'EdgeColor', 'none', 'VerticalAlignment','middle', 'HorizontalAlignment','left');
    end
    function shot(id, text)
        % '@' in the narration = show the next arrow from here on ('@3' = the next 3).
        % Each piece becomes its own picture + voice clip, so the arrows appear
        % while the voice talks about them.
        parts = regexp(text, '@\d*', 'split');
        tok = regexp(text, '@(\d*)', 'tokens');
        n = ones(1, numel(tok));
        for q_ = 1:numel(tok), if ~isempty(tok{q_}{1}), n(q_) = str2double(tok{q_}{1}); end, end
        cum = [0 cumsum(n)];
        keep = find(~cellfun(@(c) isempty(strtrim(c)), parts));
        for q_ = keep
            last = q_ == keep(end);
            nShow = numel(arrH); if ~last, nShow = min(cum(q_), numel(arrH)); end
            set(arrH(1:nShow), 'Visible', 'on'); set(arrH(nShow+1:end), 'Visible', 'off');
            pid = id; if numel(keep) > 1, pid = sprintf('%s%d', id, find(keep == q_)); end
            drawnow;
            print(f, fullfile(frDir, [pid '.png']), '-dpng', '-r0');
            narr(end+1,:) = {pid, strtrim(parts{q_}), last}; %#ok<AGROW>
            fprintf('  frame %s\n', pid);
        end
        close(f);
    end
    function fixLims(axs)
        drawnow;
        for a_ = axs(:)'
            a_.XLimMode = 'manual'; a_.YLimMode = 'manual';
            if numel(a_.YAxis) > 1
                yyaxis(a_,'left'); a_.YLimMode = 'manual'; yyaxis(a_,'right'); a_.YLimMode = 'manual';
            end
        end
    end
    function arrow(ax, x, y, txt, off, col)
        p = d2f(ax, x, y);
        s0 = min(max(p + off, 0.02), 0.97);
        arrH(end+1) = annotation(f, 'textarrow', [s0(1) p(1)], [s0(2) p(2)], 'String', txt, 'FontSize', 17, ...
            'FontWeight','bold', 'Color', col, 'LineWidth', 2.5, 'HeadWidth', 14, 'HeadLength', 14, ...
            'TextBackgroundColor', [1 1 1], 'TextEdgeColor', col, 'TextMargin', 4, 'Interpreter','tex');
    end
    function txtAt(ax, x, y, s, col, va)
        if nargin < 6, va = 'middle'; end
        text(ax, x, y, s, 'Color', col, 'FontSize', 16, 'FontWeight','bold', ...
            'HorizontalAlignment','center', 'VerticalAlignment', va);
    end
end

% =====================================================================
function p = d2f(ax, x, y)
% data coordinates -> figure-normalized coordinates (linear axes)
pos = ax.Position; xl = ax.XLim;
if numel(ax.YAxis) > 1
    yl = ax.YAxis(strcmp(ax.YAxisLocation, {'left','right'})).Limits;
else
    yl = ax.YLim;
end
p = [pos(1) + (x - xl(1))/diff(xl)*pos(3), pos(2) + (y - yl(1))/diff(yl)*pos(4)];
end

function [a1, a2, a3] = threeAxes(f)
a1 = axes(f, 'Position',[0.06 0.64 0.56 0.22]);
a2 = axes(f, 'Position',[0.06 0.39 0.56 0.22]);
a3 = axes(f, 'Position',[0.06 0.12 0.56 0.22]);
linkaxes([a1 a2 a3], 'x');
end

function circuit(ax)
% the Table-Based block's equivalent circuit, drawn with lines
hold(ax,'on'); axis(ax,'off'); xlim(ax,[-0.3 12.4]); ylim(ax,[0 5.6]);
lw = 3; k = [0.1 0.1 0.1];
plot(ax, [0.5 0.5], [1 4], 'Color',k, 'LineWidth',lw);
rectangle(ax, 'Position',[0 1.9 1 1.2], 'Curvature',[1 1], 'LineWidth',lw, 'FaceColor',[0.85 0.95 0.85]);
text(ax, 0.5, 2.5, 'V_0', 'HorizontalAlignment','center', 'FontSize', 22, 'FontWeight','bold');
plot(ax, [0.5 2], [4 4], 'Color',k, 'LineWidth',lw);
rectangle(ax, 'Position',[2 3.7 1.6 0.6], 'LineWidth',lw, 'FaceColor',[1 0.9 0.8]);
text(ax, 2.8, 4.75, 'R_0', 'HorizontalAlignment','center', 'FontSize', 22, 'FontWeight','bold');
x0 = 3.6;
labs = {{'R_1','\tau_1'}, {'R_2','\tau_2'}};
for q = 1:2
    xa = x0 + 0.4;
    plot(ax, [x0 xa], [4 4], 'Color',k, 'LineWidth',lw);
    plot(ax, [xa xa], [3.3 4.7], 'Color',k, 'LineWidth',lw); plot(ax, [xa+2.4 xa+2.4], [3.3 4.7], 'Color',k, 'LineWidth',lw);
    plot(ax, [xa xa+0.6], [4.7 4.7], 'Color',k, 'LineWidth',lw); plot(ax, [xa+1.8 xa+2.4], [4.7 4.7], 'Color',k, 'LineWidth',lw);
    rectangle(ax, 'Position',[xa+0.6 4.45 1.2 0.5], 'LineWidth',lw, 'FaceColor',[0.85 0.9 1]);
    plot(ax, [xa xa+1.1], [3.3 3.3], 'Color',k, 'LineWidth',lw); plot(ax, [xa+1.3 xa+2.4], [3.3 3.3], 'Color',k, 'LineWidth',lw);
    plot(ax, [xa+1.1 xa+1.1], [2.95 3.65], 'Color',k, 'LineWidth',lw); plot(ax, [xa+1.3 xa+1.3], [2.95 3.65], 'Color',k, 'LineWidth',lw);
    text(ax, xa+1.2, 5.25, labs{q}{1}, 'HorizontalAlignment','center', 'FontSize', 20, 'FontWeight','bold');
    text(ax, xa+1.2, 2.55, labs{q}{2}, 'HorizontalAlignment','center', 'FontSize', 20, 'FontWeight','bold');
    x0 = xa + 2.4;
end
plot(ax, [x0 11.2], [4 4], 'Color',k, 'LineWidth',lw); plot(ax, [0.5 11.2], [1 1], 'Color',k, 'LineWidth',lw);
plot(ax, 11.2, 4, 'o', 'MarkerSize', 14, 'MarkerFaceColor','w', 'Color',k, 'LineWidth',2);
plot(ax, 11.2, 1, 'o', 'MarkerSize', 14, 'MarkerFaceColor','w', 'Color',k, 'LineWidth',2);
text(ax, 11.6, 4, '+', 'FontSize', 26); text(ax, 11.6, 1, '-', 'FontSize', 26);
text(ax, 11.4, 2.5, 'V', 'FontSize', 24, 'FontWeight','bold');
text(ax, 6, 0.3, 'all tables over SOC  ·  thermal mass m·c_p,  convection h·A', 'HorizontalAlignment','center', 'FontSize', 17, 'Color',[0.3 0.3 0.3]);
end

function [s, Rv, hot] = allSteps(d, soc, C, AH, Tref)
% every current step the R0 rule looks at, and whether it was left out
% because the cell was too far from Tref (same rules as r0FromEdges)
I = d.I; V = d.V; t = d.t;
dI = diff(I); dV = diff(V); dt = diff(t); dtAfter = dt;
if ~isempty(d.stepTime)
    st = d.stepTime(2:end); use = isfinite(st) & st >= 0 & st < dt; dtAfter(use) = st(use);
end
thr = max(C.minStepC*AH, 10*d.restThr);
k = find(abs(dI) > thr & dtAfter <= C.maxEdgeDt & dt > 0);
Rv = dV(k)./dI(k); ok = Rv > 0 & Rv < 1; k = k(ok); Rv = Rv(ok);
hot = abs(d.Tcell(k+1) - Tref) > C.maxDT;
s = soc(k);
end
