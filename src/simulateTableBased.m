function out = simulateTableBased(P, t, I, Tamb_C, Tcell_C)
%SIMULATETABLEBASED  The Battery (Table-Based) block's equations, in plain MATLAB.
%
%   out = simulateTableBased(P, t, I, Tamb_C)            temperature from the block's thermal mass
%   out = simulateTableBased(P, t, I, Tamb_C, Tcell_C)   tables looked up at this temperature
%
%   P        SOC_vec, T_vec (K), V0, R0, R1.., tau1.. (nSOC x nT), AH, SOC0,
%            T0 (K), thermal_mass (J/K), hA (W/K), nRC  - the batt_* values
%   t, I     time (s) and current (A, + = charge); I(i) holds from t(i) to t(i+1)
%   Tamb_C   chamber temperature (°C) at t  (the convection block's ambient)
%
%   This is what the Simulink model computes, sample by sample:
%     V      = V0(SOC,T) + I*R0(SOC,T) + U1 + U2 + U3      terminal voltage
%     dUk/dt = (I*Rk(SOC,T) - Uk) / tauk                    each RC pair
%     dSOC/dt = I / (3600*AH)                               coulomb counting
%     m*cp*dT/dt = I^2*R0 + sum Uk^2/Rk - hA*(T - Tamb)     block heat + convection
%   Within one interval the current is constant, so U and T move with their
%   exact exponential solution. Long intervals are split (<= 0.2 % SOC) so the
%   SOC lookups are as fine as Simulink's solver. Tables are linear between
%   breakpoints and held outside them (Extrapolation = Nearest).

t = t(:); I = I(:); t0 = t;
[t, I, iD] = refineTimeGrid(t0, I, P.AH);
Tamb_C = interp1(t0, Tamb_C(:), t);
givenT = nargin >= 5 && ~isempty(Tcell_C);
if givenT, Tcell_C = interp1(t0, Tcell_C(:), t); end
N = numel(t); dt = [diff(t); 0];
soc = P.SOC0 + [0; cumsum(I(1:end-1).*dt(1:end-1))]/3600/P.AH;
g = P.SOC_vec(:)'; Tg = P.T_vec(:)' - 273.15; nT = numel(Tg); nRC = P.nRC;

% every table, already interpolated along SOC: N x nT
s = min(max(soc, g(1)), g(end));
k = discretize(s, g); k(isnan(k)) = numel(g)-1; k = min(k, numel(g)-1);
f = (s - g(k)')./(g(k+1)' - g(k)');
Ws = sparse([1:N, 1:N]', [k; k+1], [1-f; f], N, numel(g));
X = cell(1, 2 + 2*nRC);
X{1} = Ws*P.V0; X{2} = Ws*P.R0;
for q = 1:nRC
    X{2+q} = Ws*P.(sprintf('R%d',q));
    X{2+nRC+q} = Ws*P.(sprintf('tau%d',q));
end

V = zeros(N,1); T = zeros(N,1); Q = zeros(N,1); v0s = zeros(N,1);
U = zeros(1, nRC);
Tk = P.T0 - 273.15;
for i = 1:N
    if givenT, Tk = Tcell_C(i); end
    if nT == 1
        j = 1; j2 = 1; w = 0;
    else
        Tq = min(max(Tk, Tg(1)), Tg(end));
        j = find(Tg <= Tq, 1, 'last'); j = min(j, nT-1); j2 = j + 1;
        w = (Tq - Tg(j))/(Tg(j2) - Tg(j));
    end
    v0 = X{1}(i,j) + w*(X{1}(i,j2) - X{1}(i,j));
    r0 = X{2}(i,j) + w*(X{2}(i,j2) - X{2}(i,j));
    V(i) = v0 + I(i)*r0 + sum(U); v0s(i) = v0; T(i) = Tk;
    q = I(i)^2*r0;
    for m = 1:nRC
        A = X{2+m};     rk = A(i,j) + w*(A(i,j2) - A(i,j));
        A = X{2+nRC+m}; tk = A(i,j) + w*(A(i,j2) - A(i,j));
        q = q + U(m)^2/max(rk, 1e-9);
        a = exp(-dt(i)/tk);
        U(m) = U(m)*a + (1-a)*I(i)*rk;
    end
    Q(i) = q;
    if ~givenT && i < N
        Tinf = Tamb_C(i) + q/P.hA;
        Tk = Tinf + (Tk - Tinf)*exp(-P.hA*dt(i)/P.thermal_mass);
    end
end
out = struct('t',t(iD), 'V',V(iD), 'soc',soc(iD), 'T_C',T(iD), 'Q',Q(iD), 'V0',v0s(iD));
end
