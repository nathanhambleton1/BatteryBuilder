function fig = BatteryDataBuilder(file)
%BATTERYDATABUILDER  Battery test viewer + Simscape "Battery (Table-Based)" parameter tool.
%
%   BatteryDataBuilder               open the app
%   BatteryDataBuilder('cell.csv')   open the app with a test file already loaded
%
%     src/plotTab.m              Tab 1  Plot          - zoom / pan / cursor viewer
%     src/loadProfileTab.m       Tab 2  Load profile  - current profile -> workspace
%     src/modelingTab.m          Tab 3  Modeling      - block parameters -> workspace
% 
%     src/loadBatteryCsv.m       reads a cycler CSV (current: + = charge)
%     src/extractCellParameters.m  the calculations (capacity, OCV, R0, RC, thermal)
%     src/blockParameterList.m   every block parameter shown on the Modeling tab
%     src/explainParameter.m     the "How?" pop-up windows
%

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'src'));

% default folder for the Open dialog (falls back to the current folder if unreachable)
lastFolder = ['\\Ssnx\ssn(x)\Documents\Non-Prop Electrical and Combat Systems\NP Electrical\' ...
              '5_Energy Storage\3_Analysis\NRL_Battery_Data'];

fig = uifigure('Name','Battery Builder','Color',[0.96 0.96 0.97],'Visible','off');
fig.Position(3:4) = [1450 880];
movegui(fig,'center');
if nargin == 0, fig.WindowState = 'maximized'; end

top = uigridlayout(fig,[2 4],'RowHeight',{34,'1x'},'ColumnWidth',{250,130,'1x',20}, ...
    'Padding',[8 8 8 8],'RowSpacing',6);
uilabel(top,'Text','Battery Builder','FontSize',20,'FontWeight','bold');
uibutton(top,'Text','Open CSV...','FontWeight','bold','FontSize',13, ...
    'ButtonPushedFcn',@(~,~) onOpen(), 'Tooltip','Open one cycler test file (one temperature)');
lblFile = uilabel(top,'Text','No file loaded','FontColor',[0.3 0.3 0.35]);
lblFile.Layout.Column = [3 4];

tabs = uitabgroup(top);
tabs.Layout.Row = 2; tabs.Layout.Column = [1 4];
t1 = uitab(tabs,'Title','   Plot   ');
t2 = uitab(tabs,'Title','   Load profile   ');
t3 = uitab(tabs,'Title','   Modeling   ');

plotApi    = plotTab(t1, fig);
profileApi = loadProfileTab(t2, fig);
modelApi   = modelingTab(t3, fig, @onDataChanged);

fig.UserData.api = struct('open',@openFile, 'plot',plotApi, 'profile',profileApi, ...
    'model',modelApi, 'selectTab',@(k) set(tabs,'SelectedTab',tabs.Children(k)));
fig.Visible = 'on';
if nargin > 0, openFile(file); end

% -------------------------------------------------------------------------
    function onOpen()
        [f, p] = uigetfile({'*.csv;*.txt','Cycler export (*.csv, *.txt)'}, ...
            'Open a battery test file', lastFolder);
        figure(fig);
        if isequal(f, 0), return; end
        lastFolder = p;
        openFile(fullfile(p, f));
    end

    function openFile(file)
        dlg = uiprogressdlg(fig,'Title','Loading','Message',['Reading ' file],'Indeterminate','on');
        try
            d = loadBatteryCsv(file);
        catch ME
            delete(dlg);
            uialert(fig, sprintf('%s\n\n%s', file, ME.message), 'Could not read file');
            return
        end
        delete(dlg);
        if isfinite(d.T_C), tStr = sprintf('%.1f °C', d.T_C); else, tStr = 'temperature unknown'; end
        info = sprintf('%s   |   %s   |   %.1f h   |   %d rows   |   current: %s', ...
            d.name, tStr, d.t(end)/3600, numel(d.t), d.signNote);
        if ~isempty(d.warn), info = [info '   |   ! ' strjoin(d.warn, '; ')]; end
        lblFile.Text = info;
        lblFile.Tooltip = d.file;
        plotApi.setData(d);
        profileApi.setData(d);
        modelApi.setData(d);
    end

    function onDataChanged(x, what)
        % messages from the Modeling tab
        switch what
            case 'soc'          % x = dataset with the new 'SOC (-)' column
                plotApi.setData(x);
            case 'capacity'     % x = AH (Ah, NaN if unknown) for the C-rate labels
                profileApi.setCapacity(x);
        end
    end
end
