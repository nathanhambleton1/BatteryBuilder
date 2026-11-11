function d = loadBatteryCsv(file)
%LOADBATTERYCSV  Read one cycler CSV into a simple dataset struct.
%
%   d = loadBatteryCsv('cell_25C.csv')
%
%   Expected columns (names are matched loosely, order does not matter):
%     Record#  Step  TestTime (s)  StepTime (s)  Capacity (Ah)  Energy (Wh)
%     Current (A)  Voltage (V)  State  ES  DateTime  Temp 1  Chamber Temperature (C)
%
%   Output fields
%     d.name, d.file   file name / full path
%     d.t              test time (s), starts at the first sample
%     d.V              terminal voltage (V)
%     d.I              current (A), POSITIVE = CHARGE, NEGATIVE = DISCHARGE, 0 = rest
%     d.Iraw           current exactly as it is in the file
%     d.stepTime       StepTime column (s) or [] if not present
%     d.Tcell, d.Tch   cell / chamber temperature (°C), NaN if not present
%     d.capFile        the file's own "Capacity (Ah)" column, [] if not present
%                      (only used to cross-check the capacity)
%     d.T_C            test temperature label (°C) = median chamber temperature
%                      during the discharges (the chamber is at 25 °C while charging)
%     d.T_chg_C        chamber temperature during the charges (°C), NaN if unknown
%     d.signNote       how the current sign was worked out
%     d.warn           cell array of warnings about the file
%     d.tbl            the whole file as a table + a few added plot columns
%     d.soc            [] here; filled in by extractCellParameters

if ~isfile(file), error('File not found: %s', file); end
io = detectImportOptions(file, 'VariableNamingRule','preserve');
% date/text columns are read as plain strings (avoids datetime-format warnings)
textVars = io.VariableNames(ismember(io.VariableTypes, {'char','datetime'}));
if ~isempty(textVars), io = setvaropts(io, textVars, 'Type','string'); end
T = readtable(file, io);
if height(T) < 3, error('File has fewer than 3 data rows.'); end

[~, n, e] = fileparts(file);
d.name = [n e];
d.file = file;
d.warn = {};

% ---- find the columns -------------------------------------------------------
names = T.Properties.VariableNames;
c.time     = findCol(names, {'testtimes','testtime','totaltime','runtime','time'}, {'step','date'});
c.stepTime = findCol(names, {'steptimes','steptime'}, {});
c.current  = findCol(names, {'currenta','current','amps','i'}, {});
c.voltage  = findCol(names, {'voltagev','voltage','volts','v'}, {});
c.state    = findCol(names, {'state','md','mode'}, {});
c.tcell    = findCol(names, {'temp1','celltemp','temperature1','auxtemp1','temp'}, {'chamber'});
c.tch      = findCol(names, {'chambertemperaturec','chambertemperature','chamber'}, {});
c.datetime = findCol(names, {'datetime','date'}, {});
c.capacity = findCol(names, {'capacityah','capacity'}, {'energy','charge','dis'});
if isempty(c.current) || isempty(c.voltage)
    error('Could not find Current and Voltage columns. Columns found: %s', strjoin(names, ', '));
end

% ---- time, voltage, current ----------------------------------------------------
if ~isempty(c.time)
    t = toSeconds(T.(c.time));
elseif ~isempty(c.datetime)
    dt = datetime(T.(c.datetime));
    t = seconds(dt - dt(1));
else
    error('Could not find a test-time column.');
end
V    = toNum(T.(c.voltage));
Iraw = toNum(T.(c.current));
good = isfinite(t) & isfinite(V) & isfinite(Iraw);
if any(~good)
    d.warn{end+1} = sprintf('%d rows with missing time/V/I dropped', nnz(~good));
end
T = T(good,:); t = t(good); V = V(good); Iraw = Iraw(good);
if any(diff(t) < 0)                       % cyclers occasionally repeat a stamp
    [t, ord] = sort(t); T = T(ord,:); V = V(ord); Iraw = Iraw(ord);
    d.warn{end+1} = 'time column was not in order - rows were sorted';
end
t = t - t(1);

state = '';
if ~isempty(c.state)
    s = upper(strtrim(string(T.(c.state))));
    s(ismissing(s)) = "";
    state = char(extractBefore(s + " ", 2));   % first letter: C / D / R / ...
end
d.t = t; d.V = V; d.Iraw = Iraw;
d.stepTime = [];
if ~isempty(c.stepTime), d.stepTime = toSeconds(T.(c.stepTime)); end
d.Tcell = nan(size(t)); d.Tch = nan(size(t));
if ~isempty(c.tcell), d.Tcell = toNum(T.(c.tcell)); end
if ~isempty(c.tch),   d.Tch   = toNum(T.(c.tch));   end
% names of the matched columns (the Plot tab pairs twin signals with these)
d.colNames = struct('voltage',c.voltage, 'current',c.current, 'tcell',c.tcell, 'tch',c.tch);
d.capFile = [];                           % cycler's own Ah column (cross-check only)
if ~isempty(c.capacity), d.capFile = toNum(T.(c.capacity)); end
d.dtMedian = median(diff(t));

% ---- test temperature label -------------------------------------------------------
if any(isfinite(d.Tch))
    d.T_C = round(median(d.Tch(isfinite(d.Tch)))*10)/10;
elseif any(isfinite(d.Tcell))
    d.T_C = round(median(d.Tcell(isfinite(d.Tcell)))*10)/10;
    d.warn{end+1} = 'no chamber column: test temperature taken from the cell sensor';
else
    tok = regexp(d.name, '(-?\d+(\.\d+)?)\s*(C|degC|°C)', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok), d.T_C = str2double(tok{1}); else, d.T_C = NaN; end
    d.warn{end+1} = 'no temperature columns in the file';
end

% ---- current sign: positive = CHARGE ------------------------------------------------
% Cyclers differ: some log signed current, some log magnitude + a State column.
thr = max(2e-3, 0.002*max(abs(Iraw)));    % |I| below this counts as rest
d.restThr = thr;
hasState = ~isempty(state) && any(state == 'C' | state == 'D');
if hasState
    isC = state(:) == 'C'; isD = state(:) == 'D';
    mC = median(Iraw(isC & abs(Iraw) > thr));
    mD = median(Iraw(isD & abs(Iraw) > thr));
    if any(Iraw < -thr) && (isnan(mC) || mC > 0) && (isnan(mD) || mD < 0)
        I = Iraw;  d.signNote = 'signed in file, charge already positive';
    elseif any(Iraw < -thr) && (isnan(mC) || mC < 0) && (isnan(mD) || mD > 0)
        I = -Iraw; d.signNote = 'signed in file, discharge was positive -> flipped';
    else
        I = abs(Iraw); I(isD) = -I(isD);
        d.signNote = 'magnitude in file, sign taken from the State column';
    end
    I(state(:) == 'R') = 0;
else
    % no State column: charging current must RAISE the voltage
    dv = gradient(V) ./ max(gradient(t), eps);
    m = abs(Iraw) > thr;
    if sum(Iraw(m) .* dv(m)) >= 0
        I = Iraw;  d.signNote = 'no State column, charge positive (checked with dV/dt)';
    else
        I = -Iraw; d.signNote = 'no State column, flipped so charge is positive (dV/dt)';
    end
end
I(abs(I) < thr) = 0;
d.I = I;

% ---- test temperature = the chamber temperature during the DISCHARGES -------------
% The chamber schedule of these tests: 25 °C while charging (and in the rest after
% each discharge), the file's own test temperature from the end of each charge
% through the rest and the discharge. The median over the whole file can then land
% on 25 °C for a 10 °C test, so the label is taken over the discharge samples.
d.T_all_C = d.T_C;
% chamber temperature during the CHARGES (25 °C in these tests): the second
% temperature the tables are built for when it differs from the discharge one
d.T_chg_C = NaN;
chg = I > 0 & isfinite(d.Tch);
if nnz(chg) > 10, d.T_chg_C = round(median(d.Tch(chg))*10)/10; end
dis = I < 0 & isfinite(d.Tch);
if nnz(dis) > 10
    d.T_C = round(median(d.Tch(dis))*10)/10;
    if any(isfinite(d.Tch)) && abs(max(d.Tch) - min(d.Tch)) > 3
        d.warn{end+1} = sprintf(['chamber changes between %.1f and %.1f °C: test temperature = %.1f °C ' ...
            '(chamber during the discharges); data with the cell more than 3 K away is left out'], ...
            min(d.Tch), max(d.Tch), d.T_C);
    end
end

% ---- extra columns for the Plot tab ---------------------------------------------------------
T.('Test Time (h)') = t/3600;
T.('Current, +charge (A)') = I;
T.('Power, +charge (W)') = I .* V;
% zero-order hold: a logged current applies until the next sample
T.('Net Ah in (Ah)') = [0; cumsum(I(1:end-1).*diff(t))]/3600;
d.tbl = T;
d.soc = [];
end

% =========================================================================
function name = findCol(names, patterns, exclude)
% loose header matching: ignores case, spaces and punctuation
key = lower(regexprep(names, '[^a-zA-Z0-9]', ''));
name = '';
for p = 1:numel(patterns)
    hit = strcmp(key, patterns{p});
    if ~any(hit) && numel(patterns{p}) > 1, hit = startsWith(key, patterns{p}); end
    if ~any(hit) && numel(patterns{p}) > 3, hit = contains(key, patterns{p}); end
    for e = 1:numel(exclude)
        hit = hit & ~contains(key, exclude{e});
    end
    j = find(hit, 1);
    if ~isempty(j), name = names{j}; return; end
end
end

function x = toNum(v)
if isnumeric(v) || islogical(v), x = double(v); return; end
if isduration(v), x = seconds(v); return; end
if isdatetime(v), x = seconds(v - v(1)); return; end
x = str2double(string(v));
end

function t = toSeconds(v)
% numeric seconds, durations, or strings such as "1d 02:03:04.5" / "02:03:04"
if isnumeric(v) || isduration(v) || isdatetime(v), t = toNum(v); return; end
s = string(v);
t = str2double(s);
bad = ~isfinite(t) & ~ismissing(s);
if any(bad)
    tok = regexp(s(bad), '^\s*(?:(\d+)\s*d\s*)?(\d+):(\d+):(\d+(?:\.\d*)?)\s*$', 'tokens', 'once');
    tt = nan(nnz(bad),1);
    for k = 1:numel(tok)
        if isempty(tok{k}), continue; end
        p = str2double(tok{k}); p(isnan(p)) = 0;
        tt(k) = p(1)*86400 + p(2)*3600 + p(3)*60 + p(4);
    end
    t(bad) = tt;
end
end
