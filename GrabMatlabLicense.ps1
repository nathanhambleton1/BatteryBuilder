<#
.SYNOPSIS
    MATLAB License Hunter - keeps trying to get a MATLAB seat and shows live team analytics
    right in the PowerShell window.

.DESCRIPTION
    Right-click this file -> "Run with PowerShell" (Windows 11: "Show more options" first).
    Keep it next to MATLABLicenseAcquisition.m on the shared network drive.
    If your PC blocks scripts, open PasteIntoPowerShell.txt instead and follow the steps in it.

    What it does:
      * Launches MATLAB and watches the window for a licensing error, killing and retrying
        until it gets in.
      * Once MATLAB starts, MATLAB auto-runs MATLABLicenseAcquisition.m, which grabs the toolbox
        licenses (Simulink, Simscape, ...) and logs them too.
      * Every attempt by every user is logged to the shared LicenseData folder next to this script,
        so the dashboard shows when during the work day (6am-6pm) MATLAB is actually obtainable.

    Keys:  [H] hunt  [P] pause/resume  [R] release MATLAB (asks MATLAB to quit)  [K] kill MATLAB
           [D] details page  [Q] quit

    Details page: [D] opens MATLABLicenseHunter.html (keep it next to this script) in your browser.
    It reads LicenseData\dashboard-data.js, which this dashboard rewrites whenever the data changes.

    Releasing licenses: MATLAB can't hand back a single toolbox license; everything is returned
    only when MATLAB exits ([R] here, or "Release All & Exit" in the MATLAB window).

    A MATLAB that fails to start is closed gently first. If it has to be force-killed mid-startup,
    MATLAB's preferences folder is restored from a snapshot taken when the hunt started, so a
    half-written prefs file can't make MATLAB crash on its next start.

.EXAMPLE
    .\GrabMatlabLicense.ps1 -DashboardOnly
#>
[CmdletBinding()]
param(
    # Path to bin\win64\MATLAB.exe. Blank = newest install under C:\Program Files\MATLAB.
    [string]$MatlabPath = '',
    # Shared tracking folder. Blank = .\LicenseData next to this script (put the script on the network drive).
    [string]$DataRoot = '',
    # Seconds between MATLAB launches.
    [int]$RetryDelaySeconds = 5,
    # Give up on a single launch after this long.
    [int]$LaunchTimeoutSeconds = 180,
    # Without the MATLAB auto-run script: seconds the MATLAB window must be up with no error to count as success.
    [int]$ConfirmSeconds = 15,
    # Don't auto-run MATLABLicenseAcquisition inside MATLAB.
    [switch]$NoAutoRun,
    # Open the dashboard without starting a hunt (press H to start one).
    [switch]$DashboardOnly,
    # Print a single frame and exit (for testing).
    [switch]$RenderOnce,
    # Folder this script lives in. Only needed when it's run as pasted code (PasteIntoPowerShell.txt),
    # where PowerShell can't tell where the file came from.
    [string]$ScriptRoot = ''
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# ---------------------------------------------------------------------------------------------
# Paths and shared data layout
# ---------------------------------------------------------------------------------------------
$ScriptDir = if ($ScriptRoot) { $ScriptRoot } elseif ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $DataRoot) { $DataRoot = Join-Path $ScriptDir 'LicenseData' }
$Me = $env:USERNAME
$ClientId = "$($env:USERNAME)@$($env:COMPUTERNAME)"
$Dirs = @{
    Attempts  = Join-Path $DataRoot 'attempts'    # one CSV per user@pc, written by this script
    Toolboxes = Join-Path $DataRoot 'toolboxes'   # one CSV per user@pc, written by MATLABLicenseAcquisition.m
    Active    = Join-Path $DataRoot 'active'      # heartbeats + ready/release signals
}
foreach ($d in $Dirs.Values) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$MyAttemptFile = Join-Path $Dirs.Attempts "$ClientId.csv"
$HeartbeatFile = Join-Path $Dirs.Active "$ClientId.txt"
$ReadyFile     = Join-Path $Dirs.Active "$ClientId.ready"
$ReleaseFile   = Join-Path $Dirs.Active "$ClientId.release"
$AttemptHeader = 'Timestamp,User,Computer,Hunt,Result,Seconds,SeatsUsed,SeatsTotal,Detail'
$Inv = [Globalization.CultureInfo]::InvariantCulture
$DayHours = 6..17   # analytics only cover the 6am-6pm work day

$LicenseErrorPatterns = @(
    '*Licensing Error*', '*License Manager Error*', '*licensed number of users*',
    '*License checkout failed*', '*maximum number of users*'
)

# ---------------------------------------------------------------------------------------------
# MATLAB discovery
# ---------------------------------------------------------------------------------------------
function Find-Matlab {
    $installs = Get-ChildItem -Path 'C:\Program Files\MATLAB' -Directory -Filter 'R20*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($i in $installs) {
        $exe = Join-Path $i.FullName 'bin\win64\MATLAB.exe'
        if (Test-Path $exe) { return $exe }
    }
    return $null
}

if (-not $MatlabPath) { $MatlabPath = Find-Matlab }
$MatlabRoot = if ($MatlabPath) { Split-Path (Split-Path (Split-Path $MatlabPath)) } else { $null }

# MATLAB's per-release preferences folder, and where we keep a known-good copy of it during a hunt
$Release  = if ($MatlabRoot) { Split-Path $MatlabRoot -Leaf } else { '' }
$PrefDir  = if ($Release) { Join-Path $env:APPDATA "MathWorks\MATLAB\$Release" } else { '' }
$PrefSnap = if ($Release) { Join-Path $env:LOCALAPPDATA "MatlabLicenseHunter\prefs-$Release" } else { '' }

# ---------------------------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------------------------
$S = @{
    Mode = 'IDLE'            # IDLE | HUNT | HAVE
    Phase = 'WAIT'           # (HUNT) WAIT | LAUNCH | CLOSING
    Paused = $false
    Quit = $false
    Attempt = 0
    HuntId = ''
    HuntStart = $null
    HuntStrip = New-Object System.Collections.Generic.List[string]
    NextAt = Get-Date
    Proc = $null
    OwnSession = $false
    TreeIds = @()
    LaunchTime = $null
    MainSeenAt = $null
    NextScan = Get-Date
    SessionStart = $null
    LastResult = ''
    LastDetail = ''
    Rows = @()
    Tool = @()
    Stats = $null
    Online = @()
    NextData = Get-Date
    NextBeat = Get-Date
    BeatMode = ''
    ShareSkew = [timespan]::Zero
    CloseBy = $null          # (CLOSING) force-kill after this
    PrefSnapOk = $false
    ReleaseAt = $null
    ReleaseWarned = $false
    KillAt = $null
    Popup = $null            # @{ Op = R|K|Q|GOT; Stage = CONFIRM|WORK|DONE; Since; Secs }
    NextRender = Get-Date
    NextExport = Get-Date
    ExportSig = ''
    Log = New-Object System.Collections.Generic.List[object]   # @{ T; Kind; Msg }
    Spin = 0
}

# ---------------------------------------------------------------------------------------------
# Glyphs and colors (built from code points so the file stays plain ASCII)
# ---------------------------------------------------------------------------------------------
$E = [string][char]27
function U([int]$code) { [string][char]$code }
$G = @{
    H = U 0x2550; V = U 0x2551; TL = U 0x2554; TR = U 0x2557; BL = U 0x255A; BR = U 0x255D
    LT = U 0x2560; RT = U 0x2563; TT = U 0x2566; BT = U 0x2569; X = U 0x256C
    Full = U 0x2588; Dot = U 0x25CF; Ring = U 0x25CB; Mid = U 0x00B7; Cross = U 0x00D7
    Ell = U 0x2026; Light = U 0x2591; AxV = U 0x2502; AxC = U 0x2514; AxH = U 0x2500; Up = U 0x25B2
}
$Eighths = @(' ') + (0x2581..0x2588 | ForEach-Object { U $_ })
$Grad = @(196, 202, 208, 214, 220, 226, 190, 154, 118, 46)   # red -> green
$BorderColor = 31
$AnsiRx = [regex]"$([char]27)\[[0-9;?]*[A-Za-z]"

function C([string]$t, [int]$c) { "$E[38;5;$($c)m$t$E[0m" }
function Bold([string]$t, [int]$c) { "$E[1;38;5;$($c)m$t$E[0m" }
function Badge([string]$t, [int]$bg) { "$E[1;48;5;$($bg);38;5;16m $t $E[0m" }
function VisLen([string]$str) { $AnsiRx.Replace($str, '').Length }
function Fit([string]$str, [int]$w) {
    $v = VisLen $str
    if ($v -le $w) { return $str + (' ' * ($w - $v)) }
    $plain = $AnsiRx.Replace($str, '')
    return $plain.Substring(0, $w - 1) + $G.Ell
}
# Shortens plain text to $w columns with an ellipsis (color it afterwards so colors survive).
function Trunc([string]$s, [int]$w) {
    if ($w -le 0) { return '' }
    if ($s.Length -le $w) { return $s }
    return $s.Substring(0, $w - 1) + $G.Ell
}
# Word-wraps plain text to $w columns; words longer than a line (paths) are hard-split.
function Wrap-Text([string]$s, [int]$w) {
    $out = New-Object System.Collections.Generic.List[string]
    $cur = ''
    foreach ($word in ($s -split ' ' | Where-Object { $_ })) {
        while ($word.Length -gt $w) {
            $room = if ($cur) { $w - $cur.Length - 1 } else { $w }
            if ($room -lt 8) { $out.Add($cur); $cur = ''; continue }
            $out.Add($(if ($cur) { "$cur $($word.Substring(0, $room))" } else { $word.Substring(0, $room) }))
            $cur = ''
            $word = $word.Substring($room)
        }
        if (-not $word) { continue }
        if (-not $cur) { $cur = $word }
        elseif ($cur.Length + 1 + $word.Length -le $w) { $cur += " $word" }
        else { $out.Add($cur); $cur = $word }
    }
    if ($cur -or $out.Count -eq 0) { $out.Add($cur) }
    $out.ToArray()
}
function RateColor([double]$p) { $Grad[[math]::Min(9, [int][math]::Floor($p * 10))] }
function Fmt-Dur([double]$sec) {
    if ($sec -lt 0) { $sec = 0 }
    $ts = [timespan]::FromSeconds($sec)
    if ($ts.TotalHours -ge 1) { return '{0}h{1:00}m' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes }
    if ($ts.TotalMinutes -ge 1) { return '{0}m{1:00}s' -f $ts.Minutes, $ts.Seconds }
    return '{0}s' -f $ts.Seconds
}
function Fmt-Clock([double]$sec) {
    $ts = [timespan]::FromSeconds([math]::Max(0, $sec))
    '{0:00}:{1:00}:{2:00}' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds
}
function Fmt-N([int]$n) { $n.ToString('N0', $Inv) }
function Result-Glyph([string]$r) {
    switch ($r) {
        'SUCCESS' { C $G.Dot 46 }
        'DENIED'  { C $G.Cross 196 }
        'FULL'    { C $G.Mid 240 }
        default   { C '!' 220 }
    }
}
function Result-Color([string]$r) {
    switch ($r) { 'SUCCESS' { 46 } 'DENIED' { 196 } 'FULL' { 208 } default { 220 } }
}

# Two-row block font for the banner: '#' full, '^' upper half, '_' lower half
$Font = @{
    'M' = @('#^_^#', '# ^ #'); 'A' = @('_^#', '#^#'); 'T' = @('^#^', ' # '); 'L' = @('#  ', '#__')
    'B' = @('#__', '#_#'); 'I' = @('#', '#'); 'C' = @('#^^', '#__'); 'E' = @('#^^', '##_')
    'N' = @('#_ #', '# ^#'); 'S' = @('#^', '_#'); 'H' = @('# #', '#^#'); 'U' = @('# #', '#_#')
    'R' = @('#^#', '#^_'); ' ' = @('  ', '  ')
}
# Renders (text, color) pairs side by side, one flat color per word.
function New-Banner([object[]]$words) {
    $out = @('', '')
    foreach ($w in $words) {
        for ($i = 0; $i -lt 2; $i++) {
            $row = (($w.Text.ToCharArray() | ForEach-Object { $Font[[string]$_][$i] }) -join ' ')
            $row = $row.Replace('#', $G.Full).Replace('^', (U 0x2580)).Replace('_', (U 0x2584))
            $out[$i] += (C $row $w.Color) + '   '
        }
    }
    $out
}
$Banner = New-Banner @(@{ Text = 'MATLAB'; Color = 208 }, @{ Text = 'LICENSE HUNTER'; Color = 252 })

# ---------------------------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------------------------
function Add-Log([string]$kind, [string]$msg) {
    $S.Log.Add(@{ T = Get-Date; Kind = $kind; Msg = $msg })
    while ($S.Log.Count -gt 50) { $S.Log.RemoveAt(0) }
}

function Add-SharedLine([string]$path, [string]$header, [string]$line) {
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $text = $line + "`r`n"
            if (-not (Test-Path $path)) { $text = $header + "`r`n" + $text }
            [IO.File]::AppendAllText($path, $text)
            return $true
        } catch { Start-Sleep -Milliseconds 300 }
    }
    Add-Log 'WARN' "Could not write to shared log $path"
    return $false
}

function Write-Attempt([string]$result, [double]$seconds, [string]$detail) {
    $clean = ($detail -replace '[,\r\n"]', ' ').Trim()
    if ($clean.Length -gt 120) { $clean = $clean.Substring(0, 120) }
    $line = '{0},{1},{2},{3},{4},{5},,,{6}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $Inv),
        $env:USERNAME, $env:COMPUTERNAME, $S.HuntId, $result, [int][math]::Round($seconds), $clean
    [void](Add-SharedLine $MyAttemptFile $AttemptHeader $line)
    $S.NextData = Get-Date
}

# ---------------------------------------------------------------------------------------------
# Shared data loading (cached per file so the network share is only re-read when it changes)
# ---------------------------------------------------------------------------------------------
$script:FileCache = @{}
function Read-SharedFile([string]$path) {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}

function Get-CsvRows([string]$folder, [scriptblock]$parser) {
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($f in Get-ChildItem -Path $folder -Filter '*.csv' -File -ErrorAction SilentlyContinue) {
        $key = $f.FullName
        $stamp = "$($f.Length)|$($f.LastWriteTimeUtc.Ticks)"
        $c = $script:FileCache[$key]
        if (-not $c -or $c.Stamp -ne $stamp) {
            try { $text = Read-SharedFile $key } catch { if ($c) { $all.AddRange($c.Rows) }; continue }
            $rows = New-Object System.Collections.Generic.List[object]
            foreach ($line in ($text -split "`r?`n" | Select-Object -Skip 1)) {
                if (-not $line) { continue }
                try { $r = & $parser $line.Split(',') } catch { $r = $null }
                if ($r) { $rows.Add($r) }
            }
            $c = @{ Stamp = $stamp; Rows = $rows }
            $script:FileCache[$key] = $c
        }
        $all.AddRange($c.Rows)
    }
    , $all
}

function ConvertTo-Time([string]$str) {
    $t = [datetime]::MinValue
    if ([datetime]::TryParseExact($str, 'yyyy-MM-dd HH:mm:ss', $Inv, 'None', [ref]$t)) { return $t }
    return $null
}

$ParseAttempt = {
    param($p)
    if ($p.Count -lt 9) { return }
    $t = ConvertTo-Time $p[0]
    if (-not $t) { return }
    [pscustomobject]@{ T = $t; User = $p[1]; Pc = $p[2]; Hunt = $p[3]; Result = $p[4]; Sec = [double]$p[5]; Detail = $p[8] }
}

$ParseToolbox = {
    param($p)
    if ($p.Count -lt 7) { return }
    $t = ConvertTo-Time $p[0]
    if (-not $t) { return }
    [pscustomobject]@{ T = $t; User = $p[1]; Pc = $p[2]; Session = $p[3]; Feature = $p[4]; Event = $p[5]; Wait = [double]$p[6] }
}

function Get-Stats($rows) {
    $st = @{
        Launch = 0; Success = 0; Denied = 0; Full = 0; Fail = 0
        Users = @{}; First = $null
        HourOk = New-Object int[] 24; HourAll = New-Object int[] 24
        HeatOk = New-Object int[] 168; HeatAll = New-Object int[] 168
        SessSum = 0.0; SessN = 0; MineToday = 0; AvgWait = $null
        Recent = New-Object System.Collections.Generic.List[string]
        Best = $null; Worst = $null
    }
    $hunts = @{}
    $today = (Get-Date).Date
    foreach ($r in ($rows | Sort-Object T)) {
        if ($DayHours -notcontains $r.T.Hour) { continue }
        if (-not $st.First) { $st.First = $r.T }
        $st.Users[$r.User] = 1
        $h = $r.T.Hour
        $i = ((([int]$r.T.DayOfWeek) + 6) % 7) * 24 + $h
        switch ($r.Result) {
            'SUCCESS' { $st.Success++; $st.HourOk[$h]++; $st.HourAll[$h]++; $st.HeatOk[$i]++; $st.HeatAll[$i]++ }
            'DENIED'  { $st.Denied++; $st.HourAll[$h]++; $st.HeatAll[$i]++ }
            'FULL'    { $st.Full++; $st.HourAll[$h]++; $st.HeatAll[$i]++ }
            'SESSION_END' { $st.SessSum += $r.Sec; $st.SessN++ }
            default   { $st.Fail++ }
        }
        if ($r.Result -in 'SUCCESS', 'DENIED', 'TIMEOUT', 'ERROR') {
            $st.Launch++
            $st.Recent.Add($r.Result)
            if ($r.User -eq $Me -and $r.T -ge $today) { $st.MineToday++ }
        }
        if ($r.Hunt -and $r.Result -ne 'SESSION_END') {
            $k = "$($r.User)|$($r.Pc)|$($r.Hunt)"
            if (-not $hunts.ContainsKey($k)) {
                $hunts[$k] = @{ Start = (ConvertTo-HuntTime $r.Hunt $r.T); Got = $null }
            }
            if ($r.Result -eq 'SUCCESS' -and -not $hunts[$k].Got) { $hunts[$k].Got = $r.T }
        }
    }
    $waits = @($hunts.Values | Where-Object { $_.Got } | ForEach-Object { ($_.Got - $_.Start).TotalSeconds })
    if ($waits.Count) { $st.AvgWait = ($waits | Measure-Object -Average).Average }
    # Any hour with an attempt counts; on equal rates the hour with more attempts wins
    for ($h = 0; $h -lt 24; $h++) {
        $n = $st.HourAll[$h]
        if ($n -lt 1) { continue }
        $p = $st.HourOk[$h] / $n
        if (-not $st.Best -or $p -gt $st.Best.P -or ($p -eq $st.Best.P -and $n -gt $st.Best.N)) { $st.Best = @{ H = $h; P = $p; N = $n } }
        if (-not $st.Worst -or $p -lt $st.Worst.P -or ($p -eq $st.Worst.P -and $n -gt $st.Worst.N)) { $st.Worst = @{ H = $h; P = $p; N = $n } }
    }
    if ($st.Best -and $st.Worst -and $st.Worst.H -eq $st.Best.H) { $st.Worst = $null }
    $st
}

function ConvertTo-HuntTime([string]$hunt, [datetime]$fallback) {
    $t = [datetime]::MinValue
    if ([datetime]::TryParseExact($hunt, 'yyyyMMddHHmmss', $Inv, 'None', [ref]$t)) { return $t }
    return $fallback
}

# Other people with the dashboard open. File times come from the network share's clock, so the
# cutoff is shifted by the skew measured on our own heartbeat.
function Get-Online {
    $cut = (Get-Date) + $S.ShareSkew - [timespan]::FromSeconds(45)
    foreach ($f in Get-ChildItem -Path $Dirs.Active -Filter '*.txt' -File -ErrorAction SilentlyContinue) {
        if ($f.BaseName -eq $ClientId -or $f.LastWriteTime -lt $cut) { continue }
        $mode = 'IDLE'
        try { $mode = ((Read-SharedFile $f.FullName) -split "`t")[0].Trim() } catch {}
        [pscustomobject]@{ Id = $f.BaseName; User = ($f.BaseName -split '@')[0]; Mode = $mode }
    }
}

function Update-Data {
    if ((Get-Date) -lt $S.NextData) { return }
    $S.NextData = (Get-Date).AddSeconds(10)
    $S.Rows = Get-CsvRows $Dirs.Attempts $ParseAttempt
    $S.Tool = Get-CsvRows $Dirs.Toolboxes $ParseToolbox
    $S.Stats = Get-Stats $S.Rows
    $S.Online = @(Get-Online)
}

function Update-Heartbeat {
    # Write right away when our mode changes, otherwise every 15s
    $mode = if ($S.Paused) { 'PAUSED' } else { $S.Mode }
    if ((Get-Date) -lt $S.NextBeat -and $mode -eq $S.BeatMode) { return }
    $S.NextBeat = (Get-Date).AddSeconds(15)
    $S.BeatMode = $mode
    try {
        [IO.File]::WriteAllText($HeartbeatFile, "$mode`t$($S.Attempt)`t$((Get-Date).ToString('s'))")
        $S.ShareSkew = (Get-Item $HeartbeatFile).LastWriteTime - (Get-Date)
    } catch {}
}

# ---------------------------------------------------------------------------------------------
# Data for the details page (MATLABLicenseHunter.html loads LicenseData\dashboard-data.js)
# ---------------------------------------------------------------------------------------------
function Js([string]$s) {
    '"' + ($s -replace '[\x00-\x1f]', ' ').Replace('\', '\\').Replace('"', '\"') + '"'
}

# Rewrites dashboard-data.js at most every 30s, and only when the data changed. -Force skips both checks.
function Export-WebData([switch]$Force) {
    $now = Get-Date
    if (-not $Force -and $now -lt $S.NextExport) { return }
    $myMode = if ($S.Paused) { 'PAUSED' } else { $S.Mode }
    $sig = "$($S.Rows.Count)|$($S.Tool.Count)|$myMode|" + ((@($S.Online) | ForEach-Object { "$($_.Id)=$($_.Mode)" }) -join ',')
    if (-not $Force -and $sig -eq $S.ExportSig) { return }
    $S.NextExport = $now.AddSeconds(30)
    try {
        $cut = $now.AddDays(-180)
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('window.LICENSE_DATA = {"generated":' + (Js $now.ToString('s')) + ',"by":' + (Js $ClientId) + ',"online":[')
        $on = @('[' + (Js $env:USERNAME) + ',' + (Js $env:COMPUTERNAME) + ',' + (Js $myMode) + ']')
        foreach ($o in @($S.Online)) {
            $pc = ($o.Id -split '@', 2)[-1]
            $on += '[' + (Js $o.User) + ',' + (Js $pc) + ',' + (Js $o.Mode) + ']'
        }
        [void]$sb.Append(($on -join ',') + '],"attempts":[')
        $first = $true
        foreach ($r in $S.Rows) {
            if ($r.T -lt $cut) { continue }
            if (-not $first) { [void]$sb.Append(',') }; $first = $false
            [void]$sb.Append('[' + (Js $r.T.ToString('s')) + ',' + (Js $r.User) + ',' + (Js $r.Pc) + ',' + (Js $r.Hunt) + ',' +
                (Js $r.Result) + ',' + ([int]$r.Sec) + ',' + (Js $r.Detail) + ']')
        }
        [void]$sb.Append('],"toolboxes":[')
        $first = $true
        foreach ($t in $S.Tool) {
            if ($t.T -lt $cut) { continue }
            if (-not $first) { [void]$sb.Append(',') }; $first = $false
            [void]$sb.Append('[' + (Js $t.T.ToString('s')) + ',' + (Js $t.User) + ',' + (Js $t.Pc) + ',' + (Js $t.Session) + ',' +
                (Js $t.Feature) + ',' + (Js $t.Event) + ',' + ([int]$t.Wait) + ']')
        }
        [void]$sb.Append(']};')
        # Write a private temp file, then copy over the shared one so readers never see half a file
        $tmp = Join-Path $DataRoot "dashboard-data.$ClientId.tmp"
        [IO.File]::WriteAllText($tmp, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
        [IO.File]::Copy($tmp, (Join-Path $DataRoot 'dashboard-data.js'), $true)
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
        $S.ExportSig = $sig
    } catch {}
}

function Open-Details {
    Export-WebData -Force
    $page = Join-Path $ScriptDir 'MATLABLicenseHunter.html'
    if (-not (Test-Path $page)) { Add-Log 'WARN' "Details page not found: $page"; return }
    try {
        Start-Process -FilePath $page
        Add-Log 'INFO' 'Opened the details page in your browser'
    } catch { Add-Log 'ERR' "Could not open the details page: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------------------------
# MATLAB process handling
# ---------------------------------------------------------------------------------------------
function Get-ExistingMatlab {
    $sid = (Get-Process -Id $PID).SessionId
    Get-Process -Name 'MATLAB' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | Select-Object -First 1
}

function Update-TreeIds {
    if (-not $S.Proc) { return }
    try {
        $procs = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction Stop
        $ids = New-Object 'System.Collections.Generic.HashSet[int]'
        [void]$ids.Add($S.Proc.Id)
        $changed = $true
        while ($changed) {
            $changed = $false
            foreach ($p in $procs) {
                if ($ids.Contains([int]$p.ParentProcessId) -and $ids.Add([int]$p.ProcessId)) { $changed = $true }
            }
        }
        $S.TreeIds = @($ids)
    } catch {}
}

function Stop-MatlabTree {
    $ids = @($S.TreeIds) + @($S.Proc.Id) | Select-Object -Unique
    [array]::Reverse($ids)
    foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
}

# Asks every window in MATLAB's process tree to close (like clicking X), so MATLAB can shut down cleanly.
function Close-MatlabGently {
    $ids = @(@($S.TreeIds) + @($S.Proc.Id) | Where-Object { $_ } | Select-Object -Unique)
    foreach ($id in $ids) {
        try { [void](Get-Process -Id $id -ErrorAction Stop).CloseMainWindow() } catch {}
    }
}

# Snapshot of MATLAB's prefs folder, taken when a hunt starts with no MATLAB running (known good).
function Save-Prefs {
    $S.PrefSnapOk = $false
    if (-not $PrefDir -or -not (Test-Path $PrefDir)) { return }
    try {
        $null = & robocopy $PrefDir $PrefSnap /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1
        $S.PrefSnapOk = $LASTEXITCODE -lt 8
    } catch {}
    if (-not $S.PrefSnapOk) { Add-Log 'WARN' 'Could not back up MATLAB prefs before hunting' }
}

# Puts the snapshot back after MATLAB had to be force-killed mid-startup (half-written prefs make
# MATLAB crash on every later start). Never used after the user's own [K] kill of a running session.
function Restore-Prefs {
    if (-not $S.PrefSnapOk -or (Get-ExistingMatlab)) { return }
    try {
        $null = & robocopy $PrefSnap $PrefDir /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1
        if ($LASTEXITCODE -lt 8) { Add-Log 'INFO' 'MATLAB prefs restored after a forced close' }
        else { Add-Log 'WARN' "Could not restore MATLAB prefs (robocopy $LASTEXITCODE)" }
    } catch {}
}

function Test-LicenseError([string]$name) {
    foreach ($p in $LicenseErrorPatterns) { if ($name -like $p) { return $true } }
    return $false
}

# Scans MATLAB's windows (and anything its child processes own) for licensing errors.
function Find-MatlabWindows {
    $res = @{ Main = $false; Error = $null }
    Update-TreeIds
    $root = [Windows.Automation.AutomationElement]::RootElement
    $wins = $root.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $wins) {
        try {
            $name = $w.Current.Name
            $ours = $S.TreeIds -contains $w.Current.ProcessId
            if (-not $ours -and $name -notlike 'MATLAB R20*') { continue }
            if (Test-LicenseError $name) { $res.Error = $name; return $res }
            if ($name -like 'MATLAB*') { $res.Main = $true }
            foreach ($el in $w.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)) {
                $n = $el.Current.Name
                if ($n -and (Test-LicenseError $n)) { $res.Error = $n; return $res }
            }
        } catch {}
    }
    $res
}

function Start-Hunt {
    $existing = Get-ExistingMatlab
    if ($existing) {
        $S.Proc = $existing; $S.TreeIds = @(); $S.OwnSession = $false
        $S.Mode = 'HAVE'
        $S.SessionStart = Get-Date
        try { $S.SessionStart = $existing.StartTime } catch {}
        Add-Log 'INFO' 'MATLAB already running here - watching it'
        return
    }
    if (-not $MatlabPath -or -not (Test-Path $MatlabPath)) {
        $S.Mode = 'IDLE'
        Add-Log 'ERR' 'MATLAB.exe not found - use -MatlabPath'
        return
    }
    $S.Mode = 'HUNT'; $S.Phase = 'WAIT'; $S.Paused = $false
    $S.NextAt = Get-Date
    $S.Attempt = 0
    $S.HuntId = (Get-Date).ToString('yyyyMMddHHmmss', $Inv)
    $S.HuntStart = Get-Date
    $S.HuntStrip.Clear()
    Save-Prefs
    Add-Log 'INFO' 'Hunt started'
}

function Start-MatlabLaunch {
    $S.Attempt++
    $argList = '-nosplash'
    if (-not $NoAutoRun) {
        $sd = $ScriptDir.TrimEnd('\')
        $dr = $DataRoot.TrimEnd('\') -replace "'", "''"
        $argList = "-nosplash -sd `"$sd`" -r `"MATLABLicenseAcquisition('AutoStart',true,'DataRoot','$dr')`""
    }
    Remove-Item -Path $ReadyFile -Force -ErrorAction SilentlyContinue
    $S.LaunchTime = Get-Date
    try {
        $S.Proc = Start-Process -FilePath $MatlabPath -ArgumentList $argList -PassThru
    } catch {
        Fail-Launch 'ERROR' "Could not start MATLAB: $($_.Exception.Message)"
        return
    }
    $S.OwnSession = $true
    $S.TreeIds = @($S.Proc.Id)
    $S.LaunchTime = Get-Date
    $S.MainSeenAt = $null
    $S.NextScan = (Get-Date).AddSeconds(3)
    $S.Phase = 'LAUNCH'
    Add-Log 'INFO' "#$($S.Attempt) launching MATLAB"
}

# Records a failed attempt right away. A MATLAB that is still alive is asked to close and gets
# up to 10s (phase CLOSING) before it is force-killed - killing it mid-startup can corrupt its prefs.
function Fail-Launch([string]$result, [string]$detail) {
    $secs = if ($S.LaunchTime) { ((Get-Date) - $S.LaunchTime).TotalSeconds } else { 0 }
    Write-Attempt $result $secs $detail
    $S.LastResult = $result; $S.LastDetail = $detail
    $S.HuntStrip.Add($result)
    Add-Log $(if ($result -eq 'DENIED') { 'DENY' } else { 'WARN' }) "#$($S.Attempt) $result - $(Trunc $detail 70)"
    $alive = $false
    if ($S.Proc) { try { $alive = -not $S.Proc.HasExited } catch {} }
    if ($alive) {
        Update-TreeIds
        Close-MatlabGently
        $S.CloseBy = (Get-Date).AddSeconds(10)
        $S.Phase = 'CLOSING'
        return
    }
    if ($S.Proc) { Stop-MatlabTree }   # leftover child processes
    $S.Proc = $null
    $S.Phase = 'WAIT'
    $S.NextAt = (Get-Date).AddSeconds($RetryDelaySeconds)
}

function Open-Popup([string]$op, [string]$stage, [double]$secs = 0) {
    $S.Popup = @{ Op = $op; Stage = $stage; Since = Get-Date; Secs = $secs }
    $S.NextRender = Get-Date
}

function Complete-Success([string]$detail) {
    Write-Attempt 'SUCCESS' ((Get-Date) - $S.LaunchTime).TotalSeconds $detail
    $S.LastResult = 'SUCCESS'; $S.LastDetail = $detail
    $S.HuntStrip.Add('SUCCESS')
    $S.Mode = 'HAVE'
    $S.SessionStart = Get-Date
    $hunt = ((Get-Date) - $S.HuntStart).TotalSeconds
    Add-Log 'GOT' "Got MATLAB on launch #$($S.Attempt) after $(Fmt-Dur $hunt)"
    if (-not $S.Popup -or $S.Popup.Stage -ne 'CONFIRM') { Open-Popup 'GOT' 'DONE' $hunt }
}

function Update-Hunt {
    $now = Get-Date
    switch ($S.Phase) {
        'WAIT' {
            if ($S.Paused) { $S.NextAt = $now.AddSeconds(1); return }
            if ($now -lt $S.NextAt) { return }
            if (Get-ExistingMatlab) { Start-Hunt; return }
            Start-MatlabLaunch
        }
        'LAUNCH' {
            $elapsed = ($now - $S.LaunchTime).TotalSeconds
            if (-not $NoAutoRun -and (Test-Path $ReadyFile)) {
                if ((Get-Item $ReadyFile).LastWriteTime -ge $S.LaunchTime.AddSeconds(-2)) {
                    Complete-Success 'MATLAB started (ready signal from MATLAB)'
                    return
                }
            }
            if ($S.Proc.HasExited) { Fail-Launch 'DENIED' 'MATLAB closed during startup'; return }
            if ($now -ge $S.NextScan) {
                $scan = Find-MatlabWindows
                $S.NextScan = (Get-Date).AddSeconds(2)
                if ($scan.Error) { Fail-Launch 'DENIED' $scan.Error; return }
                if ($scan.Main -and -not $S.MainSeenAt) { $S.MainSeenAt = Get-Date }
            }
            if ($NoAutoRun -and $S.MainSeenAt -and ($now - $S.MainSeenAt).TotalSeconds -ge $ConfirmSeconds) {
                Complete-Success "No licensing error after $ConfirmSeconds s"
                return
            }
            if ($elapsed -ge $LaunchTimeoutSeconds) {
                if ($S.MainSeenAt) { Complete-Success 'MATLAB window up with no license error (no ready signal)' }
                else { Fail-Launch 'TIMEOUT' "No MATLAB window after $LaunchTimeoutSeconds s" }
            }
        }
        'CLOSING' {
            $gone = $true
            try { $gone = $S.Proc.HasExited } catch {}
            if (-not $gone -and $now -lt $S.CloseBy) { return }
            Stop-MatlabTree   # leftover children, or MATLAB itself if it ignored the close request
            if (-not $gone) {
                try { [void]$S.Proc.WaitForExit(5000) } catch {}
                Restore-Prefs
            }
            $S.Proc = $null
            $S.Phase = 'WAIT'
            $S.NextAt = (Get-Date).AddSeconds($RetryDelaySeconds)
        }
    }
}

function Update-Have {
    $gone = $true
    try { $gone = $S.Proc.HasExited } catch {}
    if ($S.Proc -and -not $gone) {
        if ($S.ReleaseAt -and -not $S.ReleaseWarned -and ((Get-Date) - $S.ReleaseAt).TotalSeconds -gt 30) {
            $S.ReleaseWarned = $true
            Add-Log 'WARN' 'MATLAB has not closed yet - check it for a save prompt'
        }
        return
    }
    $secs = ((Get-Date) - $S.SessionStart).TotalSeconds
    if ($S.OwnSession) { Write-Attempt 'SESSION_END' $secs "MATLAB session ended" }
    Add-Log 'INFO' "MATLAB closed after $(Fmt-Dur $secs) - licenses returned"
    # Finish the release/kill popup (even if it was hidden with Esc)
    $op = if ($S.Popup -and $S.Popup.Op -in 'R', 'K') { $S.Popup.Op } elseif ($S.KillAt) { 'K' } elseif ($S.ReleaseAt) { 'R' } else { '' }
    if ($op -and (-not $S.Popup -or $S.Popup.Op -in 'R', 'K')) { Open-Popup $op 'DONE' $secs }
    $S.Proc = $null; $S.ReleaseAt = $null; $S.ReleaseWarned = $false; $S.KillAt = $null
    $S.Mode = 'IDLE'
}

function Request-Release {
    Update-TreeIds   # covers a MATLAB that was already running when the dashboard started
    try { [IO.File]::WriteAllText($ReleaseFile, (Get-Date).ToString('s')) } catch {}
    Close-MatlabGently
    $S.ReleaseAt = Get-Date
    $S.ReleaseWarned = $false
    Add-Log 'INFO' 'Asked MATLAB to close - returns ALL licenses'
}

function Kill-Matlab {
    Update-TreeIds; Stop-MatlabTree
    $S.KillAt = Get-Date
    Add-Log 'WARN' 'MATLAB force-killed'
}

# Popup housekeeping: DONE closes itself after 10s; a release/kill question is dropped once MATLAB is gone.
function Update-Popup {
    $p = $S.Popup
    if (-not $p) { return }
    if ($p.Stage -eq 'DONE' -and ((Get-Date) - $p.Since).TotalSeconds -ge 10) { $S.Popup = $null }
    elseif ($p.Stage -eq 'CONFIRM' -and $p.Op -in 'R', 'K' -and $S.Mode -ne 'HAVE') { $S.Popup = $null }
}

# Keys while a popup is open. Returns $true when the key was used up by the popup.
function Read-PopupKey([string]$ch, $key) {
    $p = $S.Popup
    if (-not $p) { return $false }
    $esc = $key -eq 'Escape'
    if ($p.Stage -eq 'CONFIRM') {
        if ($ch -eq 'N' -or $esc) { $S.Popup = $null; return $true }
        if ($ch -eq 'Y' -or $key -eq 'Enter' -or $ch -eq $p.Op) {
            $S.Popup = $null
            switch ($p.Op) {
                'Q' { $S.Quit = $true }
                'R' { if ($S.Mode -eq 'HAVE') { Request-Release; Open-Popup 'R' 'WORK' } }
                'K' { if ($S.Mode -eq 'HAVE') { Kill-Matlab; Open-Popup 'K' 'WORK' } }
            }
        }
        return $true
    }
    if ($p.Stage -eq 'WORK') {
        if ($esc) { $S.Popup = $null; return $true }   # hide it; the work carries on
        return $ch -notin 'K', 'Q', 'D'                # those keep their normal meaning
    }
    # DONE: any key closes it and then also does its normal job (so H starts a hunt)
    $S.Popup = $null
    return $false
}

function Read-Keys {
    while ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        $S.NextRender = Get-Date
        $ch = [string][char]::ToUpper($k.KeyChar)
        if ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { $ch = 'Q' }
        if (Read-PopupKey $ch ([string]$k.Key)) { continue }
        switch ($ch) {
            'Q' { Open-Popup 'Q' 'CONFIRM' }
            'H' { if ($S.Mode -eq 'IDLE') { Start-Hunt } }
            'D' { Open-Details }
            'P' {
                if ($S.Mode -eq 'HUNT') {
                    $S.Paused = -not $S.Paused
                    Add-Log 'INFO' $(if ($S.Paused) { 'Hunt paused' } else { 'Hunt resumed' })
                }
            }
            'R' {
                if ($S.Mode -eq 'HAVE') {
                    if ($S.ReleaseAt) { Open-Popup 'R' 'WORK'; $S.Popup.Since = $S.ReleaseAt }
                    else { Open-Popup 'R' 'CONFIRM' }
                }
            }
            'K' { if ($S.Mode -eq 'HAVE') { Open-Popup 'K' 'CONFIRM' } }
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------
$IW = 116          # inner width
$LW = 60           # left column
$RW = $IW - $LW - 1
$Features = @(
    @{ Id = 'simulink'; Short = 'Simulink' }, @{ Id = 'simscape'; Short = 'Simscape' },
    @{ Id = 'simscape_battery'; Short = 'Battery' }, @{ Id = 'power_system_blocks'; Short = 'PwrSys' },
    @{ Id = 'signal_toolbox'; Short = 'Signal' }
)
$Accent = 208

# One 4-column cell per work-day hour: "6a  7a  ... 12p 1p ... 5p"
function Get-HourLabels([int]$offset) {
    $nowH = (Get-Date).Hour
    $cells = foreach ($h in $DayHours) {
        $t = "$(if ($h % 12) { $h % 12 } else { 12 })$(if ($h -lt 12) { 'a' } else { 'p' })".PadRight(4)
        if ($h -eq $nowH) { Bold $t $Accent } else { C $t 244 }
    }
    (' ' * $offset) + ($cells -join '')
}

function Format-Hour([int]$h) { "$(if ($h % 12) { $h % 12 } else { 12 })$(if ($h -lt 12) { 'am' } else { 'pm' })" }

function Get-StatusLines {
    $now = Get-Date
    $spin = @('-', '\', '|', '/')[$S.Spin % 4]
    $badge = switch ($S.Mode) {
        'HUNT' { if ($S.Paused) { Badge 'PAUSED' 244 } else { Badge "HUNTING $spin" 208 } }
        'HAVE' { Badge 'YOU HAVE MATLAB' 46 }
        default { Badge 'IDLE' 240 }
    }
    $l = @(" $(Bold 'STATUS' 255)   $badge")
    # label/value rows: 1 + 10 label columns leave $VW columns for the value
    $VW = $LW - 11
    $row = { param($label, $value) ' ' + (C $label.PadRight(10) 244) + $value }
    switch ($S.Mode) {
        'HUNT' {
            $l += & $row 'Attempt' "$(Bold "#$($S.Attempt)" 255)   $(C 'hunting for' 250) $(Bold (Fmt-Clock ($now - $S.HuntStart).TotalSeconds) 255)"
            $l += & $row 'Now' $(switch ($S.Phase) {
                'WAIT'   {
                    if ($S.Paused) { C 'Paused - press P to resume' 244 }
                    else { C "Next launch in $([math]::Max(0, [int]($S.NextAt - $now).TotalSeconds))s" 250 }
                }
                'LAUNCH' {
                    $el = [int]($now - $S.LaunchTime).TotalSeconds
                    if ($S.MainSeenAt) { C "MATLAB is up, waiting for it to finish ($($el)s)" 154 }
                    else { C "Launching - watching for errors ($el/$($LaunchTimeoutSeconds)s)" 75 }
                }
                'CLOSING' { C 'Closing MATLAB cleanly before the next try' 220 }
            })
        }
        'HAVE' {
            $sess = if ($S.SessionStart) { ($now - $S.SessionStart).TotalSeconds } else { 0 }
            $l += & $row 'Session' "$(Bold (Fmt-Clock $sess) 46)$(if ($S.Attempt) { C "  got it on launch #$($S.Attempt)" 250 })"
            $l += & $row 'Now' (C 'Grabbing toolboxes - [R] gives seats back' 250)
        }
        default {
            $l += & $row 'Now' (C 'Press H to start hunting for MATLAB' 250)
            $l += & $row '' (C 'Every attempt is logged for the team charts' 244)
        }
    }
    $last = if ($S.LastResult) {
        "$(C $S.LastResult (Result-Color $S.LastResult)) $(C (Trunc $S.LastDetail ($VW - $S.LastResult.Length - 1)) 244)"
    } else { C 'none yet' 244 }
    $l += & $row 'Last' $last
    $strip = ($S.HuntStrip | Select-Object -Last $VW | ForEach-Object { Result-Glyph $_ }) -join ''
    $l += & $row 'This hunt' $(if ($strip) { $strip } else { C 'no attempts yet' 244 })
    # Counts include you; the name list only shows the others who are hunting
    $nHunt = @($S.Online | Where-Object { $_.Mode -eq 'HUNT' }).Count + $(if ($S.Mode -eq 'HUNT' -and -not $S.Paused) { 1 } else { 0 })
    $nHave = @($S.Online | Where-Object { $_.Mode -eq 'HAVE' }).Count + $(if ($S.Mode -eq 'HAVE') { 1 } else { 0 })
    $names = (@($S.Online | Where-Object { $_.Mode -eq 'HUNT' -and $_.User -ne $Me } | ForEach-Object { $_.User }) | Select-Object -Unique) -join ', '
    $counts = "$(Bold $nHunt 208) hunting  $(Bold $nHave 46) in MATLAB"
    $l += & $row 'Users:' "$counts  $(C (Trunc $names ($VW - (VisLen $counts) - 2)) 244)"
    $l
}

function Get-TeamLines {
    $st = $S.Stats
    $since = if ($st.First) { $st.First.ToString('MMM d') } else { '-' }
    $rate = if ($st.Launch) { '{0:P0}' -f ($st.Success / $st.Launch) } else { '-' }
    $wait = if ($st.AvgWait) { Fmt-Dur $st.AvgWait } else { '-' }
    $sess = if ($st.SessN) { Fmt-Dur ($st.SessSum / $st.SessN) } else { '-' }
    $l = @(" $(Bold 'TEAM STATS' 255)  $(C "$($st.Users.Count) users $($G.Mid) since $since $($G.Mid) 6am-6pm" 244)")
    $l += " $(Bold (Fmt-N $st.Launch) 255) launches    $(Bold (Fmt-N $st.Success) 46) got MATLAB ($rate)"
    $l += " Avg hunt $(Bold $wait 255)    Avg session $(Bold $sess 255)"
    if ($st.Best) {
        $best = " Best hour $(Bold (Format-Hour $st.Best.H) 46) $(C ('{0:P0}' -f $st.Best.P) 244)"
        if ($st.Worst) { $best += "    Worst $(Bold (Format-Hour $st.Worst.H) 196) $(C ('{0:P0}' -f $st.Worst.P) 244)" }
        $l += $best
    } else {
        $l += ' ' + (C 'Best/worst hour show up after the first attempt' 244)
    }
    $l += " You today $(Bold $st.MineToday 255) launches"
    $l
}

function Get-ChartLines {
    $st = $S.Stats
    $l = @(" $(Bold 'AVAILABILITY BY HOUR' 255)  $(C '% of attempts that got MATLAB' 244)")
    for ($row = 0; $row -lt 8; $row++) {
        $b = 7 - $row
        $label = if ($row % 2 -eq 0) { ('{0}%' -f ((8 - $row) * 25 / 2)).PadLeft(4) } else { '    ' }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append(' ' + (C $label 244) + (C $G.AxV 240))
        foreach ($h in $DayHours) {
            $n = $st.HourAll[$h]
            if ($n -eq 0) {
                [void]$sb.Append($(if ($b -eq 0) { C " $($G.Mid)  " 238 } else { '    ' }))
                continue
            }
            $p = $st.HourOk[$h] / $n
            $fill = [math]::Max(0, [math]::Min(8, [int][math]::Round($p * 64) - $b * 8))
            if ($b -eq 0 -and $fill -eq 0) { $fill = 1 }
            [void]$sb.Append((C ($Eighths[$fill] * 3) (RateColor $p)) + ' ')
        }
        $l += $sb.ToString()
    }
    $axis = $G.AxH * 48
    $i = [array]::IndexOf([int[]]$DayHours, (Get-Date).Hour)
    if ($i -ge 0) { $axis = (C $axis.Substring(0, $i * 4 + 1) 240) + (C $G.Up $Accent) + (C $axis.Substring($i * 4 + 2) 240) }
    else { $axis = C $axis 240 }
    $l += '      ' + $axis
    $l += Get-HourLabels 6
    $l
}

function Get-HeatLines {
    $st = $S.Stats
    $l = @(" $(Bold 'WEEK BY HOUR' 255)  $(C 'same %, split by weekday' 244)")
    $l += Get-HourLabels 5
    $days = @('Mon', 'Tue', 'Wed', 'Thu', 'Fri')   # work week only
    $today = ([int](Get-Date).DayOfWeek + 6) % 7
    for ($d = 0; $d -lt 5; $d++) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append(' ' + $(if ($d -eq $today) { Bold $days[$d] $Accent } else { C $days[$d] 250 }) + ' ')
        foreach ($h in $DayHours) {
            $n = $st.HeatAll[$d * 24 + $h]
            if ($n -eq 0) { [void]$sb.Append((C " $($G.Mid)  " 237)); continue }
            [void]$sb.Append((C ($G.Full * 3) (RateColor ($st.HeatOk[$d * 24 + $h] / $n))) + ' ')
        }
        $l += $sb.ToString()
    }
    $l += ''
    $l += "     $(C '0%' 244) $(($Grad | ForEach-Object { C $G.Full $_ }) -join '') $(C '100%' 244)    $(C "$($G.Mid) = no attempts yet" 240)"
    $l
}

function Get-BottomLeftLines {
    $st = $S.Stats
    $recent = ($st.Recent | Select-Object -Last 52 | ForEach-Object { Result-Glyph $_ }) -join ''
    $l = @(" $(Bold 'RECENT TEAM LAUNCHES' 255) $(C "$($G.Dot) got it  $($G.Cross) denied  ! timeout" 244)")
    $l += ' ' + $(if ($recent) { $recent } else { C 'no data yet' 244 })

    # Toolbox table: 11-column label + one 9-column cell per toolbox (fits the 60-column left side)
    $l += ' ' + (Bold ('TOOLBOXES'.PadRight(11)) 255) + (($Features | ForEach-Object { C $_.Short.PadRight(9) 250 }) -join '')

    # This PC's latest MATLAB session (written by MATLABLicenseAcquisition.m)
    $mine = @($S.Tool | Where-Object { $_.User -eq $Me -and $_.Pc -eq $env:COMPUTERNAME })
    $pcRow = ' ' + (C ('This PC'.PadRight(11)) 244)
    if ($mine.Count -and $S.Mode -eq 'HAVE') {
        $sess = ($mine | Sort-Object T | Select-Object -Last 1).Session
        foreach ($f in $Features) {
            $ev = $mine | Where-Object { $_.Session -eq $sess -and $_.Feature -eq $f.Id } | Sort-Object T | Select-Object -Last 1
            $pcRow += switch ($ev.Event) {
                'ACQUIRED' { C ("$($G.Dot) got".PadRight(9)) 46 }
                'WAITING'  { C ("$($G.Ring) wait".PadRight(9)) 220 }
                'SKIPPED'  { C ('- skip'.PadRight(9)) 240 }
                default    { C ('?'.PadRight(9)) 240 }
            }
        }
    } else {
        $pcRow += C $(if ($NoAutoRun) { 'auto-run off' } else { 'shown once MATLAB is running' }) 244
    }
    $l += $pcRow

    $avgRow = ' ' + (C ('Avg wait'.PadRight(11)) 244)
    foreach ($f in $Features) {
        $w = @($S.Tool | Where-Object { $_.Feature -eq $f.Id -and $_.Event -eq 'ACQUIRED' } | ForEach-Object { $_.Wait })
        $avgRow += if ($w.Count) { C ((Fmt-Dur ($w | Measure-Object -Average).Average).PadRight(9)) 255 } else { C ('-'.PadRight(9)) 240 }
    }
    $l += $avgRow
    $l
}

# Activity log: " <time> <KIND> message", message word-wrapped with continuation lines indented 15.
function Get-LogLines([int]$n) {
    $w = $RW - 16
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($S.Log | Select-Object -Last $n)) {
        $col = switch ($entry.Kind) { 'GOT' { 46 } 'DENY' { 196 } 'WARN' { 220 } 'ERR' { 196 } default { 75 } }
        $pre = ' ' + (C $entry.T.ToString('h:mm tt', $Inv).PadRight(8) 244) + ' ' + (C $entry.Kind.PadRight(4) $col) + ' '
        foreach ($part in @(Wrap-Text $entry.Msg $w)) {
            $out.Add($pre + $part)
            $pre = ' ' * 15
        }
    }
    @($out | Select-Object -Last $n)
}

function KeyHint([string]$key, [string]$label) { "$(Bold "[$key]" $Accent)$(C $label 250)" }

function Get-FooterKeys {
    $parts = @()
    if ($S.Mode -eq 'IDLE') { $parts += KeyHint 'H' ' Hunt' }
    if ($S.Mode -eq 'HUNT') { $parts += KeyHint 'P' $(if ($S.Paused) { ' Resume' } else { ' Pause' }) }
    if ($S.Mode -eq 'HAVE') { $parts += KeyHint 'R' ' Release MATLAB'; $parts += KeyHint 'K' ' Kill' }
    $parts += KeyHint 'D' ' Details'
    $parts += KeyHint 'Q' ' Quit'
    ' ' + ($parts -join '  ') + ' '
}

# ---------------------------------------------------------------------------------------------
# Popup (drawn over the dashboard while everything keeps running)
# ---------------------------------------------------------------------------------------------
$PW = 60   # popup width including its border

# 8 full blocks bouncing across a light-shade track, driven by the clock
function Get-Scanner([int]$w, [int]$col) {
    $span = $w - 8
    $t = [int64][math]::Floor([datetime]::Now.Ticks / 600000)   # 60ms steps
    $k = [int]($t % (2 * $span))
    $pos = if ($k -le $span) { $k } else { 2 * $span - $k }
    (C ($G.Light * $pos) 238) + (C ($G.Full * 8) $col) + (C ($G.Light * ($span - $pos)) 238)
}

# One progress step: 2 done, 1 active, 0 pending
function Step([int]$state, [string]$text) {
    switch ($state) {
        2 { (C $G.Dot 46) + ' ' + (C $text 250) }
        1 { (C (@('-', '\', '|', '/')[$S.Spin % 4]) $Accent) + ' ' + (Bold $text 255) }
        default { (C $G.Ring 240) + ' ' + (C $text 244) }
    }
}

function Get-PopupLines {
    $p = $S.Popup
    $el = ((Get-Date) - $p.Since).TotalSeconds
    $col = if ($p.Stage -eq 'DONE') { 46 } else { switch ($p.Op) { 'R' { 208 } 'K' { 196 } 'Q' { 75 } default { 46 } } }
    $title = ''; $info = ''; $body = @(); $keys = @()
    $closes = "closes in $([math]::Max(1, [int][math]::Ceiling(10 - $el)))s"
    switch ("$($p.Op)/$($p.Stage)") {
        'R/CONFIRM' {
            $title = 'RELEASE MATLAB?'
            $body = @(
                (C 'This closes MATLAB and returns every license,' 250),
                (C 'including the toolboxes.' 250),
                '',
                (C 'Save your work first - MATLAB refuses to close while' 220),
                (C 'Editor files have unsaved changes.' 220)
            )
            $keys = @((KeyHint 'Y' ' Release'), (KeyHint 'N' ' Cancel'))
        }
        'K/CONFIRM' {
            $title = 'FORCE-KILL MATLAB?'
            $body = @(
                (C 'MATLAB ends right away - unsaved work is lost.' 250),
                (C 'Use [R] Release normally; this is for a stuck MATLAB.' 244)
            )
            $keys = @((KeyHint 'Y' ' Kill'), (KeyHint 'N' ' Cancel'))
        }
        'Q/CONFIRM' {
            $title = 'QUIT LICENSE HUNTER?'
            $body = switch ($S.Mode) {
                'HUNT' { @((C 'Hunting stops. A MATLAB that is still starting up' 250), (C 'gets closed.' 250)) }
                'HAVE' { @((C 'Only this dashboard closes. MATLAB keeps running' 250), (C 'and keeps its licenses - [R] gives them back.' 250)) }
                default { @((C 'This closes the dashboard.' 250)) }
            }
            $keys = @((KeyHint 'Y' ' Quit'), (KeyHint 'N' ' Cancel'))
        }
        'R/WORK' {
            $title = 'RELEASING LICENSES'; $info = Fmt-Clock $el
            $body = @((Step 2 'Asked MATLAB to close'), (Step 1 'Waiting for MATLAB to shut down'),
                (Step 0 'Licenses go back to the team'), '', (Get-Scanner 54 $col))
            if ($el -ge 30) {
                $body += @('', (C 'Taking a while - check MATLAB for a save prompt' 220),
                    (C 'or unsaved Editor files.' 220))
            }
            $keys = @((KeyHint 'K' ' Force-kill'), (KeyHint 'Esc' ' Hide'))
        }
        'K/WORK' {
            $title = 'KILLING MATLAB'; $info = Fmt-Clock $el
            $body = @((Step 2 'MATLAB processes killed'), (Step 1 'Waiting for Windows to clean up'),
                (Step 0 'Licenses go back to the team'), '', (Get-Scanner 54 $col))
            $keys = @((KeyHint 'Esc' ' Hide'))
        }
        { $_ -in 'R/DONE', 'K/DONE' } {
            $title = 'LICENSES RETURNED'; $info = $closes
            $how = if ($p.Op -eq 'K') { 'MATLAB was killed after' } else { 'MATLAB closed after' }
            $body = @((Step 2 "$how $(Fmt-Dur $p.Secs)"), (Step 2 'Your seats are back with the team'), '',
                (C 'Press [H] to hunt again.' 250))
            $keys = @((KeyHint 'Any key' ' Close'))
        }
        'GOT/DONE' {
            $title = 'YOU GOT MATLAB'; $info = $closes
            $body = @(
                (C "Got a seat on launch #$($S.Attempt) after $(Fmt-Dur $p.Secs) of hunting." 250),
                (C $(if ($NoAutoRun) { 'Auto-run is off - open toolboxes in MATLAB yourself.' }
                    else { 'MATLAB is grabbing your toolboxes now.' }) 250),
                (C 'Press [R] later to give every seat back.' 244)
            )
            $keys = @((KeyHint 'Any key' ' Close'))
        }
    }
    $inner = $PW - 2
    $V = C $G.V $col
    $badge = Badge $title $col
    $gap = [math]::Max(1, $inner - 4 - (VisLen $badge) - $info.Length)
    $rows = @("  $badge$(' ' * $gap)$(C $info 244)", '') +
        @($body | ForEach-Object { if ($_) { "  $_" } else { '' } }) + @('', ('  ' + ($keys -join '   ')))
    $out = @(C ($G.TL + $G.H * $inner + $G.TR) $col)
    foreach ($r in $rows) { $out += $V + (Fit $r $inner) + $V }
    $out += C ($G.BL + $G.H * $inner + $G.BR) $col
    $out
}

function Build-Frame {
    $S.Spin++
    $now = Get-Date
    $bc = $BorderColor
    $V = C $G.V $bc
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((C ($G.TL + $G.H * $IW + $G.TR) $bc))

    $info = @(
        "$(C $now.ToString('ddd MMM d, yyyy', $Inv) 250)  $(Bold $now.ToString('h:mm:ss tt', $Inv) 255)",
        (C "$ClientId$(if ($MatlabRoot) { '  ' + (Split-Path $MatlabRoot -Leaf) })" 244)
    )
    for ($i = 0; $i -lt 2; $i++) {
        $lines.Add($V + (Fit ('  ' + $Banner[$i] + '   ' + $info[$i]) $IW) + $V)
    }
    $lines.Add((C ($G.LT + $G.H * $LW + $G.TT + $G.H * $RW + $G.RT) $bc))

    $add2 = {
        param($left, $right, $n)
        for ($i = 0; $i -lt $n; $i++) {
            $a = if ($i -lt $left.Count) { $left[$i] } else { '' }
            $b = if ($i -lt $right.Count) { $right[$i] } else { '' }
            $lines.Add($V + (Fit $a $LW) + $V + (Fit $b $RW) + $V)
        }
    }
    $sep = C ($G.LT + $G.H * $LW + $G.X + $G.H * $RW + $G.RT) $bc

    & $add2 @(Get-StatusLines) @(Get-TeamLines) 6
    $lines.Add($sep)
    & $add2 @(Get-ChartLines) @(Get-HeatLines) 11
    $lines.Add($sep)
    $log = @(" $(Bold 'ACTIVITY' 255)") + @(Get-LogLines 4)
    & $add2 @(Get-BottomLeftLines) $log 5

    $keys = Get-FooterKeys
    $fill = [math]::Max(0, $LW - 1 - (VisLen $keys))
    $right = ' shared team data '
    $rfill = [math]::Max(0, $RW - 1 - $right.Length)
    $lines.Add((C ($G.BL + $G.H) $bc) + $keys + (C ($G.H * $fill + $G.BT + $G.H * $rfill) $bc) + (C $right 244) + (C ($G.H + $G.BR) $bc))

    # Popup: dim the whole dashboard and splice the popup into the middle rows
    if ($S.Popup) {
        $pop = @(Get-PopupLines)
        $x = [int][math]::Floor(($IW + 2 - $PW) / 2)
        $y = [int][math]::Max(0, [math]::Floor(($lines.Count - $pop.Count) / 2))
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $plain = $AnsiRx.Replace($lines[$i], '').PadRight($IW + 2)
            $j = $i - $y
            if ($j -ge 0 -and $j -lt $pop.Count) {
                $lines[$i] = (C $plain.Substring(0, $x) 239) + $pop[$j] + (C $plain.Substring($x + $PW) 239)
            } else {
                $lines[$i] = C $plain 239
            }
        }
    }
    $lines
}

function Show-Frame {
    $needW = $IW + 2
    if (-not $RenderOnce -and [Console]::WindowWidth -lt $needW) {
        [Console]::Write("$E[H$E[2J" + "Make this window wider: the dashboard needs $needW columns (now $([Console]::WindowWidth)).`n" +
            'Hunting continues in the background. Press Q, then Y, to quit.')
        return
    }
    $frame = Build-Frame
    if ($RenderOnce) { $frame | ForEach-Object { [Console]::Out.WriteLine($_) }; return }
    [Console]::Write("$E[H" + ($frame -join "$E[K`n") + "$E[K$E[J")
}

# ---------------------------------------------------------------------------------------------
# Console setup
# ---------------------------------------------------------------------------------------------
[Console]::OutputEncoding = [Text.Encoding]::UTF8
if ($RenderOnce) {
    Update-Data
    Add-Log 'INFO' 'Render test'
    Show-Frame
    return
}

try {
    Add-Type -Namespace LicenseHunter -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
    $h = [LicenseHunter.Native]::GetStdHandle(-11)
    [uint32]$mode = 0
    if ([LicenseHunter.Native]::GetConsoleMode($h, [ref]$mode)) { [void][LicenseHunter.Native]::SetConsoleMode($h, $mode -bor 4) }
} catch {}
try {
    $raw = $Host.UI.RawUI
    $raw.WindowTitle = 'MATLAB License Hunter'
    $max = $raw.MaxPhysicalWindowSize
    $w = [math]::Min(120, $max.Width); $hgt = [math]::Min(31, $max.Height)
    if ($raw.BufferSize.Width -lt $w) { $raw.BufferSize = New-Object Management.Automation.Host.Size($w, [math]::Max($raw.BufferSize.Height, $hgt)) }
    if ($raw.WindowSize.Width -lt $w -or $raw.WindowSize.Height -lt $hgt) { $raw.WindowSize = New-Object Management.Automation.Host.Size($w, $hgt) }
} catch {}
[Console]::TreatControlCAsInput = $true
[Console]::Write("$E[?1049h$E[?25l$E[2J")

# ---------------------------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------------------------
if ($MatlabPath) { Add-Log 'INFO' "MATLAB: $MatlabPath" } else { Add-Log 'ERR' 'MATLAB.exe not found - use -MatlabPath' }
Add-Log 'INFO' "Shared data: $DataRoot"
if ($DashboardOnly) { Add-Log 'INFO' 'Dashboard mode - press H to start hunting' } else { Start-Hunt }
try {
    while (-not $S.Quit) {
        try {
            Read-Keys
            if ($S.Quit) { break }
            switch ($S.Mode) { 'HUNT' { Update-Hunt } 'HAVE' { Update-Have } }
            Update-Popup
            Update-Data
            Update-Heartbeat
            Export-WebData
            if ((Get-Date) -ge $S.NextRender) {
                Show-Frame
                # faster while a popup is open so its spinner and scanner animate
                $S.NextRender = (Get-Date).AddMilliseconds($(if ($S.Popup) { 150 } else { 500 }))
            }
        } catch {
            Add-Log 'ERR' $_.Exception.Message
            Start-Sleep -Milliseconds 500
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    # A MATLAB still starting up gets a chance to close cleanly; prefs are restored if it had to be killed
    if ($S.Mode -eq 'HUNT' -and $S.Phase -in 'LAUNCH', 'CLOSING' -and $S.Proc) {
        $forced = $false
        try {
            if (-not $S.Proc.HasExited) {
                Update-TreeIds
                Close-MatlabGently
                $forced = -not $S.Proc.WaitForExit(5000)
            }
        } catch {}
        Stop-MatlabTree
        if ($forced) {
            try { [void]$S.Proc.WaitForExit(5000) } catch {}
            Restore-Prefs
        }
    }
    Remove-Item -Path $HeartbeatFile -Force -ErrorAction SilentlyContinue
    [Console]::Write("$E[?25h$E[?1049l")
    [Console]::TreatControlCAsInput = $false
    Write-Host "MATLAB License Hunter closed. $(if ($S.Mode -eq 'HAVE') { 'MATLAB is still running.' })"
}
