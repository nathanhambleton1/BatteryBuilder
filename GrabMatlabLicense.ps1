<#
.SYNOPSIS
    MATLAB License Hunter - keeps trying to get a MATLAB seat and shows live team analytics
    right in the PowerShell window.

.DESCRIPTION
    Right-click this file -> "Run with PowerShell" (Windows 11: "Show more options" first).
    Keep it next to MATLABLicenseAcquisition.m on the shared network drive.

    What it does:
      * Launches MATLAB and watches the window for a licensing error, killing and retrying
        until it gets in.
      * Once MATLAB starts, MATLAB auto-runs MATLABLicenseAcquisition.m, which grabs the toolbox
        licenses (Simulink, Simscape, ...) and logs them too.
      * Every attempt by every user is logged to the shared LicenseData folder next to this script,
        so the dashboard shows when during the work day (6am-6pm) MATLAB is actually obtainable.

    Keys:  [H] hunt  [P] pause/resume  [R] release MATLAB (asks MATLAB to quit)  [K] kill MATLAB  [Q] quit

    Releasing licenses: MATLAB can't hand back a single toolbox license; everything is returned
    only when MATLAB exits ([R] here, or "Release All & Exit" in the MATLAB window).

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
    [switch]$RenderOnce
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# ---------------------------------------------------------------------------------------------
# Paths and shared data layout
# ---------------------------------------------------------------------------------------------
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
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

# ---------------------------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------------------------
$S = @{
    Mode = 'IDLE'            # IDLE | HUNT | HAVE
    Phase = 'WAIT'           # (HUNT) WAIT | LAUNCH
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
    ConfirmKey = ''
    ConfirmUntil = Get-Date
    ReleaseAt = $null
    Log = New-Object System.Collections.Generic.List[string]
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
    $col = switch ($kind) { 'GOT' { 46 } 'DENY' { 196 } 'WARN' { 220 } 'ERR' { 196 } default { 75 } }
    $S.Log.Add("$(C (Get-Date).ToString('HH:mm:ss') 244) $(C $kind.PadRight(4) $col) $msg")
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
    for ($h = 0; $h -lt 24; $h++) {
        if ($st.HourAll[$h] -lt 3) { continue }
        $p = $st.HourOk[$h] / $st.HourAll[$h]
        if (-not $st.Best -or $p -gt $st.Best.P) { $st.Best = @{ H = $h; P = $p } }
        if (-not $st.Worst -or $p -lt $st.Worst.P) { $st.Worst = @{ H = $h; P = $p } }
    }
    $st
}

function ConvertTo-HuntTime([string]$hunt, [datetime]$fallback) {
    $t = [datetime]::MinValue
    if ([datetime]::TryParseExact($hunt, 'yyyyMMddHHmmss', $Inv, 'None', [ref]$t)) { return $t }
    return $fallback
}

function Get-Online {
    $cut = (Get-Date).AddSeconds(-90)
    foreach ($f in Get-ChildItem -Path $Dirs.Active -Filter '*.txt' -File -ErrorAction SilentlyContinue) {
        if ($f.LastWriteTime -lt $cut) { continue }
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
    if ((Get-Date) -lt $S.NextBeat) { return }
    $S.NextBeat = (Get-Date).AddSeconds(30)
    try { [IO.File]::WriteAllText($HeartbeatFile, "$($S.Mode)`t$($S.Attempt)`t$((Get-Date).ToString('s'))") } catch {}
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
        Add-Log 'INFO' 'MATLAB is already running on this PC - watching it instead of hunting'
        return
    }
    if (-not $MatlabPath -or -not (Test-Path $MatlabPath)) {
        $S.Mode = 'IDLE'
        Add-Log 'ERR' 'MATLAB.exe not found - run with -MatlabPath "...\bin\win64\MATLAB.exe"'
        return
    }
    $S.Mode = 'HUNT'; $S.Phase = 'WAIT'; $S.Paused = $false
    $S.NextAt = Get-Date
    $S.Attempt = 0
    $S.HuntId = (Get-Date).ToString('yyyyMMddHHmmss', $Inv)
    $S.HuntStart = Get-Date
    $S.HuntStrip.Clear()
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
    Add-Log 'INFO' "Attempt #$($S.Attempt): launching MATLAB"
}

function Fail-Launch([string]$result, [string]$detail) {
    $secs = if ($S.LaunchTime) { ((Get-Date) - $S.LaunchTime).TotalSeconds } else { 0 }
    if ($S.Proc) { Stop-MatlabTree }
    $S.Proc = $null
    Write-Attempt $result $secs $detail
    $S.LastResult = $result; $S.LastDetail = $detail
    $S.HuntStrip.Add($result)
    Add-Log $(if ($result -eq 'DENIED') { 'DENY' } else { 'WARN' }) "#$($S.Attempt) $result - $detail"
    $S.Phase = 'WAIT'
    $S.NextAt = (Get-Date).AddSeconds($RetryDelaySeconds)
}

function Complete-Success([string]$detail) {
    Write-Attempt 'SUCCESS' ((Get-Date) - $S.LaunchTime).TotalSeconds $detail
    $S.LastResult = 'SUCCESS'; $S.LastDetail = $detail
    $S.HuntStrip.Add('SUCCESS')
    $S.Mode = 'HAVE'
    $S.SessionStart = Get-Date
    Add-Log 'GOT' "MATLAB license acquired after $($S.Attempt) launch(es) in $(Fmt-Dur ((Get-Date) - $S.HuntStart).TotalSeconds)"
    try { 880, 1100, 1320 | ForEach-Object { [Console]::Beep($_, 120) } } catch {}
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
    }
}

function Update-Have {
    $gone = $true
    try { $gone = $S.Proc.HasExited } catch {}
    if ($S.Proc -and -not $gone) {
        if ($S.ReleaseAt -and ((Get-Date) - $S.ReleaseAt).TotalSeconds -gt 30) {
            $S.ReleaseAt = $null
            Add-Log 'WARN' 'MATLAB did not close. Is the License Acquisition window open? Press K to force-kill.'
        }
        return
    }
    $secs = ((Get-Date) - $S.SessionStart).TotalSeconds
    if ($S.OwnSession) { Write-Attempt 'SESSION_END' $secs "MATLAB session ended" }
    Add-Log 'INFO' "MATLAB closed after $(Fmt-Dur $secs) - license returned. Press H to hunt again."
    $S.Proc = $null; $S.ReleaseAt = $null
    $S.Mode = 'IDLE'
}

function Request-Release {
    try { [IO.File]::WriteAllText($ReleaseFile, (Get-Date).ToString('s')) } catch {}
    foreach ($id in $S.TreeIds) {
        try { [void](Get-Process -Id $id -ErrorAction Stop).CloseMainWindow() } catch {}
    }
    $S.ReleaseAt = Get-Date
    Add-Log 'INFO' 'Asked MATLAB to save nothing and quit - this returns ALL its licenses'
}

function Confirm-Key([string]$key, [string]$question) {
    if ($S.ConfirmKey -eq $key -and (Get-Date) -lt $S.ConfirmUntil) { $S.ConfirmKey = ''; return $true }
    $S.ConfirmKey = $key
    $S.ConfirmUntil = (Get-Date).AddSeconds(5)
    Add-Log 'WARN' $question
    return $false
}

function Read-Keys {
    while ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        $ch = [char]::ToUpper($k.KeyChar)
        if ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { $ch = 'Q' }
        switch ($ch) {
            'Q' { $S.Quit = $true }
            'H' { if ($S.Mode -eq 'IDLE') { Start-Hunt } }
            'P' {
                if ($S.Mode -eq 'HUNT') {
                    $S.Paused = -not $S.Paused
                    Add-Log 'INFO' $(if ($S.Paused) { 'Hunt paused' } else { 'Hunt resumed' })
                }
            }
            'R' {
                if ($S.Mode -eq 'HAVE' -and (Confirm-Key 'R' 'Press R again to close MATLAB and give the license back (save your work first!)')) {
                    Request-Release
                }
            }
            'K' {
                if ($S.Mode -eq 'HAVE' -and (Confirm-Key 'K' 'Press K again to FORCE-KILL MATLAB (unsaved work is lost)')) {
                    Update-TreeIds; Stop-MatlabTree
                    Add-Log 'WARN' 'MATLAB killed'
                }
            }
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
    switch ($S.Mode) {
        'HUNT' {
            $l += " Attempt $(Bold "#$($S.Attempt)" 255)    Hunt time $(Bold (Fmt-Clock ($now - $S.HuntStart).TotalSeconds) 255)"
            $l += ' ' + $(switch ($S.Phase) {
                'WAIT'   {
                    if ($S.Paused) { C 'Paused - press P to resume' 244 }
                    else { C "Next try in $([math]::Max(0, [int]($S.NextAt - $now).TotalSeconds))s" 250 }
                }
                'LAUNCH' {
                    $el = [int]($now - $S.LaunchTime).TotalSeconds
                    if ($S.MainSeenAt) { C "MATLAB window is up - waiting for startup signal ($el s)" 154 }
                    else { C "Launching MATLAB, watching for license errors ($el/$LaunchTimeoutSeconds s)" 75 }
                }
            })
        }
        'HAVE' {
            $sess = if ($S.SessionStart) { ($now - $S.SessionStart).TotalSeconds } else { 0 }
            $l += " Session time $(Bold (Fmt-Clock $sess) 46)$(if ($S.Attempt) { "    got it on launch #$($S.Attempt)" })"
            $l += ' ' + (C 'Toolboxes are being grabbed in MATLAB. Close MATLAB (or press R) to give seats back.' 250)
        }
        default {
            $l += ' ' + (C 'Press H to start hunting for a MATLAB license.' 250)
            $l += ' ' + (C 'Every attempt is logged for the team charts.' 244)
        }
    }
    $last = if ($S.LastResult) { "$(C $S.LastResult (Result-Color $S.LastResult)) $(C $S.LastDetail 244)" } else { C 'none yet' 244 }
    $l += " Last result  $last"
    $strip = ($S.HuntStrip | Select-Object -Last 44 | ForEach-Object { Result-Glyph $_ }) -join ''
    $l += " This hunt    $(if ($strip) { $strip } else { C 'no attempts yet' 244 })"
    $hunting = @($S.Online | Where-Object { $_.Mode -eq 'HUNT' })
    $having = @($S.Online | Where-Object { $_.Mode -eq 'HAVE' })
    $names = (($hunting | ForEach-Object { $_.User }) | Select-Object -Unique) -join ', '
    $l += " Team now     $(Bold $hunting.Count 208) hunting  $(Bold $having.Count 46) in MATLAB  $(C $names 244)"
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
        $l += " Best hour $(Bold (Format-Hour $st.Best.H) 46) $(C ('{0:P0}' -f $st.Best.P) 244)    Worst $(Bold (Format-Hour $st.Worst.H) 196) $(C ('{0:P0}' -f $st.Worst.P) 244)"
    } else {
        $l += ' ' + (C 'Best/worst hour show up after a few attempts' 244)
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
            $col = if ($n -lt 3) { 240 } else { RateColor $p }
            [void]$sb.Append((C ($Eighths[$fill] * 3) $col) + ' ')
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
    $days = @('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
    $today = ([int](Get-Date).DayOfWeek + 6) % 7
    for ($d = 0; $d -lt 7; $d++) {
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
    $l += "     $(C '0%' 244) $(($Grad | ForEach-Object { C $G.Full $_ }) -join '') $(C '100%' 244)    $(C "$($G.Mid) no data" 238)"
    $l
}

function Get-BottomLeftLines {
    $st = $S.Stats
    $recent = ($st.Recent | Select-Object -Last 52 | ForEach-Object { Result-Glyph $_ }) -join ''
    $l = @(" $(Bold 'RECENT TEAM LAUNCHES' 255) $(C "$($G.Dot) got it  $($G.Cross) denied  ! timeout" 244)")
    $l += ' ' + $(if ($recent) { $recent } else { C 'no data yet' 244 })

    # Toolbox state for this PC's latest MATLAB session (written by MATLABLicenseAcquisition.m)
    $mine = @($S.Tool | Where-Object { $_.User -eq $Me -and $_.Pc -eq $env:COMPUTERNAME })
    $tb = " $(Bold 'TOOLBOXES' 255) "
    if ($mine.Count -and $S.Mode -eq 'HAVE') {
        $sess = ($mine | Sort-Object T | Select-Object -Last 1).Session
        foreach ($f in $Features) {
            $ev = $mine | Where-Object { $_.Session -eq $sess -and $_.Feature -eq $f.Id } | Sort-Object T | Select-Object -Last 1
            $mark = switch ($ev.Event) {
                'ACQUIRED' { C $G.Dot 46 } 'WAITING' { C $G.Ring 220 } 'SKIPPED' { C '-' 240 } default { C '?' 240 }
            }
            $tb += " $($f.Short) $mark"
        }
    } else {
        $tb += C $(if ($NoAutoRun) { 'auto-run off' } else { 'shown once MATLAB is running' }) 244
    }
    $l += $tb

    $avg = foreach ($f in $Features) {
        $w = @($S.Tool | Where-Object { $_.Feature -eq $f.Id -and $_.Event -eq 'ACQUIRED' } | ForEach-Object { $_.Wait })
        if ($w.Count) { "$($f.Short) $(C (Fmt-Dur ($w | Measure-Object -Average).Average) 255)" }
    }
    $l += " $(C 'Toolbox wait:' 244) $(if ($avg) { $avg -join '  ' } else { C 'no data yet' 244 })"
    $l
}

function Get-FooterKeys {
    $k = { param($key, $label) "$(Bold "[$key]" $Accent)$(C $label 250)" }
    $parts = @()
    if ($S.Mode -eq 'IDLE') { $parts += & $k 'H' ' Hunt' }
    if ($S.Mode -eq 'HUNT') { $parts += & $k 'P' $(if ($S.Paused) { ' Resume' } else { ' Pause' }) }
    if ($S.Mode -eq 'HAVE') { $parts += & $k 'R' ' Release MATLAB'; $parts += & $k 'K' ' Kill' }
    $parts += & $k 'Q' ' Quit'
    ' ' + ($parts -join '  ') + ' '
}

function Build-Frame {
    $S.Spin++
    $now = Get-Date
    $bc = $BorderColor
    $V = C $G.V $bc
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((C ($G.TL + $G.H * $IW + $G.TR) $bc))

    $info = @(
        "$(C $now.ToString('ddd dd MMM yyyy') 250)  $(Bold $now.ToString('HH:mm:ss') 255)",
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
    $log = @(" $(Bold 'ACTIVITY' 255)") + @($S.Log | Select-Object -Last 3 | ForEach-Object { " $_" })
    & $add2 @(Get-BottomLeftLines) $log 4

    $keys = Get-FooterKeys
    $fill = [math]::Max(0, $LW - 1 - (VisLen $keys))
    $right = ' shared team data '
    $rfill = [math]::Max(0, $RW - 1 - $right.Length)
    $lines.Add((C ($G.BL + $G.H) $bc) + $keys + (C ($G.H * $fill + $G.BT + $G.H * $rfill) $bc) + (C $right 244) + (C ($G.H + $G.BR) $bc))
    $lines
}

function Show-Frame {
    $needW = $IW + 2
    if (-not $RenderOnce -and [Console]::WindowWidth -lt $needW) {
        [Console]::Write("$E[H$E[2J" + "Make this window wider: the dashboard needs $needW columns (now $([Console]::WindowWidth)).`n" +
            'Hunting continues in the background. Press Q to quit.')
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
$nextRender = Get-Date
try {
    while (-not $S.Quit) {
        try {
            Read-Keys
            switch ($S.Mode) { 'HUNT' { Update-Hunt } 'HAVE' { Update-Have } }
            Update-Data
            Update-Heartbeat
            if ((Get-Date) -ge $nextRender) {
                Show-Frame
                $nextRender = (Get-Date).AddMilliseconds(500)
            }
        } catch {
            Add-Log 'ERR' $_.Exception.Message
            Start-Sleep -Milliseconds 500
        }
        Start-Sleep -Milliseconds 100
    }
} finally {
    if ($S.Mode -eq 'HUNT' -and $S.Phase -eq 'LAUNCH' -and $S.Proc) { Stop-MatlabTree }
    Remove-Item -Path $HeartbeatFile -Force -ErrorAction SilentlyContinue
    [Console]::Write("$E[?25h$E[?1049l")
    [Console]::TreatControlCAsInput = $false
    Write-Host "MATLAB License Hunter closed. $(if ($S.Mode -eq 'HAVE') { 'MATLAB is still running.' })"
}
