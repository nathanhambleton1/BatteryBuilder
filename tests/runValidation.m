function results = runValidation(outDir)
%RUNVALIDATION  Check the parameter extraction against a cell with KNOWN values.
%
%   results = runValidation            % writes test files to tempdir/bb_validation
%
%   1. makeSyntheticCellData writes 0 °C and 25 °C test files from a known
%      2-RC cell (same structure as the Simscape Table-Based block).
%   2. Each file is run through extractCellParameters on its own (exactly what
%      the Modeling tab does) and every table is compared with the truth.
%   3. A cut-down file (no full discharge, no temperature columns) checks that
%      nothing is made up: AH, SOC, OCV, R and thermal must come back EMPTY.
%   Prints PASS / FAIL.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', 'src'));
if nargin < 1, outDir = fullfile(tempdir, 'bb_validation'); end

fprintf('\n== 1. synthetic data -> %s\n', outDir);
[files, truth] = makeSyntheticCellData(outDir, [25 0]);
grid = [0 0.02 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.95 1];
ok = true;

fprintf('\n== 2. extraction, one file at a time\n');
for k = 1:numel(files)
    d = loadBatteryCsv(files{k});
    R = extractCellParameters(d, 2, grid);
    T = d.T_C;
    % the extraction defines SOC = 1 at the end of a CC-CV charge; the synthetic
    % cell has its own internal SOC -> map one onto the other before comparing
    S = load(regexprep(files{k}, '\.csv$', '_truth.mat'));
    m = [ones(numel(R.d.soc),1), R.d.soc] \ S.trueSOC;
    g = R.value.SOC_vec; gt = m(1) + m(2)*g; mid = g >= 0.1 & g <= 0.95;
    e.AH   = 100*(R.value.AH/truth.Q - 1);
    e.ocv  = 1000*max(abs(R.value.V0_vec(mid) - truth.ocv(gt(mid),T)));
    e.R0   = 100*median(abs(R.value.R0_vec(mid)./truth.R0(gt(mid),T) - 1));
    e.R1   = 100*median(abs(R.value.R1_vec(mid)./truth.R1(gt(mid),T) - 1));
    e.R2   = 100*median(abs(R.value.R2_vec(mid)./truth.R2(gt(mid),T) - 1));
    e.tau1 = 100*median(abs(R.value.tau1_vec(mid)./truth.tau1(gt(mid),T) - 1));
    e.tau2 = 100*median(abs(R.value.tau2_vec(mid)./truth.tau2(gt(mid),T) - 1));
    e.mcp  = 100*(R.value.thermal_mass/truth.mcp - 1);
    e.hA   = 100*(R.value.hA/truth.hA - 1);
    % starting SOC: the extraction's SOC (1 = end of CC-CV, 0 = cut-off) at the
    % first sample vs the true SOC mapped onto that same scale
    socTrue0 = (S.trueSOC(1) - m(1))/m(2);
    e.SOC0 = R.value.SOC0 - socTrue0;
    e.soc0chk = abs(R.diag.soc.check.socOcv - R.diag.soc.check.socCC);
    fprintf(['   %5.1f °C  AH %+.1f%% | SOC0 %.3f (err %+.3f, voltage check diff %.3f) | OCV max %.1f mV\n' ...
             '            R0 %.1f%%  R1 %.1f%%  R2 %.1f%%  tau1 %.1f%%  tau2 %.1f%% | m*cp %+.1f%%  h*A %+.1f%%\n'], ...
             T, e.AH, R.value.SOC0, e.SOC0, e.soc0chk, e.ocv, e.R0, e.R1, e.R2, e.tau1, e.tau2, e.mcp, e.hA);
    ok = ok && abs(e.AH) < 3 && abs(e.SOC0) < 0.02 && e.soc0chk < 0.03 && e.ocv < 15 && ...
         e.R0 < 10 && e.R1 < 15 && e.R2 < 15 && e.tau1 < 15 && e.tau2 < 15 && ...
         abs(e.mcp) < 15 && abs(e.hA) < 15;
    results.(sprintf('T%d', round(T))) = e;
end

fprintf('\n== 3. partial test: nothing may be guessed\n');
opts = detectImportOptions(files{1}, 'VariableNamingRule','preserve');
opts = setvaropts(opts, 'DateTime', 'Type','string');
Tb = readtable(files{1}, opts);
t = Tb.('TestTime (s)');
Tb = Tb(t >= 9*3600 & t <= 20*3600, :);              % no full discharge in here
Tb.('Temp 1') = []; Tb.('Chamber Temperature (C)') = [];
cut = fullfile(outDir, 'partial_noTemp.csv');
writetable(Tb, cut);
R = extractCellParameters(loadBatteryCsv(cut), 2, grid);
empty = {'AH','SOC0','V0_vec','R0_vec','R1_vec','tau1_vec','thermal_mass','hA','T0'};
found = cellfun(@(k) R.found.(k), empty);
fprintf('   found (should all be 0): %s\n', strjoin(string(empty) + "=" + string(double(found)), ', '));
ok = ok && ~any(found);
R = extractCellParameters(loadBatteryCsv(cut), 2, grid, truth.Q);   % datasheet AH typed in
fprintf('   with a datasheet AH: R0 found %d, R1 found %d, AH still not "calculated": %d\n', ...
    R.found.R0_vec, R.found.R1_vec, ~R.found.AH);
ok = ok && R.found.R0_vec && R.found.R1_vec && ~R.found.AH;

if ok, s = 'PASS'; else, s = 'FAIL'; end
fprintf('\n== RESULT: %s\n', s);
results.pass = ok;
end
