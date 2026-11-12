function tw = fitDigitalTwin(d, R, opts)
%FITDIGITALTWIN  Digital-twin tables, fitted to the WHOLE test.
%
%   tw = fitDigitalTwin(R.d, R)          R = extractCellParameters(...) result
%   tw = fitDigitalTwin(R.d, R, opts)    opts.progress = @(msg) ...  (status text)
%
%   In one sentence: every table number is chosen so that the model, driven
%   by the measured current, gives the measured voltage over the whole test
%   (least squares). The Modeling-tab extraction gives AH and SOC0.
%
%   WHY A CURRENT AXIS. Battery (Table-Based) has one resistance per SOC (and
%   temperature). A real cell's resistance falls as the current rises: at 0 °C
%   this cell shows ~115 mOhm 12 s into a 0.1C discharge but ~52 mOhm at 15 A.
%   One number cannot give both, so the Table-Based twin misses either the slow
%   or the fast discharge by up to ~1 V. The Simscape Battery block "Battery
%   Equivalent Circuit" has the same tables PLUS a current axis on every
%   resistance, so every discharge rate of the test gets its own column.
%
%   The model (I + = charge):
%     V(t)    = V0(SOC) + I*R0(SOC,I) + U1 + U2 + U3        terminal voltage
%     dUk/dt  = (I*Rk(SOC,I) - Uk) / tauk                   3 RC pairs
%     SOC(t)  = SOC0 + integral(I dt) / (3600*AH)           coulomb counting
%     m*cp*dT/dt = I*(V - V0) - hA*(T - T_chamber)          heat: the voltage the
%                                                           cell loses, times I
%
%   How the numbers are found:
%   1. SOC(t) is coulomb counting from SOC0 (known: AH and SOC0 from the
%      Modeling tab).
%   2. For fixed tau1..tau3 the voltage is a SUM of table values times known
%      signals (V0: interpolation weights; R0: weights x I; Rk: weights x I,
%      smoothed with tauk). So ALL table values come from ONE linear
%      least-squares solve. Rules: every R >= a small floor, V0 rises with SOC,
%      tables smooth along SOC and current.
%   3. tau1..tau3 are searched around that (fminsearch, 3 numbers).
%      They come out at ~seconds, ~minutes and ~hours: the hours one is the
%      slow creep of the voltage after a discharge to cut-off.
%   4. m*cp and h*A: the twin's heat I*(V - V0) through a lumped thermal mass
%      with the chamber as the ambient, fitted to the measured cell temperature.
%
%   Breakpoints: SOC dense at the knee and at the top of charge; current = 0
%   and the constant current of every charge / discharge in the test (median
%   of the phase), so the max-rate discharge - whatever it is in a file - gets
%   its own column, and the tail of the CV charge runs between 0 and the CC current.
%   Weights: every sample counts once; the first / last / lowest / highest
%   voltage of every charge, discharge and rest count 10 times, so the twin
%   starts, turns and ends where the cell does. The rest the file starts with
%   (the only point with no history) counts 10 times, its ends 100 times.
%
%   tw  (kind 'EC', see buildTwinModel for where each goes in the block)
%     SOC_vec, I_vec (A), V0 (nSOC x 1), R0 R1 R2 R3 (nSOC x nI), tau1..3 (s),
%     AH, SOC0, T0 (K), thermal_mass (J/K), hA (W/K), nRC
%     load [t I] (+ = charge), ambient [t K], stopTime
%     fit  data + the fitted voltage, sim  simulateTwinFast (what Simulink gives)

if nargin < 3, opts = struct(); end
say = @(m) [];
if isfield(opts, 'progress') && ~isempty(opts.progress), say = opts.progress; end
nRC = 3;
tauMax = inf;
if isfield(opts, 'tauMax'), tauMax = opts.tauMax; end

% ---------------------------------------------------------------- data
[t, iu] = unique(d.t(:) - d.t(1), 'last');
I = d.I(iu); V = d.V(iu);
Tcell = d.Tcell(iu); Tch = d.Tch(iu);
if nnz(isfinite(Tch)) < 2, Tch = 25*ones(size(t)); end
Tch = fillT(t, Tch);
hasT = nnz(isfinite(Tcell)) > 10;
if ~hasT, Tcell = Tch; end
Tcell = fillT(t, Tcell);
N = numel(t);
dt = [diff(t); 0];

AH = R.value.AH;
if isempty(AH) || ~isfinite(AH) || AH <= 0, error('The twin needs the capacity (AH): press Extract first.'); end
SOC0 = R.diag.soc.raw0;                               % not clipped to 0..1
if isempty(SOC0) || ~isfinite(SOC0), SOC0 = R.value.SOC0; end
if isempty(SOC0) || ~isfinite(SOC0), error('The twin needs the initial SOC: press Extract first.'); end
soc = SOC0 + [0; cumsum(I(1:end-1).*dt(1:end-1))]/3600/AH;

% ---------------------------------------------------------------- breakpoints
g = [0 0.005 0.01 0.02 0.03 0.04 0.05 0.075 0.1:0.05:0.9 0.925 0.95 0.97 0.98 0.99 1];
ph = phaseList(I, d.restThr);
Ig = currentBreakpoints(I, ph);
nS = numel(g); nI = numel(Ig); nC = nS*nI;
R0ext = R.value.R0_vec;
if isempty(R0ext), R0ext = 0.02; end
Rmin = max(1e-5, 0.05*min(median(R0ext, 1)));        % floor for every resistance

% ---------------------------------------------------------------- weights
w = ones(N,1);
key = 1;
for p = 1:size(ph,1)
    k = ph(p,1):ph(p,2);
    [~, ia] = min(V(k)); [~, ib] = max(V(k));
    key = [key, k(1), k(end), k(ia), k(ib)]; %#ok<AGROW>
end
key = unique(key);
w(key) = 10;
% the rest the file starts with is the one fully relaxed point (no history):
% it fixes the starting voltage, so it counts 10x all through, its ends 100x
if ph(1,2) > ph(1,1) && all(abs(I(ph(1,1):ph(1,2))) <= max(d.restThr, 1e-3))
    w(ph(1,1):ph(1,2)) = 10; w(ph(1,[1 2])) = 100;
end
keep = thinRows(t, ph, key, N);
sw = sqrt(w(keep));

% ---------------------------------------------------------------- linear least squares
% long sample intervals are split (<= 0.2 % SOC per piece) so the RC pairs see
% the tables change with SOC as finely as Simulink's solver does
[tr, Ir, iData] = refineTimeGrid(t, I, AH);
Nr = numel(tr); dtr = [diff(tr); 0];
socr = SOC0 + [0; cumsum(Ir(1:end-1).*dtr(1:end-1))]/3600/AH;
rowIdx = iData(keep);                              % fitted samples on the fine grid
isRow = false(Nr,1); isRow(rowIdx) = true;
Wv = full(lookupWeights(socr, g, [], []));         % Nr x nS     -> V0(SOC)
Wr = full(lookupWeights(socr, g, Ir, Ig));         % Nr x nS*nI  -> R(SOC,I)
u0 = Ir .* Wr;                                     % R0 columns: I x weights
b  = V(keep) .* sw;
Reg = smoothRows();

say('Fitting the tables to the whole test (searching the three time constants)...');
hist = zeros(0, nRC+1);
z = fminsearch(@(z) solveTables(z, false), log([5 150 20000]), ...
    optimset('Display','off','MaxFunEvals',120,'TolX',2e-3,'TolFun',1e-8));
say('Final least-squares solve (every resistance > 0, OCV rising with SOC)...');
[~, x] = solveTables(z, true);
[tau, order] = sort(min(exp(z), tauMax));                       % pairs numbered fast -> slow

tw.kind = 'EC';
tw.name = d.name;
tw.nRC = nRC;
tw.SOC_vec = g;
tw.I_vec = Ig;
tw.V0 = x(1:nS);
tw.R0 = reshape(x(nS + (1:nC)), nS, nI);
for k = 1:nRC
    tw.(sprintf('R%d',k)) = reshape(x(nS + order(k)*nC + (1:nC)), nS, nI);
    tw.(sprintf('tau%d',k)) = tau(k);
end
tw.AH = AH; tw.SOC0 = SOC0; tw.T0 = Tcell(1) + 273.15;
tw.Rmin = Rmin;
tw.V_range = [min(V) max(V)];

% ---------------------------------------------------------------- thermal
say('Fitting thermal mass and h*A to the cell temperature...');
mcp0 = R.value.thermal_mass; hA0 = R.value.hA;
if isempty(mcp0) || ~isfinite(mcp0), mcp0 = 40; end
if isempty(hA0) || ~isfinite(hA0), hA0 = 0.05; end
tw.thermal_mass = mcp0; tw.hA = hA0;
el = simulateTwinFast(tw, t, I, Tch);              % electrical part (no T dependence)
thermalFit = hasT && max(Tcell) - min(Tcell) > 0.5;
if thermalFit
    cost = @(p) rms(thermal(el.Q, exp(p(1)), exp(p(2))) - Tcell);
    p = fminsearch(cost, log([mcp0 hA0]), optimset('Display','off','MaxFunEvals',200,'TolX',1e-4));
    tw.thermal_mass = exp(p(1)); tw.hA = exp(p(2));
end

% ---------------------------------------------------------------- results
sim = simulateTwinFast(tw, t, I, Tch);
tw.load = [t I];
tw.ambient = [t, Tch + 273.15];
tw.stopTime = t(end);
tw.sim = sim;
tw.fit = struct('t',t, 'V',V, 'I',I, 'soc',soc, 'Tcell',Tcell, 'Tch',Tch, ...
    'w',w, 'key',key, 'phases',ph, 'hist',hist, 'hasT',hasT, 'thermalFit',thermalFit, ...
    'rms_mV',1000*rms(sim.V - V), 'rmsT_K',rms(sim.T_C - Tcell));

    function T = thermal(Q, mcp, hA)
        T = zeros(N,1); T(1) = Tcell(1);
        for i = 1:N-1
            Tinf = Tch(i) + Q(i)/hA;
            T(i+1) = Tinf + (T(i) - Tinf)*exp(-hA*dt(i)/mcp);
        end
    end

    function [e, x] = solveTables(z, final)
        % every column for these time constants, then one least-squares solve
        tauz = min(exp(z), tauMax);
        A = [Wv(rowIdx,:), u0(rowIdx,:), zeros(numel(rowIdx), nRC*nC)];
        for q = 1:nRC
            a = exp(-dtr/tauz(q));
            u = zeros(1, nC); r = 0;
            cols = nS + q*nC + (1:nC);
            for i = 1:Nr
                if isRow(i), r = r + 1; A(r, cols) = u; end
                u = a(i)*u + (1-a(i))*u0(i,:);
            end
        end
        A = A .* sw;
        M = A'*A + Reg'*Reg;
        c = A'*b;
        if ~final
            x = M \ c;                             % fast, no limits (for the search)
        else
            % same problem with R >= Rmin and V0 rising with SOC:
            % x = lo + Tm*y, y >= 0 (V0 = first value + cumulative steps >= 0)
            nx = size(M,1);
            lo = [zeros(nS,1); Rmin*ones(nx-nS,1)];
            Tm = blkdiag(tril(ones(nS)), eye(nx-nS));
            My = Tm'*M*Tm; cy = Tm'*(c - M*lo);
            Rf = chol(My + 1e-12*trace(My)/nx*eye(nx));
            x = lo + Tm*lsqnonneg(Rf, Rf'\cy);
        end
        e = sqrt(mean((A*x - b).^2));
        hist(end+1, :) = [tauz(:)', e];
    end

    function Reg = smoothRows()
        % keeps the tables smooth: second difference along SOC, first
        % difference along current. Weak enough not to fight the data, strong
        % enough to fill the corners the test never visits.
        D2 = diff(speye(nS), 2);
        Ls = kron(speye(nI), D2);
        Li = kron(diff(speye(nI), 1), speye(nS));
        nx = nS + (1+nRC)*nC;
        Reg = [0.05*D2, sparse(size(D2,1), nx-nS)];
        for kk = 0:nRC
            blk = sparse(size(Ls,1) + size(Li,1), nx);
            blk(:, nS + kk*nC + (1:nC)) = [0.3*Ls; 0.03*Li];
            Reg = [Reg; blk]; %#ok<AGROW>
        end
    end
end

% =====================================================================
function T = fillT(t, T)
ok = isfinite(T);
if nnz(ok) < 2, return; end
T = interp1(t(ok), T(ok), t, 'linear');
T = fillmissing(T, 'nearest');
end

function Ig = currentBreakpoints(I, ph)
% 0 A and the constant current of every charge / discharge (median of the
% phase), close ones (within 5 %) merged
lev = [];
for p = 1:size(ph,1)
    k = ph(p,1):ph(p,2);
    m = median(I(k));
    if abs(m) > 1e-3 && numel(k) > 3, lev(end+1) = m; end %#ok<AGROW>
end
lev = sort([lev 0]);                                % 0 A: the tail of a CV charge
Ig = lev(1);
for v = lev(2:end)
    if abs(v - Ig(end)) > 0.05*max(abs([v Ig(end)])) || v == 0 || Ig(end) == 0, Ig(end+1) = v; end %#ok<AGROW>
end
Ig = round(Ig*1000)/1000;
end

function ph = phaseList(I, thr)
% [first last] sample of every run of charge / discharge / rest
if nargin < 2 || isempty(thr) || ~isfinite(thr), thr = 1e-3; end
s = sign(I) .* (abs(I) > thr);
e = [find(diff(s) ~= 0); numel(I)];
b = [1; e(1:end-1) + 1];
ph = [b e];
end

function keep = thinRows(t, ph, key, N)
% big files: keep every sample for 10 min after a change, thin out the rest
keep = true(N,1);
if N <= 25000, return; end
first = zeros(N,1);
for p = 1:size(ph,1), first(ph(p,1):ph(p,2)) = t(ph(p,1)); end
keep = false(N,1); last = -inf; step = (t(end) - t(1))/20000;
for i = 1:N
    if t(i) - first(i) < 600 || t(i) - last >= step, keep(i) = true; last = t(i); end
end
keep(key) = true;
end

function W = lookupWeights(s, g, x, xg)
% bilinear interpolation weights in (SOC, x), end values held (Nearest);
% x empty -> SOC only
N = numel(s); nS = numel(g); nX = numel(xg);
s = min(max(s, g(1)), g(end));
is = discretize(s, g); is(isnan(is)) = nS-1; is = min(is, nS-1);
fs = (s - g(is)')./(g(is+1)' - g(is)');
if nX <= 1
    W = sparse([1:N, 1:N]', [is; is+1], [1-fs; fs], N, nS);
    return
end
x = min(max(x, xg(1)), xg(end));
ix = discretize(x, xg); ix(isnan(ix)) = nX-1; ix = min(ix, nX-1);
fx = (x - xg(ix)')./(xg(ix+1)' - xg(ix)');
rows = repmat((1:N)', 4, 1);
cols = [is + (ix-1)*nS; is+1 + (ix-1)*nS; is + ix*nS; is+1 + ix*nS];
vals = [(1-fs).*(1-fx); fs.*(1-fx); (1-fs).*fx; fs.*fx];
W = sparse(rows, cols, vals, N, nS*nX);
end
