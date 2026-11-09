function varargout = plotBatteryData(varargin)
%PLOTBATTERYDATA  Battery test viewer + Simscape "Battery (Table-Based)" parameteriser.
%
%   One self-contained MATLAB file that
%     1. views cycler CSV files (cursor read-out, fit buttons, drag-to-zoom),
%     2. extracts Table-Based battery parameters from the test data
%        (capacity, OCV(SOC,T), R0(SOC,T), Rk/tauk(SOC,T), thermal mass, h*A),
%     3. exports them as workspace variables / a .mat file / straight into a block,
%     4. exports the measured load (charge/discharge/rest) profile for a
%        Controlled Current Source, and
%     5. builds + runs a "digital twin" Simscape model and overlays it on the test.
%
%   GUI
%     plotBatteryData                       open the app
%     fig = plotBatteryData('gui', files)   open the app and pre-load CSV files
%                                           (fig.UserData.api holds a scripting API)
%
%   Headless (same engine the GUI uses)
%     opts       = plotBatteryData('defaults');
%     ds         = plotBatteryData('load',    files, opts);
%     [P, ds]    = plotBatteryData('extract', files_or_ds, opts);
%     prof       = plotBatteryData('profile', ds(k), opts);
%     names      = plotBatteryData('export',  P, prof, opts);   % -> base workspace
%     res        = plotBatteryData('twin',    P, prof, opts);   % build + simulate
%
%   Expected CSV columns (names are matched loosely, order does not matter):
%     Record#  Step  TestTime (s)  StepTime (s)  Capacity (Ah)  Energy (Wh)
%     Current (A)  Voltage (V)  State  ES  DateTime  Temp 1  Chamber Temperature (C)
%
%   One CSV per test temperature. See README.md for the method and a
%   walk-through of every section of this file.

% ======================================================================
%  SECTION 0 - Command dispatcher
% ======================================================================
if nargin == 0
    launchGui({});
    return
end
cmd = varargin{1};
if ~(ischar(cmd) || isstring(cmd))
    error('plotBatteryData:badCommand', ...
        'First argument must be a command name. Type "help plotBatteryData".');
end
switch lower(char(cmd))
    case 'gui'
        files = {};
        if nargin >= 2, files = cellstr(varargin{2}); end
        fig = launchGui(files);
        if nargout, varargout{1} = fig; end
    case 'defaults'
        varargout{1} = defaultOptions();
    case 'load'
        o = optsFromArgs(varargin, 3);
        varargout{1} = loadDatasets(cellstr(varargin{2}), o);
    case 'extract'
        o = optsFromArgs(varargin, 3);
        dsArr = asDatasets(varargin{2}, o);
        [P, dsArr] = extractParameters(dsArr, o);
        varargout{1} = P;
        if nargout > 1, varargout{2} = dsArr; end
    case 'profile'
        o = optsFromArgs(varargin, 3);
        varargout{1} = extractProfile(varargin{2}, o);
    case 'export'
        o = optsFromArgs(varargin, 4);
        varargout{1} = exportToWorkspace(varargin{2}, varargin{3}, o);
    case 'twin'
        o = optsFromArgs(varargin, 4);
        varargout{1} = runTwin(varargin{2}, varargin{3}, o);
    otherwise
        error('plotBatteryData:badCommand', 'Unknown command "%s".', char(cmd));
end
end

% ======================================================================
%  SECTION 1 - Options
% ======================================================================
function o = defaultOptions()
% Every tunable number in one place. The GUI edits a copy of this struct.

% --- data import ---------------------------------------------------------
o.currentSign   = 'auto';   % 'auto' | 'charge+' (positive = charge) | 'discharge+'
o.restCurrentA  = NaN;      % |I| below this is "rest"; NaN = auto (0.2 % of max |I|, >= 2 mA)

% --- capacity / SOC --------------------------------------------------------
o.vTol          = 0.02;     % V, tolerance when detecting full (Vmax) / empty (Vmin)
o.socBasis      = 'common'; % 'common' : one capacity (the block's AH) for every temperature
                            % 'perTemperature' : each file uses its own measured capacity
o.refTempC      = 25;       % the block takes ONE AH; it is taken from the file nearest this T
o.initialSOC    = NaN;      % only used if a file has neither a full charge nor a full discharge

% --- tables ----------------------------------------------------------------
o.socGrid       = [0 0.02 0.05 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.95 1];
o.nRC           = 2;        % RC pairs (1..3) -> block "Charge dynamics"
o.tauMin        = 1;        % s, lower bound for any time constant
o.tauMax        = 3000;     % s, upper bound for any time constant
o.minRestS      = 300;      % s, rests shorter than this are not used for RC / OCV fits
o.maxFitRmse    = 0.008;    % V, relaxation fits worse than this are rejected
o.maxEdgeDt     = 5;        % s, current steps sampled coarser than this are not used for R0
o.ocvMaxCrate   = 0.5;      % C, only CC data at or below this rate builds the dense OCV curve

% --- datasheet values (NaN = not given) ---------------------------------------
o.ds.capacityAh     = NaN;  % Ah, nominal / typical capacity
o.ds.Vmax           = NaN;  % V, charge cut-off
o.ds.Vmin           = NaN;  % V, discharge cut-off
o.ds.massKg         = NaN;  % kg, cell mass             } thermal mass = m * cp
o.ds.cpJkgK         = NaN;  % J/(kg*K), specific heat   }
o.ds.hA             = NaN;  % W/K, convective conductance cell -> chamber
o.ds.R0             = NaN;  % Ohm, DC/AC internal resistance (fallback for R0)
o.ds.Rleak          = NaN;  % Ohm, self-discharge resistance (enables self-discharge)
o.ds.ocvTable       = [];   % [SOC OCV] two-column fallback OCV curve
o.ds.preferCapacity = false;% true = use datasheet capacity even if the data gives one
o.ds.preferThermal  = false;% true = use datasheet thermal values even if fitted

% --- export / twin -------------------------------------------------------------
o.prefix        = 'batt_';  % workspace variable prefix
o.profileSign   = 'charge+';% sign of exported current (see README "Load profile")
o.profileWindow = [];       % [t1 t2] s of TestTime; [] = whole file
o.modelName     = 'batteryTwin';
o.modelDir      = pwd;
o.saveModel     = true;
end

function o = optsFromArgs(args, k)
o = defaultOptions();
if numel(args) >= k && ~isempty(args{k})
    o = mergeStruct(o, args{k});
end
end

function a = mergeStruct(a, b)
f = fieldnames(b);
for i = 1:numel(f)
    if isfield(a, f{i}) && isstruct(a.(f{i})) && isstruct(b.(f{i}))
        a.(f{i}) = mergeStruct(a.(f{i}), b.(f{i}));
    else
        a.(f{i}) = b.(f{i});
    end
end
end

% ======================================================================
%  SECTION 2 - GUI
% ======================================================================
function fig = launchGui(initialFiles)

% ---------------- shared state (visible to all nested callbacks) ----------
datasets   = emptyDatasets();   % struct array, one per CSV
opts       = defaultOptions();
P          = [];                % extraction result
prof       = [];                % last exported load profile
twinRes    = [];                % last twin simulation
series     = struct('h',{},'side',{},'x',{},'y',{},'mono',{},'name',{}, ...
                    'color',{},'marker',{},'label',{});
cursorOn   = false;
cursorX    = [];                % xline handle
zoomStack  = {};
drag       = struct('active',false,'p0',[0 0],'box',[]);
hasRight   = false;
% default folder for the file dialogs (uigetfile falls back to pwd if it is unreachable)
lastFolder = ['\\Ssnx\ssn(x)\Documents\Non-Prop Electrical and Combat Systems\NP Electrical\' ...
              '5_Energy Storage\3_Analysis\NRL_Battery_Data'];

% ---------------- figure + top level layout --------------------------------
fig = uifigure('Name','Battery Test Viewer & Model Builder', ...
    'Color',[0.96 0.96 0.97],'Visible','off');
fig.Position(3:4) = [1400 860];
movegui(fig,'center');
if isempty(initialFiles), fig.WindowState = 'maximized'; end

top = uigridlayout(fig,[2 2],'RowHeight',{36,'1x'},'ColumnWidth',{310,'1x'}, ...
    'Padding',[8 8 8 8],'RowSpacing',6,'ColumnSpacing',8);

lblTitle = uilabel(top,'Text','Battery Test Viewer & Model Builder', ...
    'FontSize',18,'FontWeight','bold');
lblTitle.Layout.Row = 1; lblTitle.Layout.Column = 1;
lblStatus = uilabel(top,'Text','Ready - add one CSV per test temperature', ...
    'FontColor',[0.35 0.35 0.4],'HorizontalAlignment','right');
lblStatus.Layout.Row = 1; lblStatus.Layout.Column = 2;

% ---------------- left: file list -----------------------------------------
pnlFiles = uipanel(top,'Title','Test files (one per temperature)','FontWeight','bold', ...
    'BackgroundColor','white');
pnlFiles.Layout.Row = 2; pnlFiles.Layout.Column = 1;
gFiles = uigridlayout(pnlFiles,[4 3],'RowHeight',{30,'1x','fit',150}, ...
    'ColumnWidth',{'1x','1x','1x'},'Padding',[6 6 6 6],'RowSpacing',6);
btnAdd = uibutton(gFiles,'Text','Add CSV...','FontWeight','bold', ...
    'ButtonPushedFcn',@(~,~) onAddFiles());
btnAdd.Layout.Row = 1; btnAdd.Layout.Column = 1;
btnRemove = uibutton(gFiles,'Text','Remove','ButtonPushedFcn',@(~,~) onRemoveFile());
btnRemove.Layout.Row = 1; btnRemove.Layout.Column = 2;
btnClear = uibutton(gFiles,'Text','Clear all','ButtonPushedFcn',@(~,~) onClearFiles());
btnClear.Layout.Row = 1; btnClear.Layout.Column = 3;
tblFiles = uitable(gFiles,'ColumnName',{'File','T (°C)','Rows','Hours'}, ...
    'ColumnEditable',[false true false false],'ColumnWidth',{'1x',52,62,52}, ...
    'RowName',{},'CellEditCallback',@onFileTableEdit,'SelectionType','row');
tblFiles.Layout.Row = 2; tblFiles.Layout.Column = [1 3];
lblFileHelp = uilabel(gFiles,'WordWrap','on','FontColor',[0.35 0.35 0.4], ...
    'Text',['T (°C) is read from the chamber column; edit it if needed. ' ...
            'Files within 1 °C of each other are merged into one table column.']);
lblFileHelp.Layout.Row = 3; lblFileHelp.Layout.Column = [1 3];
txtFileInfo = uitextarea(gFiles,'Editable','off','Value',{''},'FontName','Consolas', ...
    'FontSize',11);
txtFileInfo.Layout.Row = 4; txtFileInfo.Layout.Column = [1 3];

% ---------------- right: tabs -----------------------------------------------
tabs = uitabgroup(top);
tabs.Layout.Row = 2; tabs.Layout.Column = 2;
tabPlot   = uitab(tabs,'Title','  Plot  ');
tabModel  = uitab(tabs,'Title','  Model extraction  ');
tabExport = uitab(tabs,'Title','  Load profile & digital twin  ');

% ====== TAB 1: plot =========================================================
gPlot = uigridlayout(tabPlot,[1 2],'ColumnWidth',{240,'1x'},'Padding',[6 6 6 6]);
gCtl = uigridlayout(gPlot,[16 2],'Padding',[0 0 0 0],'RowSpacing',4,'ColumnSpacing',4, ...
    'RowHeight',{'fit',70,'fit',24,'fit','1x','fit','1x',8,26,26,24,26,26,8,'fit'});
gCtl.Layout.Column = 1;
axHolder = uipanel(gPlot,'BorderType','none','BackgroundColor','white');
axHolder.Layout.Column = 2;
gAx = uigridlayout(axHolder,[1 1],'Padding',[0 0 0 0]);

r = 1;
lbl(gCtl,'Datasets',r); r = r+1;
lbData = uilistbox(gCtl,'Multiselect','on','Items',{},'ValueChangedFcn',@(~,~) onColumnsChanged());
place(lbData,r,[1 2]); r = r+1;
lbl(gCtl,'X axis',r); r = r+1;
ddX = uidropdown(gCtl,'Items',{'(load data)'},'ValueChangedFcn',@(~,~) refreshPlot(false));
place(ddX,r,[1 2]); r = r+1;
lbl(gCtl,'Left Y axis (Ctrl+click = several)',r); r = r+1;
lbLeft = uilistbox(gCtl,'Multiselect','on','Items',{},'ValueChangedFcn',@(~,~) refreshPlot(false));
place(lbLeft,r,[1 2]); r = r+1;
lbl(gCtl,'Right Y axis',r); r = r+1;
lbRight = uilistbox(gCtl,'Multiselect','on','Items',{},'ValueChangedFcn',@(~,~) refreshPlot(false));
place(lbRight,r,[1 2]); r = r+2;
btnFitAll = uibutton(gCtl,'Text','Fit all','FontWeight','bold','ButtonPushedFcn',@(~,~) fitView('all'));
place(btnFitAll,r,[1 2]); r = r+1;
btnFitX = uibutton(gCtl,'Text','Fit horizontal','ButtonPushedFcn',@(~,~) fitView('x'));
place(btnFitX,r,1);
btnFitY = uibutton(gCtl,'Text','Fit vertical','ButtonPushedFcn',@(~,~) fitView('y'));
place(btnFitY,r,2); r = r+1;
ddDrag = uidropdown(gCtl,'Items',{'Drag: box zoom','Drag: horizontal zoom', ...
    'Drag: vertical zoom','Drag: off'},'Value','Drag: box zoom');
place(ddDrag,r,[1 2]); r = r+1;
btnBack = uibutton(gCtl,'Text','Zoom back','ButtonPushedFcn',@(~,~) zoomBack());
place(btnBack,r,1);
btnCursor = uibutton(gCtl,'state','Text','Cursor: off','ValueChangedFcn',@(s,~) setCursor(s.Value));
place(btnCursor,r,2); r = r+1;
btnSaveFig = uibutton(gCtl,'Text','Copy plot to figure','ButtonPushedFcn',@(~,~) onPopOut());
place(btnSaveFig,r,[1 2]); r = r+2;
hint = uilabel(gCtl,'WordWrap','on','FontColor',[0.35 0.35 0.4],'FontSize',11, ...
    'Text',['Drag on the plot to zoom. Scroll = zoom at the mouse. Double-click = fit all. ' ...
            'Right-click = zoom back. Cursor shows each curve''s value where it crosses the ' ...
            'mouse position.']);
place(hint,r,[1 2]);

ax = [];
createAxes();

% ====== TAB 2: model extraction ============================================
gModel = uigridlayout(tabModel,[1 2],'ColumnWidth',{330,'1x'},'Padding',[6 6 6 6]);
gSet = uigridlayout(gModel,[3 1],'RowHeight',{'fit','fit','fit'},'Padding',[0 0 0 0], ...
    'Scrollable','on');
gSet.Layout.Column = 1;

pnlSet = uipanel(gSet,'Title','Extraction settings','FontWeight','bold','BackgroundColor','white');
gS = uigridlayout(pnlSet,[10 2],'ColumnWidth',{170,'1x'},'RowHeight',repmat({24},1,10), ...
    'Padding',[6 6 6 6],'RowSpacing',4);
efSoc     = addEdit(gS,1,'SOC breakpoints',mat2str(opts.socGrid));
ddRC      = addDrop(gS,2,'RC pairs (charge dynamics)',{'1','2','3'},num2str(opts.nRC));
efTau     = addEdit(gS,3,'tau bounds [min max] (s)',mat2str([opts.tauMin opts.tauMax]));
efRest    = addNum(gS,4,'Min rest for RC/OCV fit (s)',opts.minRestS);
efEdgeDt  = addNum(gS,5,'Max sample gap at step (s)',opts.maxEdgeDt);
efOcvC    = addNum(gS,6,'Dense OCV max C-rate',opts.ocvMaxCrate);
ddSign    = addDrop(gS,7,'Current sign in file',{'auto','charge+','discharge+'},opts.currentSign);
ddBasis   = addDrop(gS,8,'SOC basis',{'common','perTemperature'},opts.socBasis);
efRefT    = addNum(gS,9,'AH reference temp (°C)',opts.refTempC);
efVtol    = addNum(gS,10,'Full/empty voltage tol (V)',opts.vTol);

pnlDs = uipanel(gSet,'Title','Datasheet values (blank = not given)','FontWeight','bold', ...
    'BackgroundColor','white');
gD = uigridlayout(pnlDs,[12 2],'ColumnWidth',{170,'1x'},'RowHeight',repmat({24},1,12), ...
    'Padding',[6 6 6 6],'RowSpacing',4);
efCap   = addNum(gD,1,'Capacity (Ah)',NaN);
efVmax  = addNum(gD,2,'Charge cut-off Vmax (V)',NaN);
efVmin  = addNum(gD,3,'Discharge cut-off Vmin (V)',NaN);
efMass  = addNum(gD,4,'Cell mass (kg)',NaN);
efCp    = addNum(gD,5,'Specific heat (J/kg/K)',NaN);
efHA    = addNum(gD,6,'Convection h*A (W/K)',NaN);
efR0    = addNum(gD,7,'Internal resistance (mOhm)',NaN);
efLeak  = addNum(gD,8,'Self-discharge R (Ohm)',NaN);
cbCap   = uicheckbox(gD,'Text','Prefer datasheet capacity'); place(cbCap,9,[1 2]);
cbTh    = uicheckbox(gD,'Text','Prefer datasheet thermal values'); place(cbTh,10,[1 2]);
btnOcv  = uibutton(gD,'Text','Load datasheet OCV table (CSV: SOC,OCV)...', ...
    'ButtonPushedFcn',@(~,~) onLoadOcvTable()); place(btnOcv,11,[1 2]);
lblOcv  = uilabel(gD,'Text','No datasheet OCV table','FontColor',[0.4 0.4 0.4]); place(lblOcv,12,[1 2]);

uibutton(gSet,'Text','Run extraction','FontWeight','bold','FontSize',14, ...
    'BackgroundColor',[0.20 0.45 0.80],'FontColor','white', ...
    'ButtonPushedFcn',@(~,~) onRunExtraction());

gRes = uigridlayout(gModel,[2 1],'RowHeight',{'1x',240},'Padding',[0 0 0 0]);
gRes.Layout.Column = 2;
gDiag = uigridlayout(gRes,[2 2],'RowHeight',{26,'1x'},'ColumnWidth',{200,'1x'},'Padding',[0 0 0 0]);
ddDiag = uidropdown(gDiag,'Items',{'OCV vs SOC','R0 vs SOC','R1 vs SOC','tau1 vs SOC', ...
    'R2 vs SOC','tau2 vs SOC','R3 vs SOC','tau3 vs SOC','SOC vs time', ...
    'Thermal model fit','Capacity vs temperature'},'ValueChangedFcn',@(~,~) drawDiag());
ddDiag.Layout.Row = 1; ddDiag.Layout.Column = 1;
lblDiag = uilabel(gDiag,'Text','Dots = individual measurements, lines = the exported table', ...
    'FontColor',[0.4 0.4 0.4]);
lblDiag.Layout.Row = 1; lblDiag.Layout.Column = 2;
axDiag = uiaxes(gDiag); axDiag.Layout.Row = 2; axDiag.Layout.Column = [1 2];
styleAxes(axDiag);
txtReport = uitextarea(gRes,'Editable','off','FontName','Consolas','FontSize',11, ...
    'Value',{'Run the extraction to see the report.'});

% ====== TAB 3: profile + twin ===============================================
gExp = uigridlayout(tabExport,[1 2],'ColumnWidth',{330,'1x'},'Padding',[6 6 6 6]);
gE = uigridlayout(gExp,[4 1],'RowHeight',{'fit','fit','fit','1x'},'Padding',[0 0 0 0]);
gE.Layout.Column = 1;

pnlP = uipanel(gE,'Title','1. Model parameters','FontWeight','bold','BackgroundColor','white');
gP = uigridlayout(pnlP,[3 2],'RowHeight',{24,28,28},'ColumnWidth',{120,'1x'},'Padding',[6 6 6 6]);
efPrefix = addEdit(gP,1,'Variable prefix',opts.prefix);
btnToWs = uibutton(gP,'Text','To workspace','ButtonPushedFcn',@(~,~) onExportParams());
place(btnToWs,2,1);
btnMat = uibutton(gP,'Text','Save .mat...','ButtonPushedFcn',@(~,~) onSaveMat());
place(btnMat,2,2);
btnApply = uibutton(gP,'Text','Apply to selected Simulink block (gcb)', ...
    'ButtonPushedFcn',@(~,~) onApplyToBlock());
place(btnApply,3,[1 2]);

pnlL = uipanel(gE,'Title','2. Load profile','FontWeight','bold','BackgroundColor','white');
gL = uigridlayout(pnlL,[4 2],'RowHeight',{24,24,24,28},'ColumnWidth',{120,'1x'},'Padding',[6 6 6 6]);
ddProfData = addDrop(gL,1,'Dataset',{'(none)'},'(none)');
ddProfSign = addDrop(gL,2,'Positive current',{'charge+','discharge+'},opts.profileSign);
cbWindow = uicheckbox(gL,'Text','Only the time window shown in the Plot tab');
place(cbWindow,3,[1 2]);
btnProf = uibutton(gL,'Text','Export load profile to workspace','FontWeight','bold', ...
    'ButtonPushedFcn',@(~,~) onExportProfile());
place(btnProf,4,[1 2]);

pnlT = uipanel(gE,'Title','3. Digital twin','FontWeight','bold','BackgroundColor','white');
gT = uigridlayout(pnlT,[3 2],'RowHeight',{24,28,28},'ColumnWidth',{120,'1x'},'Padding',[6 6 6 6]);
efModel = addEdit(gT,1,'Model name',opts.modelName);
btnTwin = uibutton(gT,'Text','Build & run twin','FontWeight','bold', ...
    'BackgroundColor',[0.20 0.45 0.80],'FontColor','white','ButtonPushedFcn',@(~,~) onRunTwin());
place(btnTwin,2,[1 2]);
btnOpenMdl = uibutton(gT,'Text','Open model','ButtonPushedFcn',@(~,~) onOpenModel());
place(btnOpenMdl,3,[1 2]);

txtExport = uitextarea(gE,'Editable','off','FontName','Consolas','FontSize',11, ...
    'Value',{'Exported variables and wiring notes appear here.'});

gTw = uigridlayout(gExp,[2 1],'RowHeight',{'1x','1x'},'Padding',[0 0 0 0]);
gTw.Layout.Column = 2;
axTwinV = uiaxes(gTw); styleAxes(axTwinV);
title(axTwinV,'Terminal voltage: measured vs twin');
axTwinE = uiaxes(gTw); styleAxes(axTwinE);
title(axTwinE,'Twin error and cell temperature');

% ---------------- figure-level mouse handlers ----------------------------------
fig.WindowButtonDownFcn   = @onMouseDown;
fig.WindowButtonMotionFcn = @onMouseMove;
fig.WindowButtonUpFcn     = @onMouseUp;
fig.WindowScrollWheelFcn  = @onScroll;
fig.KeyPressFcn           = @onKey;

% ---------------- scripting / test API -------------------------------------------
api.loadFiles   = @(f) addFiles(cellstr(f));
api.setColumns  = @setColumns;
api.cursorAt    = @(x,y) updateCursor([x y]);
api.setCursor   = @setCursor;
api.zoomBox     = @(xl,yl) applyZoom(xl,yl);
api.fit         = @fitView;
api.zoomBack    = @zoomBack;
api.runExtraction = @onRunExtraction;
api.exportProfile = @onExportProfile;
api.runTwin     = @onRunTwin;
api.selectTab   = @(k) set(tabs,'SelectedTab',tabs.Children(k));
api.setDiag     = @(name) set(ddDiag,'Value',name);
api.drawDiag    = @drawDiag;
api.getState    = @getState;
fig.UserData.api = api;

fig.Visible = 'on';
if ~isempty(initialFiles), addFiles(initialFiles); end

% =========================================================================
%  GUI helpers (layout)
% =========================================================================
    function st = getState()
        % live snapshot of the app's state (used by the scripting / test API)
        st = struct('datasets',datasets,'P',P,'prof',prof,'twin',twinRes, ...
            'series',series,'ax',ax,'opts',opts);
    end
    function h = lbl(parent,txt,row)
        h = uilabel(parent,'Text',txt,'FontWeight','bold');
        h.Layout.Row = row; h.Layout.Column = [1 2];
    end
    function place(h,row,col)
        h.Layout.Row = row; h.Layout.Column = col;
    end
    function h = addEdit(parent,row,txt,val)
        l = uilabel(parent,'Text',txt); place(l,row,1);
        h = uieditfield(parent,'text','Value',val); place(h,row,2);
    end
    function h = addNum(parent,row,txt,val)
        l = uilabel(parent,'Text',txt); place(l,row,1);
        if isnan(val), s = ''; else, s = num2str(val); end
        h = uieditfield(parent,'text','Value',s,'Placeholder','-'); place(h,row,2);
    end
    function h = addDrop(parent,row,txt,items,val)
        l = uilabel(parent,'Text',txt); place(l,row,1);
        h = uidropdown(parent,'Items',items,'Value',val); place(h,row,2);
    end
    function setStatus(txt)
        lblStatus.Text = txt; drawnow limitrate;
    end

% =========================================================================
%  File handling
% =========================================================================
    function onAddFiles()
        [f,p] = uigetfile({'*.csv;*.txt','Cycler export (*.csv, *.txt)'}, ...
            'Select battery test CSV file(s)', lastFolder, 'MultiSelect','on');
        figure(fig);
        if isequal(f,0), return; end
        lastFolder = p;
        addFiles(fullfile(p, cellstr(f)));
    end

    function addFiles(files)
        dlg = uiprogressdlg(fig,'Title','Loading','Message','Reading CSV...','Indeterminate','on');
        cleanup = onCleanup(@() delete(dlg));
        for k = 1:numel(files)
            dlg.Message = sprintf('Reading %s ...', shortName(files{k}));
            try
                d = loadDataset(files{k}, opts);
                datasets(end+1) = d; %#ok<AGROW>
            catch ME
                uialert(fig, sprintf('%s\n\n%s', files{k}, ME.message), 'Could not read file');
            end
        end
        P = [];                                  % new data invalidates old tables
        refreshFileTable();
        refreshColumnLists(true);
        refreshPlot(false);
        fitView('all');
        setStatus(sprintf('%d file(s) loaded', numel(datasets)));
    end

    function onRemoveFile()
        sel = tblFiles.Selection;
        if isempty(sel) || isempty(datasets), return; end
        datasets(unique(sel(:,1))) = [];
        P = [];
        refreshFileTable(); refreshColumnLists(true); refreshPlot(false); fitView('all');
    end

    function onClearFiles()
        datasets = emptyDatasets(); P = []; prof = []; twinRes = [];
        refreshFileTable(); refreshColumnLists(true); refreshPlot(false);
        cla(axDiag); cla(axTwinV); cla(axTwinE);
        txtReport.Value = {'Run the extraction to see the report.'};
        setStatus('Ready - add one CSV per test temperature');
    end

    function onFileTableEdit(~,evt)
        r = evt.Indices(1);
        v = evt.NewData;
        if ischar(v) || isstring(v), v = str2double(v); end
        if ~isfinite(v)
            tblFiles.Data{r,2} = evt.PreviousData; return
        end
        datasets(r).T_C = v;
        P = [];
        refreshColumnLists(false);
    end

    function refreshFileTable()
        n = numel(datasets);
        data = cell(n,4);
        info = {};
        for k = 1:n
            d = datasets(k);
            data(k,:) = {d.name, d.T_C, numel(d.t), sprintf('%.1f', (d.t(end)-d.t(1))/3600)};
            info{end+1} = sprintf('%s', d.name); %#ok<AGROW>
            info{end+1} = sprintf('  dt median %.3g s, I sign: %s', d.dtMedian, d.signNote); %#ok<AGROW>
            info{end+1} = sprintf('  V %.3f..%.3f V, |I| max %.3g A', min(d.V), max(d.V), max(abs(d.I))); %#ok<AGROW>
            if ~isempty(d.warn)
                info = [info, strcat({'  ! '}, d.warn)]; %#ok<AGROW>
            end
        end
        tblFiles.Data = data;
        if isempty(info), info = {''}; end
        txtFileInfo.Value = info;
        names = {datasets.name};
        lbData.Items = names;
        if ~isempty(names), lbData.Value = names(1); else, lbData.Value = {}; end
        if isempty(names)
            ddProfData.Items = {'(none)'}; ddProfData.Value = '(none)';
        else
            ddProfData.Items = names; ddProfData.Value = names{1};
        end
    end

    function onColumnsChanged()
        refreshColumnLists(false);
        refreshPlot(false);
        fitView('all');
    end

    function refreshColumnLists(setDefaults)
        idx = selectedDatasets();
        if isempty(idx)
            ddX.Items = {'(load data)'}; lbLeft.Items = {}; lbRight.Items = {};
            return
        end
        cols = numericColumns(datasets(idx(1)).tbl);
        oldX = ddX.Value; oldL = lbLeft.Value; oldR = lbRight.Value;
        ddX.Items = cols;
        lbLeft.Items = cols;
        lbRight.Items = cols;
        if setDefaults || ~any(strcmp(cols, oldX))
            ddX.Value = pickCol(cols, {'Test Time (h)','TestTime'});
        else
            ddX.Value = oldX;
        end
        keepL = intersect(oldL, cols, 'stable'); keepR = intersect(oldR, cols, 'stable');
        if setDefaults || isempty(keepL)
            keepL = {pickCol(cols, {'Voltage'})};
            keepR = {pickCol(cols, {'Current, +discharge','Current'})};
        end
        lbLeft.Value = keepL;
        lbRight.Value = keepR;
    end

    function setColumns(xName, leftNames, rightNames)
        ddX.Value = xName;
        lbLeft.Value = cellstr(leftNames);
        if isempty(rightNames), lbRight.Value = {}; else, lbRight.Value = cellstr(rightNames); end
        refreshPlot(false); fitView('all');
    end

    function idx = selectedDatasets()
        if isempty(datasets), idx = []; return; end
        idx = find(ismember({datasets.name}, lbData.Value));
        if isempty(idx), idx = 1; end
    end

% =========================================================================
%  Plotting
% =========================================================================
    function createAxes()
        if ~isempty(ax) && isvalid(ax), delete(ax); end
        ax = uiaxes(gAx);
        styleAxes(ax);
        ax.Interactions = [];
        disableDefaultInteractivity(ax);
        ax.Toolbar.Visible = 'off';
        cursorX = [];
    end

    function refreshPlot(keepLimits)
        if keepLimits && ~isempty(series)
            lims = currentLimits();
        else
            lims = [];
        end
        createAxes();
        series = series([]);
        idx = selectedDatasets();
        if isempty(idx)
            title(ax,'Add a CSV file to start');
            return
        end
        xName = ddX.Value;
        leftNames = lbLeft.Value; rightNames = lbRight.Value;
        rightNames = setdiff(rightNames, leftNames, 'stable');
        hasRight = ~isempty(rightNames);
        multi = numel(idx) > 1;
        palette = seriesColors(numel(idx)*(numel(leftNames)+numel(rightNames)));
        c = 0;
        if hasRight
            yyaxis(ax,'right'); hold(ax,'on');
            for d = idx
                for k = 1:numel(rightNames)
                    c = c+1; addSeries(d, xName, rightNames{k}, 'right', palette(c,:), multi);
                end
            end
            ylabel(ax, strjoin(rightNames, ', '), 'Interpreter','none');
            ax.YAxis(2).Color = [0.25 0.25 0.25];
            yyaxis(ax,'left');
        end
        hold(ax,'on');
        for d = idx
            for k = 1:numel(leftNames)
                c = c+1; addSeries(d, xName, leftNames{k}, 'left', palette(c,:), multi);
            end
        end
        ylabel(ax, strjoin(leftNames, ', '), 'Interpreter','none');
        if hasRight, ax.YAxis(1).Color = [0.25 0.25 0.25]; end
        xlabel(ax, xName, 'Interpreter','none');
        if ~isempty(series)
            legend(ax, [series.h], {series.name}, 'Interpreter','none', ...
                'Location','best','AutoUpdate','off');
        end
        hold(ax,'off');
        if ~isempty(lims)
            setLimits(lims{:});
        else
            fitView('all', false);
        end
        if cursorOn, buildCursor(); end
    end

    function addSeries(d, xName, yName, side, color, multi)
        T = datasets(d).tbl;
        if ~any(strcmp(T.Properties.VariableNames, yName)) || ...
           ~any(strcmp(T.Properties.VariableNames, xName))
            return
        end
        x = double(T.(xName)); y = double(T.(yName));
        nm = yName;
        if multi, nm = sprintf('%s | %s', datasets(d).name, yName); end
        h = plot(ax, x, y, '-', 'Color', color, 'LineWidth', 1.3, 'DisplayName', nm);
        h.PickableParts = 'none';
        xv = x(~isnan(x));
        s.h = h; s.side = side; s.x = x; s.y = y;
        s.mono = all(diff(xv) >= 0);
        s.name = nm; s.color = color; s.marker = []; s.label = [];
        series(end+1) = s;
    end

    function lims = currentLimits()
        if hasRight
            lims = {ax.XLim, ax.YAxis(1).Limits, ax.YAxis(2).Limits};
        else
            lims = {ax.XLim, ax.YLim, []};
        end
    end

    function setLimits(xl, yl, yr)
        if any(~isfinite(xl)) || diff(xl) <= 0, xl = xl(1) + [-0.5 0.5]; end
        ax.XLim = xl;
        if hasRight
            if isfinite(diff(yl)) && diff(yl) > 0, ax.YAxis(1).Limits = yl; end
            if ~isempty(yr) && isfinite(diff(yr)) && diff(yr) > 0, ax.YAxis(2).Limits = yr; end
        else
            if isfinite(diff(yl)) && diff(yl) > 0, ax.YLim = yl; end
        end
        if cursorOn, refreshCursorAtLast(); end
    end

    function [lo, hi] = extentOf(side, xr)
        lo = inf; hi = -inf;
        for k = 1:numel(series)
            if ~strcmp(series(k).side, side), continue; end
            y = series(k).y;
            if ~isempty(xr)
                m = series(k).x >= xr(1) & series(k).x <= xr(2);
                y = y(m);
            end
            y = y(isfinite(y));
            if isempty(y), continue; end
            lo = min(lo, min(y)); hi = max(hi, max(y));
        end
        if ~isfinite(lo), lo = 0; hi = 1; end
        if hi - lo < eps(max(abs([lo hi]))+1)*100
            pad = max(abs(hi)*0.05, 0.5);
        else
            pad = 0.04*(hi - lo);
        end
        lo = lo - pad; hi = hi + pad;
    end

    function fitView(mode, push)
        if nargin < 2, push = true; end
        if isempty(series), return; end
        if push, pushZoom(); end
        lims = currentLimits();
        xl = lims{1}; yl = lims{2}; yr = lims{3};
        if any(strcmp(mode, {'all','x'}))
            xs = cellfun(@(v) [min(v(isfinite(v))) max(v(isfinite(v)))], {series.x}, ...
                'UniformOutput', false);
            xs = vertcat(xs{:});
            xl = [min(xs(:,1)) max(xs(:,2))];
        end
        if any(strcmp(mode, {'all','y'}))
            if strcmp(mode,'all'), xr = []; else, xr = xl; end
            [a,b] = extentOf('left', xr); yl = [a b];
            if hasRight, [a,b] = extentOf('right', xr); yr = [a b]; end
        end
        setLimits(xl, yl, yr);
    end

    function pushZoom()
        if isempty(series), return; end
        zoomStack{end+1} = currentLimits();
        if numel(zoomStack) > 50, zoomStack(1) = []; end
    end

    function zoomBack()
        if isempty(zoomStack), fitView('all', false); return; end
        lims = zoomStack{end}; zoomStack(end) = [];
        setLimits(lims{:});
    end

    function applyZoom(xl, yl)
        % xl / yl are in LEFT-axis data units; [] keeps that direction unchanged
        pushZoom();
        lims = currentLimits();
        newX = lims{1}; newL = lims{2}; newR = lims{3};
        if ~isempty(xl), newX = sort(xl); end
        if ~isempty(yl)
            yl = sort(yl);
            if hasRight
                f = (yl - lims{2}(1)) / diff(lims{2});
                newR = lims{3}(1) + f*diff(lims{3});
            end
            newL = yl;
        end
        setLimits(newX, newL, newR);
    end

    function onPopOut()
        if isempty(series), return; end
        f2 = figure('Name','Battery plot','Color','w');
        a2 = axes(f2);
        lims = currentLimits();
        if hasRight, yyaxis(a2,'right'); hold(a2,'on'); end
        for k = 1:numel(series)
            if strcmp(series(k).side,'right')
                plot(a2, series(k).x, series(k).y, 'Color', series(k).color, 'DisplayName', series(k).name);
            end
        end
        if hasRight, ylim(a2, lims{3}); ylabel(a2, ax.YAxis(2).Label.String); yyaxis(a2,'left'); end
        hold(a2,'on');
        for k = 1:numel(series)
            if strcmp(series(k).side,'left')
                plot(a2, series(k).x, series(k).y, 'Color', series(k).color, 'DisplayName', series(k).name);
            end
        end
        xlim(a2, lims{1}); ylim(a2, lims{2});
        xlabel(a2, ax.XLabel.String); ylabel(a2, ax.YAxis(1).Label.String);
        legend(a2,'Interpreter','none'); grid(a2,'on');
    end

% =========================================================================
%  Mouse interaction: cursor, drag-zoom, scroll-zoom
% =========================================================================
    function [inside, p] = mouseInAxes()
        inside = false; p = [NaN NaN];
        if isempty(series) || isempty(ax) || ~isvalid(ax), return; end
        if tabs.SelectedTab ~= tabPlot, return; end
        cp = ax.CurrentPoint;            % left-axis data units (left side is active)
        p = cp(1,1:2);
        xl = ax.XLim;
        if hasRight, yl = ax.YAxis(1).Limits; else, yl = ax.YLim; end
        inside = p(1) >= xl(1) && p(1) <= xl(2) && p(2) >= yl(1) && p(2) <= yl(2);
    end

    function onMouseDown(~,~)
        [inside, p] = mouseInAxes();
        if ~inside, return; end
        switch fig.SelectionType
            case 'open'                       % double-click
                drag.active = false; deleteBox();
                fitView('all');
            case 'alt'                        % right-click / ctrl-click
                zoomBack();
            case 'normal'
                if strcmp(ddDrag.Value,'Drag: off'), return; end
                drag.active = true; drag.p0 = p;
                deleteBox();
                hold(ax,'on');
                if hasRight, yyaxis(ax,'left'); end
                drag.box = plot(ax, NaN, NaN, '-', 'Color',[0.1 0.3 0.8], 'LineWidth',1, ...
                    'HandleVisibility','off','PickableParts','none');
                hold(ax,'off');
        end
    end

    function onMouseMove(~,~)
        if drag.active
            cp = ax.CurrentPoint; p = cp(1,1:2);
            [xr, yr] = dragRect(drag.p0, clampToAxes(p));
            set(drag.box, 'XData', xr([1 2 2 1 1]), 'YData', yr([1 1 2 2 1]));
            return
        end
        if ~cursorOn, return; end
        [inside, p] = mouseInAxes();
        if inside, updateCursor(p); end
    end

    function onMouseUp(~,~)
        if ~drag.active, return; end
        drag.active = false;
        cp = ax.CurrentPoint; p = clampToAxes(cp(1,1:2));
        deleteBox();
        [xr, yr] = dragRect(drag.p0, p);
        lims = currentLimits();
        fx = abs(diff(xr))/diff(lims{1}); fy = abs(diff(yr))/diff(lims{2});
        mode = ddDrag.Value;
        if contains(mode,'horizontal')
            if fx > 0.005, applyZoom(xr, []); end
        elseif contains(mode,'vertical')
            if fy > 0.005, applyZoom([], yr); end
        else
            if fx > 0.005 && fy > 0.005, applyZoom(xr, yr); end
        end
    end

    function [xr, yr] = dragRect(p0, p1)
        lims = currentLimits();
        mode = ddDrag.Value;
        xr = sort([p0(1) p1(1)]); yr = sort([p0(2) p1(2)]);
        if contains(mode,'horizontal'), yr = lims{2}; end
        if contains(mode,'vertical'),   xr = lims{1}; end
    end

    function p = clampToAxes(p)
        lims = currentLimits();
        p(1) = min(max(p(1), lims{1}(1)), lims{1}(2));
        p(2) = min(max(p(2), lims{2}(1)), lims{2}(2));
    end

    function deleteBox()
        if ~isempty(drag.box) && isvalid(drag.box), delete(drag.box); end
        drag.box = [];
    end

    function onScroll(~,evt)
        [inside, p] = mouseInAxes();
        if ~inside, return; end
        f = 1.25^evt.VerticalScrollCount;     % >1 zoom out, <1 zoom in
        lims = currentLimits();
        mode = ddDrag.Value;
        xl = lims{1}; yl = lims{2};
        newX = []; newY = [];
        if ~contains(mode,'vertical'), newX = p(1) + (xl - p(1))*f; end
        if contains(mode,'vertical') || contains(mode,'box'), newY = p(2) + (yl - p(2))*f; end
        applyZoom(newX, newY);
    end

    function onKey(~,evt)
        switch evt.Key
            case 'escape', drag.active = false; deleteBox();
            case 'f',      fitView('all');
            case 'backspace', zoomBack();
        end
    end

    function setCursor(on)
        cursorOn = logical(on);
        btnCursor.Value = cursorOn;
        if cursorOn
            btnCursor.Text = 'Cursor: on';
            buildCursor();
            lims = currentLimits();
            updateCursor([mean(lims{1}) mean(lims{2})]);
        else
            btnCursor.Text = 'Cursor: off';
            deleteCursor();
        end
    end

    function buildCursor()
        deleteCursor();
        if isempty(series), return; end
        hold(ax,'on');
        for k = 1:numel(series)
            if hasRight, yyaxis(ax, series(k).side); end
            series(k).marker = plot(ax, NaN, NaN, 'o', 'MarkerSize',7, 'LineWidth',1.5, ...
                'MarkerEdgeColor', series(k).color, 'MarkerFaceColor','w', ...
                'HandleVisibility','off','PickableParts','none');
            series(k).label = text(ax, NaN, NaN, '', 'Color', series(k).color*0.8, ...
                'FontSize',11,'FontWeight','bold','BackgroundColor',[1 1 1 0.85], ...
                'EdgeColor', series(k).color, 'Margin',2, 'Interpreter','none', ...
                'Clipping','on','PickableParts','none','VerticalAlignment','middle');
        end
        if hasRight, yyaxis(ax,'left'); end
        cursorX = xline(ax, mean(ax.XLim), '-', '', 'Color',[0.15 0.15 0.15], ...
            'LineWidth',1, 'LabelOrientation','horizontal', ...
            'LabelVerticalAlignment','bottom','FontSize',11,'FontWeight','bold', ...
            'HandleVisibility','off','PickableParts','none','Interpreter','none');
        hold(ax,'off');
    end

    function deleteCursor()
        for k = 1:numel(series)
            if ~isempty(series(k).marker) && isvalid(series(k).marker), delete(series(k).marker); end
            if ~isempty(series(k).label) && isvalid(series(k).label), delete(series(k).label); end
            series(k).marker = []; series(k).label = [];
        end
        if ~isempty(cursorX) && isvalid(cursorX), delete(cursorX); end
        cursorX = [];
    end

    function refreshCursorAtLast()
        if isempty(cursorX) || ~isvalid(cursorX), return; end
        lims = currentLimits();
        x = cursorX.Value;
        if x < lims{1}(1) || x > lims{1}(2), x = mean(lims{1}); end
        updateCursor([x mean(lims{2})]);
    end

    function updateCursor(p)
        if isempty(series) || isempty(cursorX) || ~isvalid(cursorX), return; end
        lims = currentLimits();
        xl = lims{1};
        xc = p(1);
        cursorX.Value = xc;
        cursorX.Label = [' ' ddX.Value ' = ' fmtNum(xc) ' '];
        if (xc - xl(1))/diff(xl) > 0.6
            cursorX.LabelHorizontalAlignment = 'left';    % text on the left of the line
        else
            cursorX.LabelHorizontalAlignment = 'right';
        end
        fracY = (p(2) - lims{2}(1)) / diff(lims{2});
        n = numel(series);
        yFrac = nan(n,1); yVal = nan(n,1); xVal = nan(n,1);
        for k = 1:n
            s = series(k);
            yl = lims{2}; if strcmp(s.side,'right'), yl = lims{3}; end
            if s.mono
                [xv, yv] = interpMono(s.x, s.y, xc);
            else
                % non-monotonic X (e.g. V vs capacity): nearest point on screen
                yc = yl(1) + fracY*diff(yl);
                dd = ((s.x - xc)/diff(xl)).^2 + ((s.y - yc)/diff(yl)).^2;
                [~, j] = min(dd);
                xv = s.x(j); yv = s.y(j);
            end
            xVal(k) = xv; yVal(k) = yv;
            yFrac(k) = (yv - yl(1)) / diff(yl);
        end
        % spread labels that would overlap (in screen fraction units)
        labFrac = yFrac;
        [~, order] = sort(labFrac);
        order = order(isfinite(labFrac(order)));
        minGap = 0.055;
        for j = 2:numel(order)
            if labFrac(order(j)) - labFrac(order(j-1)) < minGap
                labFrac(order(j)) = labFrac(order(j-1)) + minGap;
            end
        end
        rightSide = (xc - xl(1))/diff(xl) > 0.72;
        dx = 0.012*diff(xl);
        for k = 1:n
            s = series(k);
            if isempty(s.marker) || ~isvalid(s.marker), continue; end
            yl = lims{2}; if strcmp(s.side,'right'), yl = lims{3}; end
            ok = isfinite(yVal(k)) && yFrac(k) >= 0 && yFrac(k) <= 1;
            if ~ok
                set(s.marker,'XData',NaN,'YData',NaN);
                set(s.label,'Position',[NaN NaN 0],'String','');
                continue
            end
            set(s.marker,'XData',xVal(k),'YData',yVal(k));
            ly = yl(1) + min(max(labFrac(k),0.03),0.97)*diff(yl);
            str = sprintf('%s: %s', s.name, fmtNum(yVal(k)));
            if rightSide
                set(s.label,'Position',[xVal(k)-dx ly 0],'HorizontalAlignment','right','String',str);
            else
                set(s.label,'Position',[xVal(k)+dx ly 0],'HorizontalAlignment','left','String',str);
            end
        end
    end

% =========================================================================
%  Extraction tab
% =========================================================================
    function ok = readSettings()
        ok = true;
        try
            g = str2num(efSoc.Value); %#ok<ST2NM> % accepts e.g. [0 0.05 0.1:0.1:0.9 1]
            if isempty(g), error('SOC breakpoints: not a numeric vector'); end
            g = unique(max(0, min(1, double(g(:)'))));
            if numel(g) < 3, error('need >= 3 SOC breakpoints'); end
            opts.socGrid = g;
            tb = str2num(efTau.Value); %#ok<ST2NM>
            opts.tauMin = tb(1); opts.tauMax = tb(2);
        catch ME
            uialert(fig, ['Settings: ' ME.message], 'Bad setting'); ok = false; return
        end
        opts.nRC = str2double(ddRC.Value);
        opts.minRestS = numOr(efRest.Value, opts.minRestS);
        opts.maxEdgeDt = numOr(efEdgeDt.Value, opts.maxEdgeDt);
        opts.ocvMaxCrate = numOr(efOcvC.Value, opts.ocvMaxCrate);
        opts.currentSign = ddSign.Value;
        opts.socBasis = ddBasis.Value;
        opts.refTempC = numOr(efRefT.Value, opts.refTempC);
        opts.vTol = numOr(efVtol.Value, opts.vTol);
        opts.ds.capacityAh = numOr(efCap.Value, NaN);
        opts.ds.Vmax = numOr(efVmax.Value, NaN);
        opts.ds.Vmin = numOr(efVmin.Value, NaN);
        opts.ds.massKg = numOr(efMass.Value, NaN);
        opts.ds.cpJkgK = numOr(efCp.Value, NaN);
        opts.ds.hA = numOr(efHA.Value, NaN);
        opts.ds.R0 = numOr(efR0.Value, NaN)/1000;
        opts.ds.Rleak = numOr(efLeak.Value, NaN);
        opts.ds.preferCapacity = cbCap.Value;
        opts.ds.preferThermal = cbTh.Value;
        opts.prefix = matlab.lang.makeValidName(strtrim(efPrefix.Value));
        opts.profileSign = ddProfSign.Value;
        opts.modelName = matlab.lang.makeValidName(strtrim(efModel.Value));
    end

    function onLoadOcvTable()
        [f,p] = uigetfile({'*.csv;*.txt','SOC,OCV table'}, 'Datasheet OCV table', lastFolder);
        figure(fig);
        if isequal(f,0), return; end
        try
            m = readmatrix(fullfile(p,f));
            m = m(all(isfinite(m(:,1:2)),2),1:2);
            if max(m(:,1)) > 1.5, m(:,1) = m(:,1)/100; end   % percent -> fraction
            opts.ds.ocvTable = sortrows(m);
            lblOcv.Text = sprintf('%s (%d points)', f, size(m,1));
        catch ME
            uialert(fig, ME.message, 'Could not read OCV table');
        end
    end

    function onRunExtraction()
        if isempty(datasets)
            uialert(fig,'Add at least one CSV first.','No data'); return
        end
        if ~readSettings(), return; end
        if any(~isfinite([datasets.T_C]))
            uialert(fig,'Every file needs a temperature. Edit the T (°C) column.','Missing temperature');
            return
        end
        dlg = uiprogressdlg(fig,'Title','Extracting','Message','Re-reading current sign...', ...
            'Indeterminate','on');
        cleanup = onCleanup(@() delete(dlg));
        try
            for k = 1:numel(datasets)       % current-sign setting may have changed
                datasets(k) = applyCurrentSign(datasets(k), opts);
            end
            dlg.Message = 'Fitting capacity, OCV, resistances, time constants, thermal...';
            [P, datasets] = extractParameters(datasets, opts);
        catch ME
            delete(dlg);
            uialert(fig, sprintf('%s\n\n(%s, line %d)', ME.message, ME.stack(1).name, ...
                ME.stack(1).line), 'Extraction failed');
            return
        end
        txtReport.Value = P.report;
        refreshColumnLists(false);
        drawDiag();
        setStatus(sprintf('Extraction done: %d temperature(s), %d SOC points, %d RC pair(s)', ...
            numel(P.T_vec), numel(P.SOC_vec), P.nRC));
    end

    function drawDiag()
        cla(axDiag,'reset'); styleAxes(axDiag);
        legend(axDiag,'off');
        if isempty(P), title(axDiag,'Run the extraction first'); return; end
        nT = numel(P.T_vec);
        cols = seriesColors(max(nT,1));
        hold(axDiag,'on');
        what = ddDiag.Value;
        leg = {};
        hs = [];
        switch what
            case {'OCV vs SOC','R0 vs SOC','R1 vs SOC','tau1 vs SOC','R2 vs SOC', ...
                  'tau2 vs SOC','R3 vs SOC','tau3 vs SOC'}
                [tbl, fld, scale, unit] = diagTable(what);
                if isempty(tbl)
                    title(axDiag, sprintf('%s: not available with %d RC pair(s)', what, P.nRC));
                    hold(axDiag,'off'); return
                end
                for j = 1:nT
                    pts = P.points(j).(fld);
                    if ~isempty(pts)
                        scatter(axDiag, pts(:,1), pts(:,2)*scale, 18, cols(j,:), 'filled', ...
                            'MarkerFaceAlpha',0.45,'HandleVisibility','off');
                    end
                    hs(end+1) = plot(axDiag, P.SOC_vec, tbl(:,j)*scale, '-o', 'Color', cols(j,:), ...
                        'LineWidth',1.6,'MarkerSize',4); %#ok<AGROW>
                    leg{end+1} = sprintf('%.1f °C', P.T_vec_C(j)); %#ok<AGROW>
                end
                xlabel(axDiag,'SOC (-)'); ylabel(axDiag, unit);
                title(axDiag, what);
            case 'SOC vs time'
                for k = 1:numel(datasets)
                    if isempty(datasets(k).soc), continue; end
                    hs(end+1) = plot(axDiag, (datasets(k).t - datasets(k).t(1))/3600, datasets(k).soc, ...
                        'LineWidth',1.2); %#ok<AGROW>
                    leg{end+1} = datasets(k).name; %#ok<AGROW>
                end
                xlabel(axDiag,'Test time (h)'); ylabel(axDiag,'SOC (-)'); title(axDiag,'Coulomb-counted SOC');
            case 'Thermal model fit'
                th = P.thermalFits;
                for k = 1:numel(th)
                    if isempty(th(k).t), continue; end
                    hs(end+1) = plot(axDiag, th(k).t/3600, th(k).Tmeas, '-', 'Color', cols(min(k,end),:), ...
                        'LineWidth',1); %#ok<AGROW>
                    leg{end+1} = sprintf('%s measured', th(k).name); %#ok<AGROW>
                    hs(end+1) = plot(axDiag, th(k).t/3600, th(k).Tmodel, '--', 'Color', cols(min(k,end),:)*0.7, ...
                        'LineWidth',1.4); %#ok<AGROW>
                    leg{end+1} = sprintf('%s model (rmse %.2f K)', th(k).name, th(k).rmse); %#ok<AGROW>
                end
                xlabel(axDiag,'Test time (h)'); ylabel(axDiag,'Cell temperature (°C)');
                title(axDiag, sprintf('Lumped thermal model: m*cp = %.4g J/K, h*A = %.4g W/K', ...
                    P.thermal_mass, P.hA));
            case 'Capacity vs temperature'
                hs = plot(axDiag, P.capacity.T_C, P.capacity.Ah, 'o-', 'LineWidth',1.6);
                leg = {'measured capacity'};
                yline(axDiag, P.AH, '--', sprintf('block AH = %.4g Ah', P.AH));
                xlabel(axDiag,'Temperature (°C)'); ylabel(axDiag,'Capacity (Ah)');
                title(axDiag,'Discharge capacity per test temperature');
        end
        if ~isempty(hs), legend(axDiag, hs, leg, 'Location','best','Interpreter','none'); end
        hold(axDiag,'off');
    end

    function [tbl, fld, scale, unit] = diagTable(what)
        tbl = []; scale = 1;
        switch what
            case 'OCV vs SOC', tbl = P.V0_mat; fld = 'ocv'; unit = 'OCV (V)';
            case 'R0 vs SOC',  tbl = P.R0_mat; fld = 'R0';  unit = 'R0 (mOhm)'; scale = 1000;
            otherwise
                k = str2double(what(regexp(what,'\d','once')));
                fld = sprintf('%s%d', regexprep(what,'\d.*',''), k);
                if strncmp(what,'tau',3), unit = sprintf('tau%d (s)',k);
                else, unit = sprintf('R%d (mOhm)',k); scale = 1000; end
                if k <= P.nRC
                    if strncmp(what,'tau',3), tbl = P.tau{k}; else, tbl = P.R{k}; end
                end
        end
    end

% =========================================================================
%  Export / twin tab
% =========================================================================
    function ok = needP()
        ok = ~isempty(P);
        if ~ok, uialert(fig,'Run the extraction first (Model extraction tab).','No parameters'); end
    end

    function onExportParams()
        if ~needP() || ~readSettings(), return; end
        names = exportToWorkspace(P, prof, opts);
        txtExport.Value = [{'Exported to base workspace:'}; strcat({'  '}, names(:)); ...
            {''}; P.blockHelp(:)];
        setStatus(sprintf('%d variables exported (prefix "%s")', numel(names), opts.prefix));
    end

    function onSaveMat()
        if ~needP() || ~readSettings(), return; end
        [f,p] = uiputfile('*.mat','Save battery parameters', fullfile(lastFolder,'batteryParams.mat'));
        figure(fig);
        if isequal(f,0), return; end
        S = workspaceVariables(P, prof, opts);
        save(fullfile(p,f), '-struct', 'S');
        setStatus(['Saved ' fullfile(p,f)]);
    end

    function onApplyToBlock()
        if ~needP() || ~readSettings(), return; end
        try
            blk = gcb;
            exportToWorkspace(P, prof, opts);
            applyToBlock(blk, P, opts);
            setStatus(['Parameters applied to ' strrep(blk, newline, ' ')]);
            uialert(fig, sprintf('Applied to:\n%s', strrep(blk,newline,' ')), 'Done', 'Icon','success');
        catch ME
            uialert(fig, ME.message, 'Could not apply to block');
        end
    end

    function onExportProfile()
        if isempty(datasets), uialert(fig,'Load data first.','No data'); return; end
        if ~readSettings(), return; end
        k = find(strcmp({datasets.name}, ddProfData.Value), 1);
        o = opts;
        if cbWindow.Value
            if ~strcmp(ddX.Value, 'Test Time (h)') && ~strcmp(ddX.Value, datasets(k).cols.time)
                uialert(fig,'The window option needs a time column on the Plot tab X axis.','X axis');
                return
            end
            xl = ax.XLim;
            if strcmp(ddX.Value,'Test Time (h)'), xl = xl*3600;
            else, xl = xl - datasets(k).t(1); end
            o.profileWindow = xl;
        end
        prof = extractProfile(datasets(k), o);
        names = exportToWorkspace(P, prof, o);
        txtExport.Value = [{sprintf('Load profile from "%s" (%.2f h, %d points)', datasets(k).name, ...
            prof.t(end)/3600, numel(prof.t))}; {''}; prof.help(:); {''}; ...
            {'Workspace variables:'}; strcat({'  '}, names(:))];
        setStatus('Load profile exported');
    end

    function onRunTwin()
        if ~needP() || ~readSettings(), return; end
        if isempty(prof)
            onExportProfile();
            if isempty(prof), return; end
        end
        dlg = uiprogressdlg(fig,'Title','Digital twin','Message','Building and simulating the model...', ...
            'Indeterminate','on');
        cleanup = onCleanup(@() delete(dlg));
        try
            twinRes = runTwin(P, prof, opts);
        catch ME
            delete(dlg);
            uialert(fig, sprintf('%s\n\n(%s, line %d)', ME.message, ME.stack(1).name, ME.stack(1).line), ...
                'Twin failed');
            return
        end
        % add the twin traces to the dataset so they can be viewed on the Plot tab
        k = find(strcmp({datasets.name}, prof.datasetName), 1);
        if ~isempty(k)
            datasets(k) = attachTwin(datasets(k), twinRes, prof);
            refreshColumnLists(false);
        end
        drawTwin();
        txtExport.Value = [twinRes.summary(:); {''}; prof.help(:)];
        setStatus(sprintf('Twin RMSE %.1f mV, max %.1f mV', twinRes.rmse_mV, twinRes.maxErr_mV));
    end

    function drawTwin()
        delete(axTwinV); delete(axTwinE);            % fresh axes (yyaxis state included)
        axTwinV = uiaxes(gTw); axTwinV.Layout.Row = 1; styleAxes(axTwinV);
        axTwinE = uiaxes(gTw); axTwinE.Layout.Row = 2; styleAxes(axTwinE);
        r2 = twinRes;
        th = r2.t/3600;
        plot(axTwinV, th, r2.Vmeas, '-', 'Color',[0.2 0.2 0.2], 'LineWidth',1.2, 'DisplayName','measured');
        hold(axTwinV,'on');
        plot(axTwinV, th, r2.Vsim, '--', 'Color',[0.85 0.33 0.1], 'LineWidth',1.2, 'DisplayName','twin');
        hold(axTwinV,'off');
        legend(axTwinV,'Location','best'); ylabel(axTwinV,'Voltage (V)'); xlabel(axTwinV,'Time (h)');
        title(axTwinV, sprintf('Terminal voltage - RMSE %.1f mV, max |err| %.1f mV', r2.rmse_mV, r2.maxErr_mV));
        yyaxis(axTwinE,'left');
        eV = 1000*(r2.Vsim - r2.Vmeas);
        plot(axTwinE, th, eV, '-', 'LineWidth',1);
        lim = max(5, 1.1*max(abs(eV(isfinite(eV)))));
        axTwinE.YAxis(1).Limits = [-lim lim];
        ylabel(axTwinE,'V twin - V meas (mV)');
        yyaxis(axTwinE,'right');
        plot(axTwinE, th, r2.TsimC, '--', 'LineWidth',1.2); hold(axTwinE,'on');
        if any(isfinite(r2.TmeasC)), plot(axTwinE, th, r2.TmeasC, '-', 'LineWidth',1); end
        hold(axTwinE,'off');
        ylabel(axTwinE,'Cell temperature (°C)'); xlabel(axTwinE,'Time (h)');
        legend(axTwinE, {'voltage error','T twin','T measured'}, 'Location','best');
        title(axTwinE,'Error and temperature');
    end

    function onOpenModel()
        mdl = matlab.lang.makeValidName(strtrim(efModel.Value));
        try
            if ~bdIsLoaded(mdl)
                f = fullfile(opts.modelDir, [mdl '.slx']);
                if ~isfile(f), uialert(fig,'Build the twin first.','No model'); return; end
                load_system(f);
            end
            open_system(mdl);
        catch ME
            uialert(fig, ME.message, 'Open model');
        end
    end
end

% ---------------- small GUI utilities (non-nested) -----------------------
function styleAxes(a)
a.FontName = 'Segoe UI'; a.FontSize = 11; a.Box = 'on';
grid(a,'on'); a.GridAlpha = 0.12;
a.Title.FontWeight = 'bold';
end

function c = seriesColors(n)
base = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56;
        0.93 0.69 0.13; 0.30 0.75 0.93; 0.64 0.08 0.18; 0.25 0.25 0.25];
c = base(mod(0:max(n,1)-1, size(base,1)) + 1, :);
end

function s = fmtNum(v)
if ~isfinite(v), s = 'NaN'; return; end
a = abs(v);
if a == 0, s = '0';
elseif a >= 1e5 || a < 1e-3, s = sprintf('%.4g', v);
elseif a >= 100, s = sprintf('%.1f', v);
elseif a >= 1, s = sprintf('%.4f', v);
else, s = sprintf('%.4g', v);
end
end

function v = numOr(str, dflt)
v = str2double(str);
if ~isfinite(v), v = dflt; end
end

function c = pickCol(cols, prefs)
c = cols{1};
for k = 1:numel(prefs)
    j = find(strncmpi(cols, prefs{k}, numel(prefs{k})), 1);
    if ~isempty(j), c = cols{j}; return; end
end
end

function cols = numericColumns(T)
v = T.Properties.VariableNames;
keep = false(size(v));
for k = 1:numel(v)
    x = T.(v{k});
    keep(k) = (isnumeric(x) || islogical(x)) && isvector(x) && any(isfinite(double(x)));
end
cols = v(keep);
% put the most useful columns first
pri = {'Test Time (h)','TestTime (s)','Voltage (V)','Current, +discharge (A)','Current (A)', ...
       'SOC (-)','Temp 1','Chamber Temperature (C)','V twin (V)','V error (mV)'};
[tf, loc] = ismember(pri, cols);
first = cols(loc(tf));
cols = [first, setdiff(cols, first, 'stable')];
end

function [xv, yv] = interpMono(x, y, xc)
% value of a curve with non-decreasing X at xc (linear between samples)
n = numel(x);
k = find(x <= xc, 1, 'last');
if isempty(k), k = 1; end
if k >= n || x(k+1) <= x(k)
    xv = x(k); yv = y(k);
    if k < n && abs(x(k+1) - xc) < abs(x(k) - xc), xv = x(k+1); yv = y(k+1); end
    return
end
f = (xc - x(k)) / (x(k+1) - x(k));
xv = xc;
yv = y(k) + f*(y(k+1) - y(k));
if ~isfinite(yv)          % gap in the data: fall back to the nearest real sample
    if f < 0.5, yv = y(k); xv = x(k); else, yv = y(k+1); xv = x(k+1); end
end
end

function n = shortName(f)
[~, n, e] = fileparts(f); n = [n e];
end

% ======================================================================
%  SECTION 3 - Data import
% ======================================================================
function d = emptyDatasets()
d = struct('name',{},'file',{},'tbl',{},'cols',{},'t',{},'V',{},'I',{},'Iraw',{}, ...
    'state',{},'step',{},'stepTime',{},'Tcell',{},'Tch',{},'T_C',{},'dtMedian',{}, ...
    'signNote',{},'warn',{},'soc',{},'phases',{},'restThr',{});
end

function dsArr = asDatasets(x, o)
if isstruct(x), dsArr = x; return; end
dsArr = loadDatasets(cellstr(x), o);
end

function dsArr = loadDatasets(files, o)
dsArr = emptyDatasets();
for k = 1:numel(files)
    dsArr(end+1) = loadDataset(files{k}, o); %#ok<AGROW>
end
end

function d = loadDataset(file, o)
% Read one cycler CSV and normalise it into a dataset struct.
if ~isfile(file), error('File not found: %s', file); end
io = detectImportOptions(file, 'VariableNamingRule','preserve');
textVars = io.VariableNames(ismember(io.VariableTypes, {'char','datetime'}));
if ~isempty(textVars), io = setvaropts(io, textVars, 'Type','string'); end
T = readtable(file, io);
if height(T) < 3, error('File has fewer than 3 data rows.'); end

d = emptyDatasets();
d(1).name = shortName(file);
d.file = file;
d.warn = {};
names = T.Properties.VariableNames;
c.time     = findCol(names, {'testtimes','testtime','totaltime','runtime','time'}, {'step','date'});
c.stepTime = findCol(names, {'steptimes','steptime'}, {});
c.step     = findCol(names, {'step','stepindex','stepnumber','stepno'}, {'time'}, true);
c.current  = findCol(names, {'currenta','current','amps','i'}, {}, false);
c.voltage  = findCol(names, {'voltagev','voltage','volts','v'}, {}, false);
c.state    = findCol(names, {'state','md','mode'}, {}, true);
c.tcell    = findCol(names, {'temp1','celltemp','temperature1','auxtemp1','temp'}, {'chamber'});
c.tch      = findCol(names, {'chambertemperaturec','chambertemperature','chamber'}, {});
c.datetime = findCol(names, {'datetime','date'}, {});
if isempty(c.current) || isempty(c.voltage)
    error('Could not find Current and Voltage columns. Columns found: %s', strjoin(names, ', '));
end

% --- time -----------------------------------------------------------------
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
if nnz(~good) > 0
    d.warn{end+1} = sprintf('%d rows with missing time/V/I dropped', nnz(~good));
end
T = T(good,:); t = t(good); V = V(good); Iraw = Iraw(good);
% enforce non-decreasing time (cyclers occasionally repeat a stamp)
if any(diff(t) < 0)
    [t, ord] = sort(t); T = T(ord,:); V = V(ord); Iraw = Iraw(ord);
    d.warn{end+1} = 'time column was not monotonic - rows were sorted';
end

d.t = t; d.V = V; d.Iraw = Iraw;
d.step = []; d.stepTime = []; d.state = '';
if ~isempty(c.step), d.step = toNum(T.(c.step)); end
if ~isempty(c.stepTime), d.stepTime = toSeconds(T.(c.stepTime)); end
if ~isempty(c.state)
    s = string(T.(c.state)); s(ismissing(s)) = "";
    s = upper(strtrim(s));
    first = extractBefore(s + " ", 2);
    d.state = char(first);
end
d.Tcell = nan(size(t)); d.Tch = nan(size(t));
if ~isempty(c.tcell), d.Tcell = toNum(T.(c.tcell)); end
if ~isempty(c.tch),   d.Tch   = toNum(T.(c.tch));   end
d.cols = c;
d.dtMedian = median(diff(t));

% --- test temperature label ---------------------------------------------------
if any(isfinite(d.Tch))
    d.T_C = round(median(d.Tch(isfinite(d.Tch)))*10)/10;
elseif any(isfinite(d.Tcell))
    d.T_C = round(median(d.Tcell(isfinite(d.Tcell)))*10)/10;
    d.warn{end+1} = 'no chamber column: temperature label taken from the cell sensor';
else
    tok = regexp(d.name, '(-?\d+(\.\d+)?)\s*(C|degC|°C)', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok), d.T_C = str2double(tok{1}); else, d.T_C = NaN; end
    d.warn{end+1} = 'no temperature columns: enter T (°C) in the file table';
end

d.tbl = T;
d.soc = []; d.phases = [];
d = applyCurrentSign(d, o);
end

function d = applyCurrentSign(d, o)
% Builds d.I (A, positive = DISCHARGE) from the raw current, the State
% column and the user's sign setting, then (re)builds the derived columns.
Iraw = d.Iraw;
thr = o.restCurrentA;
if ~isfinite(thr), thr = max(2e-3, 0.002*max(abs(Iraw))); end
d.restThr = thr;
st = d.state;
hasState = ~isempty(st) && any(st == 'C' | st == 'D');
switch o.currentSign
    case 'charge+',    I = -Iraw; note = 'positive = charge (setting)';
    case 'discharge+', I =  Iraw; note = 'positive = discharge (setting)';
    otherwise
        if hasState
            isC = st(:) == 'C'; isD = st(:) == 'D';
            mC = median(Iraw(isC & abs(Iraw) > thr)); mD = median(Iraw(isD & abs(Iraw) > thr));
            if any(Iraw < -thr) && (isnan(mD) || mD < 0) && (isnan(mC) || mC > 0)
                I = -Iraw; note = 'signed, positive = charge (from State)';
            elseif any(Iraw < -thr) && (isnan(mD) || mD > 0) && (isnan(mC) || mC < 0)
                I = Iraw;  note = 'signed, positive = discharge (from State)';
            else
                I = abs(Iraw); I(isC) = -I(isC);
                I(~isC & ~isD) = Iraw(~isC & ~isD);     % rests / other steps keep raw value
                note = 'magnitude only, sign from State column';
            end
        else
            % no State column: positive current should RAISE voltage if it is charge
            dv = gradient(d.V) ./ max(gradient(d.t), eps);
            m = abs(Iraw) > thr;
            if sum(Iraw(m) .* dv(m)) > 0
                I = -Iraw; note = 'positive = charge (inferred from dV/dt)';
            else
                I = Iraw;  note = 'positive = discharge (inferred from dV/dt)';
            end
        end
end
if hasState
    I(d.state(:) == 'R') = 0;
end
I(abs(I) < thr) = 0;
d.I = I;
d.signNote = note;

% --- derived columns for plotting ---------------------------------------------
T = d.tbl;
T.('Test Time (h)') = (d.t - d.t(1))/3600;
T.('Current, +discharge (A)') = d.I;
T.('Power, +discharge (W)') = d.I .* d.V;
code = zeros(size(d.I)); code(d.I < 0) = 1; code(d.I > 0) = -1;
T.('State code (C=1 R=0 D=-1)') = code;
% zero-order hold: a sample's current applies until the next sample. This is
% how cyclers log step starts and it is exactly what the exported profile
% reproduces, so data SOC and twin SOC stay consistent.
T.('Ah discharged, cumulative') = [0; cumsum(d.I(1:end-1).*diff(d.t))]/3600;
d.tbl = T;
end

function name = findCol(names, patterns, exclude, exact)
% loose header matching: case/space/punctuation-insensitive
if nargin < 4, exact = false; end
key = lower(regexprep(names, '[^a-zA-Z0-9]', ''));
name = '';
for p = 1:numel(patterns)
    if exact
        hit = strcmp(key, patterns{p});
    else
        hit = strcmp(key, patterns{p});
        if ~any(hit) && numel(patterns{p}) > 1, hit = startsWith(key, patterns{p}); end
        if ~any(hit) && numel(patterns{p}) > 3, hit = contains(key, patterns{p}); end
    end
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

% ======================================================================
%  SECTION 4 - Step / phase segmentation
% ======================================================================
function ph = findPhases(d)
% A phase is a run of samples with the same mode: 'C' charge, 'D' discharge,
% 'R' rest. Consecutive cycler steps of the same mode (e.g. CC then CV) merge.
I = d.I;
mode = repmat('R', numel(I), 1);
mode(I > 0) = 'D'; mode(I < 0) = 'C';
brk = [true; mode(2:end) ~= mode(1:end-1)];
i1 = find(brk); i2 = [i1(2:end)-1; numel(I)];
n = numel(i1);
ph = struct('i1',num2cell(i1),'i2',num2cell(i2),'type',num2cell(mode(i1)));
ah = d.tbl.('Ah discharged, cumulative');
for k = 1:n
    a = i1(k); b = i2(k);
    ph(k).t1 = d.t(a); ph(k).t2 = d.t(b);
    if b < numel(I), ph(k).t2 = d.t(b+1); end
    ph(k).dur = ph(k).t2 - ph(k).t1;
    ph(k).Imean = mean(I(a:b));
    ph(k).Imax = max(abs(I(a:b)));
    ph(k).Iend = I(b);
    ph(k).ah = ah(b) - ah(a);
    ph(k).Vmin = min(d.V(a:b)); ph(k).Vmax = max(d.V(a:b));
end
end

% ======================================================================
%  SECTION 5 - Capacity and SOC
% ======================================================================
function [isCV, Vcv] = cvPhases(d, ph)
% A charge phase ends in a constant-voltage hold when its current has tapered
% to < 35 % of its maximum while the voltage over that taper stayed flat.
isCV = false(numel(ph),1); Vcv = nan(numel(ph),1);
for k = 1:numel(ph)
    if ph(k).type ~= 'C' || abs(ph(k).Iend) > 0.35*ph(k).Imax, continue; end
    idx = ph(k).i1:ph(k).i2;
    taper = idx(abs(d.I(idx)) < 0.9*ph(k).Imax);   % samples after the CC part
    if numel(taper) < 3, continue; end
    v = d.V(taper);
    if max(v) - min(v) < 0.015
        isCV(k) = true; Vcv(k) = median(v);
    end
end
end

function [cap, info] = capacityFromData(d, ph, Vmax, Vmin, vTol)
% Discharged Ah between a FULL point (end of a CC-CV charge) and the next
% EMPTY point (discharge reaching Vmin). Lowest-rate candidate wins.
ah = d.tbl.('Ah discharged, cumulative');
isFull = false(numel(ph),1); isEmpty = false(numel(ph),1);
[isCV, Vcv] = cvPhases(d, ph);
for k = 1:numel(ph)
    if ph(k).type == 'C'
        isFull(k) = isCV(k) && Vcv(k) >= Vmax - vTol;
    elseif ph(k).type == 'D'
        isEmpty(k) = ph(k).Vmin <= Vmin + vTol;
    end
end
cand = [];
for e = find(isEmpty)'
    f = find(isFull(1:e-1), 1, 'last');
    if isempty(f), continue; end
    a = ph(f).i2; b = ph(e).i2;
    capAh = ah(b) - ah(a);
    idx = a:b; idx = idx(d.I(idx) > 0);
    rate = mean(d.I(idx));
    cand(end+1,:) = [capAh, rate, a, b]; %#ok<AGROW>
end
info.fullIdx  = arrayfun(@(p) p.i2, ph(isFull));
info.emptyIdx = arrayfun(@(p) p.i2, ph(isEmpty));
info.candidates = cand;
if isempty(cand)
    cap = NaN; info.rateA = NaN;
else
    [~, j] = min(cand(:,2));
    cap = cand(j,1); info.rateA = cand(j,2);
end
end

function soc = socFromAnchors(d, info, capAh, initialSOC)
% Coulomb counting, re-anchored to SOC = 1 at every full charge.
ah = d.tbl.('Ah discharged, cumulative');
n = numel(ah);
soc = nan(n,1);
if ~isempty(info.fullIdx)
    f = sort(info.fullIdx(:));
    soc(1:f(1)) = 1 - (ah(1:f(1)) - ah(f(1)))/capAh;
    for k = 1:numel(f)
        a = f(k);
        if k < numel(f), b = f(k+1); else, b = n; end
        soc(a:b) = 1 - (ah(a:b) - ah(a))/capAh;
    end
elseif ~isempty(info.emptyIdx)
    e = info.emptyIdx(1);
    soc = (ah(e) - ah)/capAh;
else
    soc = initialSOC - ah/capAh;
end
end

% ======================================================================
%  SECTION 6 - Resistance and relaxation (RC) analysis
% ======================================================================
function pts = r0FromEdges(d, soc, maxDt)
% Instantaneous resistance at every current step: R0 = -dV/dI
I = d.I; V = d.V; t = d.t;
dI = diff(I); dV = diff(V); dt = diff(t);
thr = max(0.05*max(abs(I)), 10*d.restThr);
k = find(abs(dI) > thr & dt <= maxDt & dt > 0);
R = -dV(k)./dI(k);
ok = R > 0 & R < 1;
pts = [soc(k(ok)), R(ok)];
end

function fits = fitRelaxations(d, soc, ph, o, AH)
% Fit every long rest that follows a current pulse:
%   V(t) = Vinf - sum_k R_k * x_k(t_sw) * exp(-(t - t_sw)/tau_k)
% where x_k(t_sw) is the RC branch current at the switch instant, obtained by
% passing the real current history through a first-order filter with tau_k.
% Vinf is the relaxed (open-circuit) voltage -> OCV point at that SOC.
fits = struct('soc',{},'Vinf',{},'R',{},'tau',{},'rmse',{},'Iprev',{},'t0',{},'dur',{});
t = d.t; I = d.I; V = d.V;
for k = 2:numel(ph)
    r = ph(k);
    if r.type ~= 'R' || r.dur < o.minRestS, continue; end
    prev = ph(k-1);
    if prev.type == 'R' || abs(prev.ah) < 0.002*AH, continue; end
    a = r.i1; b = r.i2;
    tsw = t(a);
    if ~isempty(d.stepTime) && isfinite(d.stepTime(a)) && d.stepTime(a) < (t(a) - t(a-1))
        tsw = t(a) - d.stepTime(a);               % exact switch time from StepTime
    end
    tsw = max(tsw, t(a-1));
    tr = t(a:b) - tsw; v = V(a:b);
    keep = tr <= min(r.dur, 8*o.tauMax);
    tr = tr(keep); v = v(keep);
    if numel(tr) < 3*o.nRC + 4, continue; end
    tauHi = min(o.tauMax, max(r.dur/1.5, 3*o.tauMin));
    f = fitOneRelaxation(t, I, tsw, tr, v, o.nRC, o.tauMin, tauHi, o.tauMax);
    if isempty(f) || f.rmse > o.maxFitRmse, continue; end
    f.soc = soc(a);
    f.Iprev = prev.Imean;
    f.t0 = tsw; f.dur = r.dur;
    fits(end+1) = f; %#ok<AGROW>
end
end

function f = fitOneRelaxation(t, I, tsw, tr, v, nRC, tauLo, tauHi, tauHist)
f = [];
% current history on a uniform grid just before the switch (zero-order hold)
dtw = min(max(median(diff(t)), 0.5), 5);
win = min(10*tauHist, tsw - t(1));
nW = floor(win/dtw);
if nW < 5, return; end
tw = tsw - (nW:-1:1)'*dtw;
Iw = zohSample(t, I, tw);

lo = log(tauLo); hi = log(tauHi);
toTau = @(z) exp(lo + (hi - lo)./(1 + exp(-z)));
obj = @(z) relaxSSE(toTau(z));

% coarse grid search for a good start, then Nelder-Mead
nG = [40 16 9]; nG = nG(nRC);
g = linspace(lo, hi, nG);
best = inf; bestTau = [];
switch nRC
    case 1
        for i = 1:nG
            e = relaxSSE(exp(g(i))); if e < best, best = e; bestTau = exp(g(i)); end
        end
    case 2
        for i = 1:nG
            for j = i+2:nG
                e = relaxSSE(exp(g([i j])));
                if e < best, best = e; bestTau = exp(g([i j])); end
            end
        end
    case 3
        for i = 1:nG
            for j = i+2:nG
                for m = j+2:nG
                    e = relaxSSE(exp(g([i j m])));
                    if e < best, best = e; bestTau = exp(g([i j m])); end
                end
            end
        end
end
if isempty(bestTau), return; end
fr = (log(bestTau) - lo)/(hi - lo);
fr = min(max(fr, 0.02), 0.98);
z0 = -log(1./fr - 1);
z = fminsearch(obj, z0, optimset('Display','off','MaxFunEvals',600,'MaxIter',400,'TolX',1e-4));
tau = toTau(z);
[sse, c] = relaxSSE(tau);
[tau, ord] = sort(tau);
R = c(2:end); R = R(ord);
R(R <= 0) = NaN;                 % pair not identifiable from this rest
tau(isnan(R)) = NaN;
f.Vinf = c(1); f.R = R(:)'; f.tau = tau(:)';
f.rmse = sqrt(sse/numel(v));
f.soc = NaN; f.Iprev = NaN; f.t0 = NaN; f.dur = NaN;

    function [sse, c] = relaxSSE(tau)
        A = ones(numel(tr), 1 + numel(tau));
        for q = 1:numel(tau)
            aq = exp(-dtw/tau(q));
            w = aq.^((nW-1):-1:0)';
            x0 = (1 - aq) * (w' * Iw);         % RC branch current at the switch
            A(:,q+1) = -x0 * exp(-tr/tau(q));
        end
        [c, sse] = lsqNonnegTail(A, v);
    end
end

function [c, sse] = lsqNonnegTail(A, y)
% least squares with c(2:end) >= 0 (c(1) free) by checking every active set
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

% ======================================================================
%  SECTION 7 - Gridding scattered points onto the SOC breakpoints
% ======================================================================
function [col, prov] = gridPoints(pts, g, fallback)
% pts = [soc value]. For each breakpoint take the median of the points in its
% neighbourhood; fill gaps by interpolation (I) / end extrapolation (E) /
% fallback value (D). prov: M measured, I interpolated, E extrapolated, D datasheet, - none
n = numel(g);
col = nan(n,1); prov = repmat('-', n, 1);
if ~isempty(pts)
    pts = pts(all(isfinite(pts),2),:);
end
if ~isempty(pts)
    edges = [g(1) - 1e-9, (g(1:end-1) + g(2:end))/2, g(end) + 1e-9];
    s = min(max(pts(:,1), g(1)), g(end));
    for j = 1:n
        m = s >= edges(j) & s <= edges(j+1);
        if any(m), col(j) = median(pts(m,2)); prov(j) = 'M'; end
    end
end
have = isfinite(col);
if nnz(have) >= 2
    gi = g(have); ci = col(have);
    inside = ~have(:) & g(:) > gi(1) & g(:) < gi(end);
    col(inside) = interp1(gi, ci, g(inside), 'linear');
    prov(inside) = 'I';
    lo = ~have(:) & g(:) < gi(1);  col(lo) = ci(1);   prov(lo) = 'E';
    hi = ~have(:) & g(:) > gi(end); col(hi) = ci(end); prov(hi) = 'E';
elseif nnz(have) == 1
    col(~have) = col(have); prov(~have) = 'E';
elseif nargin > 2 && isfinite(fallback)
    col(:) = fallback; prov(:) = 'D';
end
end

function [ocv, prov] = buildOcv(restPts, densePts, g, dsTable)
% OCV(SOC) on the breakpoints g.
%   restPts  [soc Vinf] relaxed voltages (most trusted)
%   densePts [soc ocv]  IR/RC-corrected low-rate curve (fills gaps between rests)
%   dsTable  [soc ocv]  datasheet curve (last resort)
n = numel(g);
ocv = nan(n,1); prov = repmat('-', n, 1);
g = g(:);
% cluster rest points that sit at the same SOC (charge + discharge side -> average)
if ~isempty(restPts)
    restPts = sortrows(restPts(all(isfinite(restPts),2),:));
    cl = cumsum([true; diff(restPts(:,1)) > 0.01]);
    restPts = [accumarray(cl, restPts(:,1), [], @mean), accumarray(cl, restPts(:,2), [], @mean)];
end
dense = [];
if ~isempty(densePts) && size(densePts,1) > 10
    dense = sortrows(densePts(all(isfinite(densePts),2),:));
end
if ~isempty(dense) && ~isempty(restPts)
    % shape from the dense curve, absolute level from the rests: the offset
    % (dense - rest) is interpolated linearly between neighbouring rests
    denseAt = @(x) interp1(dense(:,1), dense(:,2), x, 'linear', NaN);
    sr = restPts(:,1); vr = restPts(:,2);
    off = denseAt(sr) - vr;
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
    % rest points alone (pchip) where the dense curve does not reach
    sr = restPts(:,1); vr = restPts(:,2);
    for j = 1:n
        if isfinite(ocv(j)), continue; end
        if g(j) >= sr(1) - 0.02 && g(j) <= sr(end) + 0.02
            k = find(sr >= g(j), 1);
            if isempty(k), k = numel(sr); end
            km = max(k-1, 1);
            if min(abs(sr - g(j))) < 0.02 || sr(k) - sr(km) <= 0.21
                ocv(j) = interp1(sr, vr, min(max(g(j), sr(1)), sr(end)), 'pchip');
                if min(abs(sr - g(j))) <= 0.02, prov(j) = 'M'; else, prov(j) = 'I'; end
            end
        end
    end
elseif isempty(restPts) && ~isempty(dense)
    in = g >= dense(1,1) & g <= dense(end,1);
    ocv(in) = interp1(dense(:,1), dense(:,2), g(in));
    prov(in) = 'I';
end
% datasheet curve for anything still missing
if any(~isfinite(ocv)) && ~isempty(dsTable)
    miss = ~isfinite(ocv);
    ocv(miss) = interp1(dsTable(:,1), dsTable(:,2), g(miss), 'pchip', 'extrap');
    prov(miss) = 'D';
end
% end extrapolation with the nearest slope
have = find(isfinite(ocv));
if numel(have) >= 2
    for j = 1:n
        if isfinite(ocv(j)), continue; end
        if j < have(1)
            a = have(1); b = have(2);
        else
            a = have(end-1); b = have(end);
        end
        ocv(j) = ocv(a) + (ocv(b) - ocv(a))/(g(b) - g(a))*(g(j) - g(a));
        prov(j) = 'E';
    end
end
% OCV must rise with SOC
for j = 2:n
    if ocv(j) <= ocv(j-1), ocv(j) = ocv(j-1) + 1e-4; end
end
end

% ======================================================================
%  SECTION 8 - The extraction pipeline
% ======================================================================
function [P, dsArr] = extractParameters(dsArr, o)
if isempty(dsArr), error('No datasets.'); end
if any(~isfinite([dsArr.T_C]))
    error('Every dataset needs a temperature (T_C).');
end
o.nRC = max(1, min(3, round(o.nRC)));
g = o.socGrid(:)';
rep = {};
rep{end+1} = sprintf('Battery (Table-Based) parameter extraction  -  %s', ...
    char(datetime('now','Format','yyyy-MM-dd HH:mm')));
rep{end+1} = repmat('=', 1, 78);

% ---- 1. voltage limits ---------------------------------------------------------
nD = numel(dsArr);
allV = vertcat(dsArr.V);
VcvAll = [];
for k = 1:nD
    dsArr(k).phases = findPhases(dsArr(k));
    [~, vc] = cvPhases(dsArr(k), dsArr(k).phases);
    VcvAll = [VcvAll; vc(isfinite(vc))]; %#ok<AGROW>
end
Vmax = o.ds.Vmax; srcVmax = 'datasheet';
if ~isfinite(Vmax) && ~isempty(VcvAll)
    Vmax = max(VcvAll); srcVmax = sprintf('CV hold voltage of %d CC-CV charge(s)', numel(VcvAll));
elseif ~isfinite(Vmax)
    Vmax = max(allV); srcVmax = 'highest measured voltage (no CV hold found)';
end
Vmin = o.ds.Vmin; srcVmin = 'datasheet';
if ~isfinite(Vmin), Vmin = min(allV); srcVmin = 'lowest measured voltage'; end
rep{end+1} = sprintf('Voltage window: %.3f V (%s) .. %.3f V (%s)', Vmin, srcVmin, Vmax, srcVmax);

% ---- 2. capacity per file -------------------------------------------------------------
capD = nan(nD,1); rateD = nan(nD,1); infos = cell(nD,1);
for k = 1:nD
    [capD(k), infos{k}] = capacityFromData(dsArr(k), dsArr(k).phases, Vmax, Vmin, o.vTol);
    rateD(k) = infos{k}.rateA;
end
rep{end+1} = '';
rep{end+1} = 'CAPACITY (full charge -> discharge to Vmin, lowest-rate discharge in each file)';
for k = 1:nD
    if isfinite(capD(k))
        rep{end+1} = sprintf('  %-34s %6.1f °C  %.4f Ah at %.3g A  (%d full / %d empty points)', ...
            dsArr(k).name, dsArr(k).T_C, capD(k), rateD(k), numel(infos{k}.fullIdx), numel(infos{k}.emptyIdx)); %#ok<AGROW>
    else
        rep{end+1} = sprintf('  %-34s %6.1f °C  no complete full->empty discharge found', ...
            dsArr(k).name, dsArr(k).T_C); %#ok<AGROW>
    end
end
% block AH (scalar)
[~, iRef] = min(abs([dsArr.T_C] - o.refTempC) + 1e6*~isfinite(capD'));
if o.ds.preferCapacity && isfinite(o.ds.capacityAh)
    AH = o.ds.capacityAh; srcAH = 'datasheet (preferred)';
elseif any(isfinite(capD))
    AH = capD(iRef); srcAH = sprintf('measured, %s at %.1f °C', dsArr(iRef).name, dsArr(iRef).T_C);
elseif isfinite(o.ds.capacityAh)
    AH = o.ds.capacityAh; srcAH = 'datasheet (no full discharge in the data)';
else
    ah = arrayfun(@(d) max(d.tbl.('Ah discharged, cumulative')) - min(d.tbl.('Ah discharged, cumulative')), dsArr);
    AH = max(ah); srcAH = 'ESTIMATE: largest Ah swing in the data (enter a datasheet capacity!)';
end
rep{end+1} = sprintf('  -> block AH = %.4f Ah  [%s]', AH, srcAH);

% ---- 3. SOC per file ------------------------------------------------------------------
for k = 1:nD
    capK = AH;
    if strcmp(o.socBasis, 'perTemperature') && isfinite(capD(k)), capK = capD(k); end
    s0 = o.initialSOC;
    if isempty(infos{k}.fullIdx) && isempty(infos{k}.emptyIdx)
        if ~isfinite(s0)
            s0 = 1;
            rep{end+1} = sprintf('  ! %s: no full/empty anchor, initial SOC assumed 1.0', dsArr(k).name); %#ok<AGROW>
        end
    end
    dsArr(k).soc = socFromAnchors(dsArr(k), infos{k}, capK, s0);
    dsArr(k).tbl.('SOC (-)') = dsArr(k).soc;
end

% ---- 4. temperature groups --------------------------------------------------------------
Tlab = [dsArr.T_C];
Tg = [];
grp = zeros(nD,1);
for k = 1:nD
    j = find(abs(Tg - Tlab(k)) < 1, 1);
    if isempty(j), Tg(end+1) = Tlab(k); j = numel(Tg); end %#ok<AGROW>
    grp(k) = j;
end
[Tg, ord] = sort(Tg);
[~, inv] = sort(ord); grp = inv(grp);
nT = numel(Tg);
nS = numel(g);
R0 = nan(nS,nT); V0 = nan(nS,nT);
Rk = repmat({nan(nS,nT)}, 1, o.nRC); Tk = Rk;
prov.V0 = repmat(' ', nS, nT); prov.R0 = prov.V0;
prov.R = repmat({prov.V0}, 1, o.nRC); prov.tau = prov.R;
pointsTmpl = struct('ocv',[],'ocvDense',[],'R0',[],'R1',[],'tau1',[],'R2',[],'tau2',[],'R3',[],'tau3',[]);
points = repmat(pointsTmpl, 1, nT);
nFitAll = zeros(1,nT); nEdgeAll = zeros(1,nT);
rep{end+1} = '';
rep{end+1} = sprintf('PER-TEMPERATURE FITS  (%d RC pair(s), rests >= %g s, tau in [%g, %g] s)', ...
    o.nRC, o.minRestS, o.tauMin, o.tauMax);
for j = 1:nT
    members = find(grp == j)';
    % --- R0 from steps, RC + OCV points from rests
    for k = members
        pe = r0FromEdges(dsArr(k), dsArr(k).soc, o.maxEdgeDt);
        points(j).R0 = [points(j).R0; pe];
        fits = fitRelaxations(dsArr(k), dsArr(k).soc, dsArr(k).phases, o, AH);
        nFitAll(j) = nFitAll(j) + numel(fits);
        for f = fits
            points(j).ocv = [points(j).ocv; f.soc, f.Vinf];
            for q = 1:o.nRC
                points(j).(sprintf('R%d',q))   = [points(j).(sprintf('R%d',q));   f.soc, f.R(q)];
                points(j).(sprintf('tau%d',q)) = [points(j).(sprintf('tau%d',q)); f.soc, f.tau(q)];
            end
        end
    end
    nEdgeAll(j) = size(points(j).R0,1);
    [R0(:,j), prov.R0(:,j)] = gridPoints(points(j).R0, g, o.ds.R0);
    for q = 1:o.nRC
        [Rk{q}(:,j),  prov.R{q}(:,j)]   = gridPoints(points(j).(sprintf('R%d',q)), g, NaN);
        [Tk{q}(:,j),  prov.tau{q}(:,j)] = gridPoints(points(j).(sprintf('tau%d',q)), g, NaN);
    end
end
% fill parameters that were not measured at all at some temperature from the
% nearest temperature that has them (provenance 'T')
[R0, prov.R0] = fillAcrossT(R0, prov.R0, Tg);
for q = 1:o.nRC
    [Rk{q}, prov.R{q}]   = fillAcrossT(Rk{q}, prov.R{q}, Tg);
    [Tk{q}, prov.tau{q}] = fillAcrossT(Tk{q}, prov.tau{q}, Tg);
end
% anything still empty: R -> small default, tau -> geometric spread (flagged 'A' = assumed)
for q = 1:o.nRC
    miss = ~isfinite(Rk{q});
    if any(miss(:))
        base = R0; base(~isfinite(base)) = 0.01;
        Rk{q}(miss) = 0.3*base(miss); prov.R{q}(miss) = 'A';
    end
    miss = ~isfinite(Tk{q});
    if any(miss(:))
        Tk{q}(miss) = exp(log(o.tauMin) + (log(o.tauMax) - log(o.tauMin))*q/(o.nRC+1));
        prov.tau{q}(miss) = 'A';
    end
end
miss = ~isfinite(R0);
if any(miss(:)), R0(miss) = 0.01; prov.R0(miss) = 'A'; end

% --- OCV: rests + dense low-rate curve corrected with the fitted R0/RC
for j = 1:nT
    members = find(grp == j)';
    dense = [];
    for k = members
        dense = [dense; denseOcvPoints(dsArr(k), g, R0(:,j), Rk, Tk, j, o, AH)]; %#ok<AGROW>
    end
    points(j).ocvDense = dense;
    [V0(:,j), prov.V0(:,j)] = buildOcv(points(j).ocv, dense, g, o.ds.ocvTable);
end
[V0, prov.V0] = fillAcrossT(V0, prov.V0, Tg);
if any(~isfinite(V0(:)))
    error(['Could not build an OCV curve: no rests >= %g s, no low-rate CC data and no ' ...
           'datasheet OCV table. Lower "Min rest" or load a datasheet OCV table.'], o.minRestS);
end
for j = 1:nT
    rep{end+1} = sprintf('  %6.1f °C : %d step edges for R0, %d relaxation fits, %d dense OCV points', ...
        Tg(j), nEdgeAll(j), nFitAll(j), size(points(j).ocvDense,1)); %#ok<AGROW>
end

% ---- 5. thermal ---------------------------------------------------------------------------
thermalFits = [];
for k = 1:nD
    th = fitThermal(dsArr(k), g, R0(:, grp(k)), Rk, Tk, grp(k));
    th.name = dsArr(k).name;
    if isempty(thermalFits), thermalFits = th; else, thermalFits(end+1) = th; end %#ok<AGROW>
end
okTh = [thermalFits.ok];
mcpMeas = median([thermalFits(okTh).mcp]);
hAMeas  = median([thermalFits(okTh).hA]);
mcpDs = o.ds.massKg * o.ds.cpJkgK;
if o.ds.preferThermal && isfinite(mcpDs), mcp = mcpDs; srcMcp = 'datasheet m*cp (preferred)';
elseif any(okTh), mcp = mcpMeas; srcMcp = sprintf('fitted (%d file(s))', nnz(okTh));
elseif isfinite(mcpDs), mcp = mcpDs; srcMcp = 'datasheet m*cp';
else, mcp = 900*0.045*AH/2.5; srcMcp = 'ASSUMED (~18 J/K per Ah) - enter mass and cp!';
end
if o.ds.preferThermal && isfinite(o.ds.hA), hA = o.ds.hA; srcHA = 'datasheet (preferred)';
elseif any(okTh), hA = hAMeas; srcHA = sprintf('fitted (%d file(s))', nnz(okTh));
elseif isfinite(o.ds.hA), hA = o.ds.hA; srcHA = 'datasheet';
else, hA = 0.05; srcHA = 'ASSUMED 0.05 W/K - enter h*A!';
end
% recompute model curves with the chosen values for the diagnostics plot
for k = 1:nD
    if ~isempty(thermalFits(k).t)
        thermalFits(k) = simulateThermal(thermalFits(k), mcp, hA);
    end
end

% ---- 6. assemble ---------------------------------------------------------------------------
P = struct();
P.SOC_vec = g;
P.T_vec_C = Tg;
P.T_vec = Tg + 273.15;
P.V0_mat = V0;
P.R0_mat = R0;
P.nRC = o.nRC;
P.R = Rk; P.tau = Tk;
P.AH = AH;
P.capacity = struct('T_C', Tlab(isfinite(capD)), 'Ah', capD(isfinite(capD))');
[~, iTr] = min(abs(Tg - o.refTempC));
P.refIndex = iTr;
P.thermal_mass = mcp;
P.hA = hA;
P.Rleak = o.ds.Rleak;
P.Vmin = Vmin; P.Vmax = Vmax;
P.provenance = prov;
P.points = points;
P.thermalFits = thermalFits;
P.datasets = {dsArr.name};
P.opts = o;
P.sources = struct('AH',srcAH,'thermal_mass',srcMcp,'hA',srcHA,'Vmax',srcVmax,'Vmin',srcVmin);

% ---- 7. report --------------------------------------------------------------------------------
rep{end+1} = '';
rep{end+1} = 'THERMAL (lumped: m*cp dT/dt = I^2*R0 + sum Rk*xk^2 - h*A*(T - T_chamber))';
for k = 1:nD
    th = thermalFits(k);
    if th.ok
        rep{end+1} = sprintf('  %-34s m*cp %.4g J/K, h*A %.4g W/K, fit rmse %.2f K', ...
            th.name, th.mcp, th.hA, th.rmse); %#ok<AGROW>
    else
        rep{end+1} = sprintf('  %-34s not fitted (%s)', th.name, th.why); %#ok<AGROW>
    end
end
rep{end+1} = sprintf('  -> thermal_mass = %.4g J/K  [%s]', mcp, srcMcp);
rep{end+1} = sprintf('  -> h*A          = %.4g W/K  [%s]', hA, srcHA);
rep{end+1} = '';
rep{end+1} = 'TABLES  (provenance: M measured, I interpolated, E extrapolated, T from other temperature, D datasheet, A assumed)';
rep = [rep, tableText('OCV V0 (V)', V0, prov.V0, g, Tg, '%7.4f')];
rep = [rep, tableText('R0 (mOhm)', R0*1000, prov.R0, g, Tg, '%7.2f')];
for q = 1:o.nRC
    rep = [rep, tableText(sprintf('R%d (mOhm)',q), Rk{q}*1000, prov.R{q}, g, Tg, '%7.2f')]; %#ok<AGROW>
    rep = [rep, tableText(sprintf('tau%d (s)',q), Tk{q}, prov.tau{q}, g, Tg, '%7.1f')]; %#ok<AGROW>
end
counts = provCounts(prov);
rep{end+1} = '';
rep{end+1} = sprintf('Table cells: %d measured, %d interpolated, %d extrapolated, %d other-T, %d datasheet, %d assumed', ...
    counts.M, counts.I, counts.E, counts.T, counts.D, counts.A);
dts = [dsArr.dtMedian];
if any(dts > 2)
    rep{end+1} = sprintf(['  ! median sample interval up to %.3g s: R0 from step edges includes some ' ...
        'RC relaxation (R0 slightly high, R1 slightly low).'], max(dts));
end
P.report = rep(:);
P.blockHelp = blockHelpText(P, o);
end

function [M, pv] = fillAcrossT(M, pv, Tg)
for j = 1:size(M,2)
    if all(~isfinite(M(:,j))) || all(pv(:,j) == '-' | pv(:,j) == ' ')
        have = find(any(isfinite(M),1) & ~all(pv == '-' | pv == ' ', 1));
        have(have == j) = [];
        if isempty(have), continue; end
        [~, i] = min(abs(Tg(have) - Tg(j)));
        M(:,j) = M(:,have(i)); pv(:,j) = 'T';
    end
end
end

function c = provCounts(prov)
allP = [prov.V0(:); prov.R0(:)];
for q = 1:numel(prov.R), allP = [allP; prov.R{q}(:); prov.tau{q}(:)]; end %#ok<AGROW>
for L = 'MIETDA', c.(L) = nnz(allP == L); end
end

function lines = tableText(name, M, pv, g, Tg, fmt)
lines = {''; sprintf('  %s', name)};
hdr = sprintf('  %6s', 'SOC');
for j = 1:numel(Tg), hdr = [hdr sprintf(' %9s', sprintf('%.1fC', Tg(j)))]; end %#ok<AGROW>
lines{end+1} = hdr;
for i = 1:numel(g)
    s = sprintf('  %6.3f', g(i));
    for j = 1:numel(Tg), s = [s sprintf([' ' fmt ' %c'], M(i,j), pv(i,j))]; end %#ok<AGROW>
    lines{end+1} = s; %#ok<AGROW>
end
lines = lines(:)';
end

function pts = denseOcvPoints(d, g, R0col, Rk, Tk, j, o, AH)
% OCV estimate along low-rate CC charge/discharge:
%   OCV = V + I*R0(SOC) + sum_k R_k(SOC) * x_k     (I positive = discharge)
% Charge and discharge estimates are averaged per 1 % SOC bin, which cancels
% most of the remaining model error and the hysteresis.
pts = [];
I = d.I; V = d.V; t = d.t; soc = d.soc;
mask = abs(I) > 0 & abs(I) <= o.ocvMaxCrate*AH;
if nnz(mask) < 20, return; end
nRC = numel(Rk);
sc = min(max(soc, g(1)), g(end));
est = V + I.*interp1(g, R0col, sc);
for q = 1:nRC
    tau = median(Tk{q}(:,j), 'omitnan');
    x = rcCurrent(t, I, tau);
    est = est + interp1(g, Rk{q}(:,j), sc).*x;
end
% only well-settled parts of CC phases (skip the first 3*tau_max of each phase)
tauMaxUsed = max(cellfun(@(T) median(T(:,j),'omitnan'), Tk));
ph = d.phases;
settled = false(size(I));
for k = 1:numel(ph)
    if ph(k).type == 'R', continue; end
    idx = ph(k).i1:ph(k).i2;
    settled(idx) = (t(idx) - ph(k).t1) > min(3*tauMaxUsed, 0.3*ph(k).dur);
end
mask = mask & settled & soc >= -0.02 & soc <= 1.02;
bins = round(soc*100)/100;
dch = mask & I > 0; chg = mask & I < 0;
[ud, ~, id] = unique(bins(dch)); vd = accumarray(id, est(dch), [], @mean);
[uc, ~, ic] = unique(bins(chg)); vc = accumarray(ic, est(chg), [], @mean);
[ub, ia, ib] = intersect(ud, uc);
both = [ub, (vd(ia) + vc(ib))/2];
onlyD = [ud(~ismember(ud, ub)), vd(~ismember(ud, ub))];
onlyC = [uc(~ismember(uc, ub)), vc(~ismember(uc, ub))];
if ~isempty(both)
    % a one-sided bin is shifted by the mean charge/discharge offset (hysteresis)
    hd = mean(vd(ia) - both(:,2)); hc = mean(vc(ib) - both(:,2));
    onlyD(:,2) = onlyD(:,2) - hd; onlyC(:,2) = onlyC(:,2) - hc;
end
pts = sortrows([both; onlyD; onlyC]);
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
%  SECTION 9 - Thermal identification
% ======================================================================
function th = fitThermal(d, g, R0col, Rk, Tk, j)
% Lumped model  m*cp * dT/dt = Q - h*A*(T - Tch)
% with the same Joule heat the Simscape block generates:
%   Q = I^2*R0(SOC) + sum_k R_k(SOC) * x_k^2      (x_k = RC branch current)
% It is linear in [1/(m*cp), h*A/(m*cp)] -> least squares on the derivative.
th = struct('name','','t',[],'Tmeas',[],'Tmodel',[],'Q',[],'Tamb',[],'mcp',NaN,'hA',NaN, ...
    'rmse',NaN,'ok',false,'why','');
if all(~isfinite(d.Tcell)), th.why = 'no cell temperature column'; return; end
Tch = d.Tch;
if all(~isfinite(Tch)), Tch(:) = d.T_C; end
ok = isfinite(d.Tcell) & isfinite(Tch);
if max(d.Tcell(ok)) - min(d.Tcell(ok)) < 0.5, th.why = 'cell temperature varies < 0.5 K'; return; end
sc = min(max(d.soc, g(1)), g(end));
Qall = d.I.^2 .* interp1(g, R0col, sc);
for q = 1:numel(Rk)
    x = rcCurrent(d.t, d.I, median(Tk{q}(:,j), 'omitnan'));
    Qall = Qall + interp1(g, Rk{q}(:,j), sc) .* x.^2;
end
t = d.t(ok); Tc = d.Tcell(ok); Ta = Tch(ok); Q = Qall(ok);
% uniform 10 s grid; heat averaged over each interval through its integral
dtg = 10;
tg = (t(1):dtg:t(end))';
if numel(tg) < 50, th.why = 'record too short'; return; end
[tu, iu] = unique(t);
E = cumtrapz(tu, Q(iu));
Qg = diff(interp1(tu, E, [tg; tg(end)+dtg], 'linear', 'extrap'))/dtg;
Tg = interp1(tu, Tc(iu), tg); Tag = interp1(tu, Ta(iu), tg);
Ts = smoothdata(Tg, 'movmean', 7);
dT = gradient(Ts, dtg);
A = [Qg, -(Ts - Tag)];
m = all(isfinite([A dT]), 2);
c = A(m,:) \ dT(m);
if any(c <= 0) || ~all(isfinite(c))
    th.why = 'fit gave non-physical values (no heating visible?)'; return
end
th.mcp = 1/c(1); th.hA = c(2)/c(1);
if th.mcp < 0.5 || th.mcp > 1e5 || th.hA > 1e3
    th.why = sprintf('fit out of range (m*cp %.3g, hA %.3g)', th.mcp, th.hA); return
end
th.t = tg - tg(1); th.Tmeas = Tg; th.Q = Qg; th.Tamb = Tag;
% The derivative regression is biased by the smoothing it needs; refine both
% values by fitting the simulated temperature trajectory itself (output error).
p0 = log([th.mcp th.hA]);
cost = @(p) rmseOf(simulateThermal(th, exp(p(1)), exp(p(2))));
p1 = fminsearch(cost, p0, optimset('Display','off','MaxFunEvals',300,'TolX',1e-5));
if cost(p1) < cost(p0), th.mcp = exp(p1(1)); th.hA = exp(p1(2)); end
th = simulateThermal(th, th.mcp, th.hA);
th.ok = true;
end

function r = rmseOf(th)
r = th.rmse;
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
%  SECTION 10 - Load profile for a Controlled Current Source
% ======================================================================
function prof = extractProfile(d, o)
t = d.t; I = d.I; V = d.V;
w = true(size(t));
if ~isempty(o.profileWindow)              % window in seconds from the start of the file
    tr = t - t(1);
    w = tr >= o.profileWindow(1) & tr <= o.profileWindow(2);
end
idx = find(w);
if numel(idx) < 2, error('The profile window contains fewer than 2 samples.'); end
t = t(idx); I = I(idx); V = V(idx);
[t, iu] = unique(t, 'last'); I = I(iu); V = V(iu); idx = idx(iu);
t0 = t(1); t = t - t0;
% The cycler logs the NEW current on the first sample of a step. Insert a
% point just before each step carrying the OLD current so that linear
% interpolation in From Workspace reproduces the step exactly.
thr = max(0.01, 0.02*max(abs(I)));
k = find(abs(diff(I)) > thr) + 1;
eps_t = min(1e-3, 0.1*min(diff(t(t > 0)), [], 'omitnan'));
if isempty(eps_t) || ~isfinite(eps_t), eps_t = 1e-3; end
tb = t(k) - eps_t; Ib = I(k-1);
[tt, ord] = sort([t; tb]); II = [I; Ib]; II = II(ord);
switch o.profileSign
    case 'charge+',    sgn = -1; signTxt = 'positive = CHARGE current into the cell';
    otherwise,         sgn =  1; signTxt = 'positive = DISCHARGE current out of the cell';
end
prof.datasetName = d.name;
prof.t0 = t0;
prof.t = tt;
prof.I_source = sgn*II;
prof.I_dis = II;
prof.tMeas = t; prof.Vmeas = V;
Tch = d.Tch(idx); if all(~isfinite(Tch)), Tch(:) = d.T_C; end
Tch = fillmissing(Tch, 'nearest');
prof.Tamb_K = Tch + 273.15;
Tc = d.Tcell(idx);
if any(isfinite(Tc)), prof.Tcell_C = Tc; else, prof.Tcell_C = nan(size(t)); end
if isfinite(Tc(1)), prof.T0_K = Tc(1) + 273.15; else, prof.T0_K = prof.Tamb_K(1); end
if ~isempty(d.soc), prof.SOC0 = min(max(d.soc(idx(1)), 0), 1);
elseif isfinite(o.initialSOC), prof.SOC0 = o.initialSOC;
else, prof.SOC0 = NaN;
end
prof.sign = o.profileSign;
p = o.prefix;
prof.help = {
    sprintf('Current profile: %s', signTxt)
    sprintf('  %sload      [t I]  -> From Workspace -> Simulink-PS Converter (unit A)', p)
    '                       -> Controlled Current Source (Simscape Foundation)'
    sprintf('  %sambient   [t T_K] -> From Workspace -> Simulink-PS (unit K) -> Controlled Temperature Source', p)
    sprintf('  %sload_ts / %sambient_ts are the same data as timeseries objects', p, p)
    sprintf('  %svmeas     [t V] measured terminal voltage for comparison', p)
    sprintf('  %sSOC0 = %.4f, %sT0 = %.2f K (initial SOC / cell temperature)', p, prof.SOC0, p, prof.T0_K)
    ''
    'Wiring for the default charge+ sign:'
    '  Controlled Current Source "+" (head) -> battery "+",  "-" (tail) -> battery "-"'
    '  A positive signal then pushes current INTO the battery (charging).'
    '  If you wire the source the other way round, export with "discharge+".'
    'From Workspace: Interpolate data ON (step points are pre-inserted), '
    '  Form output after final data value = Holding final value.'
    sprintf('Stop time = %.6g s', prof.t(end))};
end

% ======================================================================
%  SECTION 11 - Workspace export and block parameterisation
% ======================================================================
function S = workspaceVariables(P, prof, o)
p = o.prefix;
S = struct();
S.([p 'SOC_vec']) = P.SOC_vec;
S.([p 'T_vec'])   = P.T_vec;                  % K
S.([p 'V0_mat'])  = P.V0_mat;
S.([p 'R0_mat'])  = P.R0_mat;
for q = 1:P.nRC
    S.(sprintf('%sR%d_mat', p, q))   = P.R{q};
    S.(sprintf('%stau%d_mat', p, q)) = P.tau{q};
end
r = P.refIndex;                                 % single-temperature versions
S.([p 'V0_vec']) = P.V0_mat(:,r)';
S.([p 'R0_vec']) = P.R0_mat(:,r)';
for q = 1:P.nRC
    S.(sprintf('%sR%d_vec', p, q))   = P.R{q}(:,r)';
    S.(sprintf('%stau%d_vec', p, q)) = P.tau{q}(:,r)';
end
S.([p 'AH'])           = P.AH;
S.([p 'thermal_mass']) = P.thermal_mass;
S.([p 'hA'])           = P.hA;
if isfinite(P.Rleak), S.([p 'Rleak']) = P.Rleak; end
S.([p 'Vmin']) = P.Vmin; S.([p 'Vmax']) = P.Vmax;
params = P; params = rmfield(params, {'points','thermalFits'});
S.([p 'params']) = params;
if ~isempty(prof)
    S.([p 'load'])       = [prof.t, prof.I_source];
    S.([p 'load_ts'])    = timeseries(prof.I_source, prof.t, 'Name', 'Cell current');
    S.([p 'ambient'])    = [prof.tMeas, prof.Tamb_K];
    S.([p 'ambient_ts']) = timeseries(prof.Tamb_K, prof.tMeas, 'Name', 'Chamber temperature (K)');
    S.([p 'vmeas'])      = [prof.tMeas, prof.Vmeas];
    S.([p 'SOC0'])       = prof.SOC0;
    S.([p 'T0'])         = prof.T0_K;
    S.([p 'stopTime'])   = prof.t(end);
else
    S.([p 'SOC0']) = 1;
    S.([p 'T0'])   = P.T_vec(P.refIndex);
end
end

function names = exportToWorkspace(P, prof, o)
S = workspaceVariables(P, prof, o);
names = fieldnames(S);
for k = 1:numel(names)
    assignin('base', names{k}, S.(names{k}));
end
end

function applyToBlock(blk, P, o)
% Point every parameter of a Battery (Table-Based) block at the exported variables.
dp = get_param(blk, 'DialogParameters');
if ~isfield(dp, 'V0_mat') || ~isfield(dp, 'prm_dyn')
    error('Selected block "%s" is not a Battery (Table-Based) block. Click the block first.', ...
        strrep(blk, newline, ' '));
end
p = o.prefix;
multiT = numel(P.T_vec) > 1;
pv = {'prm_dyn', sprintf('simscape.enum.tablebattery.prm_dyn.rc%d', P.nRC), ...
      'SOC_vec', [p 'SOC_vec'], 'AH', [p 'AH'], 'AH_unit', 'A*hr', ...
      'thermal_port', 'simscape.enum.thermaleffects.model', ...
      'thermal_mass', [p 'thermal_mass'], 'thermal_mass_unit', 'J/K', ...
      'SOC_port', 'simscape.enum.tablebattery.enable.yes', ...
      'extrapolation_option', 'simscape.enum.extrapolation.nearest', ...
      'stateOfCharge_specify', 'on', 'stateOfCharge_priority', 'High', 'stateOfCharge', [p 'SOC0'], ...
      'cell_temperature_specify', 'on', 'cell_temperature_priority', 'High', ...
      'cell_temperature', [p 'T0'], 'cell_temperature_unit', 'K'};
if multiT
    pv = [pv, {'T_dependence', 'simscape.enum.tablebattery.temperature_dependence.yes', ...
        'T_vec', [p 'T_vec'], 'T_vec_unit', 'K', 'V0_mat', [p 'V0_mat'], 'R0_mat', [p 'R0_mat']}];
    for q = 1:P.nRC
        pv = [pv, {sprintf('R%d_mat',q), sprintf('%sR%d_mat',p,q), ...
                   sprintf('tau%d_mat',q), sprintf('%stau%d_mat',p,q)}]; %#ok<AGROW>
    end
else
    pv = [pv, {'T_dependence', 'simscape.enum.tablebattery.temperature_dependence.no', ...
        'V0_vec', [p 'V0_vec'], 'R0_vec', [p 'R0_vec']}];
    for q = 1:P.nRC
        pv = [pv, {sprintf('R%d_vec',q), sprintf('%sR%d_vec',p,q), ...
                   sprintf('tau%d_vec',q), sprintf('%stau%d_vec',p,q)}]; %#ok<AGROW>
    end
end
if isfinite(P.Rleak)
    pv = [pv, {'prm_leak', 'simscape.enum.tablebattery.prm_leak.enabled', 'Rleak', [p 'Rleak']}];
end
for k = 1:2:numel(pv)
    if isfield(dp, pv{k}), set_param(blk, pv{k}, pv{k+1}); end
end
end

function lines = blockHelpText(P, o)
p = o.prefix;
lines = {
    'Battery (Table-Based) block settings (Simscape Battery > Cells):'
    sprintf('  Charge dynamics            : %d time-constant dynamics', P.nRC)
    sprintf('  Tabulate over temperature  : %s', ternary(numel(P.T_vec) > 1, 'Yes', 'No'))
    sprintf('  SOC breakpoints            : %sSOC_vec', p)
    sprintf('  Temperatures (K)           : %sT_vec', p)
    sprintf('  Open-circuit voltage       : %sV0_mat  (one T: %sV0_vec)', p, p)
    sprintf('  Terminal resistance        : %sR0_mat', p)
    sprintf('  R1..R%d / tau1..tau%d        : %sR1_mat, %stau1_mat, ...', P.nRC, P.nRC, p, p)
    sprintf('  Cell capacity AH (A*hr)    : %sAH = %.4g', p, P.AH)
    '  Thermal port               : Model  (connect H to a Convective Heat Transfer)'
    sprintf('  Thermal mass (J/K)         : %sthermal_mass = %.4g', p, P.thermal_mass)
    sprintf('  Convection h*A (W/K)       : %shA = %.4g  (Convective Heat Transfer: area 1 m^2, coefficient %shA)', p, P.hA, p)
    '  Expose SOC port            : Yes'
    sprintf('  Initial SOC / temperature  : %sSOC0 / %sT0 (K)', p, p)};
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

% ======================================================================
%  SECTION 12 - Digital twin: build + simulate a Simscape model
% ======================================================================
function res = runTwin(P, prof, o)
if isempty(prof), error('Export a load profile first.'); end
if ~isfinite(prof.SOC0), error('Initial SOC unknown: run the extraction first.'); end
exportToWorkspace(P, prof, o);
mdl = o.modelName;
buildTwinModel(mdl, P, o);
% A variable-step solver would happily step over a 10 s pulse after a long
% rest, so the step is capped at the data's own sample interval.
maxStep = min(max(median(diff(prof.tMeas)), 0.5), 10);
set_param(mdl, 'StopTime', num2str(prof.t(end), '%.10g'), 'MaxStep', num2str(maxStep), ...
    'OutputOption', 'AdditionalOutputTimes', 'OutputTimes', [o.prefix 'vmeas(:,1)']);
if o.saveModel
    if ~isfolder(o.modelDir), mkdir(o.modelDir); end
    save_system(mdl, fullfile(o.modelDir, [mdl '.slx']), 'OverwriteIfChangedOnDisk', true);
end
% the block asserts 0 <= SOC <= 1; brief excursions (charge pulses at full,
% discharge just past Vmin) are reported once in the summary instead
ws = warning('off', 'physmod:common:simtypes:assert:Assertion');
restoreWarn = onCleanup(@() warning(ws));
tic;
out = sim(mdl, 'ReturnWorkspaceOutputs', 'on');
wall = toc;
vts = out.get('twin_V'); sts = out.get('twin_SOC'); tts = out.get('twin_T');
tm = prof.tMeas;
res.t = tm;
res.Vmeas = prof.Vmeas;
res.Vsim   = sampleTs(vts, tm);
res.SOCsim = sampleTs(sts, tm);
res.TsimC  = sampleTs(tts, tm) - 273.15;
res.TmeasC = prof.Tcell_C;
err = res.Vsim - res.Vmeas;
active = true(size(err));
res.rmse_mV = 1000*sqrt(mean(err(active).^2, 'omitnan'));
res.maxErr_mV = 1000*max(abs(err(active)));
res.model = mdl;
res.wallTime = wall;
[~, iMax] = max(abs(err));
res.tMaxErr = tm(iMax);
res.summary = {
    sprintf('Digital twin "%s" on %s', mdl, prof.datasetName)
    sprintf('  simulated %.2f h in %.1f s wall time', tm(end)/3600, wall)
    sprintf('  terminal voltage RMSE  %.2f mV', res.rmse_mV)
    sprintf('  max |error|            %.2f mV  (at t = %.4g h, twin SOC %.3f)', res.maxErr_mV, ...
        res.tMaxErr/3600, res.SOCsim(iMax))
    sprintf('  final SOC twin         %.4f', res.SOCsim(end))};
if min(res.SOCsim) < -0.005 || max(res.SOCsim) > 1.005
    res.summary{end+1} = sprintf(['  note: twin SOC ranged %.3f .. %.3f (outside the 0..1 tables, ' ...
        'values are held at the table ends)'], min(res.SOCsim), max(res.SOCsim));
end
if any(isfinite(res.TmeasC))
    res.summary{end+1} = sprintf('  cell temperature RMSE  %.2f K', ...
        sqrt(mean((res.TsimC - res.TmeasC).^2, 'omitnan')));
end
res.summary{end+1} = 'The twin traces were added to the dataset (Plot tab: "V twin (V)", "V error (mV)", ...).';
end

function y = sampleTs(ts, tq)
% value of a logged signal at the requested times (last value if a time
% appears twice, i.e. just after a discontinuity)
[tu, iu] = unique(ts.Time, 'last');
y = interp1(tu, double(squeeze(ts.Data(iu))), tq, 'linear', 'extrap');
end

function d = attachTwin(d, res, prof)
n = numel(d.t);
cols = {'V twin (V)','V error (mV)','SOC twin (-)','Temp twin (C)'};
for k = 1:numel(cols), d.tbl.(cols{k}) = nan(n,1); end
tt = d.t - prof.t0;
in = tt >= res.t(1) & tt <= res.t(end);
d.tbl.('V twin (V)')(in)    = interp1(res.t, res.Vsim, tt(in));
d.tbl.('V error (mV)')(in)  = 1000*(d.tbl.('V twin (V)')(in) - d.V(in));
d.tbl.('SOC twin (-)')(in)  = interp1(res.t, res.SOCsim, tt(in));
d.tbl.('Temp twin (C)')(in) = interp1(res.t, res.TsimC, tt(in));
end

function buildTwinModel(mdl, P, o)
% Builds:
%   From Workspace(load) -> S-PS -> Controlled Current Source -> battery +/-
%   From Workspace(ambient) -> S-PS -> Controlled Temperature Source
%        -> Convective Heat Transfer -> battery thermal port H
%   battery +/- -> Voltage Sensor -> twin_V ; SOC port -> twin_SOC ; H -> twin_T
p = o.prefix;
if bdIsLoaded(mdl), close_system(mdl, 0); end
f = fullfile(o.modelDir, [mdl '.slx']);
if isfile(f), delete(f); end
new_system(mdl);
load_system('fl_lib'); load_system('nesl_utility');
battSrc = findLibBlock({'batt_lib','ee_lib'}, '^Battery\s\(Table-Based\)$');
L.isrc  = findLibBlock({'fl_lib'}, '^Controlled\sCurrent\sSource$');
L.tsrc  = findLibBlock({'fl_lib'}, '^Controlled\sTemperature\sSource$');
L.conv  = findLibBlock({'fl_lib'}, '^Convective\sHeat\sTransfer$');
L.vsen  = 'fl_lib/Electrical/Electrical Sensors/Voltage Sensor';
L.tsen  = 'fl_lib/Thermal/Thermal Sensors/Temperature Sensor';
L.eref  = 'fl_lib/Electrical/Electrical Elements/Electrical Reference';
L.tref  = 'fl_lib/Thermal/Thermal Elements/Thermal Reference';
L.solv  = findLibBlock({'nesl_utility'}, '^Solver\sConfiguration$');
L.s2ps  = findLibBlock({'nesl_utility'}, '^Simulink-PS\sConverter$');
L.ps2s  = findLibBlock({'nesl_utility'}, '^PS-Simulink\sConverter$');

B = @(n) [mdl '/' n];
add_block(battSrc, B('Battery'), 'Position', [520 170 600 270]);
applyToBlock(B('Battery'), P, o);

add_block('simulink/Sources/From Workspace', B('Load current'), 'Position', [40 120 150 150], ...
    'VariableName', [p 'load'], 'Interpolate', 'on', 'OutputAfterFinalValue', 'Holding final value');
add_block(L.s2ps, B('I to PS'), 'Position', [200 120 240 150], 'Unit', 'A');
add_block(L.isrc, B('Current source'), 'Position', [300 160 360 220]);
add_block(L.eref, B('Ground'), 'Position', [440 330 480 360]);
add_block(L.solv, B('Solver'), 'Position', [300 320 360 350]);

add_block('simulink/Sources/From Workspace', B('Chamber temperature'), 'Position', [40 420 150 450], ...
    'VariableName', [p 'ambient'], 'Interpolate', 'on', 'OutputAfterFinalValue', 'Holding final value');
add_block(L.s2ps, B('T to PS'), 'Position', [200 420 240 450], 'Unit', 'K');
add_block(L.tsrc, B('Chamber'), 'Position', [300 440 360 500]);
add_block(L.tref, B('Thermal ref'), 'Position', [300 560 360 590]);
add_block(L.conv, B('Convection'), 'Position', [440 440 500 480], ...
    'area', '1', 'area_unit', 'm^2', 'heat_tr_coeff', [p 'hA'], 'heat_tr_coeff_unit', 'W/(m^2*K)');

add_block(L.vsen, B('V sensor'), 'Position', [700 170 760 230]);
add_block(L.ps2s, B('V out'), 'Position', [800 190 840 210], 'Unit', 'V');
add_block('simulink/Sinks/To Workspace', B('twin_V'), 'Position', [880 185 960 215], ...
    'VariableName', 'twin_V', 'SaveFormat', 'Timeseries');
add_block(L.ps2s, B('SOC out'), 'Position', [800 260 840 280], 'Unit', '1');
add_block('simulink/Sinks/To Workspace', B('twin_SOC'), 'Position', [880 255 960 285], ...
    'VariableName', 'twin_SOC', 'SaveFormat', 'Timeseries');
add_block(L.tsen, B('T sensor'), 'Position', [700 400 760 440]);
add_block(L.ps2s, B('T out'), 'Position', [800 410 840 430], 'Unit', 'K');
add_block('simulink/Sinks/To Workspace', B('twin_T'), 'Position', [880 405 960 435], ...
    'VariableName', 'twin_T', 'SaveFormat', 'Timeseries');

ph = @(n) get_param(B(n), 'PortHandles');
bt = ph('Battery');                % LConn1 +, LConn2 SOC, RConn1 -, RConn2 H
pos = bt.LConn(1); socP = bt.LConn(2); neg = bt.RConn(1); H = bt.RConn(2);
is = ph('Current source');         % LConn1 + (head), RConn1 signal, RConn2 - (tail)
ts = ph('Chamber');                % LConn1 B, RConn1 signal, RConn2 A
vs = ph('V sensor');               % LConn1 +, RConn1 V, RConn2 -
cv = ph('Convection');
tsn = ph('T sensor');
lines = {
    ph('Load current').Outport(1), ph('I to PS').Inport(1)
    ph('I to PS').RConn(1),        is.RConn(1)
    is.LConn(1),                   pos
    is.RConn(2),                   neg
    neg,                           ph('Ground').LConn(1)
    ph('Solver').RConn(1),         neg
    vs.LConn(1),                   pos
    vs.RConn(2),                   neg
    vs.RConn(1),                   ph('V out').LConn(1)
    ph('V out').Outport(1),        ph('twin_V').Inport(1)
    socP,                          ph('SOC out').LConn(1)
    ph('SOC out').Outport(1),      ph('twin_SOC').Inport(1)
    ph('Chamber temperature').Outport(1), ph('T to PS').Inport(1)
    ph('T to PS').RConn(1),        ts.RConn(1)
    ts.RConn(2),                   ph('Thermal ref').LConn(1)
    ts.LConn(1),                   cv.RConn(1)
    cv.LConn(1),                   H
    ph('T out').Outport(1),        ph('twin_T').Inport(1)};
for k = 1:size(lines,1)
    add_line(mdl, lines{k,1}, lines{k,2}, 'autorouting', 'smart');
end
% temperature sensor: A -> battery H, (B -> reference if exposed), T -> PS-Simulink
add_line(mdl, tsn.LConn(1), H, 'autorouting', 'smart');
if numel(tsn.RConn) >= 2
    try
        add_line(mdl, tsn.RConn(1), ph('Thermal ref').LConn(1), 'autorouting', 'smart');
        add_line(mdl, tsn.RConn(2), ph('T out').LConn(1), 'autorouting', 'smart');
    catch
        delete_line(find_system(mdl, 'FindAll', 'on', 'Type', 'line', 'SrcPortHandle', tsn.RConn(1)));
        add_line(mdl, tsn.RConn(2), ph('Thermal ref').LConn(1), 'autorouting', 'smart');
        add_line(mdl, tsn.RConn(1), ph('T out').LConn(1), 'autorouting', 'smart');
    end
else
    add_line(mdl, tsn.RConn(1), ph('T out').LConn(1), 'autorouting', 'smart');
end
try
    a = Simulink.Annotation(mdl, sprintf(['Digital twin generated by plotBatteryData. ' ...
        'Parameters: base-workspace variables "%s*". Current source: positive signal = charge.'], p));
    a.Position = [40 20 600 40];
catch
end
set_param(mdl, 'Solver', 'daessc', 'RelTol', '1e-4', 'AbsTol', 'auto', ...
    'MaxStep', 'auto', 'ReturnWorkspaceOutputs', 'on', 'SignalLogging', 'off');
end

function blk = findLibBlock(libs, regexName)
for k = 1:numel(libs)
    try
        load_system(libs{k});
    catch
        continue
    end
    b = find_system(libs{k}, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
        'RegExp', 'on', 'Name', regexName);
    if ~isempty(b), blk = b{1}; return; end
end
error('Library block matching "%s" not found (is Simscape / Simscape Battery installed?).', regexName);
end
