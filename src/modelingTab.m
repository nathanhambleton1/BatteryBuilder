function api = modelingTab(tab, fig, onDataChanged)
%MODELINGTAB  "Modeling" tab: fill in the Battery (Table-Based) parameters.
%
%   api = modelingTab(tab, fig, onDataChanged)
%     onDataChanged(d)  called after an extraction with the dataset that now
%                       has a 'SOC (-)' column (so the Plot tab can show it)
%
%   Walk-through:
%     1. "Extract data from test"  - calculates everything the test supports
%        and fills those boxes (green). Boxes it cannot fill stay empty and
%        say whether a datasheet value is required or optional.
%     2. Type any missing values into the empty boxes.
%     3. "Save to workspace"       - writes every filled box as a batt_*
%        variable. Hover over a box to see its variable and where it goes in
%        the block. "How?" opens the calculation behind a green box.

rows = blockParameterList();
nRows = numel(rows);
d = [];
R = [];
vals = struct(); src = struct();          % src: '' | 'calc' | 'user'
for k = 1:nRows, vals.(rows(k).key) = []; src.(rows(k).key) = ''; end
vals.SOC_vec = [0 0.02 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.95 1];
src.SOC_vec = 'user';

C_GREEN = [0.10 0.50 0.20]; C_ORANGE = [0.80 0.40 0.00];
C_GREY = [0.45 0.45 0.45];  C_BLUE = [0.10 0.35 0.75];

% ---------------- layout -------------------------------------------------------
g = uigridlayout(tab,[2 2],'RowHeight',{40,'1x'},'ColumnWidth',{'1x',400}, ...
    'Padding',[6 6 6 6],'RowSpacing',6);
gTop = uigridlayout(g,[1 3],'ColumnWidth',{230,190,'1x'},'Padding',[0 0 0 0]);
gTop.Layout.Row = 1; gTop.Layout.Column = [1 2];
btnExtract = uibutton(gTop,'Text','1.  Extract data from test','FontSize',14,'FontWeight','bold', ...
    'BackgroundColor',[0.20 0.45 0.80],'FontColor','white','Enable','off', ...
    'ButtonPushedFcn',@(~,~) onExtract(), ...
    'Tooltip','Calculate every parameter the loaded test file supports and fill in those boxes.');
btnSave = uibutton(gTop,'Text','2.  Save to workspace','FontSize',14,'FontWeight','bold', ...
    'BackgroundColor',[0.15 0.55 0.30],'FontColor','white', ...
    'ButtonPushedFcn',@(~,~) onSave(), ...
    'Tooltip','Write every filled box to the MATLAB base workspace as batt_* variables.');
lblStatus = uilabel(gTop,'Text','Open a CSV file, then press Extract.','FontColor',[0.3 0.3 0.35], ...
    'WordWrap','on');

pnl = uipanel(g,'Title','Battery (Table-Based) parameters  -  hover over any box for details', ...
    'FontWeight','bold','BackgroundColor','white');
pnl.Layout.Row = 2; pnl.Layout.Column = 1;

% one grid row per group heading / parameter / option line
groups = unique({rows.group}, 'stable');
nGridRows = 3 + numel(groups) + nRows;
gl = uigridlayout(pnl,[nGridRows 5],'ColumnWidth',{190,'1x',38,105,48}, ...
    'RowHeight',repmat({26}, 1, nGridRows),'Padding',[8 8 8 8],'RowSpacing',3, ...
    'ColumnSpacing',6,'Scrollable','on','BackgroundColor','white');

r = 1;
header('Block options (set these in the block dialog)', r); r = r+1;
l = uilabel(gl,'Text','Charge dynamics (RC pairs)');
l.Layout.Row = r; l.Layout.Column = 1;
tipRC = sprintf(['Battery (Table-Based) block > Main > Charge dynamics\n' ...
    '1 = "One time-constant dynamics", 2 = "Two ...", 3 = "Three ..."\n' ...
    'Saved as batt_nRC. Changing it needs a new Extract.']);
l.Tooltip = tipRC;
ddRC = uidropdown(gl,'Items',{'1','2','3'},'Value','2','Tooltip',tipRC, ...
    'ValueChangedFcn',@(~,~) refreshRows());
ddRC.Layout.Row = r; ddRC.Layout.Column = 2;
r = r+1;
optText = ['Tabulate parameters over temperature = No  |  Current directionality = No  |  Thermal port = Model  |  ' ...
           'Expose SOC port = Yes  |  Self-discharge = Disabled (Enabled only if Rleak is filled)  |  ' ...
           'Fade / calendar aging = Disabled  |  Extrapolation = Nearest'];
lOpt = uilabel(gl,'Text',optText,'WordWrap','on','FontColor',[0.3 0.3 0.35],'FontSize',11, ...
    'Tooltip',sprintf('These block options match the parameters listed below.\nSet them once in the Battery (Table-Based) block dialog.'));
lOpt.Layout.Row = r; lOpt.Layout.Column = [1 5];
gl.RowHeight{r} = 60;
r = r+1;

ui = struct('lab',{},'edit',{},'unit',{},'status',{},'how',{});
for gi = 1:numel(groups)
    header(groups{gi}, r); r = r+1;
    for k = find(strcmp({rows.group}, groups{gi}))
        p = rows(k);
        tip = sprintf('Workspace variable: %s\nWhere: %s\nUnit: %s\n\nIf not in the data: %s', ...
            p.var, p.where, p.unit, p.hint);
        u.lab = uilabel(gl,'Text',p.label,'Tooltip',tip);
        u.lab.Layout.Row = r; u.lab.Layout.Column = 1;
        u.edit = uieditfield(gl,'text','Tooltip',tip,'Placeholder','—', ...
            'ValueChangedFcn',@(s,~) onEdit(k, s));
        u.edit.Layout.Row = r; u.edit.Layout.Column = 2;
        u.unit = uilabel(gl,'Text',p.unit,'FontColor',C_GREY,'Tooltip',tip);
        u.unit.Layout.Row = r; u.unit.Layout.Column = 3;
        u.status = uilabel(gl,'Text','','FontSize',11);
        u.status.Layout.Row = r; u.status.Layout.Column = 4;
        u.how = uibutton(gl,'Text','How?','Enable','off','FontSize',11, ...
            'Tooltip','Show how this value was calculated from the test data', ...
            'ButtonPushedFcn',@(~,~) onHow(k));
        u.how.Layout.Row = r; u.how.Layout.Column = 5;
        ui(k) = u;
        r = r+1;
    end
end

gR = uigridlayout(g,[2 1],'RowHeight',{'1x','1x'},'Padding',[0 0 0 0]);
gR.Layout.Row = 2; gR.Layout.Column = 2;
axTest = uiaxes(gR); styleAxes(axTest); title(axTest,'Test overview');
axTab = uiaxes(gR); styleAxes(axTab); title(axTab,'Extracted tables');
refreshRows();

api.setData = @setData;
api.extract = @onExtract;
api.save = @onSave;
api.setValue = @setValue;
api.setRC = @(n) setRC(n);
api.explain = @(key) onHow(find(strcmp({rows.key}, key), 1));
api.getState = @getState;

    function st = getState()     % nested (not anonymous) so it sees the live values
        st = struct('vals',vals,'src',src,'R',R);
    end

% =========================================================================
    function setData(newD)
        if ~isempty(d) && strcmp(d.file, newD.file) && ~isempty(newD.soc)
            d = newD; return                 % our own SOC update coming back
        end
        d = newD;
        R = [];
        for k = 1:nRows                      % forget the old file's results
            if strcmp(src.(rows(k).key), 'calc'), vals.(rows(k).key) = []; src.(rows(k).key) = ''; end
        end
        btnExtract.Enable = 'on';
        lblStatus.Text = sprintf('%s loaded. Press "Extract data from test".', d.name);
        refreshRows();
        drawOverview();
        notifyCapacity();                    % a typed AH still applies to the new file
    end

    function onExtract()
        if isempty(d), return; end
        sv = vals.SOC_vec;
        if isempty(sv)
            uialert(fig,'Fill in the SOC breakpoints first (e.g. [0 0.1 0.2 ... 1]).','SOC breakpoints');
            return
        end
        userAH = NaN;
        if strcmp(src.AH,'user') && ~isempty(vals.AH), userAH = vals.AH; end
        dlg = uiprogressdlg(fig,'Title','Extracting','Indeterminate','on', ...
            'Message','Finding capacity, SOC, OCV, R0, RC pairs and thermal values...');
        try
            R = extractCellParameters(d, str2double(ddRC.Value), sv, userAH);
        catch ME
            delete(dlg);
            uialert(fig, sprintf('%s\n\n(%s, line %d)', ME.message, ME.stack(1).name, ME.stack(1).line), ...
                'Extraction failed');
            return
        end
        delete(dlg);
        for k = 1:nRows
            key = rows(k).key;
            if strcmp(key, 'SOC_vec'), continue; end     % the user's choice, not a result
            if isfield(R.found, key) && R.found.(key)
                vals.(key) = R.value.(key); src.(key) = 'calc';
            elseif strcmp(src.(key), 'calc')
                vals.(key) = []; src.(key) = '';       % old result no longer valid
            end
        end
        d = R.d;
        refreshRows();
        drawOverview();
        nCalc = sum(cellfun(@(k) strcmp(src.(k),'calc'), {rows.key}));
        lblStatus.Text = sprintf(['%d boxes calculated from %s. Fill in any empty REQUIRED boxes ' ...
            'from the datasheet, then Save.'], nCalc, d.name);
        if ~isempty(onDataChanged), onDataChanged(d, 'soc'); end
        notifyCapacity();
    end

    function notifyCapacity()
        % tell the main window the capacity (calculated or typed) for the
        % Load profile tab's C-rate labels
        if isempty(onDataChanged) || isempty(d), return; end
        ah = vals.AH;
        if ~(isnumeric(ah) && isscalar(ah) && isfinite(ah) && ah > 0), ah = NaN; end
        onDataChanged(ah, 'capacity');
    end

    function onEdit(k, s)
        key = rows(k).key;
        str = strtrim(s.Value);
        if isempty(str)
            vals.(key) = []; src.(key) = '';
        else
            v = str2num(str); %#ok<ST2NM>  accepts "[1 2 3]", "0:0.1:1", "3.0"
            if isempty(v) || ~isnumeric(v) || any(~isfinite(v(:)))
                uialert(fig, sprintf('"%s" is not a number or vector.', str), rows(k).label);
                s.Value = fmtVal(vals.(key));
                return
            end
            v = double(v);
            if isvector(v), v = v(:)'; end           % vectors as rows; matrices (SOC x T) kept
            vals.(key) = v; src.(key) = 'user';
        end
        refreshRows();
        if strcmp(key, 'AH'), notifyCapacity(); end
    end

    function setValue(key, v)        % scripting / test helper
        vals.(key) = v; src.(key) = 'user';
        if isempty(v), src.(key) = ''; end
        refreshRows();
        if strcmp(key, 'AH'), notifyCapacity(); end
    end

    function setRC(n)
        ddRC.Value = num2str(n); refreshRows();
    end

    function refreshRows()
        nRC = str2double(ddRC.Value);
        if numel(vals.T_vec) > 1, tabT = 'Yes'; else, tabT = 'No'; end
        lOpt.Text = regexprep(lOpt.Text, 'over temperature = \w+', ['over temperature = ' tabT]);
        for k = 1:nRows
            p = rows(k); u = ui(k); key = p.key;
            u.edit.Value = fmtVal(vals.(key));
            unused = p.rc > nRC;
            u.edit.Enable = onOff(~unused);
            u.how.Enable = onOff(strcmp(src.(key),'calc') && ~isempty(R) && ~unused);
            note = '';
            if ~isempty(R) && isfield(R.note, key), note = R.note.(key); end
            % short text in the box, the full story in the tooltip
            if unused
                txt = 'Not used'; col = C_GREY;
                why = sprintf('Not used: Charge dynamics is set to %d RC pair(s).', nRC);
            elseif strcmp(src.(key),'calc')
                txt = char([10003 ' From data']); col = C_GREEN;
                why = 'Calculated from the test data. Press "How?" to see how.';
                if contains(note, 'CHECK')          % a cross-check disagreed
                    txt = char([9888 ' Check']); col = C_ORANGE;
                    why = 'Calculated from the test data, but a cross-check disagreed. Press "How?".';
                end
            elseif strcmp(src.(key),'user')
                txt = 'Entered by you'; col = C_BLUE;
                why = 'Typed in by you (e.g. from the datasheet).';
                if strcmp(key,'SOC_vec')
                    txt = 'Your choice'; why = 'Your choice of SOC points - edit before Extract if needed.';
                end
            elseif strcmp(p.need,'required')
                txt = 'Required'; col = C_ORANGE;
                why = 'REQUIRED by the block. Not found in the data - enter it from the datasheet.';
                if isempty(R), why = 'REQUIRED by the block. Press Extract first; enter it yourself if the data cannot give it.'; end
            else
                txt = 'Optional'; col = C_GREY;
                why = 'Optional. Leave empty if you do not have it.';
            end
            u.status.Text = txt;
            u.status.FontColor = col;
            stip = sprintf('%s\n\nDatasheet: %s', why, p.hint);
            if ~isempty(note), stip = sprintf('%s\n\nFrom the data: %s', stip, note); end
            u.status.Tooltip = stip;
        end
    end

    function h = onHow(k)
        h = [];
        if isempty(R) || isempty(k), return; end
        key = rows(k).key;
        if isempty(R.byT) || strcmp(key, 'T_vec')
            h = explainParameter(key, R, rows(k)); return
        end
        Rp = R.byT{R.iPrim};
        if ~rows(k).isVec || strcmp(key, 'SOC_vec')
            h = explainParameter(key, Rp, rows(k)); return      % AH, thermal, ... : test temperature
        end
        % SOC tables: one window per temperature (each from its own data)
        for j = numel(R.byT):-1:1
            Rj = R.byT{j};
            if ~Rj.found.(key), continue; end
            rj = rows(k);
            rj.label = sprintf('%s  at %.3g °C', rj.label, R.T_C(j));
            h = explainParameter(key, Rj, rj);
        end
        if isfield(R,'copiedT') && isfield(R.copiedT, key) && any(R.copiedT.(key))
            j = find(R.copiedT.(key), 1);
            uialert(fig, sprintf(['At %.3g °C this table could not be measured from this file, so the ' ...
                '%.3g °C values are used there as well:\n\n%s'], R.T_C(j), R.T_C(3-j), R.note.(key)), ...
                sprintf('%s at %.3g °C', rows(k).label, R.T_C(j)), 'Icon','info');
        end
    end

    function onSave()
        nRC = str2double(ddRC.Value);
        nSoc = numel(vals.SOC_vec);
        nT = max(1, numel(vals.T_vec));
        saved = {}; missing = {}; problems = {};
        for k = 1:nRows
            p = rows(k); v = vals.(p.key);
            if p.rc > nRC, continue; end
            if isempty(v)
                if strcmp(p.need,'required'), missing{end+1} = sprintf('  %s  (%s)', p.label, p.var); end %#ok<AGROW>
                continue
            end
            if p.isVec
                if isscalar(v), v = repmat(v, 1, nSoc); end          % one datasheet number -> every SOC
                if nT > 1 && isvector(v), v = repmat(v(:), 1, nT); end   % same values at every T
                if nT == 1 && ~isvector(v)
                    problems{end+1} = sprintf('  %s is a matrix but there is only one temperature', p.var); %#ok<AGROW>
                elseif size(v,2) ~= nT && nT > 1 || (isvector(v) && numel(v) ~= nSoc) || (~isvector(v) && size(v,1) ~= nSoc)
                    problems{end+1} = sprintf('  %s is %s but needs %d SOC x %d T', ...
                        p.var, mat2str(size(v)), nSoc, nT); %#ok<AGROW>
                end
            elseif strcmp(p.key,'Rleak') && nT > 1 && isscalar(v)
                v = repmat(v, 1, nT);                              % Rleak(T)
            end
            assignin('base', p.var, v);
            saved{end+1} = sprintf('  %-18s %s', p.var, sizeStr(v)); %#ok<AGROW>
        end
        assignin('base', 'batt_nRC', nRC);
        saved{end+1} = sprintf('  %-18s %d  (block: Charge dynamics)', 'batt_nRC', nRC);
        msg = [{'Saved to the base workspace:'}, saved];
        if nT > 1
            msg = [msg, {'', sprintf(['Two temperatures (%s K): set the block option "Tabulate parameters ' ...
                'over temperature" = Yes and Vector of temperatures T = batt_T_vec. The tables are %d SOC x %d T.'], ...
                mat2str(vals.T_vec, 5), nSoc, nT)}];
        end
        if ~isempty(missing)
            msg = [msg, {'', 'Still EMPTY (required for the block):'}, missing];
        end
        if ~isempty(problems)
            msg = [msg, {'', 'Check these (length mismatch - re-run Extract or fix the box):'}, problems];
        end
        icon = 'success';
        if ~isempty(missing) || ~isempty(problems), icon = 'warning'; end
        uialert(fig, strjoin(msg, newline), 'Saved', 'Icon', icon);
        lblStatus.Text = sprintf('%d variables saved to the workspace.', numel(saved));
    end

% =========================================================================
%  Overview plots
% =========================================================================
    function drawOverview()
        delete(axTest); delete(axTab);
        axTest = uiaxes(gR); axTest.Layout.Row = 1; styleAxes(axTest);
        axTab = uiaxes(gR); axTab.Layout.Row = 2; styleAxes(axTab);
        if isempty(d), return; end
        th = d.t/3600;
        yyaxis(axTest,'right');
        plot(axTest, th, d.I, '-', 'Color',[0.75 0.75 0.75]);
        ylabel(axTest,'Current (A, + = charge)');
        axTest.YAxis(2).Color = [0.5 0.5 0.5];
        yyaxis(axTest,'left');
        hs = plot(axTest, th, d.V, '-', 'Color',[0.15 0.15 0.15]); lg = {'voltage'};
        ylabel(axTest,'Voltage (V)'); xlabel(axTest,'Test time (h)');
        axTest.YAxis(1).Color = [0.15 0.15 0.15];
        if ~isempty(R)
            hold(axTest,'on');
            c = R.diag.capacity;
            if ~isempty(c.fullIdx)
                hs(end+1) = plot(axTest, th(c.fullIdx), d.V(c.fullIdx), '^', 'MarkerFaceColor',C_GREEN, ...
                    'MarkerEdgeColor','none','MarkerSize',8); lg{end+1} = 'full (end of CC-CV)';
            end
            if ~isempty(c.emptyIdx)
                hs(end+1) = plot(axTest, th(c.emptyIdx), d.V(c.emptyIdx), 'v', 'MarkerFaceColor',[0.85 0.2 0.1], ...
                    'MarkerEdgeColor','none','MarkerSize',8); lg{end+1} = 'empty (cut-off)';
            end
            if ~isempty(R.diag.fits)
                t0 = [R.diag.fits.t0];
                [~, i0] = min(abs(d.t(:) - t0), [], 1);
                hs(end+1) = plot(axTest, th(i0), d.V(i0), 'o', 'Color',[0 0.45 0.74], ...
                    'MarkerSize',7,'LineWidth',1.3); lg{end+1} = 'rest used for RC/OCV fit';
            end
            if ~isempty(R.diag.edgeIdx)
                k = R.diag.edgeIdx;
                hs(end+1) = plot(axTest, th(k), d.V(k), '.', 'Color',[0.85 0.33 0.1], ...
                    'MarkerSize',6); lg{end+1} = 'current step used for R0';
            end
            hold(axTest,'off');
        end
        legend(axTest, hs, lg, 'Location','best');
        title(axTest, sprintf('Test overview: %s', d.name), 'Interpreter','none');
        axTest.XLim = [0 max(th(end), 1e-6)];
        axTest.YAxis(1).Limits = [min(d.V) max(d.V)] + [-0.05 0.05]*max(max(d.V) - min(d.V), 0.01);
        iMax = max(max(abs(d.I)), 1e-3);
        axTest.YAxis(2).Limits = [-1.3 1.3]*iMax;

        if isempty(R), title(axTab,'Press "Extract data from test"'); return; end
        sg = R.value.SOC_vec;
        lg = {}; hs = [];
        % limits are set explicitly: uiaxes + yyaxis can keep stale automatic limits
        yyaxis(axTab,'left');
        % one line per temperature column: solid = lowest T, dashed = next
        sty = {'-','--',':'};
        Tl = R.T_C; nTc = numel(Tl);
        tSuf = @(j) '';
        if nTc > 1, tSuf = @(j) sprintf(' %.3g°C', Tl(j)); end
        if R.found.V0_vec
            v = R.value.V0_vec; if isvector(v), v = v(:); end
            for j = 1:size(v,2)
                if nTc > 1 && isfield(R,'copiedT') && R.copiedT.V0_vec(j), continue; end
                hs(end+1) = plot(axTab, sg, v(:,j), [sty{min(j,3)} 'o'], 'Color',[0 0.45 0.74], ...
                    'LineWidth',1.5); lg{end+1} = ['OCV V0' tSuf(j)]; %#ok<AGROW>
            end
            axTab.YAxis(1).Limits = [min(v(:)) max(v(:))] + [-0.05 0.05]*max(max(v(:)) - min(v(:)), 0.01);
        end
        ylabel(axTab,'OCV (V)');
        yyaxis(axTab,'right'); hold(axTab,'on');
        cols = [0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56; 0.93 0.69 0.13];
        allR = [];
        for q = 0:R.nRC
            if q == 0, key = 'R0_vec'; else, key = sprintf('R%d_vec', q); end
            if R.found.(key)
                y = 1000*R.value.(key); if isvector(y), y = y(:); end
                for j = 1:size(y,2)
                    hs(end+1) = plot(axTab, sg, y(:,j), [sty{min(j,3)} 's'], 'Color',cols(q+1,:), ...
                        'LineWidth',1.2, 'MarkerSize',4); %#ok<AGROW>
                    lg{end+1} = [strrep(key,'_vec','') tSuf(j)]; %#ok<AGROW>
                end
                allR = [allR; y(:)]; %#ok<AGROW>
            end
        end
        hold(axTab,'off');
        if ~isempty(allR)
            axTab.YAxis(2).Limits = [0, 1.1*max(allR)];
        end
        axTab.XLim = [min(sg) max(sg)];
        ylabel(axTab,'Resistance (mOhm)'); xlabel(axTab,'SOC (-)');
        if ~isempty(hs), legend(axTab, hs, lg, 'Location','best'); end
        title(axTab,'Extracted tables vs SOC (click "How?" for details)');
    end

    function header(txt, row)
        h = uilabel(gl,'Text',txt,'FontWeight','bold','FontSize',13, ...
            'BackgroundColor',[0.92 0.94 0.97]);
        h.Layout.Row = row; h.Layout.Column = [1 5];
    end
end

% =========================================================================
function s = fmtVal(v)
% vectors as [a b c]; SOC x T matrices as [a1 a2; b1 b2; ...] (one row per SOC)
if isempty(v), s = ''; return; end
if isscalar(v), s = sprintf('%.5g', v); return; end
if isvector(v), v = v(:)'; end
rowsTxt = cell(1, size(v,1));
for i = 1:size(v,1)
    rowsTxt{i} = strjoin(arrayfun(@(x) sprintf('%.5g', x), v(i,:), 'UniformOutput', false), ' ');
end
s = ['[' strjoin(rowsTxt, '; ') ']'];
end

function s = sizeStr(v)
if isscalar(v), s = sprintf('%.6g', v);
elseif isvector(v), s = sprintf('1x%d vector', numel(v));
else, s = sprintf('%dx%d matrix (SOC x T)', size(v,1), size(v,2));
end
end

function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

function styleAxes(a)
a.FontName = 'Segoe UI'; a.FontSize = 11; a.Box = 'on';
grid(a,'on'); a.GridAlpha = 0.12;
a.Title.FontWeight = 'bold';
end
