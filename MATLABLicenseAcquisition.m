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
    % Simscape Battery is unchecked by default; tick it if you need it.
    %
    % Note: MATLAB has no way to hand back a single toolbox license once it is checked out.
    % Licenses are returned when MATLAB exits, which is what "Release All & Exit" does.
    properties (Access = public)
        UIFigure      matlab.ui.Figure
        StartButton   matlab.ui.control.Button
        StopButton    matlab.ui.control.Button
        ReleaseButton matlab.ui.control.Button
        Timer         timer
        WatchTimer    timer
        LogoImage     matlab.ui.control.Image
        ElapsedValue  matlab.ui.control.Label
        ChecksValue   matlab.ui.control.Label
        AcquiredValue matlab.ui.control.Label
        AcquiredCaption matlab.ui.control.Label
        DataRoot      char
    end
    properties (Constant, Access = private)
        Background = [0.95 0.96 0.97];
        Ink        = [0.13 0.15 0.19];
        Muted      = [0.45 0.48 0.53];
        Accent     = [0.89 0.45 0.13];   % MATLAB orange
        Good       = [0.16 0.60 0.33];
        Warn       = [0.90 0.58 0.10];
        Bad        = [0.80 0.20 0.18];
        Idle       = [0.70 0.72 0.75];
    end
    properties (Access = private)
        FeatureOrder = {'simulink', 'simscape', 'simscape_battery', 'power_system_blocks', 'signal_toolbox'};
        FeaturesMap = containers.Map(...
            {'simulink', 'simscape', 'simscape_battery', 'power_system_blocks', 'signal_toolbox'}, ...
            {'Simulink', 'Simscape', 'Simscape Battery', 'Power System Blocks', 'Signal Processing Toolbox'});
        StatusLabels
        CheckBoxes
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
                    app.setStatus(i, 'SKIPPED');
                    app.logEvent(i, 'SKIPPED');
                    continue;
                end

                app.CheckBoxes(i).FontColor = app.Ink;

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
                    app.setStatus(i, 'ACQUIRED');
                    app.logEvent(i, 'ACQUIRED');
                else
                    app.setStatus(i, 'WAITING');
                    app.logEvent(i, 'WAITING');
                    allAcquired = false;
                end
            end
            if allAcquired && isempty(app.AcquisitionTime)
                app.AcquisitionTime = currentTime;
            end
            app.updateMetrics(currentTime);
            if ~isempty(app.AcquisitionTime)
                app.stopProcess();
            end
        end

        function setStatus(app, i, state)
            colors = struct('IDLE', app.Idle, 'WAITING', app.Warn, 'ACQUIRED', app.Good, 'SKIPPED', app.Idle);
            label = app.StatusLabels(i);
            label.Text = state;
            label.BackgroundColor = colors.(state);
            label.FontColor = [1 1 1];
            if strcmp(state, 'SKIPPED')
                label.BackgroundColor = app.Background;
                label.FontColor = app.Muted;
                app.CheckBoxes(i).FontColor = app.Muted;
            end
        end

        function updateMetrics(app, currentTime)
            if isempty(app.AcquisitionTime)
                elapsed = currentTime - app.StartTime;
            else
                elapsed = app.AcquisitionTime - app.StartTime;
            end
            elapsed.Format = 'hh:mm:ss';
            app.ElapsedValue.Text = char(elapsed);
            app.ChecksValue.Text = sprintf('%d', app.AttemptCount);

            wanted = [app.CheckBoxes.Value];
            got = strcmp({app.StatusLabels.Text}, 'ACQUIRED');
            app.AcquiredValue.Text = sprintf('%d / %d', nnz(got & wanted), nnz(wanted));
            if isempty(app.AcquisitionTime)
                app.AcquiredValue.FontColor = app.Ink;
                app.AcquiredCaption.Text = 'ACQUIRED';
            else
                app.AcquiredValue.FontColor = app.Good;
                app.AcquiredCaption.Text = ['ALL IN AT ' char(app.AcquisitionTime, 'HH:mm')];
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
                    'Options', {'Release & Exit', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
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

        function [value, caption] = addTile(app, parent, captionText, initial)
            tile = uipanel(parent, 'BackgroundColor', [1 1 1], 'BorderType', 'none');
            g = uigridlayout(tile, [2 1], 'RowHeight', {16, '1x'}, 'Padding', [12 8 12 6], ...
                'RowSpacing', 0, 'BackgroundColor', [1 1 1]);
            caption = uilabel(g, 'Text', captionText, 'FontSize', 10, 'FontWeight', 'bold', 'FontColor', app.Muted);
            value = uilabel(g, 'Text', initial, 'FontSize', 20, 'FontWeight', 'bold', 'FontColor', app.Ink);
        end
    end
    methods (Access = protected)
        function setup(app)
            warning('off', 'all');
            figWidth = 440;
            figHeight = 430;
            screenSize = get(0, 'ScreenSize');
            app.UIFigure = uifigure('Name', 'License Acquisition', 'Color', app.Background, 'Resize', 'off', ...
                'Position', [(screenSize(3) - figWidth) / 2, (screenSize(4) - figHeight) / 2, figWidth, figHeight], ...
                'CloseRequestFcn', @(~, ~) app.onClose());
            main = uigridlayout(app.UIFigure, [4 1], 'RowHeight', {70, '1x', 76, 58}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', app.Background);

            % Header bar
            header = uipanel(main, 'BackgroundColor', app.Ink, 'BorderType', 'none');
            hg = uigridlayout(header, [2 2], 'ColumnWidth', {'1x', 90}, 'RowHeight', {'1x', 18}, ...
                'Padding', [20 10 16 12], 'RowSpacing', 0, 'BackgroundColor', app.Ink);
            uilabel(hg, 'Text', 'License Acquisition', 'FontSize', 18, 'FontWeight', 'bold', 'FontColor', [1 1 1]);
            logoPath = fullfile(fileparts(mfilename('fullpath')), 'assets', 'NNS Logo.png');
            if isfile(logoPath)
                app.LogoImage = uiimage(hg, 'ImageSource', logoPath);
                app.LogoImage.Layout.Row = [1 2];
                app.LogoImage.Layout.Column = 2;
            end
            sub = uilabel(hg, 'Text', sprintf('%s  %s  MATLAB %s', app.ClientId, char(183), version('-release')), ...
                'FontSize', 11, 'FontColor', [0.70 0.73 0.78]);
            sub.Layout.Row = 2;
            sub.Layout.Column = 1;

            % Toolbox list card
            body = uigridlayout(main, [1 1], 'Padding', [16 14 16 10], 'BackgroundColor', app.Background);
            card = uipanel(body, 'BackgroundColor', [1 1 1], 'BorderType', 'none');
            n = length(app.FeatureOrder);
            cg = uigridlayout(card, [n + 1, 2], 'ColumnWidth', {'1x', 96}, 'RowHeight', [{18}, repmat({26}, 1, n)], ...
                'Padding', [16 10 16 12], 'RowSpacing', 6, 'BackgroundColor', [1 1 1]);
            uilabel(cg, 'Text', 'TOOLBOX', 'FontSize', 10, 'FontWeight', 'bold', 'FontColor', app.Muted);
            uilabel(cg, 'Text', 'STATUS', 'FontSize', 10, 'FontWeight', 'bold', 'FontColor', app.Muted, ...
                'HorizontalAlignment', 'center');
            app.StatusLabels = gobjects(n, 1);
            app.CheckBoxes = gobjects(n, 1);
            for i = 1:n
                rawName = app.FeatureOrder{i};
                % Battery is opt-in: it's scarce, so only take it when you tick it
                app.CheckBoxes(i) = uicheckbox(cg, 'Text', app.FeaturesMap(rawName), 'FontSize', 13, ...
                    'FontColor', app.Ink, 'Value', ~strcmp(rawName, 'simscape_battery'));
                app.StatusLabels(i) = uilabel(cg, 'Text', 'IDLE', 'FontSize', 10, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'center');
                app.setStatus(i, 'IDLE');
            end

            % Metric tiles
            tiles = uigridlayout(main, [1 3], 'Padding', [16 0 16 0], 'ColumnSpacing', 10, 'BackgroundColor', app.Background);
            app.ElapsedValue = app.addTile(tiles, 'ELAPSED', '00:00:00');
            app.ChecksValue = app.addTile(tiles, 'CHECKS', '0');
            [app.AcquiredValue, app.AcquiredCaption] = app.addTile(tiles, 'ACQUIRED', '-');

            % Actions
            actions = uigridlayout(main, [1 3], 'ColumnWidth', {'1x', 70, '1.3x'}, 'Padding', [16 12 16 14], ...
                'ColumnSpacing', 10, 'BackgroundColor', app.Background);
            app.StartButton = uibutton(actions, 'push', 'Text', 'Start', 'FontWeight', 'bold', 'FontSize', 13, ...
                'BackgroundColor', app.Accent, 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) app.startProcess());
            app.StopButton = uibutton(actions, 'push', 'Text', 'Stop', 'FontSize', 13, 'Enable', 'off', ...
                'BackgroundColor', [1 1 1], 'FontColor', app.Ink, 'ButtonPushedFcn', @(~, ~) app.stopProcess());
            app.ReleaseButton = uibutton(actions, 'push', 'Text', 'Release All & Exit', 'FontSize', 13, ...
                'BackgroundColor', [1 1 1], 'FontColor', app.Bad, 'Tooltip', 'Closes MATLAB, returning every license', ...
                'ButtonPushedFcn', @(~, ~) app.releaseAndExit(true));
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
                app.setStatus(i, 'IDLE');
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
