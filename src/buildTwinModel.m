function mdl = buildTwinModel(file)
%BUILDTWINMODEL  Builds the Simulink digital-twin model (BatteryTwin.slx).
%
%   buildTwinModel                       writes BatteryTwin.slx next to BatteryDataBuilder.m
%   buildTwinModel(file)                 another file name
%
%   Two batteries run side by side on the SAME measured current and chamber
%   temperature, so they can be compared with the test and with each other:
%
%   1. DIGITAL TWIN  (Battery Equivalent Circuit, Simscape Battery)
%        twin_load -> Controlled Current Source -> battery + / -
%        Current dependence = Current dependent, 3 RC pairs, Temperature independent.
%        Tables ec_* from fitDigitalTwin (fitted to the whole test).
%        Heat: Q = I*(V - V0(SOC)) -> Controlled Heat Flow Rate Source ->
%        Thermal Mass (ec_mcp J/K) -> Convective Heat Transfer (ec_hA W/K) ->
%        chamber (twin_ambient).
%        Logs: twin_voltage, twin_current, twin_soc, twin_temp  (the Plot tab's
%        "Load twin from workspace" reads exactly these names).
%
%   2. MODELING-TAB BASELINE  (Battery (Table-Based))
%        The Modeling tab's batt_* variables as they are (SOC x T tables, the
%        block's own thermal mass, Convective Heat Transfer batt_hA to the chamber).
%        Fixed set-up so one model fits every file: 3 RC pairs and Tabulate over
%        temperature = Yes (twinWorkspace pads fewer pairs with empty ones and a
%        single temperature with a copy 2 K away).
%        Logs: tb_voltage, tb_soc, tb_temp.
%
%   Run it with runDigitalTwin (or the Modeling tab's "3. Digital twin" button),
%   which puts every variable in the base workspace first.

if nargin < 1 || isempty(file)
    file = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'BatteryTwin.slx');
end
nRC_TB = 3; twoT = true;
[folder, mdl] = fileparts(file);
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
load_system('batt_lib'); load_system('fl_lib'); load_system('nesl_utility');

L.ec   = lib('batt_lib', '^Battery\sEquivalent\sCircuit$');
L.tb   = lib('batt_lib', '^Battery\s\(Table-Based\)$');
L.isrc = lib('fl_lib', '^Controlled\sCurrent\sSource$');
L.tsrc = lib('fl_lib', '^Controlled\sTemperature\sSource$');
L.qsrc = lib('fl_lib', '^Controlled\sHeat\sFlow\sRate\sSource$');
L.conv = lib('fl_lib', '^Convective\sHeat\sTransfer$');
L.mass = lib('fl_lib', '^Thermal\sMass$');
L.vsen = lib('fl_lib', '^Voltage\sSensor$');
L.tsen = lib('fl_lib', '^Temperature\sSensor$');
L.eref = lib('fl_lib', '^Electrical\sReference$');
L.tref = lib('fl_lib', '^Thermal\sReference$');
L.solv = lib('nesl_utility', '^Solver\sConfiguration$');
L.s2ps = lib('nesl_utility', '^Simulink-PS\sConverter$');
L.ps2s = lib('nesl_utility', '^PS-Simulink\sConverter$');

B = @(n) [mdl '/' n];
add = @(src, n, pos, varargin) add_block(src, B(n), 'Position', pos, varargin{:});
P = @(n) get_param(B(n), 'PortHandles');
wire = @(a, b) add_line(mdl, a, b, 'autorouting', 'smart');

% ================================================================ inputs
add('simulink/Sources/From Workspace', 'Current (A, +charge)', [30 200 150 230], ...
    'VariableName', 'twin_load', 'Interpolate', 'off', 'ZeroCross', 'on', ...
    'OutputAfterFinalValue', 'Holding final value');
add('simulink/Sources/From Workspace', 'Chamber (K)', [30 560 150 590], ...
    'VariableName', 'twin_ambient', 'Interpolate', 'on', 'OutputAfterFinalValue', 'Holding final value');

% ================================================================ 1. digital twin
y = 150;
add(L.s2ps, 'I to PS', [200 y+50 240 y+80], 'Unit', 'A');
add(L.isrc, 'Current source', [280 y+90 340 y+150]);
add(L.ec, 'Digital twin (Battery Equivalent Circuit)', [430 y+40 530 y+160]);
ec = B('Digital twin (Battery Equivalent Circuit)');
set_param(ec, ...
    'ThermalModel', 'simscape.battery.enum.cells.BatteryThermalModel.TemperatureIndependent', ...
    'CurrentDependence', 'simscape.battery.enum.cells.CurrentDependence.CurrentDependent', ...
    'RCPairs', 'simscape.battery.enum.cells.RCPairs.rc3', ...
    'ExtrapolationMethod', 'simscape.enum.extrapolation.nearest', ...
    'BatteryCapacity', 'ec_AH', 'BatteryCapacity_unit', 'A*hr', ...
    'SOCBreakpoints', 'ec_SOC_vec', 'OpenCircuitVoltage', 'ec_V0', ...
    'ResistanceSOCBreakpoints', 'ec_SOC_vec', 'ResistanceCurrentBreakpoints', 'ec_I_vec', ...
    'R0I', 'ec_R0', 'R1I', 'ec_R1', 'R2I', 'ec_R2', 'R3I', 'ec_R3', ...
    'Tau1I', 'ec_tau1', 'Tau2I', 'ec_tau2', 'Tau3I', 'ec_tau3', ...
    'VoltageRange', '[0 inf]', ...
    'stateOfCharge_specify', 'on', 'stateOfCharge_priority', 'High', 'stateOfCharge', 'ec_SOC0');
add(L.vsen, 'V sensor', [620 y+60 680 y+120]);
add(L.eref, 'Ground', [440 y+230 480 y+260]);
add(L.solv, 'Solver (twin)', [280 y+230 340 y+260]);
add(L.ps2s, 'V', [730 y+70 770 y+90], 'Unit', 'V');
add('simulink/Sinks/To Workspace', 'twin_voltage', [1040 y+65 1120 y+95], 'VariableName', 'twin_voltage', 'SaveFormat', 'Timeseries');
add('simulink/Sinks/To Workspace', 'twin_current', [200 y-20 280 y+10], 'VariableName', 'twin_current', 'SaveFormat', 'Timeseries');

ecP = P('Digital twin (Battery Equivalent Circuit)'); is = P('Current source'); vs = P('V sensor');
wire(P('Current (A, +charge)').Outport(1), P('I to PS').Inport(1));
wire(P('Current (A, +charge)').Outport(1), P('twin_current').Inport(1));
wire(P('I to PS').RConn(1), is.RConn(1));
wire(is.LConn(1), ecP.LConn(1));                 % source head -> battery +  (+ signal = charge)
wire(is.RConn(2), ecP.RConn(1));
wire(ecP.RConn(1), P('Ground').LConn(1));
wire(P('Solver (twin)').RConn(1), ecP.RConn(1));
wire(vs.LConn(1), ecP.LConn(1));
wire(vs.RConn(2), ecP.RConn(1));
wire(vs.RConn(1), P('V').LConn(1));
wire(P('V').Outport(1), P('twin_voltage').Inport(1));

% ---- twin SOC (the block's own coulomb count, written out) and heat
add('simulink/Math Operations/Gain', 'per 3600*AH', [200 y+300 260 y+330], 'Gain', '1/(3600*ec_AH)');
add('simulink/Continuous/Integrator', 'SOC', [300 y+300 340 y+330], 'InitialCondition', 'ec_SOC0');
add('simulink/Lookup Tables/1-D Lookup Table', 'V0(SOC)', [390 y+300 450 y+330], ...
    'BreakpointsForDimension1', 'ec_SOC_vec', 'Table', 'ec_V0', 'ExtrapMethod', 'Clip');
add('simulink/Math Operations/Sum', 'V - V0', [500 y+290 520 y+340], 'Inputs', '+-');
add('simulink/Math Operations/Product', 'Q = I*(V - V0)', [570 y+300 610 y+340]);
add('simulink/Sinks/To Workspace', 'twin_soc', [390 y+360 470 y+390], 'VariableName', 'twin_soc', 'SaveFormat', 'Timeseries');
wire(P('Current (A, +charge)').Outport(1), P('per 3600*AH').Inport(1));
wire(P('per 3600*AH').Outport(1), P('SOC').Inport(1));
wire(P('SOC').Outport(1), P('V0(SOC)').Inport(1));
wire(P('SOC').Outport(1), P('twin_soc').Inport(1));
wire(P('V').Outport(1), P('V - V0').Inport(1));
wire(P('V0(SOC)').Outport(1), P('V - V0').Inport(2));
wire(P('Current (A, +charge)').Outport(1), P('Q = I*(V - V0)').Inport(1));
wire(P('V - V0').Outport(1), P('Q = I*(V - V0)').Inport(2));

% ---- twin thermal network
add(L.s2ps, 'Q to PS', [660 y+305 700 y+335], 'Unit', 'W');
add(L.qsrc, 'Heat into cell', [740 y+290 800 y+350]);
add(L.mass, 'Cell thermal mass', [860 y+260 920 y+300], 'mass', 'ec_mcp', 'mass_unit', 'kg', ...
    'sp_heat', '1', 'sp_heat_unit', 'J/(kg*K)', 'T_specify', 'on', 'T_priority', 'High', 'T', 'ec_T0', 'T_unit', 'K');
add(L.conv, 'Convection (twin)', [860 y+400 920 y+440], 'area', '1', 'area_unit', 'm^2', ...
    'heat_tr_coeff', 'ec_hA', 'heat_tr_coeff_unit', 'W/(m^2*K)');
add(L.tsen, 'T sensor (twin)', [960 y+300 1000 y+340]);
add(L.ps2s, 'T twin', [1040 y+305 1080 y+325], 'Unit', 'K');
add('simulink/Sinks/To Workspace', 'twin_temp', [1120 y+300 1200 y+330], 'VariableName', 'twin_temp', 'SaveFormat', 'Timeseries');
add(L.tref, 'Thermal ref (twin)', [740 y+380 780 y+410]);
qs = P('Heat into cell'); cm = P('Cell thermal mass').LConn(1);
wire(P('Q = I*(V - V0)').Outport(1), P('Q to PS').Inport(1));
wire(P('Q to PS').RConn(1), qs.RConn(1));
wire(qs.LConn(1), cm);
wire(qs.RConn(2), P('Thermal ref (twin)').LConn(1));
wire(P('Convection (twin)').LConn(1), cm);
wire(P('T twin').Outport(1), P('twin_temp').Inport(1));
tempSensor(P('T sensor (twin)'), cm, P('Thermal ref (twin)').LConn(1), P('T twin').LConn(1));

% ---- chamber (shared by both batteries; the Table-Based battery's solver
%      block serves this whole thermal network, it is connected through it)
add(L.s2ps, 'Tamb to PS', [200 565 240 595], 'Unit', 'K');
add(L.tsrc, 'Chamber', [960 520 1020 580]);
add(L.tref, 'Thermal ref (chamber)', [960 640 1000 670]);
ts = P('Chamber');
wire(P('Chamber (K)').Outport(1), P('Tamb to PS').Inport(1));
wire(P('Tamb to PS').RConn(1), ts.RConn(1));
wire(ts.RConn(2), P('Thermal ref (chamber)').LConn(1));
wire(P('Convection (twin)').RConn(1), ts.LConn(1));

% ================================================================ 2. Modeling-tab baseline
y = 760;
add(L.s2ps, 'I to PS (TB)', [200 y+50 240 y+80], 'Unit', 'A');
add(L.isrc, 'Current source (TB)', [280 y+90 340 y+150]);
add(L.tb, 'Modeling tab (Battery Table-Based)', [430 y+40 530 y+160]);
tb = B('Modeling tab (Battery Table-Based)');
pv = {'prm_dyn', sprintf('simscape.enum.tablebattery.prm_dyn.rc%d', nRC_TB), ...
      'SOC_vec', 'batt_SOC_vec', 'AH', 'batt_AH', 'AH_unit', 'A*hr', 'V_range', '[0 inf]', ...
      'thermal_port', 'simscape.enum.thermaleffects.model', ...
      'thermal_mass', 'batt_thermal_mass', 'thermal_mass_unit', 'J/K', ...
      'SOC_port', 'simscape.enum.tablebattery.enable.yes', ...
      'extrapolation_option', 'simscape.enum.extrapolation.nearest', ...
      'stateOfCharge_specify', 'on', 'stateOfCharge_priority', 'High', 'stateOfCharge', 'batt_SOC0', ...
      'cell_temperature_specify', 'on', 'cell_temperature_priority', 'High', ...
      'cell_temperature', 'batt_T0', 'cell_temperature_unit', 'K'};
if twoT
    pv = [pv, {'T_dependence', 'simscape.enum.tablebattery.temperature_dependence.yes', ...
        'T_vec', 'batt_T_vec', 'T_vec_unit', 'K', 'V0_mat', 'batt_V0_vec', 'R0_mat', 'batt_R0_vec'}];
    sfx = '_mat';
else
    pv = [pv, {'T_dependence', 'simscape.enum.tablebattery.temperature_dependence.no', ...
        'V0_vec', 'batt_V0_vec', 'R0_vec', 'batt_R0_vec'}];
    sfx = '_vec';
end
for q = 1:nRC_TB
    pv = [pv, {sprintf('R%d%s',q,sfx), sprintf('batt_R%d_vec',q), sprintf('tau%d%s',q,sfx), sprintf('batt_tau%d_vec',q)}]; %#ok<AGROW>
end
set_param(tb, pv{:});
add(L.vsen, 'V sensor (TB)', [620 y+60 680 y+120]);
add(L.eref, 'Ground (TB)', [440 y+230 480 y+260]);
add(L.solv, 'Solver (TB)', [280 y+230 340 y+260]);
add(L.ps2s, 'V (TB)', [730 y+70 770 y+90], 'Unit', 'V');
add('simulink/Sinks/To Workspace', 'tb_voltage', [1040 y+65 1120 y+95], 'VariableName', 'tb_voltage', 'SaveFormat', 'Timeseries');
add(L.ps2s, 'SOC (TB)', [620 y-10 660 y+10], 'Unit', '1');
add('simulink/Sinks/To Workspace', 'tb_soc', [700 y-15 780 y+15], 'VariableName', 'tb_soc', 'SaveFormat', 'Timeseries');
add(L.conv, 'Convection (TB)', [860 y+200 920 y+240], 'area', '1', 'area_unit', 'm^2', ...
    'heat_tr_coeff', 'batt_hA', 'heat_tr_coeff_unit', 'W/(m^2*K)');
add(L.tsen, 'T sensor (TB)', [960 y+140 1000 y+180]);
add(L.ps2s, 'T (TB)', [1040 y+145 1080 y+165], 'Unit', 'K');
add('simulink/Sinks/To Workspace', 'tb_temp', [1120 y+140 1200 y+170], 'VariableName', 'tb_temp', 'SaveFormat', 'Timeseries');
add(L.tref, 'Thermal ref (TB)', [960 y+260 1000 y+290]);

tbP = P('Modeling tab (Battery Table-Based)'); is = P('Current source (TB)'); vs = P('V sensor (TB)');
wire(P('Current (A, +charge)').Outport(1), P('I to PS (TB)').Inport(1));
wire(P('I to PS (TB)').RConn(1), is.RConn(1));
wire(is.LConn(1), tbP.LConn(1));
wire(is.RConn(2), tbP.RConn(1));
wire(tbP.RConn(1), P('Ground (TB)').LConn(1));
wire(P('Solver (TB)').RConn(1), tbP.RConn(1));
wire(vs.LConn(1), tbP.LConn(1));
wire(vs.RConn(2), tbP.RConn(1));
wire(vs.RConn(1), P('V (TB)').LConn(1));
wire(P('V (TB)').Outport(1), P('tb_voltage').Inport(1));
wire(tbP.LConn(2), P('SOC (TB)').LConn(1));
wire(P('SOC (TB)').Outport(1), P('tb_soc').Inport(1));
wire(P('Convection (TB)').LConn(1), tbP.RConn(2));
wire(P('Convection (TB)').RConn(1), P('Chamber').LConn(1));
wire(P('T (TB)').Outport(1), P('tb_temp').Inport(1));
tempSensor(P('T sensor (TB)'), tbP.RConn(2), P('Thermal ref (TB)').LConn(1), P('T (TB)').LConn(1));

% ================================================================ notes + solver
note(mdl, [30 20], sprintf(['DIGITAL TWIN of one cycler test (BatteryBuilder). Run it with runDigitalTwin(''cell.csv'') ' ...
    'or the Modeling tab''s "3. Digital twin" button: they fill the workspace (twin_load, twin_ambient, ec_*, batt_*) and simulate.\n' ...
    'Top: the fitted twin, Battery Equivalent Circuit with resistances over SOC x CURRENT (ec_*). ' ...
    'Bottom: the Modeling tab''s values in Battery (Table-Based) (batt_*), for comparison. Same current, same chamber.\n' ...
    'Current: + = charge. Twin heat = I*(V - V0): all the voltage the cell loses becomes heat.']));
set_param(mdl, 'Solver', 'daessc', 'RelTol', '1e-4', 'AbsTol', 'auto', 'MaxStep', '30', ...
    'StopTime', 'twin_stopTime', 'ReturnWorkspaceOutputs', 'on', 'SignalLogging', 'off', ...
    'OutputOption', 'AdditionalOutputTimes', 'OutputTimes', 'twin_load(1:end-1,1) + 1e-3', ...
    'SimscapeLogType', 'none');
if ~isempty(folder) && ~isfolder(folder), mkdir(folder); end
save_system(mdl, file);
end

% =====================================================================
function blk = lib(libName, rx)
b = find_system(libName, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'RegExp', 'on', 'Name', rx);
if isempty(b), error('Library block "%s" not found in %s (is Simscape Battery installed?).', rx, libName); end
blk = b{1};
end

function tempSensor(ph, node, ref, out)
% Temperature Sensor: A -> the node, B -> reference, T -> PS-Simulink.
% (Which right-hand port is B and which is T differs between releases.)
mdl = bdroot(get_param(ph.LConn(1), 'Parent'));
add_line(mdl, ph.LConn(1), node, 'autorouting', 'smart');
if numel(ph.RConn) >= 2
    try
        add_line(mdl, ph.RConn(1), ref, 'autorouting', 'smart');
        add_line(mdl, ph.RConn(2), out, 'autorouting', 'smart');
    catch
        delete_line(find_system(mdl, 'FindAll', 'on', 'Type', 'line', 'SrcPortHandle', ph.RConn(1)));
        add_line(mdl, ph.RConn(2), ref, 'autorouting', 'smart');
        add_line(mdl, ph.RConn(1), out, 'autorouting', 'smart');
    end
else
    add_line(mdl, ph.RConn(1), out, 'autorouting', 'smart');
end
end

function note(mdl, xy, txt)
try
    a = Simulink.Annotation(mdl, txt);
    a.Position = [xy xy + [1100 60]];
    a.FontSize = 11;
catch
end
end
