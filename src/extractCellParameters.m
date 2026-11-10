function R = extractCellParameters(d, nRC, socGrid, userAH)
%EXTRACTCELLPARAMETERS  Battery (Table-Based) parameters from ONE test file.
%
%   R = extractCellParameters(d, nRC, socGrid)
%   R = extractCellParameters(d, nRC, socGrid, userAH)
%
%   d        dataset from loadBatteryCsv (current: positive = charge)
%   nRC      number of RC pairs to fit (1..3) = block "Charge dynamics"
%   socGrid  SOC breakpoints (block SOC_vec), e.g. [0 0.05 0.1:0.1:0.9 0.95 1]
%   userAH   optional capacity (Ah) typed in by the user. It is ONLY used to
%            build the SOC axis when the test has no complete full->empty
%            discharge (so the capacity cannot be measured).
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
%   Keys: SOC_vec V0_vec V_range R0_vec AH R1_vec tau1_vec R2_vec tau2_vec
%         R3_vec tau3_vec thermal_mass hA SOC0 T0

if nargin < 4, userAH = NaN; end
C = constants();
nRC = max(1, min(3, round(nRC)));
g = unique(min(max(double(socGrid(:)'), 0), 1));
if numel(g) < 3, error('SOC_vec needs at least 3 breakpoints between 0 and 1.'); end

keys = {'SOC_vec','V0_vec','V_range','R0_vec','AH','R1_vec','tau1_vec','R2_vec', ...
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
% 4. R0 from current steps, RC pairs + OCV points from rests
% ======================================================================
pts.R0 = []; pts.ocv = []; pts.ocvDense = []; pts.Rdc = [];
for q = 1:3, pts.(sprintf('R%d',q)) = []; pts.(sprintf('tau%d',q)) = []; end
fits = [];
edgeIdx = [];
Tref = d.T_C;                         % the temperature these tables are for
R.diag.Tref = Tref;
R.diag.hot = struct('edges',0, 'fits',0);
mr = struct('ok',false, 'why','needs SOC first');
if ~isempty(soc)
    [pts.R0, edgeIdx, R.diag.hot.edges] = r0FromEdges(d, soc, C, capUse, Tref);
    [fits, R.diag.hot.fits] = fitRelaxations(d, soc, ph, C, nRC, capUse, Tref);
    % RC branches seen in the rests (median over the fits) -> how long the
    % multi-rate fit must wait after a step before the transient is gone
    % Only rests that follow a DISCHARGE are used for this: the multi-rate fit
    % waits on discharges, and a rest after a CC-CV charge starts with almost
    % no branch current (the CV taper), so its R_k / tau_k are poorly defined
    % (a long tau / large R there made the wait longer than the 0.5C and 1C
    % discharges themselves, which left the OCV empty in the 25 °C files,
    % the only ones where the post-charge rests are not dropped as too warm).
    rc = struct('R',[], 'tau',[], 'from','');
    if ~isempty(fits)
        useF = [fits.after] == 'D';
        rc.from = sprintf('%d rest(s) after a discharge', nnz(useF));
        if ~any(useF), useF = true(size(fits)); rc.from = sprintf('%d rest(s) after a charge (no discharge rest fitted)', numel(fits)); end
        rc.R = median(vertcat(fits(useF).R), 1, 'omitnan');
        rc.tau = median(vertcat(fits(useF).tau), 1, 'omitnan');
        keep = isfinite(rc.R) & isfinite(rc.tau);
        rc.R = rc.R(keep); rc.tau = rc.tau(keep);
    end
    mr = multiRate(d, soc, ph, C, capUse, Tref, rc);
    if mr.ok, pts.Rdc = mr.RdcPts; end
    for f = fits
        pts.ocv = [pts.ocv; f.soc, f.Vinf];
        for q = 1:nRC
            pts.(sprintf('R%d',q))   = [pts.(sprintf('R%d',q));   f.soc, f.R(q)];
            pts.(sprintf('tau%d',q)) = [pts.(sprintf('tau%d',q)); f.soc, f.tau(q)];
        end
    end
end
R.diag.edgeIdx = edgeIdx;
R.diag.fits = fits;
R.diag.multiRate = mr;
R.diag.ocvExample = [];
prov = struct();
hotNote = '';
if R.diag.hot.edges + R.diag.hot.fits > 0
    hotNote = sprintf(' (%d step(s) / %d rest(s) left out: cell more than %g K away from %.3g °C)', ...
        R.diag.hot.edges, R.diag.hot.fits, C.maxDT, Tref);
end

% --- R0
if isempty(soc)
    R.note.R0_vec = noSoc;
elseif isempty(pts.R0)
    R.note.R0_vec = sprintf('no sharp current steps sampled faster than %g s', C.maxEdgeDt);
else
    [R.value.R0_vec, prov.R0_vec] = gridPoints(pts.R0, g);
    R.found.R0_vec = true;
    R.note.R0_vec = sprintf('R0 = dV/dI at %d current steps, median per SOC breakpoint%s', size(pts.R0,1), hotNote);
end
% --- R1..R3, tau1..tau3
for q = 1:3
    kR = sprintf('R%d_vec',q); kT = sprintf('tau%d_vec',q);
    if q > nRC
        R.note.(kR) = sprintf('not used (Charge dynamics = %d RC pair(s))', nRC);
        R.note.(kT) = R.note.(kR);
        continue
    end
    pR = pts.(sprintf('R%d',q)); pT = pts.(sprintf('tau%d',q));
    if isempty(soc)
        R.note.(kR) = noSoc; R.note.(kT) = noSoc; continue
    end
    if isempty(pR) || all(~isfinite(pR(:,2)))
        why = sprintf('no rest of at least %g s after a current pulse could be fitted', C.minRestS);
        if ~isempty(fits), why = sprintf('the %d relaxation fits did not resolve a pair #%d', numel(fits), q); end
        R.note.(kR) = why; R.note.(kT) = why; continue
    end
    [R.value.(kR), prov.(kR)] = gridPoints(pR, g);
    [R.value.(kT), prov.(kT)] = gridPoints(pT, g);
    R.found.(kR) = true; R.found.(kT) = true;
    n = nnz(isfinite(pR(:,2)));
    R.note.(kR) = sprintf('fitted to %d voltage relaxations (rests after a current pulse)%s', n, hotNote);
    R.note.(kT) = R.note.(kR);
end

% --- between the measured SOC points: make R0 + R1 + ... equal the DC
%     resistance measured by the multi-rate fit (the split between them
%     stays interpolated, the SUM is measured)
R.diag.rdcCheck = [];
if R.found.R0_vec && mr.ok
    [R, prov, R.diag.rdcCheck] = scaleToRdc(R, prov, mr, g, nRC);
    if any(prov.R0_vec == 'S')
        R.note.R0_vec = [R.note.R0_vec sprintf(['; between them (S) R0 + R1..R%d are scaled so their sum ' ...
            'equals the DC resistance from the %d discharge rates'], nRC, numel(mr.use))];
        for q = 1:nRC
            kR = sprintf('R%d_vec',q);
            if R.found.(kR), R.note.(kR) = [R.note.(kR) ' (S breakpoints: sum scaled to the multi-rate DC resistance)']; end
        end
    end
end

% --- OCV: relaxed rest voltages + low-rate CC curve corrected for R0 / RC drops
if isempty(soc)
    R.note.V0_vec = noSoc;
elseif mr.ok
    pts.ocvDense = mr.dense;
    [ocv, prov.V0_vec] = ocvFromMultiRate(pts.ocv, mr.dense, g);
    if all(isfinite(ocv))
        R.value.V0_vec = ocv(:)'; R.found.V0_vec = true;
        if isempty(mr.Ic)
            chgTxt = 'discharge side only (no charge within the temperature window: charges run at 25 °C)';
        else
            chgTxt = sprintf('averaged with the charge branch (%s)', mr.chargeHow);
        end
        R.note.V0_vec = sprintf(['zero-current extrapolation of %d discharges (%s C) at each SOC, %s; ' ...
            'ends (above / below the fit) from %d relaxed rest voltages'], numel(mr.use), ...
            strjoin(compose('%.2g', mr.crate(mr.use)), ', '), chgTxt, size(pts.ocv,1));
    else
        R.note.V0_vec = sprintf('the multi-rate OCV and the rests do not cover SOC %.2f..%.2f', g(1), g(end));
        if ~isempty(mr.unsettled)
            R.note.V0_vec = [R.note.V0_vec sprintf(' (%s C discharge(s) left out: the RC wait of %s s is longer than the discharge)', ...
                strjoin(compose('%.2g', mr.crate(mr.unsettled)), ', '), strjoin(compose('%.0f', mr.settle(mr.unsettled)), ', '))];
        end
        R.diag.ocvPartial = ocv;
    end
else
    if R.found.R0_vec
        Rk = {}; Tk = {};
        for q = 1:nRC
            if R.found.(sprintf('R%d_vec',q))
                Rk{end+1} = R.value.(sprintf('R%d_vec',q)); %#ok<AGROW>
                Tk{end+1} = R.value.(sprintf('tau%d_vec',q)); %#ok<AGROW>
            end
        end
        [pts.ocvDense, R.diag.ocvExample] = denseOcvPoints(d, soc, ph, g, R.value.R0_vec, Rk, Tk, C, capUse);
    end
    [ocv, prov.V0_vec] = buildOcv(pts.ocv, pts.ocvDense, g);
    if all(isfinite(ocv))
        R.value.V0_vec = ocv(:)'; R.found.V0_vec = true;
        R.note.V0_vec = sprintf(['%d relaxed rest voltages + %d points of a low-rate curve corrected with ' ...
            'R0 / RC (only one discharge rate from full, so no multi-rate fit: %s)'], ...
            size(pts.ocv,1), size(pts.ocvDense,1), mr.why);
    else
        R.note.V0_vec = sprintf(['not enough rests (>= %g s) or low-rate (<= %g C) charge/discharge ' ...
            'data to cover SOC %.2f..%.2f'], C.minRestS, C.ocvMaxCrate, g(1), g(end));
    end
end
R.diag.points = pts;
R.diag.prov = prov;

% --- check the coulomb-counted SOC against the voltage at the start
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
% 5. Thermal mass and h*A
% ======================================================================
th = [];
if ~R.found.V0_vec
    why = 'needs the OCV first (the heat generated is I*(V - OCV))';
    R.note.thermal_mass = why; R.note.hA = why;
else
    Rk = {}; Tk = {};
    for q = 1:nRC
        if R.found.(sprintf('R%d_vec',q))
            Rk{end+1} = R.value.(sprintf('R%d_vec',q)); %#ok<AGROW>
            Tk{end+1} = R.value.(sprintf('tau%d_vec',q)); %#ok<AGROW>
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
% 6. Initial cell temperature
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

% ---- report ---------------------------------------------------------------------
for k = 1:numel(keys)
    if R.found.(keys{k}), tag = 'calculated'; else, tag = 'NOT FOUND '; end
    rep{end+1} = sprintf('  %-13s %s  %s', keys{k}, tag, R.note.(keys{k})); %#ok<AGROW>
end
R.report = rep(:);
R.d = d;
R.constants = C;
end

% ======================================================================
%  Fixed analysis settings (kept out of the GUI on purpose)
% ======================================================================
function C = constants()
C.vTol        = 0.02;   % V    tolerance when matching the CV-hold / cut-off voltage
C.tauMin      = 1;      % s    shortest time constant allowed in the RC fits
C.tauMax      = 3000;   % s    longest time constant allowed in the RC fits
C.minRestS    = 300;    % s    rests shorter than this are not used for RC / OCV
C.maxFitRmse  = 0.008;  % V    relaxation fits worse than this are thrown away
C.maxEdgeDt   = 5;      % s    current steps sampled coarser than this are not used for R0
C.ocvMaxCrate = 0.5;    % C    only CC data at or below this rate builds the OCV curve
C.minStepC    = 0.08;   % C    smallest current step used for R0 (0.08C: a 0.1C step counts)
C.maxDT       = 3;      % K    points where the cell is further than this from the test
                        %      temperature are left out of the tables (they belong to a
                        %      different temperature: resistance depends on temperature)
C.mrMaxCrate  = 2;      % C    discharges faster than this are left out of the multi-rate
                        %      fit (V is no longer linear in I, and the cell heats up)
C.settleV     = 0.001;  % V    multi-rate fit: wait after a step until the RC transient
                        %      left over is below this
C.settleNoFit = 1800;   % s    ... or this long when no rest could be fitted (no RC known)

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

% ======================================================================
%  R0 and RC relaxations
% ======================================================================
function [pts, k, nHot] = r0FromEdges(d, soc, C, AH, Tref)
% Instantaneous (ohmic) resistance at every current step:  R0 = dV / dI
%   between the last sample before the step and the first sample after it
%   (INL Battery Test Manual eq. 4; MathWorks "Characterize Battery Cell").
% What matters is how soon after the step that first sample was taken (the
% RC branches start to charge straight away): it must be <= C.maxEdgeDt.
% The StepTime column says exactly when the step happened; without it the
% gap between the two samples is used (a 10 s rest log is then too coarse).
% Steps where the cell is more than C.maxDT away from Tref are left out.
I = d.I; V = d.V; t = d.t;
dI = diff(I); dV = diff(V); dt = diff(t);
dtAfter = dt;
if ~isempty(d.stepTime)
    st = d.stepTime(2:end);
    use = isfinite(st) & st >= 0 & st < dt;
    dtAfter(use) = st(use);
end
if isfinite(AH), thr = C.minStepC*AH; else, thr = 0.05*max(abs(I)); end
thr = max(thr, 10*d.restThr);
k = find(abs(dI) > thr & dtAfter <= C.maxEdgeDt & dt > 0);
Rv = dV(k)./dI(k);
ok = Rv > 0 & Rv < 1;
k = k(ok); Rv = Rv(ok);
nHot = 0;
if isfinite(Tref) && any(isfinite(d.Tcell))
    hot = abs(d.Tcell(k+1) - Tref) > C.maxDT;
    nHot = nnz(hot);
    k = k(~hot); Rv = Rv(~hot);
end
pts = [soc(k), Rv];
end

function [fits, nHot] = fitRelaxations(d, soc, ph, C, nRC, AH, Tref)
% Fit every long rest that follows a current pulse with
%   V(t) = Vinf + sum_k R_k * x_k(t_sw) * exp(-(t - t_sw)/tau_k)
% x_k(t_sw) = current in RC branch k when the current switched off, found by
% passing the real current history through a first-order filter (tau_k).
% Vinf = fully relaxed voltage = an OCV point at that SOC.
% Rests that start with the cell more than C.maxDT away from Tref (e.g. after
% a fast discharge heated it) are left out: the relaxation is then mixed with
% the cell cooling down, and the values belong to another temperature.
fits = struct('soc',{},'Vinf',{},'R',{},'tau',{},'x0',{},'rmse',{},'t0',{},'tr',{},'v',{},'vfit',{},'after',{});
t = d.t; I = d.I; V = d.V;
nHot = 0;
for k = 2:numel(ph)
    r = ph(k);
    if r.type ~= 'R' || r.dur < C.minRestS, continue; end
    prev = ph(k-1);
    if prev.type == 'R' || abs(prev.ah) < 0.002*AH, continue; end
    a = r.i1; b = r.i2;
    if isfinite(Tref) && isfinite(d.Tcell(a)) && abs(d.Tcell(a) - Tref) > C.maxDT
        nHot = nHot + 1; continue
    end
    tsw = t(a);
    if ~isempty(d.stepTime) && isfinite(d.stepTime(a)) && d.stepTime(a) < (t(a) - t(a-1))
        tsw = t(a) - d.stepTime(a);              % exact switch time from StepTime
    end
    tsw = max(tsw, t(a-1));
    tr = t(a:b) - tsw; v = V(a:b);
    keep = tr <= min(r.dur, 8*C.tauMax);
    tr = tr(keep); v = v(keep);
    if numel(tr) < 3*nRC + 4, continue; end
    tauHi = min(C.tauMax, max(r.dur/1.5, 3*C.tauMin));
    f = fitOneRelaxation(t, I, tsw, tr, v, nRC, C.tauMin, tauHi, C.tauMax);
    if isempty(f) || f.rmse > C.maxFitRmse, continue; end
    f.soc = soc(a);
    f.t0 = tsw;
    f.after = prev.type;                         % 'C' or 'D': what the rest follows
    fits(end+1) = f; %#ok<AGROW>
end
end

function f = fitOneRelaxation(t, I, tsw, tr, v, nRC, tauLo, tauHi, tauHist)
f = [];
dtw = min(max(median(diff(t)), 0.5), 5);         % current history, uniform grid
win = min(10*tauHist, tsw - t(1));
nW = floor(win/dtw);
if nW < 5, return; end
tw = tsw - (nW:-1:1)'*dtw;
Iw = zohSample(t, I, tw);

lo = log(tauLo); hi = log(tauHi);
toTau = @(z) exp(lo + (hi - lo)./(1 + exp(-z)));
obj = @(z) relaxSSE(toTau(z));
% coarse grid search for a starting point, then Nelder-Mead
nG = [40 16 9]; nG = nG(nRC);
gr = linspace(lo, hi, nG);
best = inf; bestTau = [];
switch nRC
    case 1
        for i = 1:nG
            e = relaxSSE(exp(gr(i))); if e < best, best = e; bestTau = exp(gr(i)); end
        end
    case 2
        for i = 1:nG
            for j = i+2:nG
                e = relaxSSE(exp(gr([i j])));
                if e < best, best = e; bestTau = exp(gr([i j])); end
            end
        end
    case 3
        for i = 1:nG
            for j = i+2:nG
                for m = j+2:nG
                    e = relaxSSE(exp(gr([i j m])));
                    if e < best, best = e; bestTau = exp(gr([i j m])); end
                end
            end
        end
end
if isempty(bestTau), return; end
fr = min(max((log(bestTau) - lo)/(hi - lo), 0.02), 0.98);
z = fminsearch(obj, -log(1./fr - 1), optimset('Display','off','MaxFunEvals',600,'MaxIter',400,'TolX',1e-4));
tau = toTau(z);
[sse, c, A, x0] = relaxSSE(tau);
[tau, ord] = sort(tau);
Rv = c(2:end); Rv = Rv(ord); x0 = x0(ord);
Rv(Rv <= 0) = NaN;                  % pair not identifiable from this rest
tau(isnan(Rv)) = NaN;
f.soc = NaN; f.Vinf = c(1); f.R = Rv(:)'; f.tau = tau(:)';
f.x0 = x0(:)';                      % RC branch currents when the current stopped (A)
f.rmse = sqrt(sse/numel(v));
f.t0 = NaN; f.tr = tr; f.v = v; f.vfit = A*c;

    function [sse, c, A, x0] = relaxSSE(tau)
        A = ones(numel(tr), 1 + numel(tau));
        x0 = zeros(1, numel(tau));
        for q = 1:numel(tau)
            aq = exp(-dtw/tau(q));
            w = aq.^((nW-1):-1:0)';
            x0(q) = (1 - aq) * (w' * Iw);       % RC branch current at the switch
            A(:,q+1) = x0(q) * exp(-tr/tau(q));
        end
        [c, sse] = lsqNonnegTail(A, v);
    end
end

function [c, sse] = lsqNonnegTail(A, y)
% least squares with c(2:end) >= 0 (c(1) free), by checking every active set
m = size(A,2);
best = inf; c = zeros(m,1);
for mask = 0:2^(m-1)-1
    use = [true, bitget(mask, 1:m-1) == 0];
    As = A(:,use);
    if rank(As) < size(As,2), continue; end
    cs = As \ y;
    if any(cs(2:end) < 0), continue; end
    e = sum((y - As*cs).^2);
    if e < best, best = e; c = zeros(m,1); c(use) = cs; end
end
sse = best;
end

function y = zohSample(t, x, tq)
[tu, ia] = unique(t, 'last');
k = discretize(tq, [tu; inf]);
y = zeros(size(tq));
ok = ~isnan(k);
y(ok) = x(ia(k(ok)));
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

function [pts, ex] = denseOcvPoints(d, soc, ph, g, R0, Rk, Tk, C, AH)
% OCV estimate along low-rate CC charge / discharge (I positive = charge):
%   OCV = V - I*R0(SOC) - sum_k R_k(SOC) * x_k
% Charge and discharge estimates are averaged per 1 % SOC bin, which cancels
% most of the remaining model error and the hysteresis.
% ex = one sample worked through by hand (for the "How?" window)
pts = []; ex = [];
I = d.I; V = d.V; t = d.t;
mask = abs(I) > 0 & abs(I) <= C.ocvMaxCrate*AH;
if nnz(mask) < 20, return; end
sc = min(max(soc, g(1)), g(end));
r0 = interp1(g, R0, sc);
est = V - I.*r0;
Rx = zeros(numel(I), numel(Rk));
tauMaxUsed = 0;
for q = 1:numel(Rk)
    tau = median(Tk{q}, 'omitnan');
    tauMaxUsed = max(tauMaxUsed, tau);
    Rx(:,q) = interp1(g, Rk{q}, sc).*rcCurrent(t, I, tau);
    est = est - Rx(:,q);
end
settled = false(size(I));          % skip the first 3*tau of each phase
for k = 1:numel(ph)
    if ph(k).type == 'R', continue; end
    idx = ph(k).i1:ph(k).i2;
    settled(idx) = (t(idx) - ph(k).t1) > min(3*tauMaxUsed, 0.3*ph(k).dur);
end
mask = mask & settled & soc >= -0.02 & soc <= 1.02;
cand = find(mask & I < 0);
if isempty(cand), cand = find(mask); end
if ~isempty(cand)
    [~, j] = min(abs(soc(cand) - 0.5)); i = cand(j);
    ex = struct('t',t(i), 'soc',soc(i), 'V',V(i), 'I',I(i), 'R0',r0(i), 'IR0',I(i)*r0(i), ...
        'Rx',Rx(i,:), 'est',est(i));
end
bins = round(soc*100)/100;
dch = mask & I < 0; chg = mask & I > 0;
[ud, ~, id] = unique(bins(dch)); vd = accumarray(id, est(dch), [], @mean);
[uc, ~, ic] = unique(bins(chg)); vc = accumarray(ic, est(chg), [], @mean);
[ub, ia, ib] = intersect(ud, uc);
both = [ub, (vd(ia) + vc(ib))/2];
onlyD = [ud(~ismember(ud, ub)), vd(~ismember(ud, ub))];
onlyC = [uc(~ismember(uc, ub)), vc(~ismember(uc, ub))];
if ~isempty(both)
    % one-sided bins are shifted by the mean charge/discharge offset (hysteresis)
    onlyD(:,2) = onlyD(:,2) - mean(vd(ia) - both(:,2));
    onlyC(:,2) = onlyC(:,2) - mean(vc(ib) - both(:,2));
end
pts = sortrows([both; onlyD; onlyC]);
end

function [ocv, prov] = buildOcv(restPts, dense, g)
% OCV on the breakpoints g:
%   shape from the dense (corrected low-rate) curve, level from the relaxed
%   rest voltages; rest points alone where the dense curve does not reach.
n = numel(g);
ocv = nan(1,n); prov = repmat('-', 1, n);
if ~isempty(restPts)          % average rest points at the same SOC (charge + discharge side)
    restPts = sortrows(restPts(all(isfinite(restPts),2),:));
    cl = cumsum([true; diff(restPts(:,1)) > 0.01]);
    restPts = [accumarray(cl, restPts(:,1), [], @mean), accumarray(cl, restPts(:,2), [], @mean)];
end
if size(dense,1) <= 10, dense = []; end
if ~isempty(dense) && ~isempty(restPts)
    denseAt = @(x) interp1(dense(:,1), dense(:,2), x, 'linear', NaN);
    sr = restPts(:,1);
    off = denseAt(sr) - restPts(:,2);
    fin = isfinite(off);
    if any(fin)
        so = sr(fin); oo = off(fin);
        for j = 1:n
            dj = denseAt(g(j));
            if ~isfinite(dj), continue; end
            if numel(so) == 1, c = oo;
            else, c = interp1(so, oo, min(max(g(j), so(1)), so(end)), 'linear');
            end
            ocv(j) = dj - c;
            if min(abs(sr - g(j))) <= 0.02, prov(j) = 'M'; else, prov(j) = 'I'; end
        end
    end
end
if size(restPts,1) >= 2
    sr = restPts(:,1); vr = restPts(:,2);
    for j = 1:n
        if isfinite(ocv(j)), continue; end
        if g(j) >= sr(1) - 0.02 && g(j) <= sr(end) + 0.02
            k = find(sr >= g(j), 1); if isempty(k), k = numel(sr); end
            km = max(k-1, 1);
            if min(abs(sr - g(j))) < 0.02 || sr(k) - sr(km) <= 0.21
                ocv(j) = interp1(sr, vr, min(max(g(j), sr(1)), sr(end)), 'pchip');
                if min(abs(sr - g(j))) <= 0.02, prov(j) = 'M'; else, prov(j) = 'I'; end
            end
        end
    end
elseif isempty(restPts) && ~isempty(dense)
    in = g >= dense(1,1) & g <= dense(end,1);
    ocv(in) = interp1(dense(:,1), dense(:,2), g(in)); prov(in) = 'I';
end
% one breakpoint past the data on either end: extend with the nearest slope
have = find(isfinite(ocv));
if numel(have) >= 2
    for j = [have(1)-1, have(end)+1]
        if j < 1 || j > n, continue; end
        if j < have(1), a = have(1); b = have(2); else, a = have(end-1); b = have(end); end
        if abs(g(j) - g(a)) > 0.06, continue; end      % only short extensions
        ocv(j) = ocv(a) + (ocv(b) - ocv(a))/(g(b) - g(a))*(g(j) - g(a));
        prov(j) = 'E';
    end
end
fin = find(isfinite(ocv));            % OCV must rise with SOC
for j = 2:numel(fin)
    if ocv(fin(j)) <= ocv(fin(j-1)), ocv(fin(j)) = ocv(fin(j-1)) + 1e-4; end
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

% ======================================================================
%  Multi-rate analysis (the rate test: the same full -> empty discharge at
%  several C-rates)
% ======================================================================
function mr = multiRate(d, soc, ph, C, AH, Tref, rc)
% Once the RC branches have settled after the step, a constant-current
% discharge sits at
%     V(SOC, I) = OCV(SOC) - R_dc(SOC) * |I|,   R_dc = R0 + R1 + R2 + ...
% (the block's own equation with every branch current equal to I). With the
% same discharge done at several currents, a straight-line fit of V against
% |I| at each SOC gives
%     intercept = OCV on the discharge side   (voltage at zero current)
%     slope     = R_dc                         (the DC resistance)
% Only CC discharges that start from a full charge are used (so SOC is
% exact), only samples within C.maxDT of Tref, rates <= C.mrMaxCrate.
% "Settled": what is left of each RC transient, R_k*|I|*exp(-t/tau_k), is
% below C.settleV (R_k, tau_k = median of the rest fits), i.e.
%     t >= max_k tau_k * ln(R_k*|I| / C.settleV)
% (C.settleNoFit when no rest could be fitted).
% The charge side: CC part of the charges. With 2+ charge rates it gets its
% own fit; with one rate (0.34C here) its OCV is V - I*R_dc (one resistance
% for both directions, as in the block). OCV = average of the two sides
% (cancels hysteresis), like the low-rate "pseudo-OCV" method.
mr = struct('ok',false, 'why','', 'sf',(0:0.01:1)', 'rates',[], 'crate',[], 'phase',[], ...
    'use',[], 'Vd',[], 'nRate',[], 'ocvD',[], 'Rdc',[], 'rms',[], 'Ic',[], 'Vc',[], ...
    'ocvC',[], 'chargeHow','', 'hyst',NaN, 'dense',[], 'RdcPts',[], 'settle',[], 'dur',[], 'unsettled',[], 'rc',rc, ...
    'maxDT',C.maxDT, 'Tref',Tref, 'maxCrate',C.mrMaxCrate);
if ~isfinite(AH), mr.why = 'needs the capacity'; return; end
sf = mr.sf;
useT = isfinite(Tref) && any(isfinite(d.Tcell));
if isempty(rc.R)
    settleT = @(I) C.settleNoFit;
else
    settleT = @(I) max([60, rc.tau .* log(max(rc.R*I/C.settleV, 1))]);
end
% ---- discharges from full
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
for r = 1:numel(mr.rates)
    p = ph(mr.phase(r));
    idx = (p.i1:p.i2)';
    mr.settle(r) = settleT(mr.rates(r));
    keep = d.t(idx) - p.t1 >= mr.settle(r);
    if useT, keep = keep & abs(d.Tcell(idx) - Tref) <= C.maxDT; end
    mr.Vd(r,:) = binMean(soc(idx(keep)), d.V(idx(keep)), sf);
end
mr.dur = arrayfun(@(k) ph(k).dur, mr.phase);
mr.unsettled = find(mr.crate <= C.mrMaxCrate & ~any(isfinite(mr.Vd), 2)');   % rates that never settled
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
% ---- charge side
chg = struct('I',{},'V',{});
for k = 1:numel(ph)
    p = ph(k);
    if p.type ~= 'C' || p.dur < 300, continue; end
    idx = (p.i1:p.i2)';
    Ia = d.I(idx);
    cc = Ia >= 0.95*max(Ia);                            % the CC part
    keep = cc & d.t(idx) - p.t1 >= settleT(median(Ia(cc)));
    if useT, keep = keep & abs(d.Tcell(idx) - Tref) <= C.maxDT; end
    if nnz(keep) < 10, continue; end
    chg(end+1).I = median(Ia(cc)); %#ok<AGROW>
    chg(end).V = binMean(soc(idx(keep)), d.V(idx(keep)), sf);
end
mr.ocvC = nan(numel(sf),1);
if ~isempty(chg)
    Ic = [chg.I]; Vc = vertcat(chg.V);
    lev = round(Ic/(0.02*AH));                          % same rate = within 0.02C
    [ul, ~, id] = unique(lev);
    Vl = nan(numel(ul), numel(sf)); Il = nan(1, numel(ul));
    for q = 1:numel(ul)
        Vl(q,:) = median(Vc(id == q,:), 1, 'omitnan'); Il(q) = median(Ic(id == q));
    end
    mr.Ic = Il; mr.Vc = Vl;
    if numel(ul) >= 2
        for j = 1:numel(sf)
            u = find(isfinite(Vl(:,j)));
            if numel(u) < 2, continue; end
            c = [ones(numel(u),1), Il(u)'] \ Vl(u,j);
            mr.ocvC(j) = c(1);
        end
        mr.chargeHow = sprintf('%d-rate charge fit', numel(ul));
    else
        mr.ocvC = Vl(1,:)' - Il(1)*mr.Rdc;
        mr.chargeHow = sprintf('%.2gC charge (V - I*R_dc)', Il(1)/AH);
    end
end
both = isfinite(mr.ocvD) & isfinite(mr.ocvC);
if nnz(both) >= 3
    mr.hyst = mean(mr.ocvC(both) - mr.ocvD(both))/2;    % half the charge-discharge gap
    ocv = (mr.ocvD + mr.ocvC)/2;
    onlyD = isfinite(mr.ocvD) & ~both; ocv(onlyD) = mr.ocvD(onlyD) + mr.hyst;
    onlyC = isfinite(mr.ocvC) & ~both; ocv(onlyC) = mr.ocvC(onlyC) - mr.hyst;
else
    ocv = mr.ocvD;
    mr.chargeHow = 'no charge data (discharge side only)';
end
f = isfinite(ocv);
mr.dense = [sf(f), ocv(f)];
mr.ocv = ocv;
f = isfinite(mr.Rdc);
mr.RdcPts = [sf(f), mr.Rdc(f)];
mr.ok = true;
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


function [R, prov, chk] = scaleToRdc(R, prov, mr, g, nRC)
% Breakpoints whose R0 was NOT measured there (interpolated 'I' / held 'E')
% but where the multi-rate fit measured R_dc: scale R0 and R1..Rn together
% so R0 + sum Rk = R_dc ('S'). Measured breakpoints ('M') are left alone and
% only compared (chk = [soc, R0+sumRk, R_dc]).
chk = zeros(0,3);
keysR = {'R0_vec'};
for q = 1:nRC
    if R.found.(sprintf('R%d_vec',q)), keysR{end+1} = sprintf('R%d_vec',q); end %#ok<AGROW>
end
rdc = interp1(mr.RdcPts(:,1), mr.RdcPts(:,2), g, 'linear', NaN);
for j = 1:numel(g)
    if ~isfinite(rdc(j)), continue; end
    tot = 0;
    for q = 1:numel(keysR), tot = tot + R.value.(keysR{q})(j); end
    if prov.R0_vec(j) == 'M'
        chk(end+1,:) = [g(j), tot, rdc(j)]; %#ok<AGROW>
        continue
    end
    k = rdc(j)/tot;
    for q = 1:numel(keysR)
        R.value.(keysR{q})(j) = R.value.(keysR{q})(j)*k;
        prov.(keysR{q})(j) = 'S';
    end
end
end
