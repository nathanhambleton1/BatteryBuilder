function results = runValidation(outDir)
%RUNVALIDATION  End-to-end check of plotBatteryData on synthetic data.
%
%   results = runValidation            % writes to tempdir/plotBatteryData_validation
%
%   1. generates 0 / 25 / 45 °C test files from a known 2-RC cell
%   2. runs the parameter extraction and compares every table with the truth
%   3. exports the 25 °C and 0 °C load profiles, builds the Simscape twin,
%      simulates it and compares the terminal voltage with the "measured" data
%   Requires Simscape + Simscape Battery (or Simscape Electrical) for step 3.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..'));
if nargin < 1, outDir = fullfile(tempdir, 'plotBatteryData_validation'); end

fprintf('\n== 1. synthetic data -> %s\n', outDir);
tic; [files, truth] = makeSyntheticCellData(outDir); fprintf('   %.1f s\n', toc);

fprintf('\n== 2. extraction\n');
o = plotBatteryData('defaults');
o.nRC = 2;
tic; [P, ds] = plotBatteryData('extract', files, o); tEx = toc;
fprintf('%s\n', P.report{:});
fprintf('   extraction took %.1f s\n', tEx);

g = P.SOC_vec(:);
mid = g >= 0.1 & g <= 0.95;           % compare away from the steep ends
res = struct();
res.capacityErrPct = 100*(P.AH - truth.Q)/truth.Q;
fprintf('\n   capacity  %.4f Ah (truth %.4f)  -> %+.2f %%\n', P.AH, truth.Q, res.capacityErrPct);
% The extraction defines SOC = 1 at the end of a CC-CV charge and counts
% coulombs with the measured capacity; the synthetic cell has its own internal
% SOC. Map one onto the other (affine fit over the whole record) before
% comparing tables point by point.
map = zeros(numel(ds), 2);
for k = 1:numel(ds)
    S = load(regexprep(files{k}, '\.csv$', '_truth.mat'));
    map(k,:) = [ones(numel(ds(k).soc),1), ds(k).soc] \ S.trueSOC;
end
fprintf('   SOC map true = a + b*extracted:  a = %.4f, b = %.4f (mean of files)\n', mean(map));
for j = 1:numel(P.T_vec_C)
    T = P.T_vec_C(j);
    k = find(abs([ds.T_C] - T) < 1, 1);
    gt = map(k,1) + map(k,2)*g;                % breakpoints in true-SOC units
    e.ocv  = 1000*(P.V0_mat(mid,j) - truth.ocv(gt(mid),T));
    e.R0   = 100*(P.R0_mat(mid,j)./truth.R0(gt(mid),T) - 1);
    e.R1   = 100*(P.R{1}(mid,j)./truth.R1(gt(mid),T) - 1);
    e.R2   = 100*(P.R{2}(mid,j)./truth.R2(gt(mid),T) - 1);
    e.tau1 = 100*(P.tau{1}(mid,j)./truth.tau1(gt(mid),T) - 1);
    e.tau2 = 100*(P.tau{2}(mid,j)./truth.tau2(gt(mid),T) - 1);
    fprintf(['   %5.1f °C  OCV max|err| %5.1f mV | median |err|: R0 %4.1f%%  R1 %4.1f%%  ' ...
             'R2 %4.1f%%  tau1 %4.1f%%  tau2 %4.1f%%\n'], T, max(abs(e.ocv)), ...
        median(abs(e.R0)), median(abs(e.R1)), median(abs(e.R2)), median(abs(e.tau1)), median(abs(e.tau2)));
    res.tables(j) = e; %#ok<AGROW>
end
fprintf('   thermal  m*cp %.3g J/K (truth %.3g)  h*A %.3g W/K (truth %.3g)\n', ...
    P.thermal_mass, truth.mcp, P.hA, truth.hA);

fprintf('\n== 3. digital twin\n');
o.modelDir = outDir;
o.modelName = 'validationTwin';
for T = [25 0]
    k = find(abs([ds.T_C] - T) < 1, 1);
    prof = plotBatteryData('profile', ds(k), o);
    r = plotBatteryData('twin', P, prof, o);
    fprintf('   %s\n', r.summary{:});
    res.twin.(sprintf('T%d', T)) = r;
end
close_system(o.modelName, 0);

% ---- pass / fail
ok = abs(res.capacityErrPct) < 3;
for j = 1:numel(res.tables)
    ok = ok && max(abs(res.tables(j).ocv)) < 15 && median(abs(res.tables(j).R0)) < 15;
end
ok = ok && res.twin.T25.rmse_mV < 20 && res.twin.T0.rmse_mV < 30;
ok = ok && abs(P.thermal_mass/truth.mcp - 1) < 0.3 && abs(P.hA/truth.hA - 1) < 0.3;
fprintf('\n== RESULT: %s\n', ternary(ok, 'PASS', 'FAIL'));
res.pass = ok;
res.P = P;
results = res;
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
