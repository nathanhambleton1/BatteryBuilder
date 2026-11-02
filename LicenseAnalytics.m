function LicenseAnalytics(dataRoot)
    % Team license analytics from the shared LicenseData folder written by GrabMatlabLicense.ps1
    % and MATLABLicenseAcquisition.m.
    if nargin < 1 || isempty(dataRoot)
        dataRoot = fullfile(fileparts(mfilename('fullpath')), 'LicenseData');
    end
    attempts = readFolder(fullfile(dataRoot, 'attempts'));
    if isempty(attempts)
        uialert(uifigure('Name', 'License Analytics'), 'No attempts logged yet.', 'License Analytics');
        return;
    end
    t = datetime(attempts.Timestamp, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
    result = string(attempts.Result);
    checked = ismember(result, ["SUCCESS", "DENIED", "FULL"]);
    ok = result == "SUCCESS";

    hourOk = accumarray(hour(t(checked)) + 1, ok(checked), [24 1]);
    hourAll = accumarray(hour(t(checked)) + 1, 1, [24 1]);
    day = mod(weekday(t(checked)) - 2, 7) + 1;   % Mon = 1
    heatOk = accumarray([day, hour(t(checked)) + 1], ok(checked), [7 24]);
    heatAll = accumarray([day, hour(t(checked)) + 1], 1, [7 24]);

    fig = uifigure('Name', 'License Analytics', 'Position', [200 200 900 650]);
    grid = uigridlayout(fig, [2 1]);

    ax1 = uiaxes(grid);
    bar(ax1, 0:23, 100 * hourOk ./ max(hourAll, 1));
    xlabel(ax1, 'Hour of day');
    ylabel(ax1, '% of checks that got MATLAB');
    title(ax1, sprintf('Availability by hour  (%d launches, %d successes, %d users)', ...
        nnz(ismember(result, ["SUCCESS", "DENIED", "TIMEOUT", "ERROR"])), nnz(ok), numel(unique(attempts.User))));
    xlim(ax1, [-0.5 23.5]);
    ylim(ax1, [0 100]);

    rate = 100 * heatOk ./ heatAll;   % NaN where there is no data
    h = heatmap(grid, 0:23, {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'}, rate);
    h.Title = '% of checks that got MATLAB, by weekday and hour';
    h.XLabel = 'Hour';
    h.Colormap = interp1([0 0.5 1], [0.85 0.1 0.1; 0.95 0.8 0.1; 0.1 0.7 0.2], linspace(0, 1, 64));
    h.ColorLimits = [0 100];
    h.MissingDataLabel = 'no data';
end

function tbl = readFolder(folder)
    tbl = table();
    files = dir(fullfile(folder, '*.csv'));
    for k = 1:numel(files)
        opts = detectImportOptions(fullfile(folder, files(k).name), 'Delimiter', ',', 'TextType', 'string');
        opts = setvartype(opts, 'string');
        part = readtable(fullfile(folder, files(k).name), opts);
        tbl = [tbl; part(:, {'Timestamp', 'User', 'Result'})]; %#ok<AGROW>
    end
end
