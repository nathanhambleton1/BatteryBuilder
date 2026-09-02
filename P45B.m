function P45B(action, varargin)
%P45B  Everything for the Molicel INR-21700-P45B CC-CV pack model.
%
%   Open P45B_CCCV.slx and press Run. That is the whole workflow - the model
%   calls this file for you when it opens and when it finishes.
%
%   COMMANDS
%     P45B build      Generate the Simscape battery library with Battery Builder.
%                     Run once, and again after changing Ns or Np.
%     P45B open       Open the model (and load its parameters).
%     P45B setup      Reload the parameters into the workspace. The model does
%                     this automatically on open; call it after editing settings.
%     P45B vary       Give every cell its own capacity / resistance / initial SOC.
%     P45B reset      Make all cells identical again.
%     P45B plot       Redraw the result figure from the last run.
%
%   P45B vary takes optional 1-sigma spreads (percent, except SOC):
%     P45B('vary', Capacity=3, Resistance=8, OCV=0.2, TimeConst=10, ...
%                  SOC=0.01, Seed=42)
%   Defaults: Capacity 2%, Resistance 5%, OCV 0.2%, TimeConst 10%, SOC 0.01, Seed 0.
%   Keep OCV small - 1% of 4 V is 40 mV, a bigger imbalance than any real pack.
%
%   TO CHANGE THE PACK, THE DUTY CYCLE, THE GAINS OR THE CELL DATA:
%   edit the config() function immediately below - it is the only place any
%   number is written down. Everything else is derived from it.
%
%   Changing Ns or Np needs "P45B build" afterwards, because the series and
%   parallel counts are compiled into the generated Simscape source. Nothing
%   else does.
%
%   See README.md for how every value is calculated.

if nargin == 0, action = 'help'; end

switch lower(char(action))
    case {'setup','params'},     doSetup();
    case 'build',                doBuild();
    case {'vary','variation'},   doVary(varargin{:});
    case 'reset',                doVary('Reset',true);
    case 'plot',                 doPlot(varargin{:});
    case 'open',                 doOpen();
    case 'help',                 disp(evalc('help P45B'));
    otherwise
        error('P45B:unknownCommand', ...
            ['Unknown command "%s". Valid: build, open, setup, vary, reset, ' ...
             'plot.\nType "help P45B" for details.'], char(action));
end
end


%% ======================================================================
%  =========================  USER SETTINGS  ============================
%  ======================================================================
function c = config()
% Edit anything in this function. Nothing else in the file needs to change.

% ---- Pack configuration ("P45B build" required after changing) --------
c.Ns = 195;                 % Cells in series
c.Np = 1;                   % Cells in parallel

% ---- Duty cycle --------------------------------------------------------
c.chargeCrate       = 1.0;  % Charge current as a multiple of cell capacity (P45B limit = 1C)
c.dischargeCrate    = 1.0;  % Discharge current as a multiple of cell capacity
c.SOC0              = 0.30; % Initial state of charge of every cell
c.taperCrate        = 0.05; % End the charge when the CV current tapers below this C-rate
c.SOC_stopDischarge = 0.25; % Stop discharging (start charging) below this mean SOC

% ---- Controller --------------------------------------------------------
c.Ts           = 1;         % Controller + local solver sample time (s)
c.gainMargin   = 0.5;       % Safety factor on Kp. 1.0 = the raw rule; the loop goes
                            % unstable around 1.4, so 0.5 leaves ~2.8x margin.
c.tauRatio     = 10;        % Kp/Ki. Larger = slower, gentler CV settling
c.SOC_cvDesign = 0.95;      % SOC at which the CV loop is tuned (top of charge)

% ---- Simulation --------------------------------------------------------
c.stopTime     = 2.5*3600;  % Simulation length (s)

% ---- P45B cell ---------------------------------------------------------
% Equivalent-circuit parameterisation of the Molicel INR-21700-P45B.
% Sources and the full derivation are in README.md section 3.1. In short:
%
%   Product Data Sheet v1.2 (molicel.com) gives
%       4500 mAh / 16.2 Wh typ,  3.6 V nom,  4.2 / 2.5 V limits,
%       AC impedance  7 mOhm @ 30% SOC,   DC impedance 15 mOhm @ 50% SOC
%   Molicel's "P45B Characteristics" deck states the DC figure is
%       "<15 mOhm DCR at 10s"  -> a 10 second pulse, not steady state.
%
%   R0    = AC impedance                       (1 kHz shorts out the RC branch)
%   R1    = (DCR_10s - R0) / (1 - exp(-10/tau1))
%   tau1  = the one value no datasheet gives; 5 s assumed (see README 3.1).
%
%   With tau1 = 5 s:  R1 = (0.015 - 0.007)/0.8647 = 9.25 mOhm at 50% SOC.
%   The V0 curve is an NMC shape scaled so that its mean over SOC reproduces
%   the datasheet 16.2 Wh / 4.5 Ah = 3.6 V nominal. Only the end points and
%   that mean are datasheet-backed; the shape between them is an estimate.
%
% Replace R0/R1/tau1/V0 with your own HPPC pulse data if you have it -
% README section 3.1 gives the equations for extracting them.

c.cellP.SOC_vec  = [0     0.05   0.10   0.20   0.30   0.40   0.50   0.60   0.70   0.80   0.90   0.95   1.00 ];

% Open-circuit voltage V0(SOC), V   -> mean over SOC = 3.63 V, giving 16.2 Wh
c.cellP.V0_vec   = [2.500 3.180  3.320  3.440  3.500  3.555  3.615  3.685  3.775  3.880  4.010  4.100  4.200];

% Ohmic resistance R0(SOC), Ohm     -> 7.0 mOhm at 30% SOC = datasheet AC value
c.cellP.R0_vec   = [0.0115 0.0095 0.0084 0.0074 0.0070 0.0069 0.0069 0.0069 0.0069 0.0070 0.0072 0.0074 0.0077];

% Polarisation resistance R1(SOC), Ohm  -> R0 + R1*(1-exp(-10/tau1)) = 15 mOhm at 50% SOC
c.cellP.R1_vec   = [0.0155 0.0128 0.0113 0.0099 0.0094 0.0093 0.00925 0.0093 0.0094 0.0096 0.0100 0.0104 0.0110];

% Polarisation time constant tau1(SOC), s   -> assumed, not from any datasheet
c.cellP.tau1_vec = [8      7      6      5.5    5      5      5      5      5      5      5.5    6      7    ];

c.cellP.AH       = 4.5;     % Typical capacity, A*hr        (minimum is 4.3)
c.cellP.Vmax     = 4.2;     % Charge cut-off voltage, V
c.cellP.Vmin     = 2.5;     % Discharge cut-off voltage, V
c.cellP.Vnom     = 3.6;     % Nominal voltage, V            (= 16.2 Wh / 4.5 Ah)
c.cellP.Imaxdis  = 45;      % Max continuous discharge current, A  (80 degC cut-off)
c.cellP.Ichgstd  = 4.5;     % Standard charge current, A    (1C)
c.cellP.Imaxchg  = 13.5;    % Max charge current, A         (3C, 70 degC cut-off)
end
%  ======================================================================
%  =======================  END USER SETTINGS  ==========================
%  ======================================================================


%% ======================================================================
function doSetup()
% Derive every model variable from config() and put them in the base workspace.
S     = config();
cellP = S.cellP;
S.Ncells = S.Ns*S.Np;

% ---- Battery block parameter struct (read by the generated Module block)
S.Pack.SOC_vecCell  = cellP.SOC_vec;
S.Pack.V0_vecCell   = cellP.V0_vec;
S.Pack.R0_vecCell   = cellP.R0_vec;
S.Pack.R1_vecCell   = cellP.R1_vec;
S.Pack.tau1_vecCell = cellP.tau1_vec;
S.Pack.AHCell       = cellP.AH;
S.Pack.V_rangeCell  = [0, inf];   % [cellP.Vmin cellP.Vmax] to assert on abuse

% ---- Cell-to-cell variation (zero here; "P45B vary" randomises it)
z = zeros(S.Ncells,1);
for f = {'SOC_vec','V0_vec','R0_vec','R1_vec','tau1_vec','AH','V_range'}
    S.Pack.([f{1} 'CellPercentDeviation']) = z;
end
S.SOC0Cell = S.SOC0*ones(S.Ncells,1);   % per-cell initial SOC

% ---- Pack ratings ------------------------------------------------------
S.packVnom = S.Ns*cellP.Vnom;
S.packVmax = S.Ns*cellP.Vmax;
S.packVmin = S.Ns*cellP.Vmin;
S.packAH   = S.Np*cellP.AH;
S.packWh   = S.packVnom*S.packAH;

% ---- Duty-cycle currents ----------------------------------------------
S.Icharge    = S.chargeCrate   *cellP.AH*S.Np;   % Pack charging current, A
S.Idischarge = S.dischargeCrate*cellP.AH*S.Np;   % Pack discharging current, A
S.Iterm      = S.taperCrate    *cellP.AH*S.Np;   % Charge-termination current, A
S.dVterm     = 0.010;                            % How close to vMaxCell counts as "in CV", V

% ---- CC-CV controller gains -------------------------------------------
% The CC-CV block sees per-cell volts and commands pack amps, so the plant
% gain it must invert is d(vCell)/d(Ipack) = Rcell/Np ohms. Unity loop gain is
% therefore Kp = Np/Rcell; gainMargin backs off from that. See README.md.
S.Rcell_cv = interp1(cellP.SOC_vec, cellP.R0_vec + cellP.R1_vec, S.SOC_cvDesign, 'linear');
S.Reff     = S.Rcell_cv/S.Np;     % Plant gain the CV loop must invert, V per pack-amp

S.vMaxCell = cellP.Vmax;          % Voltage the CV loop regulates the highest cell to
S.Kp       = S.gainMargin/S.Reff; % Proportional gain, A/V  (= gainMargin*Np/Rcell)
S.Ki       = S.Kp/S.tauRatio;     % Integral gain,     A/(V*s)
S.Kaw      = 1/S.Ts;              % Anti-windup back-calculation gain, 1/s
S.Kt       = 1/S.Ts;              % Signal-tracking gain (bumpless CC->CV), 1/s
S.tauCV    = (1 + S.Kp*S.Reff)/(S.Ki*S.Reff);   % CV time constant, s (= 2*tauRatio)

checkLibrary(S.Ns, S.Np);

fn = fieldnames(S);
for k = 1:numel(fn), assignin('base', fn{k}, S.(fn{k})); end
printSummary(S);
end


%% ======================================================================
function printSummary(S)
fprintf('\n  P45B pack  %ds%dp  (%d cells)\n', S.Ns, S.Np, S.Ncells);
fprintf('    Voltage        %.1f V nominal   %.1f V full   %.1f V empty\n', ...
        S.packVnom, S.packVmax, S.packVmin);
fprintf('    Capacity       %.2f Ah   =  %.2f kWh\n', S.packAH, S.packWh/1000);
fprintf('    Currents       %.2f A charge (%.2gC)   %.2f A discharge (%.2gC)\n', ...
        S.Icharge, S.chargeCrate, S.Idischarge, S.dischargeCrate);
fprintf('    Charge ends    when the CV current tapers below %.3f A (C/%.0f)\n', ...
        S.Iterm, 1/S.taperCrate);
fprintf('    Rcell @ SOC %.2f   %.2f mOhm  (R0+R1)\n', S.SOC_cvDesign, S.Rcell_cv*1000);
fprintf('    CC-CV gains    Kp = %.4g A/V   Ki = %.4g A/(V*s)   Kaw = %.4g 1/s   Kt = %.4g 1/s\n', ...
        S.Kp, S.Ki, S.Kaw, S.Kt);
fprintf('                   (unity-loop-gain Kp would be %.4g; using gainMargin = %.2f)\n', ...
        1/S.Reff, S.gainMargin);
fprintf('    CV settling    tau = %.1f s  (%.0f x Ts)\n', S.tauCV, S.tauCV/S.Ts);
fprintf('\n    Press Run to simulate.  Edit config() in P45B.m to change the pack,\n');
fprintf('    the duty cycle or the gains.  "P45B vary" makes the cells differ.\n\n');
end


%% ======================================================================
function doBuild()
%DOBUILD  Generate the Simscape battery library with Battery Builder.
%
%   Produces, next to this file:
%       P45BPack_lib.slx    Simulink library holding the "Pack" block
%       +P45BPack/          Simscape source for the pack and its cells
%       P45BPack.mat        Battery Builder object, for the Battery Builder app
%
%   To inspect or edit the pack in the Battery Builder app afterwards:
%       load P45BPack.mat, then run  batteryBuilder

here = thisDir();
addpath(here);
old = cd(here);
restoreDir = onCleanup(@() cd(old));   % restore the caller's folder on exit

c  = config();
Ns = c.Ns;  Np = c.Np;
fprintf('Building a %ds%dp P45B pack (%d cells)...\n', Ns, Np, Ns*Np);

% ---- Cell -------------------------------------------------------------
% Table-Based cell, one RC pair, no temperature dependence, no thermal port.
cellObj = batteryCell;   % 'cell' would shadow the builtin
cellObj.Name = 'P45B';
cellObj.CellModelOptions.BlockParameters.prm_dyn      = 'rc1';   % 1 RC branch -> R1/tau1
cellObj.CellModelOptions.BlockParameters.T_dependence = 'no';    % isothermal, no T tables
cellObj.CellModelOptions.BlockParameters.thermal_port = 'omit';  % no thermal node
cellObj.CellModelOptions.BlockParameters.prm_dir      = 'noCurrentDirectionality';
cellObj.CellModelOptions.BlockParameters.SOC_port     = 'no';    % SOC read with a Probe block
cellObj.Capacity = simscape.Value(c.cellP.AH,'A*hr');

% ---- Parallel assembly (Np cells) -------------------------------------
pa = batteryParallelAssembly(cellObj);
pa.Name                   = 'PA';
pa.NumParallelCells       = Np;
pa.ModelResolution        = 'Detailed';         % model every cell individually
pa.CellParameterVariation = 'PercentDeviation'; % expose per-cell deviation inputs

% ---- Module (Ns assemblies in series) ---------------------------------
m = batteryModule(pa);
m.Name                   = 'Pack';              % -> the "Pack.*" parameter struct
m.NumSeriesAssemblies    = Ns;
m.ModelResolution        = 'Detailed';
m.CellParameterVariation = 'PercentDeviation';

% ---- Generate ---------------------------------------------------------
if isfile(fullfile(here,'P45BPack_lib.slx')) && bdIsLoaded('P45BPack_lib')
    close_system('P45BPack_lib', 0);
end
buildBattery(m, LibraryName='P45BPack', MaskParameters='VariableNamesByType');

% buildBattery also drops a P45BPack_param.m holding Simscape's stock 27 Ah
% cell defaults. Nothing uses it and the numbers contradict config(), so
% remove it rather than leave a misleading file behind.
stale = fullfile(here,'P45BPack_param.m');
if isfile(stale), delete(stale); end

save(fullfile(here,'P45BPack.mat'), 'cellObj', 'pa', 'm');
fprintf(['\nDone. %ds%dp library generated.\n' ...
         'Open P45B_CCCV.slx and press Run.\n\n'], Ns, Np);
end


%% ======================================================================
function checkLibrary(Ns, Np)
%CHECKLIBRARY  Verify the generated library matches the requested Ns/Np.
%
%   The series and parallel counts are compiled into the Simscape source that
%   Battery Builder generates, so changing Ns or Np in config() has no effect
%   until the library is rebuilt. This catches that silently-wrong case.

ssc = fullfile(thisDir(), '+P45BPack', 'Pack.ssc');
if ~isfile(ssc)
    error('P45B:noLibrary', ...
        ['The Simscape battery library has not been generated yet.\n' ...
         'Run this first:\n\n    P45B build\n']);
end

txt    = fileread(ssc);
Pbuilt = grabInt(txt, 'P');   % cells in parallel, compiled into the .ssc
Sbuilt = grabInt(txt, 'S');   % assemblies in series

if Sbuilt ~= Ns || Pbuilt ~= Np
    error('P45B:libraryMismatch', ...
        ['config() asks for a %ds%dp pack but the generated library is %ds%dp.\n' ...
         'Regenerate it:\n\n    P45B build\n'], Ns, Np, Sbuilt, Pbuilt);
end
end

function v = grabInt(txt, name)
tok = regexp(txt, ['^\s*' name '\s*=\s*(\d+)\s*;'], 'tokens', 'once', 'lineanchors');
if isempty(tok)
    error('P45B:sscParse', 'Could not read "%s" from the generated Pack.ssc.', name);
end
v = str2double(tok{1});
end


%% ======================================================================
function doVary(varargin)
%DOVARY  Give every cell in the pack its own parameters.
%
%   The generated battery block models each of the Ns*Np cells separately and
%   accepts a percent deviation per cell for each table parameter. This fills
%   those vectors with a normal distribution and writes them straight back to
%   the base workspace, so the next simulation picks them up. No rebuild.

p = inputParser;
p.addParameter('Capacity',   2,     @isnumeric);   % 1-sigma % spread of AH
p.addParameter('Resistance', 5,     @isnumeric);   % 1-sigma % spread of R0 and R1
p.addParameter('OCV',        0.2,   @isnumeric);   % 1-sigma % spread of V0
p.addParameter('TimeConst',  10,    @isnumeric);   % 1-sigma % spread of tau1
p.addParameter('SOC',        0.01,  @isnumeric);   % 1-sigma spread of initial SOC, in SOC points
p.addParameter('Seed',       0,     @isnumeric);   % random seed for a repeatable pack
p.addParameter('Reset',      false, @(x)islogical(x)||isnumeric(x));
p.parse(varargin{:});
o = p.Results;

if ~evalin('base','exist(''Pack'',''var'')')
    error('P45B:noParams', 'Open P45B_CCCV.slx first (or run "P45B setup").');
end
Pack   = evalin('base','Pack');
Ncells = evalin('base','Ncells');
SOC0   = evalin('base','SOC0');

z = zeros(Ncells,1);
if o.Reset
    dAH = z; dR = z; dR1 = z; dV0 = z; dTau = z; dSOC = z;
    fprintf('\n  Cell variation cleared - all %d cells identical.\n\n', Ncells);
else
    rng(o.Seed);                       % repeatable pack
    dAH  = o.Capacity   * randn(Ncells,1);
    dR   = o.Resistance * randn(Ncells,1);
    dR1  = o.Resistance * randn(Ncells,1);
    dV0  = o.OCV        * randn(Ncells,1);
    dTau = o.TimeConst  * randn(Ncells,1);
    dSOC = o.SOC        * randn(Ncells,1);

    % Keep the draw physical: nothing may approach -100% (a zero-capacity or
    % zero-resistance cell makes the Simscape network singular).
    clamp = @(x) max(min(x, 50), -50);
    dAH = clamp(dAH); dR = clamp(dR); dR1 = clamp(dR1); dTau = clamp(dTau);
    dV0 = max(min(dV0, 5), -5);
end

Pack.AHCellPercentDeviation       = dAH;
Pack.R0_vecCellPercentDeviation   = dR;
Pack.R1_vecCellPercentDeviation   = dR1;
Pack.V0_vecCellPercentDeviation   = dV0;
Pack.tau1_vecCellPercentDeviation = dTau;
Pack.SOC_vecCellPercentDeviation  = z;   % SOC breakpoints are a grid, never varied
Pack.V_rangeCellPercentDeviation  = z;   % V_range holds an inf, cannot be scaled

assignin('base','Pack',Pack);
assignin('base','SOC0Cell', min(max(SOC0 + dSOC, 0.01), 0.99));

if ~o.Reset
    AH  = evalin('base','cellP.AH');
    s0  = evalin('base','SOC0Cell');
    fprintf('\n  Cell-to-cell variation applied to %d cells (seed %d)\n', Ncells, o.Seed);
    fprintf('    Capacity    %.3f - %.3f Ah   (1-sigma %.1f%%)\n', ...
        AH*(1+min(dAH)/100), AH*(1+max(dAH)/100), o.Capacity);
    fprintf('    Resistance  %+.1f%% to %+.1f%%   (1-sigma %.1f%%)\n', ...
        min(dR), max(dR), o.Resistance);
    fprintf('    Initial SOC %.4f - %.4f      (1-sigma %.3f)\n', min(s0), max(s0), o.SOC);
    fprintf('  Press Run on P45B_CCCV to simulate this pack.\n\n');
end
end


%% ======================================================================
function doPlot(logsIn)
%DOPLOT  Plot the charge/discharge cycle of the P45B pack.
%
%   Runs automatically when P45B_CCCV.slx finishes (StopFcn). The per-cell
%   signals come from the Probe block attached to the battery, so the spread
%   produced by "P45B vary" shows up here.

if nargin == 0
    if evalin('base', 'exist(''logsout'',''var'')')
        logsIn = evalin('base', 'logsout');
    else
        warning('P45B:noLog', ...
            'No signal log found. Simulate P45B_CCCV first, then "P45B plot".');
        return
    end
end
g = @(n) logsIn.getElement(n).Values;

cur   = g('current');
t     = cur.Time/3600;                       % hours
Ipack = cur.Data(:);
vC    = squeeze(g('cellVoltages').Data);
soc   = squeeze(g('socCells').Data);
if size(vC,1)  ~= numel(t), vC  = vC.';  end
if size(soc,1) ~= numel(t), soc = soc.'; end

Vpack   = sum(vC, 2);
vCmax   = max(vC, [], 2);   vCmin  = min(vC, [], 2);
socMean = mean(soc, 2);
socMax  = max(soc, [], 2);  socMin = min(soc, [], 2);

vLim = evalin('base','vMaxCell');
Ns   = evalin('base','Ns');
Np   = evalin('base','Np');
blue = [0 0.447 0.741]; orange = [0.85 0.325 0.098]; grey = [0.5 0.5 0.5];

fh = findobj('Type','figure','Name','P45B_CCCV');
if isempty(fh), fh = figure('Name','P45B_CCCV'); else, fh = fh(1); end
figure(fh); clf(fh);
tl = tiledlayout(fh, 4, 1, 'TileSpacing','compact', 'Padding','compact');

ax(1) = nexttile;
plot(t, Ipack, 'LineWidth', 1.5, 'Color', blue); grid on
ylabel('Current (A)'); title('Pack current   (+ charging, - discharging)');

ax(2) = nexttile;
plot(t, vCmax, '-',  'LineWidth', 2.0, 'Color', orange); hold on
plot(t, vCmin, '--', 'LineWidth', 1.2, 'Color', blue);
yline(vLim, ':', sprintf('CV target %.2f V', vLim), 'Color', grey);
grid on; ylabel('Cell voltage (V)');
title('Cell voltage - highest and lowest cell in the pack');
legend({'max cell','min cell'}, 'Location','southeast');

ax(3) = nexttile;
plot(t, Vpack, 'LineWidth', 1.5, 'Color', blue); grid on
ylabel('Pack voltage (V)'); title('Pack terminal voltage');

ax(4) = nexttile;
fill([t; flipud(t)], [socMax; flipud(socMin)], orange, ...
     'FaceAlpha', 0.30, 'EdgeColor','none'); hold on
plot(t, socMean, 'LineWidth', 1.5, 'Color', blue); grid on
ylabel('SOC'); xlabel('Time (hours)'); ylim([0 1]);
title('State of charge - mean, with cell-to-cell spread shaded');

linkaxes(ax, 'x'); xlim(ax(1), [0 max(t)]);
title(tl, sprintf('P45B %ds%dp  CC-CV charge / discharge', Ns, Np));

fprintf(['  Simulated %.2f h  |  peak cell %.4f V  |  cell spread at end ' ...
         '%.1f mV / %.2f %% SOC\n'], t(end), max(vCmax), ...
        (vCmax(end)-vCmin(end))*1000, (socMax(end)-socMin(end))*100);
end


%% ======================================================================
function doOpen()
addpath(thisDir());
open_system(fullfile(thisDir(),'P45B_CCCV.slx'));
end

function d = thisDir()
d = fileparts(mfilename('fullpath'));
end
