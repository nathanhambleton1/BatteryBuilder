function res = runDigitalTwin(src, varargin)
%RUNDIGITALTWIN  Test file -> fitted digital twin -> Simulink run -> comparison.
%
%   res = runDigitalTwin('cell_0C.csv')        one test file
%   res = runDigitalTwin({'a.csv','b.csv'})    several files (same cycle, any max C-rate)
%   res = runDigitalTwin('C:\data\folder')     every .csv in a folder
%   res = runDigitalTwin(R)                    an extraction result (the Modeling tab uses this)
%
%   Options (name, value):
%     'graphs'    folder for the PNGs (default <app folder>/graphs, '' = none)
%     'show'      true = leave the figures open (default false)
%     'progress'  @(msg) ... status text
%
%   What it does, in order:
%     1. loadBatteryCsv + extractCellParameters   = the Modeling tab's "1. Extract"
%     2. fitDigitalTwin                           = every table fitted to the whole test
%     3. twinWorkspace                            = ec_* (twin), batt_* (Modeling tab),
%                                                   twin_load, twin_ambient in the workspace
%     4. sim BatteryTwin.slx                      = Simscape: the twin AND the Modeling-tab
%                                                   Table-Based block on the same current
%     5. twinReport                               = key-point table + graphs
%
%   res fields: name, t, I, V, Vtwin, Vtb, T, Ttwin, Ttb, Tch, soc, phases, AH,
%   tw (fitted tables), R (extraction), table (key points per phase),
%   rms_mV / rmsTB_mV / rmsT_K, files (graphs), simSeconds.
%   For several files res is an array; a one-line-per-file summary is printed.

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'src'));
o = struct('graphs', fullfile(here, 'graphs'), 'show', false, 'progress', []);
for k = 1:2:numel(varargin), o.(lower(varargin{k})) = varargin{k+1}; end
say = @(m) fprintf('%s\n', m);
if ~isempty(o.progress), say = o.progress; end

% ---- several files: run each, print a summary
files = {};
if iscell(src), files = src;
elseif (ischar(src) || isstring(src)) && isfolder(src)
    L = dir(fullfile(src, '*.csv')); files = fullfile({L.folder}, {L.name});
end
if ~isempty(files)
    res = [];
    for k = 1:numel(files)
        say(sprintf('=== %d/%d  %s', k, numel(files), files{k}));
        try
            r = runDigitalTwin(files{k}, varargin{:});
            res = [res, r]; %#ok<AGROW>
        catch ME
            say(sprintf('    FAILED: %s', ME.message));
        end
    end
    if ~isempty(res)
        fprintf('\n%-30s %8s %10s %10s %8s %10s\n', 'file', 'max C', 'twin mV', 'TB mV', 'T K', 'worst key');
        for r = res
            fprintf('%-30s %8.2g %10.1f %10.0f %8.2f %10.1f\n', r.name, max(abs(r.I))/r.AH, r.rms_mV, r.rmsTB_mV, r.rmsT_K, ...
                max(abs([r.table.err_start_mV; r.table.err_end_mV; r.table.err_min_mV; r.table.err_max_mV])));
        end
    end
    return
end

% ---- 1. data + Modeling-tab extraction
if isstruct(src)
    R = src;
else
    say('Reading the file and extracting (Modeling tab, step 1)...');
    d = loadBatteryCsv(char(src));
    R = extractCellParameters(d, 2, [0 0.02 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.95 1]);
end

% ---- 2. fit the twin to the whole test
tw = fitDigitalTwin(R.d, R, struct('progress', say));

% ---- 3. workspace, 4. Simulink
twinWorkspace(tw, R);
mdl = 'BatteryTwin';
file = fullfile(here, [mdl '.slx']);
if ~isfile(file), say('Building BatteryTwin.slx...'); buildTwinModel(file); end
load_system(file);
say('Simulating BatteryTwin.slx in Simulink (both batteries, whole test)...');
ws = warning('off', 'all');                 % the Table-Based baseline collapses at the max-rate
restore = onCleanup(@() warning(ws));        % discharge and the solver says so many times
tic; out = sim(mdl, 'ReturnWorkspaceOutputs', 'on'); simS = toc;
clear restore

% the logged twin signals to the base workspace too: the Plot tab's
% "Load twin from workspace" reads twin_voltage / twin_current / twin_soc / twin_temp
for nm = {'twin_voltage','twin_current','twin_soc','twin_temp','tb_voltage','tb_soc','tb_temp'}
    assignin('base', nm{1}, out.get(nm{1}));
end

% ---- 5. compare
f = tw.fit;
at = @(name) sampleAt(out.get(name), f.t);
res.name = tw.name;
res.t = f.t; res.I = f.I; res.V = f.V; res.T = f.Tcell; res.Tch = f.Tch;
res.Vtwin = at('twin_voltage');
res.Ttwin = at('twin_temp') - 273.15;
res.soc = at('twin_soc');
res.Vtb = at('tb_voltage');
res.Ttb = at('tb_temp') - 273.15;
res.phases = f.phases; res.AH = tw.AH;
res.tw = tw; res.R = R;
res.rms_mV = 1000*rms(res.Vtwin - res.V);
res.rmsTB_mV = 1000*rms(res.Vtb - res.V);
res.rmsT_K = rms(res.Ttwin - res.T);
res.rmsMatlabCopy_mV = 1000*rms(res.Vtwin - tw.sim.V);
res.simSeconds = simS;
[res.table, res.files] = twinReport(res, o.graphs, o.show);
say(sprintf(['%s: twin %.1f mV rms (Modeling-tab Table-Based %.0f mV), temperature %.2f K rms, ' ...
    'Simulink %.0f s'], res.name, res.rms_mV, res.rmsTB_mV, res.rmsT_K, simS));
if nargout == 0, disp(res.table); end
end

function y = sampleAt(ts, tq)
% the logged signal at the test's sample times, just after any step (the
% cycler logs a new step's first sample 0.03-0.05 s after the switch)
[tu, iu] = unique(ts.Time, 'last');
y = interp1(tu, double(squeeze(ts.Data(iu))), min(tq + 1e-3, tu(end)), 'linear', 'extrap');
y = y(:);
end
