function out = simulateTwinFast(tw, t, I, Tamb_C, Tcell_C)
%SIMULATETWINFAST  The Simulink twin's equations, in plain MATLAB.
%
%   out = simulateTwinFast(tw, t, I, Tamb_C)            temperature from the thermal model
%   out = simulateTwinFast(tw, t, I, Tamb_C, Tcell_C)   tables looked up at this temperature
%
%   Two kinds of tables (tw.kind):
%     'EC'  digital twin (fitDigitalTwin) for "Battery Equivalent Circuit":
%           V0(SOC), R0..R3(SOC, I), tau1..tau3 - no temperature axis.
%           Heat = I*(V - V0(SOC)) into a separate thermal mass (tw.heat = 'IV').
%     'TB'  Battery (Table-Based) with the Modeling-tab tables (tablesFromExtraction):
%           V0, R0, Rk, tauk (SOC x T); the block's own heat I^2*R0 + sum Uk^2/Rk
%           warms its own thermal mass, and T feeds back into the tables.
%
%   t, I     time (s) and current (A, + = charge). I(i) holds from t(i) to t(i+1),
%            exactly like the cycler (and From Workspace with Interpolate = off)
%   Tamb_C   chamber temperature (°C) at t
%
%   Every sample:
%     V      = V0 + I*R0 + U1 + U2 + U3                     terminal voltage
%     dUk/dt = (I*Rk - Uk) / tauk                           each RC pair
%     dSOC/dt = I / (3600*AH)                               coulomb counting
%     m*cp*dT/dt = Q - hA*(T - Tamb)                        lumped thermal mass
%   Within one sample interval the current is constant, so U and T move with
%   their exact exponential solution. Tables are linear between breakpoints
%   and held outside them (Nearest).

% long sample intervals are split (<= 0.2 % SOC per piece) so the SOC lookups
% follow the SOC as finely as Simulink's solver does; results at the samples
t = t(:); I = I(:); t0 = t;
[t, I, iD] = refineTimeGrid(t0, I, tw.AH);
Tamb_C = interp1(t0, Tamb_C(:), t);
if nargin >= 5 && ~isempty(Tcell_C), Tcell_C = interp1(t0, Tcell_C(:), t); else, Tcell_C = []; end
out = core(tw, t, I, Tamb_C, Tcell_C);
for f = fieldnames(out)'
    out.(f{1}) = out.(f{1})(iD,:);
end
end

function out = core(tw, t, I, Tamb_C, Tcell_C)
N = numel(t);
dt = [diff(t); 0];
soc = tw.SOC0 + [0; cumsum(I(1:end-1).*dt(1:end-1))]/3600/tw.AH;
g = tw.SOC_vec(:)'; nRC = tw.nRC;
mcp = tw.thermal_mass; hA = tw.hA;

if strcmp(tw.kind, 'EC')
    % ---------------- electrical part does not depend on T: solve it first
    Wv = weights2(soc, g, [], []);
    Wr = weights2(soc, g, I, tw.I_vec(:)');
    v0 = Wv*tw.V0(:);
    r0 = Wr*tw.R0(:);
    U = zeros(N, nRC);
    for k = 1:nRC
        rk = Wr*tw.(sprintf('R%d',k))(:);
        a = exp(-dt/tw.(sprintf('tau%d',k)));
        u = 0;
        for i = 1:N
            U(i,k) = u;
            u = a(i)*u + (1-a(i))*I(i)*rk(i);
        end
    end
    V = v0 + I.*r0 + sum(U, 2);
    Q = I .* (V - v0);                    % everything the cell loses becomes heat
    if ~isempty(Tcell_C)
        T = Tcell_C(:);
    else
        T = zeros(N,1); T(1) = tw.T0 - 273.15;
        for i = 1:N-1
            Tinf = Tamb_C(i) + Q(i)/hA;
            T(i+1) = Tinf + (T(i) - Tinf)*exp(-hA*dt(i)/mcp);
        end
    end
    out = struct('t',t, 'V',V, 'soc',soc, 'T_C',T, 'Q',Q, 'V0',v0, 'U',U);
    return
end

% ---------------- 'TB': Battery (Table-Based), tables over SOC x T, own heat
Tg = tw.T_vec(:)' - 273.15; nT = numel(Tg);
givenT = ~isempty(Tcell_C);
Ws = weights2(soc, g, [], []);
X = cell(1, 2 + 2*nRC);
X{1} = Ws*tw.V0; X{2} = Ws*tw.R0;
for k = 1:nRC
    X{2+k} = Ws*tw.(sprintf('R%d',k));
    X{2+nRC+k} = Ws*tw.(sprintf('tau%d',k));
end
V = zeros(N,1); T = zeros(N,1); Q = zeros(N,1); v0s = zeros(N,1);
u = zeros(1, nRC);
Tk = tw.T0 - 273.15;
for i = 1:N
    if givenT, Tk = Tcell_C(i); end
    if nT == 1
        j = 1; j2 = 1; f = 0;
    else
        Tq = min(max(Tk, Tg(1)), Tg(end));
        j = find(Tg <= Tq, 1, 'last'); j = min(j, nT-1); j2 = j + 1;
        f = (Tq - Tg(j))/(Tg(j2) - Tg(j));
    end
    v0 = X{1}(i,j) + f*(X{1}(i,j2) - X{1}(i,j));
    r0 = X{2}(i,j) + f*(X{2}(i,j2) - X{2}(i,j));
    V(i) = v0 + I(i)*r0 + sum(u); v0s(i) = v0;
    T(i) = Tk;
    q = I(i)^2*r0;
    for k = 1:nRC
        A = X{2+k};     rk = A(i,j) + f*(A(i,j2) - A(i,j));
        A = X{2+nRC+k}; tk = A(i,j) + f*(A(i,j2) - A(i,j));
        q = q + u(k)^2/max(rk, 1e-9);
        a = exp(-dt(i)/tk);
        u(k) = u(k)*a + (1-a)*I(i)*rk;
    end
    Q(i) = q;
    if ~givenT && i < N
        Tinf = Tamb_C(i) + q/hA;
        Tk = Tinf + (Tk - Tinf)*exp(-hA*dt(i)/mcp);
    end
end
out = struct('t',t, 'V',V, 'soc',soc, 'T_C',T, 'Q',Q, 'V0',v0s);
end

function W = weights2(s, g, x, xg)
% bilinear weights in (SOC, x), end values held; no x -> SOC only
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
