function F = fitTableBased(R, nRC, g, progress)
%FITTABLEBASED  Battery (Table-Based) tables fitted to the WHOLE test.
%
%   F = fitTableBased(R, nRC, SOC_vec)            R = extractCellParameters result
%   F = fitTableBased(R, nRC, SOC_vec, @(msg)..)  with status text
%
%   The extraction measures each value where the test shows it (R0 at the
%   steps, OCV from the rate ladder, ...). Put straight into Simulink that set
%   misses in three places, because each piece was measured on its own:
%     - the start (~70 mV): the OCV near SOC 0 came from rests that end 3 h
%       after a discharge to cut-off, while the cell is still recovering;
%     - the rests after a discharge: the voltage creeps up for hours, but the
%       RC pairs from the first 10 min of a step last seconds to a minute;
%     - the end of the fast discharges: one resistance per SOC measured at low
%       current is far too high at 15 A, so the model falls to ~0.5 V instead
%       of stopping at 2.5 V like the cell.
%   This fit chooses every table number so that THE BLOCK'S OWN EQUATIONS,
%   driven by the measured current, give the measured voltage over the whole
%   test (least squares):
%
%     V = V0(SOC) + I*R0(SOC,T) + sum Uk,   dUk/dt = (I*Rk(SOC) - Uk)/tauk
%
%   1. SOC(t) is coulomb counting from SOC0 (AH and SOC0 from the extraction).
%   2. For fixed tau1..tauN the voltage is a SUM of table values times known
%      signals, so all table values come from ONE linear least-squares solve.
%   3. tau1..tauN are searched around that solve (fminsearch).
%   4. m*cp and h*A are fitted with the block's own heat (I^2*R0 + sum Uk^2/Rk),
%      and the tables are solved again at the temperature the BLOCK computes,
%      twice, so the tables and Simulink's temperature agree.
%
%   The shapes are kept simple on purpose - each one is what kept the
%   Simulink run stable and close (other shapes were tried, see README 7.11):
%     V0(SOC)     one OCV curve, the same at every temperature (an OCV that
%                 changes with T let the fit hide overpotential in it, which
%                 makes no heat, so the simulated cell did not warm up)
%     R0(SOC,T)   the temperature axis: the fast discharge heats the cell from
%                 the test temperature to ~60 °C, and the hot cell's lower
%                 resistance is what makes it stop at 2.5 V. Only falls with T.
%     Rk(SOC)     RC pairs over SOC only, growing towards SOC 0 (the knee and
%                 the slow recovery after a discharge to cut-off). An RC
%                 resistance that changes with T, or drops to ~0 somewhere,
%                 makes the block's U^2/R heat spike when the cell warms in a rest.
%   Breakpoints: T = the chamber temperatures, then every <= 15 K up to the
%   hottest the cell got. Weights: every sample once; first / last / lowest /
%   highest point of every phase 10x; the last 10 min of every discharge 10x
%   (its last sample 30x); the opening rest 10x (its ends 100x).
%
%   F: SOC_vec, T_vec (K), V0, R0, R1.., tau1.. (nSOC x nT), AH, SOC0, T0 (K),
%      thermal_mass, hA, nRC, and F.fit (data, fitted / simulated voltage, rms).

if nargin < 4 || isempty(progress), progress = @(m) []; end
d = R.d;

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

AH = R.value.AH;
if isempty(AH) || ~isfinite(AH) || AH <= 0, error('needs the capacity AH from the extraction'); end
SOC0 = R.diag.soc.raw0;                          % not clipped to 0..1
if isempty(SOC0) || ~isfinite(SOC0), SOC0 = R.value.SOC0; end
if isempty(SOC0) || ~isfinite(SOC0), error('needs the initial SOC from the extraction'); end

% ---------------------------------------------------------------- breakpoints
g = unique(min(max(g(:)', 0), 1));
Tg = tempBreakpoints(d, Tcell);
nS = numel(g); nT = numel(Tg); nC = nS*nT;
R0ext = R.value.R0_vec;
if isempty(R0ext), R0ext = 0.02; end
Rmin = max(1e-5, 0.05*min(R0ext(:)));            % floor for every resistance

% ---------------------------------------------------------------- weights
ph = phaseList(I, d.restThr);
w = ones(N,1); key = 1;
for p = 1:size(ph,1)
    k = ph(p,1):ph(p,2);
    [~, ia] = min(V(k)); [~, ib] = max(V(k));
    key = [key, k(1), k(end), k(ia), k(ib)]; %#ok<AGROW>
end
key = unique(key); w(key) = 10;
% the knee: the last 10 min of every discharge count 10x, its last sample 30x,
% so every discharge reaches the cut-off when the cell does
for p = 1:size(ph,1)
    k = ph(p,1):ph(p,2);
    if median(I(k)) < -max(d.restThr, 1e-3)
        w(k(t(k) >= t(k(end)) - 600)) = 10; w(k(end)) = 30;
    end
end
if ph(1,2) > ph(1,1) && all(abs(I(ph(1,1):ph(1,2))) <= max(d.restThr, 1e-3))
    w(ph(1,1):ph(1,2)) = 10; w(ph(1,[1 2])) = 100;
end
sw = sqrt(w);

% ---------------------------------------------------------------- columns
% long sample intervals split (<= 0.2 % SOC) so the RC pairs see the tables
% change with SOC as finely as Simulink's solver does
[tr, Ir, iData] = refineTimeGrid(t, I, AH);
Nr = numel(tr); dtr = [diff(tr); 0];
socr = SOC0 + [0; cumsum(Ir(1:end-1).*dtr(1:end-1))]/3600/AH;
Tr = interp1(t, Tcell, tr);
isRow = false(Nr,1); isRow(iData) = true;
W  = full(lookupWeights(socr, Tr, g, Tg));       % Nr x nC   (SOC x T)
Ws = full(lookupWeights(socr, Tr, g, Tg(1)));    % Nr x nS   (SOC only)
u0 = Ir .* W;                                    % R0 columns: I x weights
us = Ir .* Ws;                                   % RC input:   I x SOC weights
nR = nS;
b  = V .* sw;
% columns: V0 (nS: same at every T), R0 (nC), then each RC pair's R (nS: same at every T)
off = [0, nS, nS + nC + (0:nRC)*nR];
nx = off(end);
Reg = smoothRows();

% x = lo + Tm*y, y >= 0, so every rule holds by construction:
%   V0  = V0(SOC 0) + rising steps                       (OCV rises with SOC)
%   R0(:,j) = R0(:,hottest) + steps towards colder T      (hotter -> lower R0)
%   Rk(SOC) = Rk(SOC 1) + steps towards SOC 0             (the knee: RC pairs
%             grow towards empty, never dip to ~0 somewhere in the middle)
%   every R >= Rmin
TmV = tril(ones(nS));
TmR = kron(triu(ones(nT)), eye(nS));
TmK = kron(eye(nRC), triu(ones(nS)));
Tm = blkdiag(TmV, TmR, TmK);
lo = [zeros(nS,1); Rmin*ones(nx - nS,1)];

progress(sprintf('Fitting the tables to the whole test (%d RC pairs, %d temperatures)...', nRC, nT));
hist = zeros(0, nRC+1);
z0 = log([1 150 20000]); z0 = z0(1:nRC);
if nRC == 1, z0 = log(60); elseif nRC == 2, z0 = log([5 600]); end
z = fminsearch(@(z) solveTables(z, false), z0, ...
    optimset('Display','off','MaxFunEvals',40*nRC,'TolX',2e-3,'TolFun',1e-8));
progress('Final least-squares solve (OCV rising, R > 0, R falling with temperature)...');
[~, x] = solveTables(z, true);
[tau, order] = sort(exp(z));

F.nRC = nRC; F.SOC_vec = g; F.T_vec = Tg + 273.15;
F.AH = AH; F.SOC0 = min(max(SOC0, 0), 1); F.T0 = Tcell(1) + 273.15;
F.Rmin = Rmin; F.hasT = hasT;
F = putTables(F, x);
mcp0 = R.value.thermal_mass; hA0 = R.value.hA;
if isempty(mcp0) || ~isfinite(mcp0), mcp0 = 40; end
if isempty(hA0) || ~isfinite(hA0), hA0 = 0.05; end
F.thermal_mass = mcp0; F.hA = hA0;
fitOut = simulateTableBased(F, t, I, Tch, Tcell);          % at the measured temperature

% ---------------------------------------------------------------- thermal
% m*cp and h*A with the block's own heat, then the tables are solved again at
% the temperature the BLOCK computes (that is the column Simulink will use),
% and once more - so tables and simulated temperature agree with each other
doThermal = hasT && max(Tcell) - min(Tcell) > 0.5;
for pass = 1:3
    if doThermal
        progress(sprintf('Thermal mass and h*A with the block''s own heat (pass %d/3)...', pass));
        cost = @(p) rms(getfield(simulateTableBased(setT(F, exp(p)), t, I, Tch), 'T_C') - Tcell); %#ok<GFLD>
        p = fminsearch(cost, log([F.thermal_mass F.hA]), optimset('Display','off','MaxFunEvals',50,'TolX',1e-3));
        F = setT(F, exp(p));
    end
    sim = simulateTableBased(F, t, I, Tch);
    if ~doThermal || pass == 3, break; end
    progress(sprintf('Tables again at the block''s own temperature (pass %d/3)...', pass));
    Tr = interp1(t, sim.T_C, tr);
    W = full(lookupWeights(socr, Tr, g, Tg)); u0 = Ir .* W;
    [~, x] = solveTables(z, true);
    F = putTables(F, x);
end
F.fit = struct('t',t, 'V',V, 'I',I, 'Tcell',Tcell, 'Tch',Tch, 'phases',ph, 'w',w, 'hist',hist, ...
    'Vfit',fitOut.V, 'sim',sim, 'rmsFit_mV',1000*rms(fitOut.V - V), ...
    'rmsSim_mV',1000*rms(sim.V - V), 'rmsT_K',rms(sim.T_C - Tcell));

    function F = putTables(F, x)
        F.V0 = repmat(x(1:nS), 1, nT);
        F.R0 = reshape(x(nS + (1:nC)), nS, nT);
        for kk = 1:nRC
            F.(sprintf('R%d',kk)) = repmat(x(off(2+order(kk)) + (1:nR)), nS/nR, nT);
            F.(sprintf('tau%d',kk)) = tau(kk)*ones(nS, nT);
        end
    end

    function [e, x] = solveTables(z, final)
        tauz = exp(z);
        A = [Ws(iData,:), u0(iData,:), zeros(N, nRC*nR)];
        for q = 1:nRC
            a = exp(-dtr/tauz(q));
            u = zeros(1, nR); r = 0;
            cols = off(2+q) + (1:nR);
            for i = 1:Nr
                if isRow(i), r = r + 1; A(r, cols) = u; end
                u = a(i)*u + (1-a(i))*us(i,:);
            end
        end
        A = A .* sw;
        M = A'*A + Reg'*Reg;
        c = A'*b;
        if ~final
            x = M \ c;                           % fast, no limits (for the search)
        else
            My = Tm'*M*Tm; cy = Tm'*(c - M*lo);
            Rf = chol(My + 1e-12*trace(My)/nx*eye(nx));
            x = lo + Tm*lsqnonneg(Rf, Rf'\cy);
        end
        e = sqrt(mean((A*x - b).^2));
        hist(end+1, :) = [tauz(:)', e];
    end

    function Reg = smoothRows()
        % second difference along SOC, first difference along T
        D2 = diff(speye(nS), 2);
        Ls = kron(speye(nT), D2);
        if nT > 1, Lt = kron(diff(speye(nT), 1), speye(nS)); else, Lt = sparse(0, nC); end
        Reg = sparse(0, nx);
        for kk = 1:2 + nRC
            if kk == 2, Lk = [0.2*Ls; 0.02*Lt]; elseif kk == 1, Lk = 0.1*D2; elseif nR > 1, Lk = 0.2*D2; else, continue; end
            blk = sparse(size(Lk,1), nx);
            blk(:, off(kk) + (1:size(Lk,2))) = Lk;
            Reg = [Reg; blk]; %#ok<AGROW>
        end
    end
end

% =====================================================================
function F = setT(F, p)
F.thermal_mass = p(1); F.hA = p(2);
end

function T = fillT(t, T)
ok = isfinite(T);
if nnz(ok) < 2, return; end
T = interp1(t(ok), T(ok), t, 'linear');
T = fillmissing(T, 'nearest');
end

function Tg = tempBreakpoints(d, Tcell)
% the chamber temperatures of the test (discharges, charges), then points
% every <= 15 K out to the coldest / hottest the cell got
base = d.T_C;
if isfield(d, 'T_chg_C') && isfinite(d.T_chg_C), base = [base d.T_chg_C]; end
base = base(isfinite(base));
if isempty(base), base = median(Tcell); end
base = unique(round(base*2)/2);
lo = min(Tcell); hi = max(Tcell);
Tg = base;
while hi > Tg(end) + 3, Tg(end+1) = Tg(end) + min(15, max(hi - Tg(end), 5)); end %#ok<AGROW>
while lo < Tg(1) - 3,   Tg = [Tg(1) - min(15, max(Tg(1) - lo, 5)), Tg]; end %#ok<AGROW>
k = 1;
while k < numel(Tg)                              % split gaps wider than 15 K
    if Tg(k+1) - Tg(k) > 15.01
        Tg = [Tg(1:k), (Tg(k)+Tg(k+1))/2, Tg(k+1:end)];
    else
        k = k + 1;
    end
end
Tg = round(Tg*2)/2;
end

function ph = phaseList(I, thr)
% [first last] sample of every run of charge / discharge / rest
if nargin < 2 || isempty(thr) || ~isfinite(thr), thr = 1e-3; end
s = sign(I) .* (abs(I) > thr);
e = [find(diff(s) ~= 0); numel(I)];
ph = [[1; e(1:end-1) + 1], e];
end

function W = lookupWeights(s, T, g, Tg)
% bilinear weights in (SOC, T), end values held (Extrapolation = Nearest)
N = numel(s); nS = numel(g); nT = numel(Tg);
s = min(max(s, g(1)), g(end));
is = discretize(s, g); is(isnan(is)) = nS-1; is = min(is, nS-1);
fs = (s - g(is)')./(g(is+1)' - g(is)');
if nT == 1
    W = sparse([1:N, 1:N]', [is; is+1], [1-fs; fs], N, nS); return
end
T = min(max(T, Tg(1)), Tg(end));
it = discretize(T, Tg); it(isnan(it)) = nT-1; it = min(it, nT-1);
ft = (T - Tg(it)')./(Tg(it+1)' - Tg(it)');
rows = repmat((1:N)', 4, 1);
cols = [is + (it-1)*nS; is+1 + (it-1)*nS; is + it*nS; is+1 + it*nS];
vals = [(1-fs).*(1-ft); fs.*(1-ft); (1-fs).*ft; fs.*ft];
W = sparse(rows, cols, vals, N, nS*nT);
end
