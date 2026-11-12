function names = twinWorkspace(tw, R)
%TWINWORKSPACE  Puts every variable BatteryTwin.slx needs in the base workspace.
%
%   twinWorkspace(tw, R)   tw = fitDigitalTwin result, R = extractCellParameters result
%
%   twin_load      [t I]  measured current, + = charge (From Workspace, Interpolate off)
%   twin_ambient   [t K]  chamber temperature
%   twin_stopTime  s
%   ec_*           the digital twin's tables (Battery Equivalent Circuit)
%   batt_*         the Modeling tab's tables (Battery (Table-Based)), exactly what
%                  the tab's "2. Save to workspace" writes

S.twin_load = tw.load;
S.twin_ambient = tw.ambient;
S.twin_stopTime = tw.stopTime;

nS = numel(tw.SOC_vec); nI = numel(tw.I_vec);
S.ec_AH = tw.AH;
S.ec_SOC_vec = tw.SOC_vec(:)';
S.ec_V0 = tw.V0(:)';
S.ec_I_vec = tw.I_vec(:)';
for k = 0:tw.nRC
    S.(sprintf('ec_R%d',k)) = tw.(sprintf('R%d',k));
end
for k = 1:tw.nRC
    S.(sprintf('ec_tau%d',k)) = tw.(sprintf('tau%d',k))*ones(nS, nI);
end
S.ec_SOC0 = min(max(tw.SOC0, 0), 1);
S.ec_T0 = tw.T0;
S.ec_mcp = tw.thermal_mass;
S.ec_hA = tw.hA;

% Modeling tab values, as "2. Save to workspace" writes them. BatteryTwin.slx
% has one fixed set-up (3 RC pairs, tabulated over temperature), so a file
% with one temperature gets a copy of its tables 2 K away, and missing RC
% pairs get an empty one (R ~ 0, tau 1 s) - neither changes the result.
v = R.value;
TK = v.T_vec;
if numel(TK) < 2, TK = v.T0 + [-1 1]; if isempty(TK), TK = 298.15 + [-1 1]; end, end
nT = numel(TK);
col = @(x) [x(:,1:min(end,nT)), repmat(x(:,1), 1, nT - size(x,2))];   % one column -> every T
S.batt_SOC_vec = v.SOC_vec;
S.batt_T_vec = TK(:)';
S.batt_V0_vec = col(v.V0_vec); S.batt_R0_vec = col(v.R0_vec);
for k = 1:3
    if k <= R.nRC && ~isempty(v.(sprintf('R%d_vec',k)))
        S.(sprintf('batt_R%d_vec',k)) = col(v.(sprintf('R%d_vec',k)));
        S.(sprintf('batt_tau%d_vec',k)) = col(v.(sprintf('tau%d_vec',k)));
    else
        S.(sprintf('batt_R%d_vec',k)) = 1e-6*ones(numel(v.SOC_vec), nT);
        S.(sprintf('batt_tau%d_vec',k)) = ones(numel(v.SOC_vec), nT);
    end
end
S.batt_AH = v.AH;
S.batt_thermal_mass = v.thermal_mass; S.batt_hA = v.hA;
if isempty(v.thermal_mass), S.batt_thermal_mass = tw.thermal_mass; end   % no temperature data
if isempty(v.hA), S.batt_hA = tw.hA; end
S.batt_SOC0 = min(max(tw.SOC0, 0), 1);
S.batt_T0 = tw.T0;
S.batt_nRC = R.nRC;

names = fieldnames(S);
for k = 1:numel(names)
    assignin('base', names{k}, S.(names{k}));
end
end
