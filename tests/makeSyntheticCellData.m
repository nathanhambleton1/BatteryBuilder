function [files, truth] = makeSyntheticCellData(outDir, tempsC, profile)
%MAKESYNTHETICCELLDATA  Cycler-style CSVs from a KNOWN cell, for testing BatteryDataBuilder.
%
%   [files, truth] = makeSyntheticCellData(outDir)            % 0, 25, 45 °C
%   [files, truth] = makeSyntheticCellData(outDir, [10 25])
%   [files, truth] = makeSyntheticCellData(outDir, 25, 'rate')
%
%   profile 'hppc' (default) - see below.
%   profile 'rate'           - the real test this tool is used on: a rate test
%       rest -> 0.34C CC-CV -> rest -> 0.1C discharge to Vmin -> rest
%            -> 0.34C CC-CV -> rest -> 0.2C  -> rest -> 0.34C CC-CV -> rest
%            -> 0.51C -> rest -> 0.34C CC-CV -> rest -> 1C -> rest
%            -> 0.34C CC-CV -> rest -> 5.8C -> rest      (2 h rests, ~60 h)
%       Files are called synthRate_<T>C.csv. No pulses at mid SOC.
%
%   The "true" cell is a 2-RC equivalent circuit with SOC- and temperature-
%   dependent OCV / R0 / R1 / R2, a lumped thermal mass and convection to the
%   chamber - i.e. exactly the structure of the Simscape Battery (Table-Based)
%   block. Each file runs the kind of test the extraction expects:
%     rest -> CC-CV charge -> rest -> C/5 discharge to Vmin -> rest -> CC-CV
%     -> HPPC (10 % SOC steps, 1 h rests, 10 s pulses) -> CC-CV
%     -> 1 h random dynamic load -> rest
%   Columns match the real exports:
%     Record# Step TestTime (s) StepTime (s) Capacity (Ah) Energy (Wh)
%     Current (A) Voltage (V) State ES DateTime Temp 1 Chamber Temperature (C)
%   (current is logged as a positive magnitude, State gives C / D / R).

if nargin < 2 || isempty(tempsC), tempsC = [0 25 45]; end
if nargin < 3, profile = 'hppc'; end
if ~isfolder(outDir), mkdir(outDir); end
rng(1);

truth = cellTruth(lower(profile));
files = cell(1, numel(tempsC));
for k = 1:numel(tempsC)
    if strcmpi(profile, 'rate')
        files{k} = fullfile(outDir, sprintf('synthRate_%gC.csv', tempsC(k)));
    else
        files{k} = fullfile(outDir, sprintf('synthCell_%gC.csv', tempsC(k)));
    end
    simulateTest(files{k}, tempsC(k), truth, lower(profile));
end
end

% -----------------------------------------------------------------------
function c = cellTruth(profile)
% 'rate': a power cell (resistances x0.4) that can actually take the 5.8C step
kR = 1; if strcmp(profile, 'rate'), kR = 0.4; end
c.Q    = 3.0;                       % Ah
c.Vmax = 4.2; c.Vmin = 2.75;
c.mcp  = 45;                        % J/K
c.hA   = 0.08;                      % W/K
c.ocv  = @(s,T) 3.25 + 0.55*s + 0.40*s.^2 - 0.55*exp(-max(s,0)/0.035) + 0.0004*(T-25).*(s-0.5);
arr    = @(T) exp(2200*(1./(T+273.15) - 1/298.15));
c.arr  = arr;
c.R0   = @(s,T) kR*0.020*arr(T).*(1 + 0.4*exp(-max(s,0)/0.10));
c.R1   = @(s,T) kR*0.010*arr(T).*(1 + 0.5*exp(-max(s,0)/0.10));
c.R2   = @(s,T) kR*0.012*arr(T).*(1 + 0.3*exp(-max(s,0)/0.15));
c.tau1 = @(s,T) 12 + 0*s;
c.tau2 = @(s,T) 350 + 0*s;
end

% -----------------------------------------------------------------------
function simulateTest(file, Tch, c, profile)
Cr = c.Q;                            % 1C in A
s0 = 0.5;                            % true SOC at the start of the file
% ---- the schedule: {type, args...}
if strcmp(profile, 'rate')
    s0 = 0.03;                       % the real test starts nearly empty (~3.1 V)
    sched = {{'rest', 1800}};
    for r = [0.1 0.2 0.51 1 5.8]
        sched = [sched; {{'cccv', 0.34*Cr, c.Q/20}; {'rest', 7200}; ...
                         {'cc', r*Cr, inf}; {'rest', 7200}}]; %#ok<AGROW>
    end
else
sched = {
    {'rest', 1800}
    {'cccv', 0.5*Cr, c.Q/20}
    {'rest', 3600}
    {'cc',   0.2*Cr, inf}            % discharge to Vmin
    {'rest', 3600}
    {'cccv', 0.5*Cr, c.Q/20}
    {'rest', 3600}
    {'hppc'}
    {'rest', 3600}
    {'cccv', 0.5*Cr, c.Q/20}
    {'rest', 1800}
    {'dyn',  3600}
    {'rest', 1800}};
end

% ---- state
s = s0; x1 = 0; x2 = 0; T = Tch; t = 0;
dt = 1;
rows = zeros(400000, 11); % t step stepTime I(+dis) V Tcell Ah Wh state(1C 2D 3R) trueSOC
nr = 0;
step = 0;

    function V = term(I)
        V = c.ocv(s,T) - I*c.R0(s,T) - c.R1(s,T)*x1 - c.R2(s,T)*x2;
    end
    function advance(I)
        a1 = exp(-dt/c.tau1(s,T)); a2 = exp(-dt/c.tau2(s,T));
        q = I^2*c.R0(s,T) + c.R1(s,T)*x1^2 + c.R2(s,T)*x2^2;
        x1 = a1*x1 + (1-a1)*I;
        x2 = a2*x2 + (1-a2)*I;
        s  = s - I*dt/3600/c.Q;
        T  = T + dt/c.mcp*(q - c.hA*(T - Tch));
        t  = t + dt;
    end
    function stepStart()
        step = step + 1; st0 = t; ah = 0; wh = 0;
    end
    function logRow(I, V, code)
        nr = nr + 1;
        rows(nr,:) = [t, step, t - st0, I, V, T, ah, wh, code, s, I^2*c.R0(s,T) + c.R1(s,T)*x1^2 + c.R2(s,T)*x2^2];
    end
    function ok = runCC(I, dur, vStop)    % constant current (+ = discharge)
        stepStart(); n = 0; ok = true;
        code = 2; if I < 0, code = 1; end
        while n < dur
            V = term(I);
            if (I > 0 && V <= vStop) || (I < 0 && V >= vStop), ok = false; break; end
            logRow(I, V, code);
            ah = ah + abs(I)*dt/3600; wh = wh + abs(I)*V*dt/3600;
            advance(I); n = n + dt;
        end
    end
    function runRest(dur)
        stepStart(); n = 0;
        while n < dur
            if n < 60 || mod(n, 10) == 0, logRow(0, term(0), 3); end
            advance(0); n = n + dt;
        end
    end
    function runCCCV(Ichg, Icut)
        runCC(-Ichg, inf, c.Vmax);                  % CC until Vmax
        stepStart();                                % CV step
        while true
            I = (c.ocv(s,T) - c.Vmax - c.R1(s,T)*x1 - c.R2(s,T)*x2)/c.R0(s,T);
            I = min(max(I, -Ichg), 0);
            if abs(I) < Icut, break; end
            logRow(I, term(I), 1);
            ah = ah + abs(I)*dt/3600; wh = wh + abs(I)*c.Vmax*dt/3600;
            advance(I);
        end
    end

st0 = 0; ah = 0; wh = 0;
for k = 1:numel(sched)
    a = sched{k};
    switch a{1}
        case 'rest', runRest(a{2});
        case 'cccv', runCCCV(a{2}, a{3});
        case 'cc',   runCC(a{2}, a{3}, c.Vmin);
        case 'hppc'
            while true
                runCC(1.0*Cr, 10, c.Vmin - 0.3);   % 1C discharge pulse
                runRest(40);
                runCC(-0.75*Cr, 10, c.Vmax + 0.1);% 0.75C charge pulse
                runRest(600);
                if ~runCC(0.5*Cr, 720, c.Vmin), break; end  % 10 % SOC step
                runRest(3600);
            end
        case 'dyn'
            stepStart(); n = 0;
            while n < a{2}
                I = (rand*1.5 - 0.5)*Cr;           % -0.5C .. +1C, new level every 20 s
                for j = 1:20
                    V = term(I);
                    if V < c.Vmin + 0.05 || V > c.Vmax - 0.02, I = 0; V = term(0); end
                    code = 3; if I > 0, code = 2; elseif I < 0, code = 1; end
                    logRow(I, V, code);
                    advance(I); n = n + dt;
                end
            end
    end
end

% ---- write the CSV like a cycler export
rows = rows(1:nr,:);
n = nr;
Vnoise = 0.0005*randn(n,1);
Tnoise = 0.03*randn(n,1);
stateChar = 'CDR';
dtm = datetime(2026,1,5,8,0,0) + seconds(rows(:,1));
tbl = table((1:n)', rows(:,2), rows(:,1), rows(:,3), rows(:,7), rows(:,8), ...
    abs(rows(:,4)) + 0.0002*randn(n,1).*(rows(:,4)~=0), round(rows(:,5) + Vnoise, 4), ...
    string(stateChar(rows(:,9))'), zeros(n,1), string(dtm, 'MM/dd/yyyy HH:mm:ss'), ...
    round(rows(:,6) + Tnoise, 2), round(Tch + 0.05*randn(n,1), 2), ...
    'VariableNames', {'Record#','Step','TestTime (s)','StepTime (s)','Capacity (Ah)', ...
    'Energy (Wh)','Current (A)','Voltage (V)','State','ES','DateTime','Temp 1', ...
    'Chamber Temperature (C)'});
writetable(tbl, file);
trueSOC = rows(:,10); trueHeat = rows(:,11); %#ok<NASGU>  % sidecar for the validation script only
save(regexprep(file, '\.csv$', '_truth.mat'), 'trueSOC', 'trueHeat');
end
