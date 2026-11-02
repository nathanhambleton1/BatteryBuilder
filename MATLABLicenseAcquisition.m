classdef MATLABLicenseAcquisition < matlab.apps.AppBase
    properties (Access = public)
        UIFigure      matlab.ui.Figure
        StatusPanel   matlab.ui.container.Panel
        StartButton   matlab.ui.control.Button
        StopButton    matlab.ui.control.Button
        GraphButton   matlab.ui.control.Button
        Timer         timer
        LogoImage     matlab.ui.control.Image
        MetricsLabel  matlab.ui.control.Label
        LogFileName   string = 'license_log.csv'
        LogFileID     double
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
    end
    methods (Access = private)
        function updateLicenseStatus(app)
            app.AttemptCount = app.AttemptCount + 1;
            allAcquired = true;
            currentTime = datetime('now');
            if isempty(app.AcquisitionTime)
                elapsedTime = currentTime - app.StartTime;
                app.MetricsLabel.Text = sprintf('Elapsed Time: %s | Total Checks: %d', char(elapsedTime), app.AttemptCount);
            else
                finalElapsed = app.AcquisitionTime - app.StartTime;
                app.MetricsLabel.Text = sprintf('Acquired at: %s\nTotal Time: %s | Total Checks: %d', ...
                    char(app.AcquisitionTime), char(finalElapsed), app.AttemptCount);
            end
            for i = 1:length(app.FeatureOrder)
                if ~app.CheckBoxes(i).Value
                    app.StatusLabels(i).Text = 'SKIPPED';
                    app.StatusLabels(i).FontColor = [0.5 0.5 0.5];
                    app.NameLabels(i).FontColor = [0.5 0.5 0.5];
                    continue;
                end
                
                % Reset color to black if checked
                app.NameLabels(i).FontColor = [0 0 0];
                
                feature = app.FeatureOrder{i};
                try
                    isAcquired = license('checkout', feature);
                catch
                    isAcquired = false;
                end
                if isAcquired
                    app.StatusLabels(i).Text = 'ACQUIRED';
                    app.StatusLabels(i).FontColor = [0 0.6 0];
                else
                    app.StatusLabels(i).Text = 'WAITING';
                    app.StatusLabels(i).FontColor = [0.8 0 0];
                    allAcquired = false;
                end
            end
            if allAcquired && isempty(app.AcquisitionTime)
                app.AcquisitionTime = currentTime;
            end
            timestamp = datestr(currentTime, 'yyyy-mm-dd HH:MM:SS');
            statusRow = cell(1, length(app.FeatureOrder));
            for i = 1:length(app.FeatureOrder)
                if ~app.CheckBoxes(i).Value
                    statusRow{i} = 'S'; 
                elseif strcmp(app.StatusLabels(i).Text, 'ACQUIRED')
                    statusRow{i} = '1'; 
                else
                    statusRow{i} = '0'; 
                end
            end
            statusString = strjoin(statusRow, ',');
            fprintf(app.LogFileID, '%s,%d,%s\n', timestamp, app.AttemptCount, statusString);
        end
    end
    methods (Access = protected)
        function setup(app)
            warning('off', 'all');
            figWidth = 500;
            figHeight = 480;
            screenSize = get(0, 'ScreenSize');
            screenWidth = screenSize(3);
            screenHeight = screenSize(4);
            left = (screenWidth - figWidth) / 2;
            bottom = (screenHeight - figHeight) / 2;
            app.UIFigure = uifigure('Name', 'License Acquisition Manager', 'Position', [left bottom figWidth figHeight]);
            appPath = fileparts(mfilename('fullpath'));
            app.LogFileName = fullfile(appPath, 'license_log.csv');
            logoPath = fullfile(appPath, 'assets', 'NNS Logo.png');
            app.LogoImage = uiimage(app.UIFigure, 'Position', [150 380 200 80], 'ImageSource', logoPath);
            app.StatusPanel = uipanel(app.UIFigure, 'Position', [25 200 450 150], 'BorderType', 'none');
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
                
                initialValue = 1;
                if strcmp(rawName, 'simscape_battery')
                    initialValue = 0;
                end
                
                app.CheckBoxes(i) = uicheckbox(app.StatusPanel, 'Text', '', 'Position', [20 yPos 40 22], 'Value', initialValue);
                app.NameLabels(i) = uilabel(app.StatusPanel, 'Text', displayName, 'Position', [100 yPos 180 22]);
                app.StatusLabels(i) = uilabel(app.StatusPanel, 'Text', 'IDLE', 'Position', [300 yPos 130 22]);
                
                % Set initial color for battery if unchecked
                if initialValue == 0
                    app.NameLabels(i).FontColor = [0.5 0.5 0.5];
                end
            end
            app.MetricsLabel = uilabel(app.UIFigure, 'Text', 'Elapsed Time: 0 | Total Checks: 0', 'Position', [50 80 400 44], 'HorizontalAlignment', 'center');
            app.StartButton = uibutton(app.UIFigure, 'push', 'Text', 'Start Acquisition', ...
                'Position', [120 20 120 30], 'ButtonPushedFcn', @(btn, event) app.startProcess());
            app.StopButton = uibutton(app.UIFigure, 'push', 'Text', 'Stop', ...
                'Position', [260 20 120 30], 'Enable', 'off', 'ButtonPushedFcn', @(btn, event) app.stopProcess());
            app.GraphButton = uibutton(app.UIFigure, 'push', 'Text', '📈', ...
                'Position', [420 440 30 30], 'ButtonPushedFcn', @(btn, event) LicenseAnalytics());
        end
        function startProcess(app)
            app.AttemptCount = 0;
            app.StartTime = datetime('now');
            app.AcquisitionTime = [];
            app.LogFileID = fopen(app.LogFileName, 'a');
            fseek(app.LogFileID, 0, 'eof');
            if ftell(app.LogFileID) == 0
                headerStr = strjoin(['Timestamp', 'Attempt', app.FeatureOrder], ',');
                fprintf(app.LogFileID, '%s\n', headerStr);
            end
            app.StartButton.Enable = 'off';
            app.StopButton.Enable = 'on';
            app.Timer = timer('ExecutionMode', 'fixedRate', 'Period', 1, ...
                'TimerFcn', @(~,~) app.updateLicenseStatus());
            start(app.Timer);
        end
        function stopProcess(app)
            if ~isempty(app.Timer)
                stop(app.Timer);
                delete(app.Timer);
            end
            if ~isempty(app.LogFileID)
                fclose(app.LogFileID);
            end
            app.StartButton.Enable = 'on';
            app.StopButton.Enable = 'off';
        end
    end
    methods (Access = public)
        function app = MATLABLicenseAcquisition()
            app.setup();
        end
    end
end