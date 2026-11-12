function [tr, Ir, iData] = refineTimeGrid(t, I, AH, maxDsoc)
%REFINETIMEGRID  Extra time points inside long sample intervals.
%
%   [tr, Ir, iData] = refineTimeGrid(t, I, AH)
%
%   The cycler logs every 30-60 s during a slow discharge, and the SOC can
%   move 2 % between two samples at 1C. The tables change with SOC, so the
%   MATLAB copy of the model (and the fit) splits every interval into equal
%   pieces of at most maxDsoc (default 0.002 = 0.2 % SOC). The current is the
%   same in every piece (it holds from one sample to the next), so the input
%   is exactly the test's; only the SOC lookups get finer, like Simulink's
%   continuous solver. tr(iData) == t.

if nargin < 4, maxDsoc = 0.002; end
t = t(:); I = I(:); N = numel(t);
dt = diff(t);
ds = abs(I(1:end-1)) .* dt / 3600 / AH;
n = max(1, ceil(ds / maxDsoc));                % pieces per interval
iData = [1; 1 + cumsum(n)];
tr = zeros(iData(end), 1); Ir = tr;
tr(iData) = t; Ir(iData) = I;
for k = find(n > 1)'
    j = iData(k) + (1:n(k)-1);
    tr(j) = t(k) + (1:n(k)-1)'/n(k)*dt(k);
    Ir(j) = I(k);
end
if N == 1, iData = 1; end
end
