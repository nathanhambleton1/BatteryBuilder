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
    % "Toolbox Stats" opens team-wide stats for each toolbox (6am-6pm), built from everyone's
    % toolbox logs on the shared drive.
    %
    % Note: MATLAB has no way to hand back a single toolbox license once it is checked out.
    % Licenses are returned when MATLAB exits, which is what "Release All & Exit" does (MATLAB
    % closes about a second after the release is confirmed).
    %
    % Both windows use the same dark terminal look as the PowerShell "MATLAB License Hunter".
    properties (Access = public)
        UIFigure      matlab.ui.Figure
        StartButton   matlab.ui.control.Button
        StopButton    matlab.ui.control.Button
        ReleaseButton matlab.ui.control.Button
        StatsButton   matlab.ui.control.Button
        StatsFigure   matlab.ui.Figure
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
        % Matches the PowerShell "MATLAB License Hunter" console
        Background = [0.05 0.05 0.05];
        Panel      = [0.09 0.09 0.09];
        Border     = [0 0.53 0.69];      % teal (xterm 31)
        Ink        = [0.93 0.93 0.93];
        Muted      = [0.50 0.50 0.50];
        Accent     = [1 0.53 0];         % MATLAB orange (xterm 208)
        Good       = [0 0.85 0.25];
        Warn       = [1 0.84 0];
        Bad        = [1 0.25 0.25];
        Idle       = [0.35 0.35 0.35];
        Font       = 'Consolas';
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
            % Bright badges with black text, like the console
            colors = struct('IDLE', app.Idle, 'WAITING', app.Warn, 'ACQUIRED', app.Good, 'SKIPPED', app.Panel);
            label = app.StatusLabels(i);
            label.Text = state;
            label.BackgroundColor = colors.(state);
            label.FontColor = [0 0 0];
            if strcmp(state, 'SKIPPED')
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
                app.AcquiredCaption.Text = ['ALL IN AT ' char(app.AcquisitionTime, 'h:mm a')];
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
            % Don't tear down or exit here: this can be running inside WatchTimer's own callback,
            % and deleting a running timer / calling exit from inside it can crash or hang MATLAB on
            % the way out, leaving half-written prefs that break every later start. So only stop
            % the timers now, and let a one-shot timer delete the app and exit once this returns.
            app.stopTimers();
            if ~isempty(app.ReleaseButton) && isvalid(app.ReleaseButton)
                app.ReleaseButton.Enable = 'off';
            end
            exitTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 1, ...
                'TimerFcn', @(~, ~) app.deleteAndExit());
            start(exitTimer);
        end

        function deleteAndExit(app)
            % Runs from the one-shot timer: the other timers are stopped by now, so the
            % destructor can safely delete them along with the windows
            try
                delete(app);
            catch
            end
            % exit deletes this still-running one-shot timer; that's expected, so skip the warning
            warning('off', 'MATLAB:timer:deleterunning');
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

        function stopTimers(app)
            % Stop only (never delete): safe to call from inside either timer's own callback
            app.stopProcess();
            if ~isempty(app.WatchTimer) && isvalid(app.WatchTimer)
                stop(app.WatchTimer);
            end
        end

        function cleanup(app)
            app.stopTimers();
            if ~isempty(app.Timer) && isvalid(app.Timer)
                delete(app.Timer);
            end
            if ~isempty(app.WatchTimer) && isvalid(app.WatchTimer)
                delete(app.WatchTimer);
            end
            if ~isempty(app.StatsFigure) && isvalid(app.StatsFigure)
                delete(app.StatsFigure);
            end
        end

        function hg = addHeader(app, parent, word1, word2, subText, sideWidth)
            % Dark title bar with a thin teal rule under it; column 2 (sideWidth wide) is left
            % free for the caller. The title is two words: word1 in orange, word2 light.
            header = uipanel(parent, 'BackgroundColor', app.Background, 'BorderType', 'none');
            outer = uigridlayout(header, [2 1], 'RowHeight', {'1x', 2}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 0, 'BackgroundColor', app.Background);
            logoPath = fullfile(fileparts(mfilename('fullpath')), 'assets', 'NNS Logo.png');
            logoWidth = 90 * isfile(logoPath);
            hg = uigridlayout(outer, [2 3], 'ColumnWidth', {'1x', sideWidth, logoWidth}, 'RowHeight', {'1x', 18}, ...
                'Padding', [20 10 16 10], 'RowSpacing', 0, 'ColumnSpacing', 12, 'BackgroundColor', app.Background);
            hg.Layout.Row = 1;
            rule = uipanel(outer, 'BackgroundColor', app.Border, 'BorderType', 'none');
            rule.Layout.Row = 2;

            titleGrid = uigridlayout(hg, [1 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 8, 'BackgroundColor', app.Background);
            titleGrid.Layout.Row = 1;
            titleGrid.Layout.Column = 1;
            uilabel(titleGrid, 'Text', word1, 'FontName', app.Font, 'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', app.Accent);
            uilabel(titleGrid, 'Text', word2, 'FontName', app.Font, 'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', app.Ink);
            sub = uilabel(hg, 'Text', subText, 'FontName', app.Font, 'FontSize', 11, 'FontColor', app.Muted);
            sub.Layout.Row = 2;
            sub.Layout.Column = 1;
            if logoWidth > 0
                logo = uiimage(hg, 'ImageSource', logoPath);
                logo.Layout.Row = [1 2];
                logo.Layout.Column = 3;
            end
        end

        function card = addCard(app, parent)
            % Panel-coloured card with a teal line border (border properties vary by release)
            card = uipanel(parent, 'BackgroundColor', app.Panel, 'BorderType', 'line');
            try
                card.BorderColor = app.Border;
            catch
                try
                    card.HighlightColor = app.Border;
                catch
                end
            end
            try
                card.BorderWidth = 1;
            catch
            end
        end

        function T = loadToolboxLog(app)
            % Everyone's toolbox CSVs from the shared drive, stacked into one table
            T = table();
            files = dir(fullfile(app.DataRoot, 'toolboxes', '*.csv'));
            for k = 1:numel(files)
                try
                    file = fullfile(files(k).folder, files(k).name);
                    opts = detectImportOptions(file, 'Delimiter', ',', 'TextType', 'string');
                    opts = setvartype(opts, 'string');
                    part = readtable(file, opts);
                    T = [T; part(:, {'Timestamp', 'User', 'Computer', 'Session', 'Feature', 'Event', 'WaitSeconds'})]; %#ok<AGROW>
                catch
                    % a file someone is writing right now can be skipped until next time
                end
            end
            if isempty(T)
                return;
            end
            T.Time = datetime(T.Timestamp, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
            T.Wait = str2double(T.WaitSeconds);
        end

        function [summary, hourly, nRequests, nPeople] = toolboxStats(app)
            % One "request" = one toolbox someone asked for in one session (6am-6pm only).
            % "Free right away" = acquired within 5 s, i.e. a seat was open when they asked.
            hours = 6:17;
            k = numel(app.FeatureOrder);
            names = string(values(app.FeaturesMap, app.FeatureOrder))';
            hourly = nan(numel(hours), k);
            requests = zeros(k, 1); gotIt = zeros(k, 1); instantPct = nan(k, 1);
            avgWait = nan(k, 1); maxWait = nan(k, 1); lastGot = NaT(k, 1);
            nRequests = 0;
            nPeople = 0;

            T = app.loadToolboxLog();
            if ~isempty(T)
                T = T(ismember(T.Event, ["WAITING", "ACQUIRED"]) & ~isnat(T.Time), :);
            end
            if ~isempty(T)
                g = findgroups(T.User, T.Computer, T.Session, T.Feature);
                startT = splitapply(@min, T.Time, g);
                feat = splitapply(@(f) f(1), T.Feature, g);
                user = splitapply(@(u) u(1), T.User, g);
                got = splitapply(@(e) any(e == "ACQUIRED"), T.Event, g);
                wait = splitapply(@(w, e) max([w(e == "ACQUIRED"); NaN]), T.Wait, T.Event, g);
                gotAt = startT + seconds(wait);

                keep = ismember(hour(startT), hours);
                [startT, feat, user, got, wait, gotAt] = deal(startT(keep), feat(keep), user(keep), got(keep), wait(keep), gotAt(keep));
                nRequests = numel(feat);
                nPeople = numel(unique(user));
                instant = got & wait <= 5;

                for i = 1:k
                    m = feat == app.FeatureOrder{i};
                    requests(i) = nnz(m);
                    gotIt(i) = nnz(m & got);
                    if requests(i)
                        instantPct(i) = 100 * nnz(m & instant) / requests(i);
                    end
                    if gotIt(i)
                        avgWait(i) = mean(wait(m & got));
                        maxWait(i) = max(wait(m & got));
                        lastGot(i) = max(gotAt(m & got));
                    end
                    for j = 1:numel(hours)
                        mh = m & hour(startT) == hours(j);
                        if any(mh)
                            hourly(j, i) = 100 * nnz(mh & instant) / nnz(mh);
                        end
                    end
                end
            end

            gotPct = strings(k, 1);
            lastText = strings(k, 1);
            for i = 1:k
                gotPct(i) = "-";
                if requests(i)
                    gotPct(i) = sprintf('%d%%', round(100 * gotIt(i) / requests(i)));
                end
                lastText(i) = "-";
                if ~isnat(lastGot(i))
                    lastText(i) = string(char(lastGot(i), 'MMM d, h:mm a'));
                end
            end
            summary = table(names, requests, gotIt, gotPct, ...
                string(arrayfun(@(p) app.fmtPct(p), instantPct, 'UniformOutput', false)), ...
                string(arrayfun(@(s) app.fmtWait(s), avgWait, 'UniformOutput', false)), ...
                string(arrayfun(@(s) app.fmtWait(s), maxWait, 'UniformOutput', false)), lastText, ...
                'VariableNames', {'Toolbox', 'Requests', 'GotIt', 'GotPct', 'Instant', 'AvgWait', 'LongestWait', 'LastGot'});
            summary.AvgWaitMinutes = avgWait / 60;
        end

        function showToolboxStats(app)
            if ~isempty(app.StatsFigure) && isvalid(app.StatsFigure)
                delete(app.StatsFigure);   % reopen with fresh data
            end
            [summary, hourly, nRequests, nPeople] = app.toolboxStats();

            pos = app.UIFigure.Position;
            app.StatsFigure = uifigure('Name', 'Toolbox License Stats', 'Color', app.Background, ...
                'Position', [pos(1) + 40, pos(2) - 80, 880, 570]);
            main = uigridlayout(app.StatsFigure, [3 1], 'RowHeight', {70, '1x', 176}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', app.Background);
            hg = app.addHeader(main, 'TOOLBOX', 'LICENSE STATS', ...
                sprintf('Whole team  %s  6am-6pm  %s  %d requests from %d people', char(183), char(183), nRequests, nPeople), 90);
            refresh = uibutton(hg, 'push', 'Text', 'Refresh', 'FontName', app.Font, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.15 0.15 0.15], 'FontColor', app.Ink, 'ButtonPushedFcn', @(~, ~) app.showToolboxStats());
            refresh.Layout.Row = [1 2];
            refresh.Layout.Column = 2;

            if nRequests == 0
                empty = uigridlayout(main, [1 1], 'Padding', [16 16 16 16], 'BackgroundColor', app.Background);
                uilabel(empty, 'Text', 'No toolbox data yet. It fills in as people use the License Acquisition window.', ...
                    'FontName', app.Font, 'FontSize', 13, 'FontColor', app.Muted, 'HorizontalAlignment', 'center');
                return;
            end

            % Console palette: MATLAB orange plus bright blue, green, purple, grey
            colors = [app.Accent; 0.37 0.69 1; app.Good; 0.69 0.53 1; app.Muted];
            names = summary.Toolbox;
            k = numel(names);

            charts = uigridlayout(main, [1 2], 'ColumnWidth', {'1x', '1.35x'}, 'Padding', [16 14 16 8], ...
                'ColumnSpacing', 12, 'BackgroundColor', app.Background);

            ax1 = app.addChartAxes(charts);
            waitMin = summary.AvgWaitMinutes;
            waitMin(isnan(waitMin)) = 0;
            b = barh(ax1, 1:k, waitMin, 0.6, 'FaceColor', 'flat', 'EdgeColor', 'none');
            b.CData = colors(1:k, :);
            ax1.YTick = 1:k;
            ax1.YTickLabel = names;
            ax1.YDir = 'reverse';
            ax1.YLim = [0.4, k + 0.6];
            title(ax1, 'Average wait to get it (minutes)', 'FontWeight', 'bold', 'Color', app.Ink);

            ax2 = app.addChartAxes(charts);
            hold(ax2, 'on');
            hours = 6:17;
            for i = 1:k
                plot(ax2, hours, hourly(:, i), '-o', 'Color', colors(i, :), 'LineWidth', 1.8, ...
                    'MarkerSize', 5, 'MarkerFaceColor', colors(i, :));
            end
            hold(ax2, 'off');
            ax2.XLim = [5.6 17.4];
            ax2.YLim = [0 100];
            ax2.XTick = hours;
            ax2.XTickLabel = {'6a', '7a', '8a', '9a', '10a', '11a', '12p', '1p', '2p', '3p', '4p', '5p'};
            ax2.YGrid = 'on';
            title(ax2, 'Free right away, by hour (%)', 'FontWeight', 'bold', 'Color', app.Ink);
            legend(ax2, names, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off', 'NumColumns', 3, ...
                'TextColor', app.Ink, 'FontName', app.Font);

            tableArea = uigridlayout(main, [1 1], 'Padding', [16 0 16 14], 'BackgroundColor', app.Background);
            shown = summary(:, {'Toolbox', 'Requests', 'GotIt', 'GotPct', 'Instant', 'AvgWait', 'LongestWait', 'LastGot'});
            uitable(tableArea, 'Data', shown, 'RowName', {}, 'FontName', app.Font, 'FontSize', 12, 'RowStriping', 'on', ...
                'BackgroundColor', [app.Panel; 0.13 0.13 0.13], 'ForegroundColor', app.Ink, ...
                'ColumnName', {'Toolbox', 'Requests', 'Got it', 'Got it %', 'Free right away', 'Avg wait', 'Longest wait', 'Last got it'}, ...
                'ColumnWidth', {190, 70, 60, 70, 110, 75, 95, 'auto'});
        end

        function ax = addChartAxes(app, parent)
            card = app.addCard(parent);
            g = uigridlayout(card, [1 1], 'Padding', [8 8 12 8], 'BackgroundColor', app.Panel);
            ax = uiaxes(g, 'Color', app.Panel, 'XColor', app.Muted, 'YColor', app.Muted, 'GridColor', [0.35 0.35 0.35], ...
                'FontName', app.Font, 'FontSize', 11, 'Box', 'off');
            try
                ax.BackgroundColor = app.Panel;   % newer releases only
            catch
            end
            ax.Toolbar.Visible = 'off';
            disableDefaultInteractivity(ax);
        end

        function [value, caption] = addTile(app, parent, captionText, initial)
            tile = app.addCard(parent);
            g = uigridlayout(tile, [2 1], 'RowHeight', {16, '1x'}, 'Padding', [12 8 12 6], ...
                'RowSpacing', 0, 'BackgroundColor', app.Panel);
            caption = uilabel(g, 'Text', captionText, 'FontName', app.Font, 'FontSize', 10, 'FontWeight', 'bold', ...
                'FontColor', app.Muted);
            value = uilabel(g, 'Text', initial, 'FontName', app.Font, 'FontSize', 20, 'FontWeight', 'bold', ...
                'FontColor', app.Ink);
        end
    end
    methods (Static, Access = private)
        function s = fmtWait(sec)
            if isnan(sec)
                s = "-";
            elseif sec < 60
                s = sprintf('%ds', round(sec));
            elseif sec < 3600
                s = sprintf('%dm', round(sec / 60));
            else
                s = sprintf('%.1fh', sec / 3600);
            end
        end

        function s = fmtPct(p)
            if isnan(p)
                s = "-";
            else
                s = sprintf('%d%%', round(p));
            end
        end
    end
    methods (Access = protected)
        function setup(app)
            figWidth = 500;
            figHeight = 430;
            screenSize = get(0, 'ScreenSize');
            app.UIFigure = uifigure('Name', 'License Acquisition', 'Color', app.Background, 'Resize', 'off', ...
                'Position', [(screenSize(3) - figWidth) / 2, (screenSize(4) - figHeight) / 2, figWidth, figHeight], ...
                'CloseRequestFcn', @(~, ~) app.onClose());
            main = uigridlayout(app.UIFigure, [4 1], 'RowHeight', {70, '1x', 76, 58}, ...
                'Padding', [0 0 0 0], 'RowSpacing', 0, 'BackgroundColor', app.Background);

            % Header bar
            hg = app.addHeader(main, 'MATLAB', 'LICENSE ACQUISITION', ...
                sprintf('%s  %s  MATLAB %s', app.ClientId, char(183), version('-release')), 112);
            app.StatsButton = uibutton(hg, 'push', 'Text', 'Toolbox Stats', 'FontName', app.Font, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.15 0.15 0.15], 'FontColor', app.Ink, ...
                'Tooltip', 'Team stats for each toolbox license', 'ButtonPushedFcn', @(~, ~) app.showToolboxStats());
            app.StatsButton.Layout.Row = [1 2];
            app.StatsButton.Layout.Column = 2;

            % Toolbox list card
            body = uigridlayout(main, [1 1], 'Padding', [16 14 16 10], 'BackgroundColor', app.Background);
            card = app.addCard(body);
            n = length(app.FeatureOrder);
            cg = uigridlayout(card, [n + 1, 2], 'ColumnWidth', {'1x', 96}, 'RowHeight', [{18}, repmat({26}, 1, n)], ...
                'Padding', [16 10 16 12], 'RowSpacing', 6, 'BackgroundColor', app.Panel);
            uilabel(cg, 'Text', 'TOOLBOX', 'FontName', app.Font, 'FontSize', 10, 'FontWeight', 'bold', 'FontColor', app.Muted);
            uilabel(cg, 'Text', 'STATUS', 'FontName', app.Font, 'FontSize', 10, 'FontWeight', 'bold', 'FontColor', app.Muted, ...
                'HorizontalAlignment', 'center');
            app.StatusLabels = gobjects(n, 1);
            app.CheckBoxes = gobjects(n, 1);
            for i = 1:n
                rawName = app.FeatureOrder{i};
                % Battery is opt-in: it's scarce, so only take it when you tick it
                app.CheckBoxes(i) = uicheckbox(cg, 'Text', app.FeaturesMap(rawName), 'FontName', app.Font, 'FontSize', 13, ...
                    'FontColor', app.Ink, 'Value', ~strcmp(rawName, 'simscape_battery'));
                app.StatusLabels(i) = uilabel(cg, 'Text', 'IDLE', 'FontName', app.Font, 'FontSize', 10, 'FontWeight', 'bold', ...
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
            app.StartButton = uibutton(actions, 'push', 'Text', 'Start', 'FontName', app.Font, 'FontWeight', 'bold', ...
                'FontSize', 13, 'BackgroundColor', app.Accent, 'FontColor', [0 0 0], 'ButtonPushedFcn', @(~, ~) app.startProcess());
            app.StopButton = uibutton(actions, 'push', 'Text', 'Stop', 'FontName', app.Font, 'FontSize', 13, 'Enable', 'off', ...
                'BackgroundColor', app.Panel, 'FontColor', app.Ink, 'ButtonPushedFcn', @(~, ~) app.stopProcess());
            app.ReleaseButton = uibutton(actions, 'push', 'Text', 'Release All & Exit', 'FontName', app.Font, 'FontSize', 13, ...
                'BackgroundColor', app.Panel, 'FontColor', app.Bad, 'Tooltip', 'Closes MATLAB, returning every license', ...
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

        function delete(app)
            % Stop the timers too when the app is deleted from code, not just when its window closes
            app.cleanup();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end
end
