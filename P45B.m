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
%   THE DUTY CYCLE is a discharge pulse train against a charger that stops when
%   the pack is full:
%     pulseCrate / pulsePeriod / pulseDuty / pulseDelay  size and time the pulse
%     V_recharge          once full, the pack rests until the highest cell
%                         falls back to this, then charges again
%     SOC_minDischarge    protection floor; the pulse is refused below it,
%     SOC_resumeDischarge and stays refused until the charger reaches this
%   The pulse always wins. Between pulses the pack charges if it needs to and
%   sits at zero current if it does not.
%
%   PASSIVE CELL BALANCING is built into the pack and enabled by default. Every
%   parallel assembly carries a bleed resistor and a switch across it, and the
%   stock Simscape Battery "Passive Cell Balancing" block closes the switch on
%   any assembly sitting more than balThreshold in SOC above the lowest one in
%   the pack. balEnable = false in config() holds every switch open. Neither
%   the threshold nor the enable needs a rebuild.
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

% ---- Charging ----------------------------------------------------------
c.chargeCrate       = 1.0;  % Charge current as a multiple of cell capacity (P45B standard = 1C)
c.SOC0              = 0.30; % Initial state of charge of every cell
c.taperCrate        = 0.05; % Charge is complete when the CV current tapers below this C-rate
c.V_recharge        = 4.10; % Once complete, charge again only after the highest
                            % cell falls back to this. This is the anti-chatter
                            % hysteresis. Cell volts, not SOC: on an unbalanced
                            % pack the mean SOC never gets near 1, so any SOC
                            % threshold high enough to trip is only millivolts
                            % clear of the CV band. See README section 2.

% ---- Discharge pulse train --------------------------------------------
% A Pulse Generator inside "Charge Logic" drives the discharge. The pulse has
% absolute priority: whenever it is high the pack discharges, whatever the
% charger wants. Between pulses the pack charges if it needs to, and rests if
% it does not.
c.pulseCrate        = 1.0;  % Pulse amplitude as a multiple of cell capacity (limit = 10C)
c.pulsePeriod       = 900;  % Pulse repeat period, s
c.pulseDuty         = 20;   % Percent of each period the pulse is on
c.pulseDelay        = 300;  % Delay before the first pulse, s
c.SOC_minDischarge  = 0.05; % Stop the pulse below this mean SOC, and
c.SOC_resumeDischarge = 0.25; % do not let it start again until the charger has
                            % brought the pack back up to here. Same one-way
                            % hysteresis as V_recharge, at the other end. Set
                            % SOC_minDischarge = 0 to let the pulse run the
                            % pack flat with no floor at all.

% ---- Passive cell balancing -------------------------------------------
% Two stock pieces, no custom blocks. Battery Builder puts a bleed resistor and
% a signal-controlled switch across every parallel assembly (BalancingStrategy
% = "Passive", set in doBuild) and brings the switch commands out as a
% "balancing" inport, Ns wide. Simscape / Battery / BMS / Cell Balancing /
% Passive Cell Balancing drives that port: it compares every assembly against
% the lowest one in the pack and commands a 1 wherever the gap exceeds
% balThreshold.
%
% The comparison is on SOC, not voltage. Under the 1C pulse a cell's terminal
% voltage moves ~80 mV on IR alone - far more than the imbalance being chased -
% so a voltage threshold would trip on load rather than on charge.
% socParallelAssembly comes straight off the pack block and is load-free.
c.balEnable     = true;     % Master enable. false holds every switch open.
c.balThreshold  = 0.02;     % Bleed an assembly this far in SOC above the lowest one
c.balHysteresis = 0.01;     % ...and stop once it is back inside threshold - this.
                            % Must be <= balThreshold. Zero would make the
                            % switch chatter at the threshold; keep some gap.
c.balOnDelay    = 10;       % The condition must hold this long before the switch
c.balOffDelay   = 10;       % closes, and this long before it opens again, s
c.balR          = 33;       % Bleed resistor, Ohm, one per parallel assembly.
                            % Smaller = faster balancing and more heat: at 3.6 V
                            % a 33 Ohm shunt is 0.11 A / 0.39 W. "P45B setup"
                            % prints the current, the power and the bleed rate.

% ---- Balancing switch idealisation (leave alone) ----------------------
% Mask parameters of the generated switch. The defaults are ideal enough that
% they do not show up in any result; they are here only because config() is
% meant to be the one place a number is written down.
c.balRon        = 0.01;     % Switch closed resistance, Ohm
c.balGoff       = 1e-8;     % Switch open conductance, 1/Ohm (leaks ~40 nA per assembly)
c.balVt         = 0.5;      % Command above this closes the switch (commands are 0/1)

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

% ---- Balancing circuit (mask parameters of the same generated block) ---
S.Pack.CellBalancingResistance       = S.balR;
S.Pack.CellBalancingClosedResistance = S.balRon;
S.Pack.CellBalancingOpenConductance  = S.balGoff;
S.Pack.CellBalancingThreshold        = S.balVt;

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
S.Icharge = S.chargeCrate*cellP.AH*S.Np;   % Pack charging current, A
S.Ipulse  = S.pulseCrate *cellP.AH*S.Np;   % Discharge-pulse amplitude, A
S.Iterm   = S.taperCrate *cellP.AH*S.Np;   % Charge-termination current, A
S.dVterm  = 0.010;                         % How close to vMaxCell counts as "in CV", V

% ---- Discharge pulse train, in controller samples ----------------------
% The model is fixed-step discrete at Ts, so the Pulse Generator runs in
% sample-based mode and its period / width have to be whole numbers of steps.
% Round here, once, and report what the pack will actually see.
S.pulseN      = max(1, round(S.pulsePeriod/S.Ts));               % steps per period
S.pulseNon    = min(S.pulseN, max(1, round(S.pulseN*S.pulseDuty/100)));  % steps on
S.pulseNdelay = max(0, round(S.pulseDelay/S.Ts));                % steps before the first pulse
S.pulseOnTime = S.pulseNon*S.Ts;                 % Achieved pulse width, s
S.pulseTime   = S.pulseN  *S.Ts;                 % Achieved period, s
S.pulseDutyOn = 100*S.pulseNon/S.pulseN;         % Achieved duty cycle, percent

% ---- Passive balancing -------------------------------------------------
% The shunt sits across a whole parallel assembly, so it drains all Np cells at
% once: the assembly loses Ibleed amps out of Np*AH amp-hours, which is why the
% bleed rate falls as Np rises.
S.balCmd   = double(S.balEnable);             % Feeds the balancer's Enable port
S.Ibleed   = cellP.Vnom/(S.balR + S.balRon);  % Bleed current at nominal cell volts, A
S.Pbleed   = cellP.Vnom*S.Ibleed;             % Resistor dissipation there, W
S.balRate  = S.Ibleed/(S.Np*cellP.AH);        % SOC bled off per hour, 1/h
S.balHours = S.balThreshold/S.balRate;        % Hours to bleed one threshold away

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
checkThresholds(S);

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
fprintf('    Currents       %.2f A charge (%.2gC)   %.2f A pulse (%.2gC)\n', ...
        S.Icharge, S.chargeCrate, S.Ipulse, S.pulseCrate);
fprintf('    Charge ends    when the CV current tapers below %.3f A (C/%.0f)\n', ...
        S.Iterm, 1/S.taperCrate);
fprintf('    Then rests     until the highest cell falls back to %.3f V\n', S.V_recharge);
fprintf('    Pulse train    %.4g s on / %.4g s off   (%.4g s period, %.3g%% duty)', ...
        S.pulseOnTime, S.pulseTime - S.pulseOnTime, S.pulseTime, S.pulseDutyOn);
if S.pulseNdelay > 0, fprintf('   first pulse at %.4g s', S.pulseNdelay*S.Ts); end
fprintf('\n');
if S.SOC_minDischarge > 0
    fprintf('    Pulse blocked  below %.2f mean SOC, until the charger reaches %.2f\n', ...
            S.SOC_minDischarge, S.SOC_resumeDischarge);
end
if S.balEnable
    fprintf('    Balancing      passive, on: bleed above %.3f SOC, stop below %.3f\n', ...
            S.balThreshold, S.balThreshold - S.balHysteresis);
    fprintf('                   %.3g Ohm shunt = %.3f A / %.2f W per assembly at %.2f V\n', ...
            S.balR, S.Ibleed, S.Pbleed, S.cellP.Vnom);
    fprintf('                   %.2f SOC points per hour, so %.2f h to clear %.3f SOC\n', ...
            100*S.balRate, S.balHours, S.balThreshold);
else
    fprintf('    Balancing      passive circuit built in, switches held open (balEnable = false)\n');
end
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
function checkThresholds(S)
%CHECKTHRESHOLDS  Catch the settings that can make the charger chatter.
%
%   The "charge complete" latch in Charge Logic is set by (in CV) AND (current
%   tapered) and cleared only when the highest cell falls back below
%   V_recharge. That one-way hysteresis is the whole anti-chatter mechanism,
%   and it only works if V_recharge sits well clear of the CV band the pack
%   rests in - which is vMaxCell, minus a few mV of IR relaxation.

band = S.vMaxCell - 4*S.dVterm;
if S.V_recharge >= band
    warning('P45B:rechargeTooHigh', ...
        ['V_recharge = %.3f V is inside the band the pack relaxes into after a ' ...
         'full charge (above %.3f V). The charge-complete latch will clear the ' ...
         'moment it sets and the charger will switch on and off every Ts. ' ...
         'Leave at least 50 mV, e.g. %.2f V.'], S.V_recharge, band, S.vMaxCell-0.1);
end
if S.V_recharge <= S.cellP.Vmin
    warning('P45B:rechargeTooLow', ...
        ['V_recharge = %.3f V is at or below the %.3f V discharge cut-off, so ' ...
         'the pack will never recharge.'], S.V_recharge, S.cellP.Vmin);
end
if S.SOC_minDischarge > 0 && S.SOC_resumeDischarge <= S.SOC_minDischarge
    warning('P45B:floorThresholds', ...
        ['SOC_resumeDischarge (%.3f) is at or below SOC_minDischarge (%.3f). ' ...
         'With no gap between them the pulse switches on and off every Ts once ' ...
         'the pack reaches the floor.'], S.SOC_resumeDischarge, S.SOC_minDischarge);
end
if S.pulseNon*S.Ts > S.pulsePeriod*S.pulseDuty/100 + S.Ts/2
    warning('P45B:pulseTooShort', ...
        ['pulseDuty = %g%% of a %g s period is less than one %g s step, so the ' ...
         'pulse is being stretched to one step. Set pulseCrate = 0 to switch the ' ...
         'discharge off altogether.'], S.pulseDuty, S.pulsePeriod, S.Ts);
end
if S.pulseNon >= S.pulseN
    warning('P45B:pulseAlwaysOn', ...
        ['pulseDuty = %g%% rounds to a pulse that is on for the whole period, so ' ...
         'the pack only ever discharges.'], S.pulseDuty);
end
if S.balHysteresis > S.balThreshold
    warning('P45B:balHysteresis', ...
        ['balHysteresis (%.3f) is bigger than balThreshold (%.3f). The Passive ' ...
         'Cell Balancing block refuses that and the model will not compile.'], ...
        S.balHysteresis, S.balThreshold);
end
if S.balThreshold <= 0
    warning('P45B:balThreshold', ...
        ['balThreshold must be greater than zero. The Passive Cell Balancing ' ...
         'block refuses %.3f and the model will not compile.'], S.balThreshold);
end
if S.balEnable && S.balHours > S.stopTime/3600
    warning('P45B:balTooSlow', ...
        ['The %.3g Ohm shunt bleeds only %.2f SOC points an hour, so clearing the ' ...
         '%.3f SOC threshold takes %.1f h - longer than the %.1f h simulation. ' ...
         'Balancing will barely register. Use a smaller balR or a longer stopTime.'], ...
        S.balR, 100*S.balRate, S.balThreshold, S.balHours, S.stopTime/3600);
end
if S.balEnable && S.Pbleed > 5
    warning('P45B:balHot', ...
        ['The %.3g Ohm shunt dissipates %.1f W per assembly. Real bleed resistors ' ...
         'are sized for a fraction of a watt; raise balR.'], S.balR, S.Pbleed);
end
if abs(S.pulseTime - S.pulsePeriod) > 1e-9 || ...
   abs(S.pulseOnTime - S.pulsePeriod*S.pulseDuty/100) > 1e-9
    fprintf(['  Note: the pulse was rounded to whole Ts steps - %g s period / ' ...
             '%g s on, instead of %g s / %g s.\n'], ...
            S.pulseTime, S.pulseOnTime, S.pulsePeriod, S.pulsePeriod*S.pulseDuty/100);
end
end


%% ======================================================================
function doBuild()
%DOBUILD  Generate the Simscape battery library with Battery Builder.
%
%   Builds the whole hierarchy - Cell -> ParallelAssembly -> Module ->
%   ModuleAssembly -> Pack - because only the pack level gives the block
%   measurement ports. buildBattery leaves that pack in a model of its own, so
%   the last step lifts it into the library the model actually references.
%
%   The pack is built with BalancingStrategy = "Passive", which is what gives
%   the block its "balancing" command inport - see the comment at that line.
%
%   Produces, next to this file:
%       P45BPack_lib.slx    Simulink library holding the "Pack" block
%       +P45BPack/          Simscape source for the modules and their cells
%       P45BPack.mat        Battery Builder object, for the Battery Builder app
%
%   To inspect or edit the pack in the Battery Builder app afterwards:
%       load P45BPack.mat        % gives you packObj
%       batteryBuilder

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
cellObj.CellModelOptions.BlockParameters.SOC_port     = 'no';    % the pack port already carries socCell
cellObj.Capacity = simscape.Value(c.cellP.AH,'A*hr');

% ---- Parallel assembly (Np cells) -------------------------------------
pa = batteryParallelAssembly(cellObj);
pa.Name                   = 'PA';
pa.NumParallelCells       = Np;
pa.ModelResolution        = 'Detailed';         % model every cell individually
pa.CellParameterVariation = 'PercentDeviation'; % expose per-cell deviation inputs

% ---- Module (Ns assemblies in series) ---------------------------------
m = batteryModule(pa);
m.Name                   = 'Module';
m.NumSeriesAssemblies    = Ns;
m.ModelResolution        = 'Detailed';
m.CellParameterVariation = 'PercentDeviation';

% ---- Module assembly and pack (one module each) -----------------------
% Nothing is added electrically - both wrap the single module in series - but
% batteryPack is the level at which Battery Builder gives the generated block
% socCell / vCell / iCell measurement outputs, so no Probe block is needed.
ma = batteryModuleAssembly(m);
ma.Name = 'ModuleAssembly';

pk = batteryPack(ma);
pk.Name = 'Pack';

% ---- Passive balancing ------------------------------------------------
% Adds a bleed resistor in series with a signal-controlled switch across every
% parallel assembly, and a "balancing" command inport on the generated block,
% Ns wide. Setting it on the pack propagates it down the whole hierarchy.
%
% The circuit is always generated, so that balEnable in config() can turn the
% balancer off at run time without a rebuild. An open switch is 1e-8 S - 40 nA
% across an assembly - and a switch plus a resistor adds no state to the network, so
% an idle circuit changes nothing electrically. Balancing that is actually
% switching does cost run time: every switch that changes state forces
% Simscape to refactorise the network. README section 6 has the measurements.
pk.BalancingStrategy = 'Passive';

% ---- Generate ---------------------------------------------------------
% buildBattery refuses to overwrite anything it generated last time, so clear
% the previous output first. Everything removed here is regenerated below.
for mdl = {'P45B_CCCV','P45BPack','P45BPack_lib'}
    if bdIsLoaded(mdl{1}), close_system(mdl{1}, 0); end
end
for f = {'P45BPack_lib.slx','P45BPack.slx','P45BPack.mat','P45BPack_param.m'}
    if isfile(fullfile(here,f{1}))
        fileattrib(fullfile(here,f{1}),'+w');
        delete(fullfile(here,f{1}));
    end
end
if isfolder(fullfile(here,'+P45BPack'))
    rmdir(fullfile(here,'+P45BPack'),'s');
end

buildBattery(pk, LibraryName='P45BPack', MaskParameters='VariableNamesByType');
promotePack(here);

% buildBattery also drops a P45BPack_param.m holding Simscape's stock 27 Ah
% cell defaults. Nothing uses it and the numbers contradict config(), so
% remove it rather than leave a misleading file behind.
stale = fullfile(here,'P45BPack_param.m');
if isfile(stale), delete(stale); end

fprintf(['\nDone. %ds%dp library generated.\n' ...
         'Open P45B_CCCV.slx and press Run.\n\n'], Ns, Np);
end


%% ======================================================================
function promotePack(here)
%PROMOTEPACK  Move the generated Pack block into P45BPack_lib.
%
%   At the pack level buildBattery writes two files: the library, holding only
%   the Module and ParallelAssembly components, and a model (P45BPack.slx)
%   holding the Pack subsystem that wires them together and brings the
%   measurement signals out as ordinary Simulink ports. P45B_CCCV references
%   P45BPack_lib/Pack, so copy that subsystem into the library and delete the
%   throwaway model.
%
%   Two mask fixups go with the copy:
%     - the generated block reads its cell tables from a struct named after the
%       module class (ModuleType1.*); point it at Pack.* instead, which is what
%       doSetup() puts in the base workspace.
%     - re-apply the per-cell initial SOC target, socCell = SOC0Cell. It lives
%       on the module block inside the library now, but SOC0Cell is still read
%       from the base workspace at compile time, so "P45B vary" still works
%       without a rebuild.
%
%   Two more fixups stop the copy going stale when Ns changes, by repointing
%   sizes that buildBattery compiled in as literals at the workspace instead:
%   the series/parallel counts on the module block, and the width of the
%   balancing command port. See the comments at each.

libFile = fullfile(here,'P45BPack_lib.slx');
fileattrib(libFile,'+w');              % buildBattery writes it read-only

load_system(fullfile(here,'P45BPack.slx'));
load_system(libFile);
set_param('P45BPack_lib','Lock','off');
if getSimulinkBlockHandle('P45BPack_lib/Pack') > 0
    delete_block('P45BPack_lib/Pack');
end
add_block('P45BPack/Pack','P45BPack_lib/Pack');

mb = 'P45BPack_lib/Pack/ModuleAssembly/Module';
mo = Simulink.Mask.get(mb);
prefix = [get_param(mb,'ClassName') '.'];
for k = 1:numel(mo.Parameters)
    prm = mo.Parameters(k);
    val = char(string(prm.Value));
    if strcmp(prm.Type,'edit') && startsWith(val, prefix)
        set_param(mb, prm.Name, ['Pack.' extractAfter(val, prefix)]);
    end
end
set_param(mb, 'socCell_specify','on', 'socCell_priority','High', 'socCell','SOC0Cell');

% The block bakes the series/parallel counts in as literals, and it carries a
% Battery Builder CopyFcn that breaks library links - so the copy sitting in
% P45B_CCCV would go stale the moment Ns or Np changed, and simulate the old
% pack in silence. Point them at the workspace instead. checkLibrary() already
% refuses to run if those disagree with the generated source.
set_param(mb, 'S', 'Ns', 'P', 'Np');

% Same problem, one level out. The balancing command port is ordinary Simulink
% plumbing rather than a Simscape parameter - an Inport and a Selector - and
% buildBattery writes Ns into both as a literal. Point them at the workspace so
% that changing Ns cannot leave a stale 195-wide port behind.
for lvl = {'P45BPack_lib/Pack','P45BPack_lib/Pack/ModuleAssembly'}
    set_param([lvl{1} '/balancing'], 'PortDimensions', 'Ns');
    set_param([lvl{1} '/balancingSelector1'], 'InputPortWidth', 'Ns', ...
              'IndexParamArray', {'1:Ns'});
end

save_system(libFile);
close_system('P45BPack_lib', 0);
close_system('P45BPack', 0);
fileattrib(libFile,'-w');              % generated file - do not hand-edit

% The pack now lives in the library; the generated model is a duplicate. Keep
% the .mat, though - it is what reopens the pack in the Battery Builder app.
% buildBattery names the variable inside it after the object ("Pack"), which
% would clobber the parameter struct of the same name on load, so rename it.
delete(fullfile(here,'P45BPack.slx'));
matFile = fullfile(here,'P45BPack.mat');
loaded  = load(matFile);
packObj = loaded.(char(fieldnames(loaded)));
save(matFile,'packObj');
end


%% ======================================================================
function checkLibrary(Ns, Np)
%CHECKLIBRARY  Verify the generated library matches the requested Ns/Np.
%
%   The series and parallel counts are compiled into the Simscape source that
%   Battery Builder generates, so changing Ns or Np in config() has no effect
%   until the library is rebuilt. This catches that silently-wrong case.

ssc = dir(fullfile(thisDir(), '+P45BPack', '+Modules', '*.ssc'));
if isempty(ssc)
    error('P45B:noLibrary', ...
        ['The Simscape battery library has not been generated yet.\n' ...
         'Run this first:\n\n    P45B build\n']);
end

txt    = fileread(fullfile(ssc(1).folder, ssc(1).name));
Pbuilt = grabInt(txt, 'P');   % cells in parallel, compiled into the .ssc
Sbuilt = grabInt(txt, 'S');   % assemblies in series

if Sbuilt ~= Ns || Pbuilt ~= Np
    error('P45B:libraryMismatch', ...
        ['config() asks for a %ds%dp pack but the generated library is %ds%dp.\n' ...
         'Regenerate it:\n\n    P45B build\n'], Ns, Np, Sbuilt, Pbuilt);
end

% The balancing circuit is compiled in the same way, and the model wires a
% balancer to a command port that only exists if it was generated. A library
% left over from before balancing was added would fail to compile with a
% "too many input ports" error that says nothing about why.
if ~contains(txt, 'enableCellBalancing')
    error('P45B:noBalancing', ...
        ['The generated library has no cell-balancing circuit, but the model ' ...
         'drives one.\nRegenerate it:\n\n    P45B build\n']);
end
end

function v = grabInt(txt, name)
tok = regexp(txt, ['^\s*' name '\s*=\s*(\d+)\s*;'], 'tokens', 'once', 'lineanchors');
if isempty(tok)
    error('P45B:sscParse', 'Could not read "%s" from the generated module .ssc.', name);
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
%   signals come straight off the Pack block's socCell / vCell ports, so the spread
%   produced by "P45B vary" shows up here.
%
%   A fifth tile appears when the log carries the balancing commands, counting
%   the assemblies with the bleed switch closed. Watching that count decay is
%   the quickest way to see the balancer working.

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

% The balancing commands, one per parallel assembly. Logged only when the model
% carries the balancer, so an older log still plots.
bal = [];
if any(strcmp(logsIn.getElementNames, 'balancing'))
    bal = squeeze(g('balancing').Data);
    if size(bal,1) ~= numel(t), bal = bal.'; end
end

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
nTiles = 4 + ~isempty(bal);
tl = tiledlayout(fh, nTiles, 1, 'TileSpacing','compact', 'Padding','compact');

ax(1) = nexttile;
plot(t, Ipack, 'LineWidth', 1.5, 'Color', blue); grid on
ylabel('Current (A)');
title('Pack current   (+ charging, - discharge pulse, 0 resting)');

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
ylabel('SOC'); ylim([0 1]);
title('State of charge - mean, with cell-to-cell spread shaded');
if isempty(bal), xlabel('Time (hours)'); end

if ~isempty(bal)
    ax(5) = nexttile;
    nBleed = sum(bal > 0.5, 2);
    stairs(t, nBleed, 'LineWidth', 1.2, 'Color', orange); grid on
    ylabel('Bleeding'); xlabel('Time (hours)');
    ylim([0 max(1, max(nBleed))*1.15]);
    title(sprintf('Passive balancing - assemblies with the bleed switch closed (of %d)', Ns));
end

linkaxes(ax, 'x'); xlim(ax(1), [0 max(t)]);
title(tl, sprintf('P45B %ds%dp  CC-CV charge with discharge pulses', Ns, Np));

fprintf(['  Simulated %.2f h  |  peak cell %.4f V  |  cell spread at end ' ...
         '%.1f mV / %.2f %% SOC\n'], t(end), max(vCmax), ...
        (vCmax(end)-vCmin(end))*1000, (socMax(end)-socMin(end))*100);
if ~isempty(bal)
    spreadStart = (max(soc(1,:)) - min(soc(1,:)))*100;
    ahBled = trapz(t, sum(bal > 0.5, 2))*evalin('base','Ibleed');   % summed over assemblies
    fprintf(['  Balancing        SOC spread %.2f %% -> %.2f %%  |  peak %d of %d ' ...
             'assemblies bleeding  |  %.2f Ah bled away in total\n'], ...
            spreadStart, (socMax(end)-socMin(end))*100, max(sum(bal > 0.5, 2)), Ns, ahBled);
end
end


%% ======================================================================
function doOpen()
addpath(thisDir());
open_system(fullfile(thisDir(),'P45B_CCCV.slx'));
end

function d = thisDir()
d = fileparts(mfilename('fullpath'));
end
