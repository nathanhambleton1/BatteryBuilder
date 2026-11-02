classdef MATLABLicenseAcquisition < matlab.apps.AppBase
    % License Acquisition Manager - keeps trying to check out toolbox licenses.
    %
    %   MATLABLicenseAcquisition                      % open the window
    %   MATLABLicenseAcquisition('AutoStart', true)   % open and start checking right away
    %
    % GrabMatlabLicense.ps1 launches MATLAB with AutoStart so this runs on its own. Every toolbox
    % checkout is logged to LicenseData\toolboxes\<user>@<pc>.csv on the shared drive, and a
    % LicenseData\active\<user>@<pc>.ready file tells the PowerShell dashboard MATLAB is up.
    %
    % Note: MATLAB has no way to hand back a single toolbox license once it is checked out.
    % Licenses are returned when MATLAB exits, which is what "Release All & Exit" does.
    properties (Access = public)
        UIFigure      matlab.ui.Figure
        StatusPanel   matlab.ui.container.Panel
        StartButton   matlab.ui.control.Button
        StopButton    matlab.ui.control.Button
        ReleaseButton matlab.ui.control.Button
        GraphButton   matlab.ui.control.Button
        Timer         timer
        WatchTimer    timer
        LogoImage     matlab.ui.control.Image
        MetricsLabel  matlab.ui.control.Label
        DataRoot      char
    end
    properties (Access = private)
        FeatureOrder = {'simulink', 'simscape', 'simscape_battery', 'power_system_blocks', 'signal_toolbox'};
        FeaturesMap = containers.Map(...
            {'simulink', 'simscape', 'simscape_battery', 'power_system_blocks', 'signal_toolbox'}, ...
            {'Simulink', 'Simscape', 'Simscape Battery', 'Power System Blocks', 'Signal Processing Toolbox'});
        StatusLabels
        CheckBoxes
        NameLabels
        AttemptCount = 0;
        StartTime
        AcquisitionTime
        AppStartTime
        ClientId char
        SessionId char
        LogFile char
        LoggedState   % last event written per feature, so the log only grows on changes
    end
    methods (Access = private)
        function updateLicenseStatus(app)
            app.AttemptCount = app.AttemptCount + 1;
            allAcquired = true;
            currentTime = datetime('now');
            for i = 1:length(app.FeatureOrder)
                feature = app.FeatureOrder{i};
                if ~app.CheckBoxes(i).Value
                    app.StatusLabels(i).Text = 'SKIPPED';
                    app.StatusLabels(i).FontColor = [0.5 0.5 0.5];
                    app.NameLabels(i).FontColor = [0.5 0.5 0.5];
                    app.logEvent(i, 'SKIPPED');
                    continue;
                end

                app.NameLabels(i).FontColor = [0 0 0];

                % A checked-out license stays ours until MATLAB exits, so don't ask again
                if strcmp(app.StatusLabels(i).Text, 'ACQUIRED')
                    continue;
                end
                try
                    isAcquired = license('checkout', feature);
                catch
                    isAcquired = false;
                end
                if isAcquired
                    app.StatusLabels(i).Text = 'ACQUIRED';
                    app.StatusLabels(i).FontColor = [0 0.6 0];
                    app.logEvent(i, 'ACQUIRED');
                else
                    app.StatusLabels(i).Text = 'WAITING';
                    app.StatusLabels(i).FontColor = [0.8 0 0];
                    app.logEvent(i, 'WAITING');
                    allAcquired = false;
                end
            end
            if allAcquired && isempty(app.AcquisitionTime)
                app.AcquisitionTime = currentTime;
            end
            if isempty(app.AcquisitionTime)
                elapsedTime = currentTime - app.StartTime;
                app.MetricsLabel.Text = sprintf('Elapsed Time: %s | Total Checks: %d', char(elapsedTime), app.AttemptCount);
            else
                finalElapsed = app.AcquisitionTime - app.StartTime;
                app.MetricsLabel.Text = sprintf('All acquired at: %s\nTotal Time: %s | Total Checks: %d', ...
                    char(app.AcquisitionTime), char(finalElapsed), app.AttemptCount);
                app.stopProcess();
            end
        end

        function logEvent(app, i, event)
            if strcmp(app.LoggedState{i}, event)
                return;
            end
            app.LoggedState{i} = event;
            waitSeconds = round(seconds(datetime('now') - app.StartTime));
            app.appendRow(app.FeatureOrder{i}, event, waitSeconds);
        end

        function appendRow(app, feature, event, waitSeconds)
            % Open/append/close every time so nothing holds a handle on the network share
            isNew = ~isfile(app.LogFile);
            fid = fopen(app.LogFile, 'a');
            if fid < 0
                return;
            end
            if isNew
                fprintf(fid, 'Timestamp,User,Computer,Session,Feature,Event,WaitSeconds\r\n');
            end
            fprintf(fid, '%s,%s,%s,%s,%s,%s,%d\r\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
                getenv('USERNAME'), getenv('COMPUTERNAME'), app.SessionId, feature, event, waitSeconds);
            fclose(fid);
        end

        function watchForRelease(app)
            % GrabMatlabLicense.ps1 drops a .release file when the user presses R there
            releaseFile = fullfile(app.DataRoot, 'active', [app.ClientId '.release']);
            if ~isfile(releaseFile)
                return;
            end
            info = dir(releaseFile);
            delete(releaseFile);
            if datetime(info.datenum, 'ConvertFrom', 'datenum') < app.AppStartTime
                return;
            end
            app.releaseAndExit(false);
        end

        function releaseAndExit(app, askFirst)
            if askFirst
                choice = uiconfirm(app.UIFigure, ...
                    ['This closes MATLAB and returns ALL of its licenses (MATLAB and every toolbox). ' ...
                     'Save your work first.'], 'Release licenses', ...
                    'Options', {'Release & Exit', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, 'Release & Exit')
                    return;
                end
            elseif app.hasUnsavedFiles()
                uialert(app.UIFigure, 'Release was requested but you have unsaved files in the Editor. Save them and try again.', ...
                    'Release cancelled');
                return;
            end
            for i = 1:length(app.FeatureOrder)
                if strcmp(app.StatusLabels(i).Text, 'ACQUIRED')
                    app.appendRow(app.FeatureOrder{i}, 'RELEASED', round(seconds(datetime('now') - app.AppStartTime)));
                end
            end
            app.cleanup();
            exit;
        end

        function tf = hasUnsavedFiles(~)
            tf = false;
            try
                docs = matlab.desktop.editor.getAll;
                tf = any([docs.Modified]);
            catch
            end
        end

        function cleanup(app)
            app.stopProcess();
            if ~isempty(app.Timer) && isvalid(app.Timer)
                delete(app.Timer);
            end
            if ~isempty(app.WatchTimer) && isvalid(app.WatchTimer)
                stop(app.WatchTimer);
                delete(app.WatchTimer);
            end
        end
    end
    methods (Access = protected)
        function setup(app)
            warning('off', 'all');
            figWidth = 500;
            figHeight = 500;
            screenSize = get(0, 'ScreenSize');
            screenWidth = screenSize(3);
            screenHeight = screenSize(4);
            left = (screenWidth - figWidth) / 2;
            bottom = (screenHeight - figHeight) / 2;
            app.UIFigure = uifigure('Name', 'License Acquisition Manager', 'Position', [left bottom figWidth figHeight], ...
                'CloseRequestFcn', @(~, ~) app.onClose());
            appPath = fileparts(mfilename('fullpath'));
            logoPath = fullfile(appPath, 'assets', 'NNS Logo.png');
            if isfile(logoPath)
                app.LogoImage = uiimage(app.UIFigure, 'Position', [150 400 200 80], 'ImageSource', logoPath);
            end
            app.StatusPanel = uipanel(app.UIFigure, 'Position', [25 220 450 150], 'BorderType', 'none');
            app.StatusLabels = gobjects(length(app.FeatureOrder), 1);
            app.CheckBoxes = gobjects(length(app.FeatureOrder), 1);
            app.NameLabels = gobjects(length(app.FeatureOrder), 1);
            uilabel(app.StatusPanel, 'Text', 'Enable', 'FontWeight', 'bold', 'Position', [20 130 60 22]);
            uilabel(app.StatusPanel, 'Text', 'Feature', 'FontWeight', 'bold', 'Position', [100 130 180 22]);
            uilabel(app.StatusPanel, 'Text', 'Status', 'FontWeight', 'bold', 'Position', [300 130 130 22]);
            for i = 1:length(app.FeatureOrder)
                yPos = 130 - (i * 25);
                rawName = app.FeatureOrder{i};
                displayName = app.FeaturesMap(rawName);
                app.CheckBoxes(i) = uicheckbox(app.StatusPanel, 'Text', '', 'Position', [20 yPos 40 22], 'Value', 1);
                app.NameLabels(i) = uilabel(app.StatusPanel, 'Text', displayName, 'Position', [100 yPos 180 22]);
                app.StatusLabels(i) = uilabel(app.StatusPanel, 'Text', 'IDLE', 'Position', [300 yPos 130 22]);
            end
            app.MetricsLabel = uilabel(app.UIFigure, 'Text', 'Elapsed Time: 0 | Total Checks: 0', 'Position', [50 140 400 44], 'HorizontalAlignment', 'center');
            app.StartButton = uibutton(app.UIFigure, 'push', 'Text', 'Start Acquisition', ...
                'Position', [120 70 120 30], 'ButtonPushedFcn', @(btn, event) app.startProcess());
            app.StopButton = uibutton(app.UIFigure, 'push', 'Text', 'Stop', ...
                'Position', [260 70 120 30], 'Enable', 'off', 'ButtonPushedFcn', @(btn, event) app.stopProcess());
            app.ReleaseButton = uibutton(app.UIFigure, 'push', 'Text', 'Release All & Exit MATLAB', ...
                'Position', [120 25 260 30], 'FontColor', [0.7 0 0], ...
                'ButtonPushedFcn', @(btn, event) app.releaseAndExit(true));
            app.GraphButton = uibutton(app.UIFigure, 'push', 'Text', '📈', ...
                'Position', [455 460 30 30], 'Tooltip', 'Team license analytics', ...
                'ButtonPushedFcn', @(btn, event) LicenseAnalytics(app.DataRoot));
        end
        function startProcess(app)
            app.stopProcess();
            if ~isempty(app.Timer) && isvalid(app.Timer)
                delete(app.Timer);
            end
            app.AttemptCount = 0;
            app.StartTime = datetime('now');
            app.AcquisitionTime = [];
            app.SessionId = char(datetime('now', 'Format', 'yyyyMMddHHmmss'));
            app.LoggedState = repmat({''}, 1, length(app.FeatureOrder));
            for i = 1:length(app.FeatureOrder)
                app.StatusLabels(i).Text = 'IDLE';
                app.StatusLabels(i).FontColor = [0 0 0];
            end
            app.StartButton.Enable = 'off';
            app.StopButton.Enable = 'on';
            app.Timer = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, 'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) app.updateLicenseStatus());
            start(app.Timer);
        end
        function stopProcess(app)
            % Only stop here: this can run inside the timer's own callback, so deleting
            % is left to startProcess/cleanup
            if ~isempty(app.Timer) && isvalid(app.Timer)
                stop(app.Timer);
            end
            if ~isempty(app.StartButton) && isvalid(app.StartButton)
                app.StartButton.Enable = 'on';
                app.StopButton.Enable = 'off';
            end
        end
        function onClose(app)
            app.cleanup();
            delete(app.UIFigure);
        end
    end
    methods (Access = public)
        function app = MATLABLicenseAcquisition(varargin)
            p = inputParser;
            p.addParameter('AutoStart', false, @(x) islogical(x) || isnumeric(x));
            p.addParameter('DataRoot', '', @(x) ischar(x) || isstring(x));
            p.parse(varargin{:});

            app.AppStartTime = datetime('now');
            app.DataRoot = char(p.Results.DataRoot);
            if isempty(app.DataRoot)
                app.DataRoot = fullfile(fileparts(mfilename('fullpath')), 'LicenseData');
            end
            app.ClientId = [getenv('USERNAME') '@' getenv('COMPUTERNAME')];
            for sub = {'toolboxes', 'active'}
                folder = fullfile(app.DataRoot, sub{1});
                if ~isfolder(folder)
                    mkdir(folder);
                end
            end
            app.LogFile = fullfile(app.DataRoot, 'toolboxes', [app.ClientId '.csv']);

            % Tell GrabMatlabLicense.ps1 that MATLAB really started (i.e. we got a seat)
            fid = fopen(fullfile(app.DataRoot, 'active', [app.ClientId '.ready']), 'w');
            if fid >= 0
                fprintf(fid, '%s', char(datetime('now')));
                fclose(fid);
            end

            app.setup();
            app.WatchTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 3, 'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) app.watchForRelease());
            start(app.WatchTimer);

            if p.Results.AutoStart
                app.startProcess();
            end
        end
    end
end
