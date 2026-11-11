function R = extractCellParameters(d, nRC, socGrid, userAH, capacityOnly)
%EXTRACTCELLPARAMETERS  Battery (Table-Based) parameters from ONE test file.
%
%   R = extractCellParameters(d, nRC, socGrid)
%   R = extractCellParameters(d, nRC, socGrid, userAH)
%   R = extractCellParameters(d, [], [], NaN, true)   capacity only (fast): R.value.AH
%
%   d        dataset from loadBatteryCsv (current: positive = charge)
%   nRC      number of RC pairs to fit (1..3) = block "Charge dynamics"
%   socGrid  SOC breakpoints (block SOC_vec), e.g. [0 0.05 0.1:0.1:0.9 0.95 1]
%   userAH   optional capacity (Ah) typed in by the user. It is ONLY used to
%            build the SOC axis when the test has no complete full->empty
%            discharge (so the capacity cannot be measured).
%
%   The test this is built for (rate test, one file per temperature):
%     rest -> CC-CV charge at 25 °C -> rest (chamber goes to the test
%     temperature) -> CC discharge to cut-off -> rest (back to 25 °C) -> ...
%     with a different discharge rate in every cycle.
%
%   What each value comes from (nothing else is used):
%     AH, SOC   coulomb count between a full CC-CV charge and the cut-off
%     R0        the first sample after each step FROM A LONG REST
%               (R0 = (V_first - V_rest) / I_first)
%     R_k,tau_k the voltage over the first minutes after those same steps,
%               all steps at one SOC fitted together (the RC pairs are the
%               only thing that changes the voltage there besides R0 and
%               the small OCV change from the charge moved)
%     V0, R_dc  the discharges at several rates, lined up on SOC: at each
%               SOC V = V0 - |I| * R_dc (straight line in I). The RC
%               tables are scaled so R0 + sum R_k = R_dc at every SOC where
%               R_dc is measured - so the model's constant-current voltage
%               is the measured one.
%
%   Two temperatures: when the charges (25 °C) and discharges (test
%   temperature) are more than C.maxDT apart, R0 / R_k / tau_k are built at
%   both, each from the steps taken at that temperature, and returned as
%   nSOC x 2 matrices (columns = T_vec). At the charge temperature R_dc
%   comes from the CC part of the charges: R_dc = (V_charge - V0) / I.
%   R.byT{j} is the full single-temperature result for T_vec(j); R.iPrim is
%   the discharge (test) temperature.
%
%   Nothing is guessed: a parameter that cannot be worked out from the data
%   is returned with R.found.(key) = false and R.note.(key) saying why.
%
%   R.value.<key>   the number / vector that goes in the block
%   R.found.<key>   true if it was calculated from the data
%   R.note.<key>    one-line explanation (how it was found / why not)
%   R.diag          everything the "How?" pop-ups need to draw their plots
%   R.d             the dataset with d.soc and a 'SOC (-)' column added
%   R.report        text report
%
%   Keys: SOC_vec T_vec V0_vec V_range R0_vec AH R1_vec tau1_vec R2_vec tau2_vec
%         R3_vec tau3_vec thermal_mass hA SOC0 T0

if nargin < 4, userAH = NaN; end
if nargin < 5, capacityOnly = false; end
if capacityOnly, nRC = 1; socGrid = [0 0.5 1]; end
C = constants();
nRC = max(1, min(3, round(nRC)));
g = unique(min(max(double(socGrid(:)'), 0), 1));
if numel(g) < 3, error('SOC_vec needs at least 3 breakpoints between 0 and 1.'); end

keys = {'SOC_vec','T_vec','V0_vec','V_range','R0_vec','AH','R1_vec','tau1_vec','R2_vec', ...
        'tau2_vec','R3_vec','tau3_vec','thermal_mass','hA','SOC0','T0'};
for k = 1:numel(keys)
    R.value.(keys{k}) = [];
    R.found.(keys{k}) = false;
    R.note.(keys{k})  = '';
end
R.nRC = nRC;
R.value.SOC_vec = g;
R.found.SOC_vec = true;
R.note.SOC_vec  = 'SOC breakpoints used for every table (your choice, not measured)';
R.constants = C;
R.byT = {}; R.iPrim = 1; R.copiedT = struct();
rep = {sprintf('Extraction from %s  (%s)', d.name, char(datetime('now','Format','yyyy-MM-dd HH:mm')))};

% ======================================================================
% 1. Phases (charge / discharge / rest) and voltage range
% ======================================================================
ah = d.tbl.('Net Ah in (Ah)');
ph = findPhases(d, ah);
[isCV, Vcv] = cvPhases(d, ph);
VmaxCV = max(Vcv(isCV));
if isempty(VmaxCV), VmaxCV = NaN; end
R.value.V_range = [min(d.V) max(d.V)];
R.found.V_range = true;
R.note.V_range  = sprintf('lowest / highest voltage measured in the test (%.3f .. %.3f V)', R.value.V_range);
R.diag.phases = ph;
R.diag.isCV = isCV;
R.diag.VmaxCV = VmaxCV;
rep{end+1} = sprintf('Phases: %d charge, %d discharge, %d rest; %d CC-CV charge(s) ending at %.3f V', ...
    nnz([ph.type] == 'C'), nnz([ph.type] == 'D'), nnz([ph.type] == 'R'), nnz(isCV), VmaxCV);

% ======================================================================
% 2. Capacity (AH)
% ======================================================================
[cap, capInfo] = capacityFromData(d, ph, ah, isCV, Vcv, VmaxCV, min(d.V), C.vTol);
R.diag.capacity = capInfo;
capUse = NaN;
if isfinite(cap)
    R.value.AH = cap; R.found.AH = true; capUse = cap;
    R.note.AH = sprintf('Ah discharged from a full CC-CV charge (%.3f V) down to the %.3f V cut-off at %.3g A', ...
        capInfo.VmaxCV, capInfo.Vmin, capInfo.rateA);
    if isfinite(capInfo.fileAh)
        dev = 100*(capInfo.fileAh/cap - 1);
        R.note.AH = [R.note.AH sprintf('; the cycler''s own Capacity column gives %.4g Ah (%+.1f %%)', ...
            capInfo.fileAh, dev)];
        if abs(dev) > 2
            R.note.AH = [R.note.AH ' - CHECK: these should agree within ~1 %'];
        end
    end
else
    R.note.AH = 'no complete "full CC-CV charge -> discharge to cut-off" in this test';
    if isfinite(userAH)
        capUse = userAH;
        R.note.AH = [R.note.AH sprintf(' (your %.4g Ah was used to build SOC)', userAH)];
    end
end
rep{end+1} = sprintf('Capacity: %s', R.note.AH);
if capacityOnly, R.report = strjoin(rep, newline); return; end

% ======================================================================
% 3. State of charge (coulomb counting)
% ======================================================================
soc = [];
R.diag.soc = struct('anchor','', 'anchorIdx',[], 'ah0',NaN, 'ahAnchor',NaN, 'cap',capUse, ...
    'raw0',NaN, 'check',[]);
if isfinite(capUse) && (~isempty(capInfo.fullIdx) || ~isempty(capInfo.emptyIdx))
    soc = socFromAnchors(ah, capInfo, capUse);
    R.value.SOC0 = min(max(soc(1), 0), 1);
    R.found.SOC0 = true;
    if ~isempty(capInfo.fullIdx)
        R.diag.soc.anchor = 'full'; R.diag.soc.anchorIdx = min(capInfo.fullIdx);
        R.note.SOC0 = sprintf(['SOC at the first sample: %.4g Ah went in between the start and the ' ...
            'first full charge, out of %.4g Ah -> 1 - %.4g/%.4g'], ah(R.diag.soc.anchorIdx) - ah(1), ...
            capUse, ah(R.diag.soc.anchorIdx) - ah(1), capUse);
    else
        R.diag.soc.anchor = 'empty'; R.diag.soc.anchorIdx = capInfo.emptyIdx(1);
        R.note.SOC0 = sprintf('SOC at the first sample: %.4g Ah came out between the start and the first empty point, out of %.4g Ah', ...
            ah(1) - ah(R.diag.soc.anchorIdx), capUse);
    end
    R.diag.soc.ah0 = ah(1); R.diag.soc.ahAnchor = ah(R.diag.soc.anchorIdx);
    R.diag.soc.raw0 = soc(1);
elseif ~isfinite(capUse)
    R.note.SOC0 = 'needs the capacity (AH) first';
else
    R.note.SOC0 = 'the test never reaches full (CC-CV) or empty, so SOC has no reference point';
end
d.soc = soc;
if ~isempty(soc), d.tbl.('SOC (-)') = soc; end
noSoc = 'SOC could not be worked out (see AH / initial SOC), so nothing can be placed on the SOC axis';

% ======================================================================
% 4. Temperatures the tables are built for
% ======================================================================
Ttest = d.T_C;
Ts = Ttest; roleT = {'discharges'};
if isfield(d,'T_chg_C') && isfinite(d.T_chg_C) && isfinite(Ttest) && abs(d.T_chg_C - Ttest) > C.maxDT
    Ts = [Ttest, d.T_chg_C]; roleT = {'discharges','charges'};
end
nT = numel(Ts);
R.diag.Tref = Ttest;
R.diag.edgeIdx = [];
R.diag.fits = [];                       % (no rest fits any more - kept for the overview plot)

% ======================================================================
% 5. Steps from rest -> R0 and the RC pairs (per temperature)
% ======================================================================
tabKeys = {'V0_vec','R0_vec'};
for q = 1:nRC, tabKeys = [tabKeys, {sprintf('R%d_vec',q), sprintf('tau%d_vec',q)}]; end %#ok<AGROW>
TB = cell(1, nT);                       % per-temperature tables
dyn = cell(1, nT);
mr = struct('ok',false, 'why','needs SOC first');
R.diag.ocvRest = zeros(0,3);
if isempty(soc)
    for k = 3:numel(tabKeys), R.note.(tabKeys{k}) = noSoc; end
    R.note.V0_vec = noSoc; R.note.R0_vec = noSoc;
else
    on = findOnsets(d, soc, ph, C, capUse);
    for j = 1:nT
        dyn{j} = fitDynamics(d, on, Ts(j), nRC, C, capUse);
    end
    % ---- OCV and R_dc at the test temperature: the multi-rate fit
    mr = multiRate(d, soc, ph, C, capUse, Ttest, dyn{1}.rc);
    restPts = restOcvPoints(d, soc, ph, C);
    R.diag.ocvRest = restPts;
    if mr.ok
        [ocv, provV0] = ocvFromMultiRate(restPts(:,1:2), mr.dense, g);
        if all(isfinite(ocv))
            R.value.V0_vec = ocv(:)'; R.found.V0_vec = true;
            R.note.V0_vec = sprintf(['zero-current line through the %s C discharges at every SOC ' ...
                '(discharge side, %.3g °C); above / below that range the relaxed voltage at the end of ' ...
                '%d long rest(s) joins it'], strjoin(compose('%.2g', mr.crate(mr.use)), ', '), Ttest, size(restPts,1));
        else
            R.note.V0_vec = sprintf('the multi-rate line and the rests do not cover SOC %.2f..%.2f', g(1), g(end));
            if ~isempty(mr.unsettled)
                R.note.V0_vec = [R.note.V0_vec sprintf(' (%s C left out: the RC wait of %s s is longer than the discharge)', ...
                    strjoin(compose('%.2g', mr.crate(mr.unsettled)), ', '), strjoin(compose('%.0f', mr.settle(mr.unsettled)), ', '))];
            end
            R.diag.ocvPartial = ocv;
        end
        R.diag.prov.V0_vec = provV0;
    else
        R.note.V0_vec = sprintf('no multi-rate fit: %s', mr.why);
        R.diag.prov.V0_vec = repmat('-', 1, numel(g));
    end
    % ---- R0 / RC tables at each temperature
    for j = 1:nT
        rdc = struct('pts',zeros(0,2), 'src','', 'charge',[]);
        if j == 1 && mr.ok
            rdc.pts = mr.RdcPts;
            rdc.src = sprintf('the %d-rate discharge line (%s C)', numel(mr.use), ...
                strjoin(compose('%.2g', mr.crate(mr.use)), ', '));
        elseif R.found.V0_vec
            cr = chargeRdc(d, soc, ph, C, Ts(j), dyn{j}.rc, g, R.value.V0_vec);
            rdc.charge = cr;
            if ~isempty(cr.pts)
                rdc.pts = cr.pts;
                rdc.src = sprintf('the CC part of %d charge(s) at %.2gC: (V - V0)/I', numel(cr.I), median(cr.I)/capUse);
            end
        end
        TB{j} = buildTables(dyn{j}, rdc, g, nRC, Ts(j), C);
    end
end
R.diag.multiRate = mr;

% ======================================================================
% 6. Check the coulomb-counted SOC against the voltage at the start
% ======================================================================
if R.found.SOC0 && R.found.V0_vec
    ck = socVoltageCheck(d, soc, ph, g, R.value.V0_vec, capInfo);
    R.diag.soc.check = ck;
    if ~isempty(ck)
        R.note.SOC0 = [R.note.SOC0 sprintf(['. Voltage check: the cell rests at %.3f V at %.2f h, ' ...
            'which the OCV table reads as SOC %.3f (coulomb count: %.3f)'], ck.V, ck.t/3600, ck.socOcv, ck.socCC)];
        if isfinite(ck.Vempty)
            R.note.SOC0 = [R.note.SOC0 sprintf('; after the discharge to cut-off it rested at %.3f V', ck.Vempty)];
        end
        if abs(ck.socOcv - ck.socCC) > max(0.08, ck.unc)
            R.note.SOC0 = [R.note.SOC0 ' - CHECK: voltage and coulomb count disagree'];
        end
    end
end

% ======================================================================
% 7. Thermal mass and h*A (with the test-temperature tables)
% ======================================================================
th = [];
if ~R.found.V0_vec || isempty(TB) || isempty(TB{1})
    why = 'needs the OCV first (the heat generated is I*(V - OCV))';
    R.note.thermal_mass = why; R.note.hA = why;
else
    Rk = {}; Tk = {};
    for q = 1:nRC
        if TB{1}.found.(sprintf('R%d_vec',q))
            Rk{end+1} = TB{1}.value.(sprintf('R%d_vec',q)); %#ok<AGROW>
            Tk{end+1} = TB{1}.value.(sprintf('tau%d_vec',q)); %#ok<AGROW>
        end
    end
    th = fitThermal(d, soc, g, R.value.V0_vec, Rk, Tk);
    if th.ok
        R.value.thermal_mass = th.mcp; R.found.thermal_mass = true;
        R.value.hA = th.hA;            R.found.hA = true;
        R.note.thermal_mass = sprintf(['fitted to the measured cell temperature with the heat I*(V - OCV) ' ...
            '(rms error %.2f K, peak rise %.1f K)'], th.rmse, max(th.Tmeas) - min(th.Tmeas));
        R.note.hA = R.note.thermal_mass;
    else
        R.note.thermal_mass = th.why; R.note.hA = th.why;
    end
end
R.diag.thermal = th;

% ======================================================================
% 8. Initial cell temperature
% ======================================================================
k = find(isfinite(d.Tcell), 1);
if ~isempty(k)
    R.value.T0 = d.Tcell(k) + 273.15; R.found.T0 = true;
    R.note.T0 = sprintf('first cell temperature reading (%.2f °C)', d.Tcell(k));
else
    k = find(isfinite(d.Tch), 1);
    if ~isempty(k)
        R.value.T0 = d.Tch(k) + 273.15; R.found.T0 = true;
        R.note.T0 = sprintf('no cell sensor: first chamber temperature reading (%.2f °C)', d.Tch(k));
    else
        R.note.T0 = 'no temperature columns in the file';
    end
end
R.d = d;

% ======================================================================
% 9. Put the tables in (one temperature: vectors; two: nSOC x 2 matrices)
% ======================================================================
R.T_C = Ttest;
if isfinite(Ttest), R.value.T_vec = Ttest + 273.15; R.found.T_vec = true; end
R.note.T_vec = 'one temperature in this file: block option "Tabulate parameters over temperature" = No';
if ~isempty(soc)
    Rs = cell(1, nT);
    for j = 1:nT
        Rs{j} = withTables(R, TB{j}, dyn{j}, Ts(j), nRC);
    end
    if nT == 1
        R = Rs{1};
    else
        Rs{2}.found.V0_vec = false;          % no discharges at the charge temperature
        [Ts, o] = sort(Ts); Rs = Rs(o); roleT = roleT(o);
        R.byT = Rs; R.iPrim = find(o == 1); R.T_C = Ts;
        R.value.T_vec = Ts + 273.15; R.found.T_vec = true;
        R.note.T_vec = sprintf(['two temperatures: %.3g °C (%s) and %.3g °C (%s), from the chamber ' ...
            'schedule; block option "Tabulate parameters over temperature" = Yes'], Ts(1), roleT{1}, Ts(2), roleT{2});
        for i = 1:numel(tabKeys)
            key = tabKeys{i};
            have = cellfun(@(r) r.found.(key), Rs);
            R.copiedT.(key) = false(1, nT);
            if ~any(have)
                R.value.(key) = []; R.found.(key) = false;
                R.note.(key) = sprintf('%.3g °C: %s | %.3g °C: %s', Ts(1), Rs{1}.note.(key), Ts(2), Rs{2}.note.(key));
                continue
            end
            M = nan(numel(g), nT); nt = cell(1, nT);
            for j = 1:nT
                if have(j), M(:,j) = Rs{j}.value.(key)(:); nt{j} = sprintf('%.3g °C: %s', Ts(j), Rs{j}.note.(key)); end
            end
            for j = find(~have)
                o2 = find(have, 1); M(:,j) = M(:,o2); R.copiedT.(key)(j) = true;
                if strcmp(key, 'V0_vec')
                    nt{j} = sprintf(['%.3g °C: same as %.3g °C (no discharges at %.3g °C; the OCV changes ' ...
                        'only a few mV with temperature)'], Ts(j), Ts(o2), Ts(j));
                else
                    nt{j} = sprintf('%.3g °C: COPIED from %.3g °C - not measurable at %.3g °C in this file (%s)', ...
                        Ts(j), Ts(o2), Ts(j), Rs{j}.note.(key));
                end
            end
            R.value.(key) = M; R.found.(key) = true;
            R.note.(key) = strjoin(nt, ' | ');
        end
        R.diag.edgeIdx = sort([Rs{1}.diag.edgeIdx(:); Rs{2}.diag.edgeIdx(:)]);
    end
end
for q = nRC+1:3
    R.note.(sprintf('R%d_vec',q)) = sprintf('not used (Charge dynamics = %d RC pair(s))', nRC);
    R.note.(sprintf('tau%d_vec',q)) = R.note.(sprintf('R%d_vec',q));
end

% ---- report ---------------------------------------------------------------------
for k = 1:numel(keys)
    if R.found.(keys{k}), tag = 'calculated'; else, tag = 'NOT FOUND '; end
    rep{end+1} = sprintf('  %-13s %s  %s', keys{k}, tag, R.note.(keys{k})); %#ok<AGROW>
end
R.report = rep(:);
end

function Rj = withTables(R, tb, dy, T, nRC)
% the full result for ONE temperature (what a "How?" window gets)
Rj = R;
Rj.T_C = T; Rj.value.T_vec = T + 273.15;
Rj.diag.Tref = T;
Rj.diag.dyn = dy;
Rj.diag.rdc = tb.rdc;
Rj.diag.edgeIdx = tb.edgeIdx;
f = fieldnames(tb.prov);
for i = 1:numel(f), Rj.diag.prov.(f{i}) = tb.prov.(f{i}); end
k = {'R0_vec'};
for q = 1:nRC, k = [k, {sprintf('R%d_vec',q), sprintf('tau%d_vec',q)}]; end %#ok<AGROW>
for i = 1:numel(k)
    Rj.value.(k{i}) = tb.value.(k{i});
    Rj.found.(k{i}) = tb.found.(k{i});
    Rj.note.(k{i})  = tb.note.(k{i});
end
end

% ======================================================================
%  Fixed analysis settings (kept out of the GUI on purpose)
% ======================================================================
function C = constants()
C.vTol        = 0.02;   % V    tolerance when matching the CV-hold / cut-off voltage
C.minRestS    = 600;    % s    a step is "from rest" when the rest before it lasted this long
C.maxEdgeDt   = 1;      % s    R0: first sample after the step must be this close to it
C.minStepC    = 0.08;   % C    smallest current step used (0.08C: a 0.1C step counts)
C.onsetMaxS   = 600;    % s    RC fit: longest stretch after a step that is used
C.onsetMaxDSOC= 0.01;   % -    ... and at most this much SOC moved (OCV ~ straight line)
C.tauMin      = 0.5;    % s    shortest time constant allowed
C.clusterSOC  = 0.03;   % -    steps closer than this in SOC are fitted together
C.maxDT       = 3;      % K    data with the cell further than this from a table's
                        %      temperature is not used for that table
C.mrMaxCrate  = 2;      % C    faster steps / discharges are left out of the RC and
                        %      multi-rate fits (V no longer linear in I, cell heats up)
C.settleV     = 0.001;  % V    multi-rate fit: wait after the step until the RC transient
                        %      left over is below this
C.settleNoFit = 1800;   % s    ... or this long when there are no RC pairs
C.ocvRestS    = 3600;   % s    rests at least this long give a relaxed OCV point
end

% ======================================================================
%  Steps from rest: R0 and the RC transient
% ======================================================================
function on = findOnsets(d, soc, ph, C, AH)
% Every charge / discharge that starts after a rest of >= C.minRestS.
%   R0      = (V(a) - V_rest) / I       a = first sample after the switch,
%                                       I = the step's constant current
%   window  = the samples after it used for the RC fit: constant current,
%             <= C.onsetMaxS, <= C.onsetMaxDSOC of SOC moved, cell within
%             C.maxDT of its temperature at the step
% "used" / "why" say whether the step can give R0 (first sample <= C.maxEdgeDt
% after the switch).
on = struct('a',{},'tsw',{},'dt1',{},'soc',{},'T',{},'I',{},'crate',{},'Vrest',{},'restDur',{}, ...
    'R0',{},'e',{},'used',{},'why',{},'type',{});
t = d.t; V = d.V; I = d.I;
Tc = d.Tcell; if all(~isfinite(Tc)), Tc = d.Tch; end
for k = 2:numel(ph)
    p = ph(k); r = ph(k-1);
    if p.type == 'R' || r.type ~= 'R' || r.dur < C.minRestS, continue; end
    a = p.i1;
    Iabs = median(abs(I(a:min(a+20, p.i2))));
    if isfinite(AH) && Iabs < C.minStepC*AH, continue; end
    tsw = t(a-1);                                    % switch time: from StepTime when it is there
    if ~isempty(d.stepTime) && isfinite(d.stepTime(a)) && d.stepTime(a) >= 0 && d.stepTime(a) < t(a) - t(a-1)
        tsw = t(a) - d.stepTime(a);
    end
    % window for the RC fit
    e = a;
    while e < p.i2 && t(e+1) - tsw <= C.onsetMaxS && abs(soc(e+1) - soc(a)) <= C.onsetMaxDSOC && ...
            abs(I(e+1)) >= 0.95*Iabs && abs(I(e+1)) <= 1.05*Iabs + d.restThr && ...
            ~(isfinite(Tc(e+1)) && isfinite(Tc(a)) && abs(Tc(e+1) - Tc(a)) > C.maxDT)
        e = e + 1;
    end
    o.a = a; o.tsw = tsw; o.dt1 = t(a) - tsw; o.soc = soc(a); o.T = Tc(a);
    o.I = sign(I(a))*Iabs; o.crate = Iabs/AH; o.Vrest = V(a-1); o.restDur = r.dur;
    o.R0 = (V(a) - V(a-1))/o.I;            % the step's set current: a first reading
                                           % can spike (0.34 A for a 0.265 A step)
    o.e = e; o.type = p.type;
    o.used = true; o.why = '';
    if o.dt1 > C.maxEdgeDt
        o.used = false; o.why = sprintf('first sample %.3g s after the switch (> %g s)', o.dt1, C.maxEdgeDt);
    elseif ~(o.R0 > 0 && o.R0 < 1)
        o.used = false; o.why = 'dV/dI implausible';
    end
    on(end+1) = o; %#ok<AGROW>
end
end

function dy = fitDynamics(d, on, Tref, nRC, C, AH)
% R0 and the RC pairs at ONE temperature, from the steps taken there.
% Steps closer than C.clusterSOC in SOC are fitted TOGETHER (same tau_k and
% OCV slope): several rates at the same SOC is what separates a slow RC pair
% from the OCV rising / falling as charge moves.
for i = 1:numel(on)
    if on(i).used && isfinite(Tref) && isfinite(on(i).T) && abs(on(i).T - Tref) > C.maxDT
        on(i).used = false; on(i).why = sprintf('cell at %.3g °C, not %.3g °C', on(i).T, Tref);
    end
end
dy.on = on;
dy.Tref = Tref;
u = find([on.used]);
dy.R0pts = zeros(0,2);
if ~isempty(u), dy.R0pts = [[on(u).soc]', [on(u).R0]']; end
dy.clusters = struct('soc',{},'idx',{},'R0',{},'R',{},'tau',{},'s',{},'rms',{},'rmsN',{},'fitsN',{},'tr',{});
fitU = u([on(u).crate] <= C.mrMaxCrate & [on(u).e] - [on(u).a] >= 6);
dy.nLeftFast = nnz([on(u).crate] > C.mrMaxCrate);
if ~isempty(fitU)
    [~, o] = sort([on(fitU).soc]); fitU = fitU(o);
    cl = 1; start = on(fitU(1)).soc; lab = ones(1, numel(fitU));
    for i = 2:numel(fitU)
        if on(fitU(i)).soc - start > C.clusterSOC, cl = cl + 1; start = on(fitU(i)).soc; end
        lab(i) = cl;
    end
    for c = 1:cl
        idx = fitU(lab == c);
        R0c = median([on(idx).R0]);
        fN = cell(1,3); rmsN = nan(1,3);
        for n = 1:3
            fN{n} = fitCluster(d, on(idx), n, C);
            rmsN(n) = fN{n}.rms;
        end
        f = fN{nRC};
        cc.soc = median([on(idx).soc]); cc.idx = idx; cc.R0 = R0c;
        cc.R = f.R; cc.tau = f.tau; cc.s = f.s; cc.rms = f.rms; cc.rmsN = rmsN; cc.fitsN = fN;
        cc.tr = f.tr;
        dy.clusters(end+1) = cc;
    end
end
% RC pairs for the multi-rate wait: the steps nearest SOC 1 (start of the
% discharges), ALWAYS the 3-pair fit - so the OCV and R_dc do not change
% with the number of RC pairs chosen for the block
dy.rc = struct('R',[], 'tau',[]);
if ~isempty(dy.clusters)
    [~, j] = max([dy.clusters.soc]);
    f3 = dy.clusters(j).fitsN{3};
    ok = isfinite(f3.R) & f3.R > 0;
    dy.rc.R = f3.R(ok); dy.rc.tau = f3.tau(ok);
end
end

function f = fitCluster(d, oc, n, C)
% Fit n RC pairs to the steps in oc (all at about the same SOC). Each step
% is a constant current I from rest, so the block's voltage after it is
%   V(t) = V_rest + I*[ R0 + sum_k R_k*(1 - exp(-t/tau_k)) ] + s*I*t/3600
%   s = dV0/dQ, the OCV slope (V per Ah): the OCV moves as charge moves
% R0 = each step's own first sample. The time constants tau_k and the OCV
% slope s are shared by all steps (same SOC, same cell); R_k is fitted per
% step, because the cell's resistance can depend on the current (it does at
% low temperature) and the block's cannot. For given tau_k the equation is
% linear in the R_k and s (all >= 0) -> least squares; the tau_k are
% searched on a log grid, then refined. Every step gets the same weight in
% ohms (its voltage error divided by its current).
nO = numel(oc);
seg = cell(1, nO);
tmax = 0;
for i = 1:nO
    k = (oc(i).a:oc(i).e)';
    tt = d.t(k) - oc(i).tsw;
    y = (d.V(k) - oc(i).Vrest)/oc(i).I - oc(i).R0;       % ohms, after R0
    seg{i} = struct('tt',tt, 'y',y, 'w',1/sqrt(numel(k)), 'V',d.V(k), 'Vrest',oc(i).Vrest, 'I',oc(i).I);
    tmax = max(tmax, tt(end));
end
lo = log(C.tauMin); hi = log(max(0.5*tmax, 4*C.tauMin));
nG = [40 16 10]; nG = nG(n);
gr = linspace(lo, hi, nG);
best = inf; bestZ = [];
switch n
    case 1
        for i = 1:nG, e = sse(gr(i)); if e < best, best = e; bestZ = gr(i); end, end
    case 2
        for i = 1:nG, for j = i+2:nG
            e = sse(gr([i j])); if e < best, best = e; bestZ = gr([i j]); end
        end, end
    case 3
        for i = 1:nG, for j = i+2:nG, for m = j+2:nG
            e = sse(gr([i j m])); if e < best, best = e; bestZ = gr([i j m]); end
        end, end, end
end
z = fminsearch(@(z) sse(z) + pen(z), bestZ, optimset('Display','off','MaxFunEvals',400*n,'TolX',1e-4));
if sse(z) + pen(z) > best, z = bestZ; end
[~, c] = sse(z);
[tau, o] = sort(exp(z(:)'));
Rs = reshape(c(1:n*nO), n, nO)';                          % one row per step
Rs = Rs(:, o);
f.tau = tau; f.s = c(end); f.Rstep = Rs;
f.R = median(Rs, 1);                                      % the table value
% every step's curve for the "How?" window: apparent resistance (V - V_rest)/I
res = []; f.tr = struct('t',{},'rMeas',{},'rFit',{},'I',{},'soc',{},'rms',{},'R0',{},'R',{},'V',{},'Vfit',{});
for i = 1:nO
    sg = seg{i};
    rf = oc(i).R0 + f.s*sg.tt/3600;
    for k = 1:n, rf = rf + Rs(i,k)*(1 - exp(-sg.tt/tau(k))); end
    vf = sg.Vrest + sg.I*rf;
    res = [res; sg.V - vf]; %#ok<AGROW>
    f.tr(i) = struct('t',sg.tt, 'rMeas',sg.y + oc(i).R0, 'rFit',rf, 'I',sg.I, 'soc',oc(i).soc, ...
        'rms',sqrt(mean((sg.V - vf).^2)), 'R0',oc(i).R0, 'R',Rs(i,:), 'V',sg.V, 'Vfit',vf);
end
f.rms = sqrt(mean(res.^2));                               % volts

    function [e, c] = sse(z)
        tauz = exp(z);
        A = zeros(0, n*nO + 1); b = [];
        for ii = 1:nO
            sg2 = seg{ii};
            X = zeros(numel(sg2.tt), n*nO + 1);
            for kk = 1:n, X(:, (ii-1)*n + kk) = 1 - exp(-sg2.tt/tauz(kk)); end
            X(:, end) = sg2.tt/3600;
            A = [A; sg2.w*X]; b = [b; sg2.w*sg2.y]; %#ok<AGROW>
        end
        c = lsqnonneg(A, b);
        e = sum((A*c - b).^2);
    end
    function p = pen(z)
        % time constants inside the window, at least 2x apart
        p = 0;
        zs = sort(z);
        if any(zs < lo) || any(zs > hi), p = p + 1e3*best; end
        if n > 1 && any(diff(zs) < log(2)), p = p + 1e3*best; end
    end
end

function tb = buildTables(dy, rdc, g, nRC, T, C)
% R0, R_k, tau_k on the SOC breakpoints at one temperature.
%   R0     median of the steps per SOC ('M'), straight line between, ends held
%   tau_k  from the step fits ('M'), same filling
%   R_k    from the step fits, then at every breakpoint where R_dc is
%          measured scaled by ONE factor so R0 + sum R_k = R_dc ('S');
%          between those and the step SOCs the factor is interpolated
tb.rdc = rdc;
tb.edgeIdx = [];
for i = 1:numel(dy.on), if dy.on(i).used, tb.edgeIdx(end+1) = dy.on(i).a - 1; end, end
tb.prov = struct();
keysT = {'R0_vec'};
for q = 1:nRC, keysT = [keysT, {sprintf('R%d_vec',q), sprintf('tau%d_vec',q)}]; end %#ok<AGROW>
for i = 1:numel(keysT)
    tb.value.(keysT{i}) = []; tb.found.(keysT{i}) = false; tb.note.(keysT{i}) = '';
    tb.prov.(keysT{i}) = repmat('-', 1, numel(g));
end
nOn = numel(dy.on);
nHot = nnz(contains({dy.on.why}, '°C'));
hotTxt = '';
if nHot > 0, hotTxt = sprintf(' (%d step(s) at another temperature left out)', nHot); end
% ---- R0
if isempty(dy.R0pts)
    if nOn == 0
        tb.note.R0_vec = sprintf('no charge / discharge starts from a rest of at least %g min', C.minRestS/60);
    else
        tb.note.R0_vec = sprintf('none of the %d step(s) from rest can be used: %s', nOn, strjoin(unique({dy.on.why}), '; '));
    end
else
    [tb.value.R0_vec, tb.prov.R0_vec] = gridPoints(dy.R0pts, g);
    tb.found.R0_vec = true;
    tb.note.R0_vec = sprintf(['R0 = (V_first - V_rest)/I at the first sample after %d step(s) from rest ' ...
        '(%s s after the switch), at SOC %s; straight line between those SOCs, end values held%s'], ...
        size(dy.R0pts,1), rangeStr([dy.on([dy.on.used]).dt1], '%.2g'), rangeStr(dy.R0pts(:,1), '%.2f'), hotTxt);
end
% ---- RC pairs
if isempty(dy.clusters)
    why = sprintf('no step from rest at %.3g °C (<= %gC) to fit the RC pairs to', T, C.mrMaxCrate);
    for q = 1:nRC
        tb.note.(sprintf('R%d_vec',q)) = why; tb.note.(sprintf('tau%d_vec',q)) = why;
    end
    return
end
cl = dy.clusters;
base = cell(1, nRC); tauV = cell(1, nRC); ok = false(1, nRC);
for q = 1:nRC
    pR = [[cl.soc]', arrayfun(@(c) c.R(q), cl)'];
    pT = [[cl.soc]', arrayfun(@(c) c.tau(q), cl)'];
    good = pR(:,2) > 0;
    if ~any(good), continue; end
    [base{q}, provR] = gridPoints(pR(good,:), g);
    [tauV{q}, provT] = gridPoints(pT(good,:), g);
    tb.prov.(sprintf('R%d_vec',q)) = provR; tb.prov.(sprintf('tau%d_vec',q)) = provT;
    ok(q) = true;
end
nStep = numel([cl.idx]);
fitTxt = sprintf('fitted to the voltage right after %d step(s) from rest at SOC %s (rms %s mV)', nStep, ...
    rangeStr([cl.soc], '%.2f'), rangeStr(1000*[cl.rms], '%.2g'));
for q = find(~ok)
    w = sprintf(['pair %d is not resolved: with %d RC pairs the fit puts no voltage in it (rms with 1/2/3 ' ...
        'pairs: %s mV) - use fewer RC pairs'], q, nRC, strjoin(compose('%.2g', 1000*cl(1).rmsN), '/'));
    tb.note.(sprintf('R%d_vec',q)) = w; tb.note.(sprintf('tau%d_vec',q)) = w;
end
% scale to R_dc
f = nan(1, numel(g));
rdcG = nan(1, numel(g));
if ~isempty(rdc.pts) && tb.found.R0_vec
    rdcG = gridMedian(rdc.pts, g);
end
sumB = zeros(1, numel(g));
for q = find(ok), sumB = sumB + base{q}; end
provR1 = tb.prov.(sprintf('R%d_vec', find(ok, 1)));
for j = 1:numel(g)
    if isfinite(rdcG(j)) && sumB(j) > 0
        f(j) = max(rdcG(j) - tb.value.R0_vec(j), 0)/sumB(j);
    elseif provR1(j) == 'M'
        f(j) = 1;
    end
end
fin = isfinite(f);
if nnz(fin) >= 2
    f(~fin) = interp1(g(fin), f(fin), g(~fin), 'linear', NaN);
    a = find(fin, 1); b = find(fin, 1, 'last');
    f(1:a-1) = f(a); f(b+1:end) = f(b);
elseif nnz(fin) == 1
    f(:) = f(fin);
else
    f(:) = 1;
end
scaled = isfinite(rdcG) & sumB > 0;
for q = find(ok)
    kR = sprintf('R%d_vec',q); kT = sprintf('tau%d_vec',q);
    tb.value.(kR) = base{q}.*f;
    tb.value.(kT) = tauV{q};
    tb.found.(kR) = true; tb.found.(kT) = true;
    tb.prov.(kR)(scaled) = 'S';
    tb.note.(kT) = [fitTxt hotTxt];
    tb.note.(kR) = tb.note.(kT);
    if any(scaled)
        tb.note.(kR) = [tb.note.(kR) sprintf(['; at the other SOCs (S) all R_k are scaled by one factor so ' ...
            'R0 + sum R_k = R_dc from %s'], rdc.src)];
    else
        tb.note.(kR) = [tb.note.(kR) '; no R_dc at this temperature, so the step values are held over SOC'];
    end
end
tb.f = f; tb.rdcG = rdcG; tb.rdc.grid = rdcG; tb.rdc.f = f;
end

function col = gridMedian(pts, g)
% median of the 1 %-SOC points nearest each breakpoint (half way to its
% neighbours); NaN where there are none - nothing is filled in
edges = [g(1) - 1e-9, (g(1:end-1) + g(2:end))/2, g(end) + 1e-9];
col = nan(1, numel(g));
for j = 1:numel(g)
    m = pts(:,1) >= edges(j) & pts(:,1) < edges(j+1) & isfinite(pts(:,2));
    if any(m), col(j) = median(pts(m,2)); end
end
end

function s = rangeStr(x, fmt)
x = x(isfinite(x));
if isempty(x), s = '-'; return; end
lo = sprintf(fmt, min(x)); hi = sprintf(fmt, max(x));
if strcmp(lo, hi), s = lo; else, s = [lo '..' hi]; end
end

% ======================================================================
%  OCV and R_dc
% ======================================================================
function pts = restOcvPoints(d, soc, ph, C)
% [SOC, V, T] at the end of every rest of at least C.ocvRestS: the cell has
% relaxed, so its voltage is the OCV there (at the temperature T it had).
pts = zeros(0,3);
for k = 1:numel(ph)
    p = ph(k);
    if p.type ~= 'R' || p.dur < C.ocvRestS || ~isfinite(soc(p.i2)), continue; end
    pts(end+1,:) = [soc(p.i2), d.V(p.i2), d.Tcell(p.i2)]; %#ok<AGROW>
end
end

function mr = multiRate(d, soc, ph, C, AH, Tref, rc)
% Once the RC pairs have settled after the step, a constant-current
% discharge sits at
%     V(SOC, I) = V0(SOC) - R_dc(SOC) * |I|,   R_dc = R0 + R1 + R2 + ...
% (the block's own equation with every branch current equal to I). With the
% same discharge done at several currents, a straight-line fit of V against
% |I| at each SOC gives
%     intercept = OCV (discharge side)    slope = R_dc
% Only CC discharges that start from a full charge are used (so SOC is
% exact), only samples within C.maxDT of Tref, rates <= C.mrMaxCrate.
% "Settled": what is left of each RC transient, R_k*|I|*exp(-t/tau_k), is
% below C.settleV (R_k, tau_k from the steps at SOC 1), i.e.
%     t >= max_k tau_k * ln(R_k*|I| / C.settleV)
mr = struct('ok',false, 'why','', 'sf',(0:0.01:1)', 'rates',[], 'crate',[], 'phase',[], ...
    'use',[], 'Vd',[], 'nRate',[], 'ocvD',[], 'Rdc',[], 'rms',[], 'dense',[], 'RdcPts',[], ...
    'settle',[], 'dur',[], 'unsettled',[], 'rc',rc, 'maxDT',C.maxDT, 'Tref',Tref, 'maxCrate',C.mrMaxCrate, ...
    'hot',[]);
if ~isfinite(AH), mr.why = 'needs the capacity'; return; end
sf = mr.sf;
useT = isfinite(Tref) && any(isfinite(d.Tcell));
if isempty(rc.R)
    settleT = @(I) C.settleNoFit;
else
    settleT = @(I) max([60, rc.tau .* log(max(rc.R*I/C.settleV, 1))]);
end
for k = 1:numel(ph)
    p = ph(k);
    if p.type ~= 'D' || p.dur < 300 || soc(p.i1) < 0.97, continue; end
    Ia = abs(d.I(p.i1:p.i2));
    if std(Ia)/mean(Ia) > 0.05, continue; end          % not constant current
    mr.phase(end+1) = k; mr.rates(end+1) = median(Ia);
end
mr.crate = mr.rates/AH;
if isempty(mr.rates), mr.why = 'no constant-current discharge starting from a full charge'; return; end
mr.Vd = nan(numel(mr.rates), numel(sf));
mr.settle = nan(1, numel(mr.rates));
mr.hot = zeros(1, numel(mr.rates));
for r = 1:numel(mr.rates)
    p = ph(mr.phase(r));
    idx = (p.i1:p.i2)';
    mr.settle(r) = settleT(mr.rates(r));
    keep = d.t(idx) - p.t1 >= mr.settle(r);
    if useT
        hot = abs(d.Tcell(idx) - Tref) > C.maxDT;
        mr.hot(r) = nnz(keep & hot)/max(nnz(keep), 1);
        keep = keep & ~hot;
    end
    mr.Vd(r,:) = binMean(soc(idx(keep)), d.V(idx(keep)), sf);
end
mr.dur = arrayfun(@(k) ph(k).dur, mr.phase);
mr.unsettled = find(mr.crate <= C.mrMaxCrate & ~any(isfinite(mr.Vd), 2)');
mr.use = find(mr.crate <= C.mrMaxCrate & any(isfinite(mr.Vd), 2)');
if numel(unique(round(mr.rates(mr.use)*1e3))) < 2
    mr.why = sprintf('only %d usable discharge rate(s) from full (need 2+ different rates)', numel(mr.use));
    return
end
[mr.ocvD, mr.Rdc, mr.rms] = deal(nan(numel(sf),1));
mr.nRate = zeros(numel(sf),1);
for j = 1:numel(sf)
    u = mr.use(isfinite(mr.Vd(mr.use, j)));
    if numel(u) < 2 || max(mr.rates(u)) < 1.5*min(mr.rates(u)), continue; end
    A = [ones(numel(u),1), -mr.rates(u)'];
    c = A \ mr.Vd(u, j);
    if c(2) <= 0, continue; end
    mr.ocvD(j) = c(1); mr.Rdc(j) = c(2); mr.nRate(j) = numel(u);
    if numel(u) >= 3, mr.rms(j) = sqrt(mean((A*c - mr.Vd(u, j)).^2)); end
end
if nnz(isfinite(mr.ocvD)) < 5, mr.why = 'the discharge rates do not overlap at enough SOC points'; return; end
f = isfinite(mr.ocvD);
mr.dense = [sf(f), mr.ocvD(f)];
mr.ocv = mr.ocvD;
f = isfinite(mr.Rdc);
mr.RdcPts = [sf(f), mr.Rdc(f)];
mr.ok = true;
end

function cr = chargeRdc(d, soc, ph, C, Tref, rc, g, V0)
% R_dc where there are no discharges (the 25 °C charges): once the RC pairs
% have settled, a CC charge sits at V = V0(SOC) + I*R_dc, so
%     R_dc = (V - V0(SOC)) / I
% with V0 the table itself (linear between breakpoints, as the block uses
% it). This R_dc also carries the gap between the charge and discharge OCV
% (hysteresis), which the block does not model - with it the model's charge
% voltage is the measured one.
sf = (0:0.01:1)';
cr = struct('sf',sf, 'I',[], 'V',[], 'Rdc',[], 'pts',zeros(0,2), 'settle',NaN, 'ocv',[]);
if isempty(rc.R), settleT = @(I) C.settleNoFit;
else, settleT = @(I) max([60, rc.tau .* log(max(rc.R*I/C.settleV, 1))]);
end
cr.ocv = interp1(g, V0, sf);
Vs = []; Is = [];
for k = 1:numel(ph)
    p = ph(k);
    if p.type ~= 'C' || p.dur < 300, continue; end
    idx = (p.i1:p.i2)';
    Ia = d.I(idx);
    cc = Ia >= 0.95*max(Ia);
    Ic = median(Ia(cc));
    cr.settle = settleT(Ic);
    keep = cc & d.t(idx) - p.t1 >= cr.settle;
    if isfinite(Tref) && any(isfinite(d.Tcell)), keep = keep & abs(d.Tcell(idx) - Tref) <= C.maxDT; end
    if nnz(keep) < 10, continue; end
    Vs(end+1,:) = binMean(soc(idx(keep)), d.V(idx(keep)), sf); %#ok<AGROW>
    Is(end+1) = Ic; %#ok<AGROW>
end
if isempty(Is), return; end
cr.I = Is; cr.V = Vs;
r = (Vs - cr.ocv')./Is(:);
cr.Rdc = median(r, 1, 'omitnan')';
f = isfinite(cr.Rdc) & cr.Rdc > 0;
cr.pts = [sf(f), cr.Rdc(f)];
end
% ======================================================================
%  Phases
% ======================================================================
function ph = findPhases(d, ah)
% A phase is a run of samples in the same mode: 'C' charge (I > 0),
% 'D' discharge (I < 0), 'R' rest. Consecutive steps of the same mode merge
% (so CC + CV is one charge phase).
I = d.I;
mode = repmat('R', numel(I), 1);
mode(I > 0) = 'C'; mode(I < 0) = 'D';
brk = [true; mode(2:end) ~= mode(1:end-1)];
i1 = find(brk); i2 = [i1(2:end)-1; numel(I)];
ph = struct('i1',num2cell(i1),'i2',num2cell(i2),'type',num2cell(mode(i1)));
for k = 1:numel(ph)
    a = i1(k); b = i2(k);
    ph(k).t1 = d.t(a);
    ph(k).t2 = d.t(min(b+1, numel(I)));
    ph(k).dur = ph(k).t2 - ph(k).t1;
    ph(k).Imean = mean(I(a:b));
    ph(k).Imax = max(abs(I(a:b)));
    ph(k).Iend = I(b);
    ph(k).ah = ah(b) - ah(a);
    ph(k).Vmin = min(d.V(a:b)); ph(k).Vmax = max(d.V(a:b));
    ph(k).Vend = d.V(b);
end
end

function [isCV, Vcv] = cvPhases(d, ph)
% A charge phase ends in a constant-voltage hold when its current tapered to
% < 35 % of its maximum while the voltage over that taper stayed flat.
isCV = false(numel(ph),1); Vcv = nan(numel(ph),1);
for k = 1:numel(ph)
    if ph(k).type ~= 'C' || abs(ph(k).Iend) > 0.35*ph(k).Imax, continue; end
    idx = ph(k).i1:ph(k).i2;
    taper = idx(abs(d.I(idx)) < 0.9*ph(k).Imax);
    if numel(taper) < 3, continue; end
    v = d.V(taper);
    if max(v) - min(v) < 0.015
        isCV(k) = true; Vcv(k) = median(v);
    end
end
end

% ======================================================================
%  Capacity and SOC
% ======================================================================
function [cap, info] = capacityFromData(d, ph, ah, isCV, Vcv, VmaxCV, ~, vTol)
% FULL  = end of a CC-CV charge at the highest CV voltage
% EMPTY = end of a long discharge (>= 5 min) that
%           - stopped at the cut-off: its END voltage is the lowest end voltage
%             of all long discharges in the test (short pulses are ignored, so
%             a 10 s pulse dipping below the cut-off cannot move the target)
%           - ended on the end-of-discharge "knee" (voltage falling much faster
%             per Ah than in the middle of the discharge), so a partial
%             discharge is never mistaken for empty.
% capacity = Ah taken out between a FULL and the next EMPTY (lowest rate wins)
isFull = isCV & Vcv >= VmaxCV - vTol;
longD = find([ph.type] == 'D' & [ph.dur] >= 300);
Vcut = NaN;
if ~isempty(longD), Vcut = min([ph(longD).Vend]); end
isEmpty = false(numel(ph),1);
for k = longD
    isEmpty(k) = ph(k).Vend <= Vcut + vTol && ph(k).Vend <= ph(k).Vmin + vTol && ...
        endsAtKnee(d, ph(k), ah);
end
info.fullIdx  = arrayfun(@(p) p.i2, ph(isFull));
info.emptyIdx = arrayfun(@(p) p.i2, ph(isEmpty));
info.Vmin = Vcut; info.VmaxCV = VmaxCV;
cand = [];
for e = find(isEmpty)'
    f = find(isFull(1:e-1), 1, 'last');
    if isempty(f), continue; end
    a = ph(f).i2; b = ph(e).i2;
    idx = a:b; idx = idx(d.I(idx) < 0);
    cand(end+1,:) = [ah(a) - ah(b), -mean(d.I(idx)), a, b]; %#ok<AGROW>
end
info.candidates = cand;
info.fileAh = NaN;
if isempty(cand)
    cap = NaN; info.rateA = NaN; info.a = []; info.b = [];
else
    [~, j] = min(cand(:,2));
    cap = cand(j,1); info.rateA = cand(j,2); info.a = cand(j,3); info.b = cand(j,4);
    info.fileAh = fileCapacity(d, info.a, info.b);
end
end

function q = fileCapacity(d, a, b)
% Cross-check: the same discharge measured by the cycler's own "Capacity (Ah)"
% column, if the file has one. That column counts up within each step and
% resets to 0 at the next step, so the step totals are added up.
q = NaN;
if ~isfield(d, 'capFile') || isempty(d.capFile), return; end
c = abs(d.capFile(a:b));
c = c(isfinite(c));
if numel(c) < 2, return; end
seg = [0; find(diff(c) < -1e-9); numel(c)];       % a drop = a new step started
q = 0;
for k = 1:numel(seg)-1
    s = c(seg(k)+1:seg(k+1));
    q = q + max(s);                                % step total (steps start from 0)
end
q = q - c(1);                                      % already counted before 'a' (end of the charge)
end

function tf = endsAtKnee(d, p, ah)
% true if dV/dAh over the last 3 % of the discharge is > 3x the slope over
% its middle half (a lithium-ion cell's voltage drops steeply when empty)
tf = false;
idx = (p.i1:p.i2)';
q = ah(idx(1)) - ah(idx);            % Ah taken out so far in this phase
v = d.V(idx);
Q = q(end);
if Q <= 0 || numel(idx) < 10, return; end
mid = q >= 0.25*Q & q <= 0.75*Q;
if nnz(mid) < 3 || max(q(mid)) - min(q(mid)) <= 0, return; end
c = polyfit(q(mid), v(mid), 1);
slopeMid = max(-c(1), eps);
j = find(q >= 0.97*Q, 1);
j = min(j, numel(q) - 2);            % at least 3 samples in the tail
dq = q(end) - q(j);
if dq <= 0, return; end
slopeEnd = (v(j) - v(end)) / dq;
tf = slopeEnd > 3*slopeMid;
end

function soc = socFromAnchors(ah, info, capAh)
% Coulomb counting, re-set to SOC = 1 at every full charge.
n = numel(ah);
soc = nan(n,1);
if ~isempty(info.fullIdx)
    f = sort(info.fullIdx(:));
    soc(1:f(1)) = 1 + (ah(1:f(1)) - ah(f(1)))/capAh;
    for k = 1:numel(f)
        a = f(k);
        if k < numel(f), b = f(k+1); else, b = n; end
        soc(a:b) = 1 + (ah(a:b) - ah(a))/capAh;
    end
else
    e = info.emptyIdx(1);
    soc = (ah - ah(e))/capAh;
end
end

function ck = socVoltageCheck(d, soc, ph, g, ocv, capInfo)
% Reads the relaxed voltage of the first rest through the OCV table and
% compares it with the coulomb-counted SOC at the same moment.
%   - first rest = the rest the file starts in (>= 60 s), otherwise the first
%     rest of >= 10 min anywhere in the test
%   - unc = SOC uncertainty from a 5 mV voltage error on the local OCV slope
%     (large on a flat curve, e.g. LFP)
% Also reports the voltage the cell relaxed to after the discharge to cut-off
% (that rest IS "SOC 0" by definition), for comparison.
ck = [];
k = [];
if ph(1).type == 'R' && ph(1).dur >= 60, k = 1; end
if isempty(k), k = find([ph.type] == 'R' & [ph.dur] >= 600, 1); end
if isempty(k), return; end
i = ph(k).i2;
V = d.V(i);
if V <= ocv(1)
    s = g(1);
elseif V >= ocv(end)
    s = g(end);
else
    s = interp1(ocv, g, V);
end
j = min(max(find(g <= s, 1, 'last'), 1), numel(g)-1);
slope = (ocv(j+1) - ocv(j)) / (g(j+1) - g(j));            % V per unit SOC
ck = struct('idx',i, 't',d.t(i), 'V',V, 'socOcv',s, 'socCC',soc(i), ...
    'slope',slope, 'unc',0.005/max(slope, 1e-6), 'Vempty',NaN, 'tEmpty',NaN);
if ~isempty(capInfo.emptyIdx)
    e = capInfo.emptyIdx(1);
    r = find([ph.i1] == e + 1 & [ph.type] == 'R', 1);
    if ~isempty(r) && ph(r).dur >= 60
        ck.Vempty = d.V(ph(r).i2); ck.tEmpty = d.t(ph(r).i2);
    end
end
end
function x = rcCurrent(t, I, tau)
% current through the resistor of one RC branch (exact for piecewise-constant I)
n = numel(t);
x = zeros(n,1);
for k = 2:n
    a = exp(-(t(k) - t(k-1))/tau);
    x(k) = a*x(k-1) + (1 - a)*I(k-1);
end
end

% ======================================================================
%  Putting scattered points on the SOC breakpoints
% ======================================================================
function [col, prov] = gridPoints(pts, g)
% pts = [soc value]. Each breakpoint takes the median of the points nearest
% to it ('M'). Breakpoints with no points are linearly interpolated ('I');
% beyond the measured range the end value is held ('E' - the same thing the
% block's "nearest" extrapolation would do).
n = numel(g);
col = nan(1,n); prov = repmat('-', 1, n);
pts = pts(all(isfinite(pts),2),:);
if isempty(pts), return; end
edges = [g(1) - 1e-9, (g(1:end-1) + g(2:end))/2, g(end) + 1e-9];
s = min(max(pts(:,1), g(1)), g(end));
for j = 1:n
    m = s >= edges(j) & s <= edges(j+1);
    if any(m), col(j) = median(pts(m,2)); prov(j) = 'M'; end
end
have = isfinite(col);
if nnz(have) >= 2
    gi = g(have); ci = col(have);
    in = ~have & g > gi(1) & g < gi(end);
    col(in) = interp1(gi, ci, g(in), 'linear'); prov(in) = 'I';
    lo = ~have & g < gi(1);  col(lo) = ci(1);   prov(lo) = 'E';
    hi = ~have & g > gi(end); col(hi) = ci(end); prov(hi) = 'E';
else
    col(~have) = col(have); prov(~have) = 'E';
end
end
% ======================================================================
%  Thermal
% ======================================================================
function th = fitThermal(d, soc, g, ocv, Rk, Tk)
% Lumped model   m*cp * dT/dt = Q - h*A*(T - T_chamber)
% Q = heat the cell generates:
%     I*(V - OCV(SOC))   electrical power lost in the cell (Bernardi et al.
%                        1985, irreversible part; I positive = charge, so it
%                        is >= 0 both ways). From the MEASURED voltage, so it
%                        is right even when the cell is hot and its
%                        resistance has dropped.
%   - sum R_k*i_k*(I - i_k)  minus the power going into / coming out of the
%                        RC capacitors (stored, not heat yet; i_k = RC branch
%                        current). This makes Q exactly the block's own heat
%                        I^2*R0 + sum R_k*i_k^2, and puts it at the right time
%                        (the capacitors give their energy back as heat
%                        during the rest that follows).
%     The reversible (entropic) heat I*T*dOCV/dT needs OCV at several
%     temperatures and is left out - the block leaves it out too.
% Linear in [1/(m*cp), h*A/(m*cp)] -> least squares on dT/dt, then refined by
% fitting the simulated temperature curve itself.
th = struct('t',[],'Tmeas',[],'Tmodel',[],'Q',[],'Tamb',[],'mcp',NaN,'hA',NaN, ...
    'rmse',NaN,'ok',false,'why','');
if all(~isfinite(d.Tcell)), th.why = 'no cell temperature column in the file'; return; end
Tch = d.Tch;
if all(~isfinite(Tch)), th.why = 'no chamber temperature column (needed as the ambient)'; return; end
ok = isfinite(d.Tcell) & isfinite(Tch) & isfinite(soc);
if max(d.Tcell(ok)) - min(d.Tcell(ok)) < 0.5
    th.why = 'cell temperature changes by less than 0.5 K - no self-heating to fit'; return
end
sc = min(max(soc, g(1)), g(end));
Qall = d.I .* (d.V - interp1(g, ocv, sc));
Qall(d.I == 0) = 0;
for q = 1:numel(Rk)
    x = rcCurrent(d.t, d.I, median(Tk{q}, 'omitnan'));
    Qall = Qall - interp1(g, Rk{q}, sc) .* x .* (d.I - x);
end

t = d.t(ok); Tc = d.Tcell(ok); Ta = Tch(ok); Q = Qall(ok);
dtg = 10;                                   % uniform 10 s grid
tg = (t(1):dtg:t(end))';
if numel(tg) < 50, th.why = 'record too short'; return; end
[tu, iu] = unique(t);
Qz = Q(iu);                                 % heat holds until the next sample
E = [0; cumsum(Qz(1:end-1).*diff(tu))];
Qg = diff(interp1(tu, E, [tg; tg(end)+dtg], 'linear', 'extrap'))/dtg;
Tg = interp1(tu, Tc(iu), tg); Tag = interp1(tu, Ta(iu), tg);
Ts = smoothdata(Tg, 'movmean', 7);
dT = gradient(Ts, dtg);
A = [Qg, -(Ts - Tag)];
m = all(isfinite([A dT]), 2);
c = A(m,:) \ dT(m);
if any(c <= 0) || ~all(isfinite(c))
    th.why = 'fit gave non-physical values (heating not visible in the temperature data)'; return
end
th.mcp = 1/c(1); th.hA = c(2)/c(1);
if th.mcp < 0.5 || th.mcp > 1e5 || th.hA > 1e3
    th.why = sprintf('fit out of range (m*cp %.3g J/K, h*A %.3g W/K)', th.mcp, th.hA); return
end
th.mcp0 = th.mcp; th.hA0 = th.hA;            % first (least-squares) estimate
th.t = tg - tg(1); th.Tmeas = Tg; th.Q = Qg; th.Tamb = Tag;
p0 = log([th.mcp th.hA]);
cost = @(p) getfield(simulateThermal(th, exp(p(1)), exp(p(2))), 'rmse'); %#ok<GFLD>
p1 = fminsearch(cost, p0, optimset('Display','off','MaxFunEvals',300,'TolX',1e-5));
if cost(p1) < cost(p0), th.mcp = exp(p1(1)); th.hA = exp(p1(2)); end
th = simulateThermal(th, th.mcp, th.hA);
th.ok = true;
end
function th = simulateThermal(th, mcp, hA)
n = numel(th.t);
T = zeros(n,1); T(1) = th.Tmeas(1);
for k = 2:n
    dt = th.t(k) - th.t(k-1);
    a = exp(-hA*dt/mcp);
    Tinf = th.Tamb(k-1) + th.Q(k-1)/hA;
    T(k) = Tinf + (T(k-1) - Tinf)*a;
end
th.Tmodel = T;
th.rmse = sqrt(mean((T - th.Tmeas).^2, 'omitnan'));
end
function y = binMean(x, v, centres)
% mean of v over the samples with x within +-0.005 of each centre (1 % SOC bins)
y = nan(1, numel(centres));
if isempty(x), return; end
b = round(x*100) + 1;                                   % centres are 0:0.01:1
ok = b >= 1 & b <= numel(centres) & isfinite(v);
if ~any(ok), return; end
s = accumarray(b(ok), v(ok), [numel(centres) 1]);
n = accumarray(b(ok), 1, [numel(centres) 1]);
lo = accumarray(b(ok), x(ok), [numel(centres) 1], @min, NaN);
hi = accumarray(b(ok), x(ok), [numel(centres) 1], @max, NaN);
y = (s./max(n,1))';
% at least 3 samples, spread over the whole bin (a bin the data only enters,
% e.g. the last 0.2 % before the cut-off, would be biased)
y((n < 3 | (hi - lo) < 0.008)') = NaN;
end

function [ocv, prov] = ocvFromMultiRate(restPts, dense, g)
% The multi-rate curve IS the OCV (zero-current voltage), so it is used as it
% is ('M'). Only above / below it (the first minutes of a discharge are never
% settled) are the relaxed rest voltages used: a smooth (pchip) curve through
% the multi-rate points and the rest points fills the gap ('I'), for gaps of
% at most 0.25 SOC. Rest points inside the multi-rate range are not used
% (they are a check only).
n = numel(g);
ocv = nan(1,n); prov = repmat('-', 1, n);
lo = dense(1,1); hi = dense(end,1);
P = dense;
if ~isempty(restPts)
    rp = sortrows(restPts(all(isfinite(restPts),2),:));
    rp = rp(rp(:,1) < lo - 0.005 | rp(:,1) > hi + 0.005, :);
    if ~isempty(rp)
        cl = cumsum([true; diff(rp(:,1)) > 0.0005]);   % same rest SOC (repeated cycles)
        rp = [accumarray(cl, rp(:,1), [], @mean), accumarray(cl, rp(:,2), [], @mean)];
        P = sortrows([P; rp]);
    end
end
[~, iu] = unique(P(:,1)); P = P(iu,:);
for j = 1:n
    if g(j) >= lo && g(j) <= hi
        ocv(j) = interp1(dense(:,1), dense(:,2), g(j)); prov(j) = 'M';
    elseif g(j) >= P(1,1) - 1e-9 && g(j) <= P(end,1) + 1e-9
        a = find(P(:,1) <= g(j), 1, 'last'); b = find(P(:,1) >= g(j), 1);
        if P(b,1) - P(a,1) > 0.25, continue; end
        ocv(j) = interp1(P(:,1), P(:,2), g(j), 'pchip');
        if min(abs(P(:,1) - g(j))) <= 0.005, prov(j) = 'M'; else, prov(j) = 'I'; end
    elseif size(P,1) >= 2 && (P(1,1) - g(j) <= 0.01 || g(j) - P(end,1) <= 0.01)
        % within 1 % SOC past the last point: carry on along the end slope
        if g(j) < P(1,1), a = 1; b = 2; else, a = size(P,1) - 1; b = size(P,1); end
        ocv(j) = P(a,2) + (P(b,2) - P(a,2))/(P(b,1) - P(a,1))*(g(j) - P(a,1));
        prov(j) = 'E';
    end
end
fin = find(isfinite(ocv));            % OCV must rise with SOC
for j = 2:numel(fin)
    if ocv(fin(j)) <= ocv(fin(j-1)), ocv(fin(j)) = ocv(fin(j-1)) + 1e-4; end
end
end
