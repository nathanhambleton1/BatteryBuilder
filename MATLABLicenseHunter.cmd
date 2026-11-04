@echo off
rem =============================================================================================
rem  MATLAB License Hunter - cmd version, for PCs where PowerShell is blocked
rem
rem  Double-click this file. Keep it in the same folder as GrabMatlabLicense.ps1,
rem  MATLABLicenseAcquisition.m and MATLABLicenseHunter.html on the shared drive.
rem
rem  * If PowerShell works on this PC, this just opens the full PowerShell dashboard.
rem  * If PowerShell is blocked, it runs a plain cmd hunter instead: same hunting, survey mode,
rem    release/kill and shared logging, so your attempts still count in the team stats. There
rem    are no live charts here - press D for the details page and click its
rem    "Load LicenseData folder" button for the newest numbers.
rem
rem  Options:  MATLABLicenseHunter.cmd /cmd      always use the cmd version
rem            MATLABLicenseHunter.cmd /survey   start in survey mode
rem =============================================================================================
setlocal EnableExtensions DisableDelayedExpansion

rem ---- Settings for the cmd version -----------------------------------------------------------
rem Full path to MATLAB.exe. Blank = newest install under C:\Program Files\MATLAB.
set "MATLAB_EXE="
rem Seconds between launches while hunting.
set "RETRY=5"
rem Give up on one launch after this many seconds. The cmd version can only see window titles,
rem not the text inside MATLAB's error dialogs, so some denied launches only end at this limit.
set "LAUNCH_TIMEOUT=120"
rem (Survey) seconds from one probe's launch to the next, and the longest toolbox check.
set "SURVEY_GAP=60"
set "PROBE_TIMEOUT=90"
rem ----------------------------------------------------------------------------------------------

set "HERE=%~dp0"
set "HERE=%HERE:~0,-1%"
pushd "%HERE%" 2>nul
set "FORCECMD="
set "STARTMODE=HUNT"
for %%a in (%*) do (
    if /i "%%~a"=="/cmd" set "FORCECMD=1"
    if /i "%%~a"=="/survey" set "STARTMODE=SURVEY"
)

rem ---- 1) Full PowerShell dashboard, if PowerShell is allowed here ---------------------------
if defined FORCECMD goto :cmdmode
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" goto :nops
if not exist "%HERE%\GrabMatlabLicense.ps1" goto :nops
rem Exit code 7 = PowerShell runs and isn't locked down (the dashboard needs FullLanguage mode)
"%PSEXE%" -NoProfile -NonInteractive -Command "if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 3 }; exit 7" >nul 2>&1
if not "%errorlevel%"=="7" goto :nops
set "HEREQ=%HERE:'=''%"
set "PSARGS="
if "%STARTMODE%"=="SURVEY" set "PSARGS= -Survey"
rem Run as code rather than as a .ps1 file, so the script execution policy doesn't apply
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText('%HEREQ%\GrabMatlabLicense.ps1'))) -ScriptRoot '%HEREQ%'%PSARGS%"
goto :end

:nops
echo PowerShell is blocked on this PC - starting the cmd version of the hunter.

rem ---- 2) cmd version ---------------------------------------------------------------------------
:cmdmode
setlocal EnableDelayedExpansion
title MATLAB License Hunter
set "DATA=%HERE%\LicenseData"
set "CLIENT=%USERNAME%@%COMPUTERNAME%"
set "ME=%USERDOMAIN%\%USERNAME%"
for %%d in (attempts toolboxes active) do if not exist "%DATA%\%%d" mkdir "%DATA%\%%d" 2>nul
set "ATT=%DATA%\attempts\%CLIENT%.csv"
set "BEAT=%DATA%\active\%CLIENT%.txt"
set "READY=%DATA%\active\%CLIENT%.ready"
set "RELEASE=%DATA%\active\%CLIENT%.release"
set "SURVEYED=%DATA%\active\%CLIENT%.surveyed"
set "TASKS=%TEMP%\MatlabLicenseHunter-tasks.txt"
set "DATAQ=!DATA:'=''!"
rem This user's Windows session (from their Explorer), used to scan window titles quickly
set "SESSIONID="
for /f "tokens=4 delims=," %%s in ('tasklist /fo csv /nh /fi "imagename eq explorer.exe" /fi "username eq %ME%" 2^>nul') do (
    if not defined SESSIONID set "SESSIONID=%%~s"
)

rem Newest MATLAB install (folders sort R2023a < R2024b, so the last match wins)
set "MATLAB=%MATLAB_EXE%"
set "REL="
if not defined MATLAB (
    for /d %%d in ("C:\Program Files\MATLAB\R20*") do (
        if exist "%%d\bin\win64\MATLAB.exe" set "MATLAB=%%d\bin\win64\MATLAB.exe"
    )
)
if defined MATLAB for %%f in ("!MATLAB!\..\..\..") do set "REL=%%~nxf"
rem MATLAB's prefs folder, and where a known-good copy is kept while hunting
set "PREFDIR="
set "SNAP="
if defined REL (
    set "PREFDIR=%APPDATA%\MathWorks\MATLAB\!REL!"
    set "SNAP=%LOCALAPPDATA%\MatlabLicenseHunter\prefs-!REL!"
)

set "MODE=IDLE"
set "PHASE=WAIT"
set "PAUSED=0"
set "ATTEMPT=0"
set "MPID="
set "OWN=0"
set "QUIT="
set "SNAPOK="
set "BEATAT=0"
set "LASTBM="
set "HUNTAT=0"
set "LAUNCHAT=0"
set "WAITFROM=0"
set "WAITSECS=0"

cls
echo.
echo   MATLAB LICENSE HUNTER  -  cmd version
echo   ------------------------------------------------------------------------------
echo   You:          %CLIENT%
if defined MATLAB (echo   MATLAB:       !MATLAB!) else (echo   MATLAB:       not found - set MATLAB_EXE at the top of this file)
echo   Shared data:  %DATA%
echo.
echo   Keys:  H hunt    S survey on/off    P pause/resume    R release MATLAB
echo          K kill MATLAB    D details page and team stats    Q quit
echo   The window title always shows what the hunter is doing right now.
echo   ------------------------------------------------------------------------------
echo.

if "%STARTMODE%"=="SURVEY" (call :start_survey) else (call :start_hunt)

:loop
call :tick
call :settitle
choice /c HSPRKDQW /n /t 2 /d W >nul
set "K=!errorlevel!"
if "!K!"=="1" call :start_hunt
if "!K!"=="2" call :key_s
if "!K!"=="3" call :key_p
if "!K!"=="4" call :key_r
if "!K!"=="5" call :key_k
if "!K!"=="6" call :key_d
if "!K!"=="7" call :key_q
if defined QUIT goto :quit
goto :loop

:quit
del /q "%BEAT%" 2>nul
del /q "%TASKS%" 2>nul
echo.
if "!MODE!"=="HAVE" (echo   License Hunter closed. MATLAB is still running and keeps its licenses.) else (echo   License Hunter closed.)
endlocal
goto :end

rem =============================================================================================
rem  One tick (every ~2 s): heartbeat, then whatever the current mode needs
rem =============================================================================================
:tick
set "BM=!MODE!"
if "!PAUSED!"=="1" set "BM=PAUSED"
call :since !BEATAT!
if "!BM!"=="!LASTBM!" if !EL! lss 15 goto :tick_mode
rem Heartbeat: the team stats show who has a hunter open (written on change, else every 15 s)
>"%BEAT%" echo !BM!
call :nowsecs
set "BEATAT=!NS!"
set "LASTBM=!BM!"
:tick_mode
if "!MODE!"=="HUNT" goto :tick_hunt
if "!MODE!"=="SURVEY" goto :tick_hunt
if "!MODE!"=="HAVE" goto :tick_have
exit /b

:tick_hunt
if "!PHASE!"=="WAIT" goto :tick_wait
if "!PHASE!"=="LAUNCH" goto :tick_launch
if "!PHASE!"=="PROBE" goto :tick_probe
exit /b

:tick_wait
if "!PAUSED!"=="1" exit /b
call :since !WAITFROM!
if !EL! lss !WAITSECS! exit /b
call :find_matlab_pid
if not defined FOUNDPID goto :launch
if "!MODE!"=="SURVEY" (
    set "MODE=IDLE"
    call :say "MATLAB was opened outside the survey - survey stopped"
    exit /b
)
set "MPID=!FOUNDPID!"
set "MODE=HAVE"
set "OWN=0"
call :say "MATLAB is already running here - watching it. Press R to release it."
exit /b

:launch
set /a ATTEMPT+=1
set "SV="
if "!MODE!"=="SURVEY" (
    rem Every survey probe is its own one-launch "hunt", so first-try stats count each probe
    call :stamp
    set "HUNT=S!STAMP!"
    set "SV=,'Survey',true"
)
del /q "%READY%" "%SURVEYED%" 2>nul
set "MPID="
set "MAINSEEN=0"
call :nowsecs
set "LAUNCHAT=!NS!"
start "" "!MATLAB!" -nosplash -sd "%HERE%" -r "MATLABLicenseAcquisition('AutoStart',true!SV!,'DataRoot','!DATAQ!')"
set "PHASE=LAUNCH"
if "!MODE!"=="SURVEY" (call :say "Probe #!ATTEMPT! - launching MATLAB") else (call :say "#!ATTEMPT! launching MATLAB")
exit /b

:tick_launch
call :since !LAUNCHAT!
set "LEL=!EL!"
rem MATLABLicenseAcquisition.m writes the .ready file as soon as MATLAB is up
if exist "%READY%" (
    call :success "MATLAB started - ready signal from MATLAB"
    exit /b
)
if not defined MPID (
    call :find_matlab_pid
    if defined FOUNDPID set "MPID=!FOUNDPID!"
)
if not defined MPID (
    if !LEL! geq 30 call :fail ERROR "MATLAB did not start"
    exit /b
)
call :pid_alive
if not defined ALIVE (
    call :fail DENIED "MATLAB closed during startup"
    exit /b
)
call :scan_titles
if defined LICERR (
    call :fail DENIED "Licensing error window"
    exit /b
)
if defined MAINUP set "MAINSEEN=1"
if !LEL! lss %LAUNCH_TIMEOUT% exit /b
if "!MAINSEEN!"=="1" (
    call :success "MATLAB window up with no license error - no ready signal"
) else (
    call :fail TIMEOUT "No MATLAB ready signal after %LAUNCH_TIMEOUT% s"
)
exit /b

:tick_probe
rem (Survey) MATLAB writes its one-pass toolbox result, then we kill it
if exist "%SURVEYED%" (
    set "SR=no result"
    for /f "usebackq delims=" %%a in ("%SURVEYED%") do set "SR=%%a"
    set "SR=!SR:ACQUIRED=free!"
    set "SR=!SR:WAITING=busy!"
    set "SR=!SR:;=, !"
    call :finish_probe "Probe #!ATTEMPT!: !SR!"
    exit /b
)
call :pid_alive
if not defined ALIVE (
    call :finish_probe "Probe #!ATTEMPT!: MATLAB closed before the toolbox check finished"
    exit /b
)
call :since !PROBEAT!
if !EL! geq %PROBE_TIMEOUT% call :finish_probe "Probe #!ATTEMPT!: toolbox check timed out"
exit /b

:tick_have
call :pid_alive
if defined ALIVE exit /b
call :since !SESSAT!
set "SEL=!EL!"
if "!OWN!"=="1" call :log_attempt SESSION_END !SEL! "MATLAB session ended"
call :fmt !SEL!
call :say "MATLAB closed after !DUR! - licenses returned. Press H to hunt again."
set "MODE=IDLE"
set "MPID="
del /q "%RELEASE%" 2>nul
exit /b

rem =============================================================================================
rem  Results
rem =============================================================================================
:success
call :since !LAUNCHAT!
call :log_attempt SUCCESS !EL! "%~1"
if "!MODE!"=="SURVEY" (
    set "PHASE=PROBE"
    call :nowsecs
    set "PROBEAT=!NS!"
    call :say "Probe #!ATTEMPT! got MATLAB - checking toolboxes"
    exit /b
)
set "MODE=HAVE"
set "OWN=1"
call :nowsecs
set "SESSAT=!NS!"
call :since !HUNTAT!
call :fmt !EL!
call :say "GOT MATLAB on launch #!ATTEMPT! after !DUR! of hunting. Press R when you're done."
rundll32 user32.dll,MessageBeep
exit /b

:fail
rem %1 = DENIED / TIMEOUT / ERROR, %2 = detail. Logs it, kills that MATLAB right away, waits.
call :since !LAUNCHAT!
call :log_attempt %~1 !EL! "%~2"
call :say "#!ATTEMPT! %~1 - %~2"
call :kill_launched
set "PHASE=WAIT"
call :schedule_next
exit /b

:finish_probe
call :kill_launched
call :say "%~1"
set "PHASE=WAIT"
call :schedule_next
exit /b

:schedule_next
rem After the retry delay, and in survey mode no sooner than SURVEY_GAP after the last launch
call :nowsecs
set "WAITFROM=!NS!"
set "WAITSECS=%RETRY%"
if not "!MODE!"=="SURVEY" exit /b
call :since !LAUNCHAT!
set /a "LEFT=SURVEY_GAP-EL"
if !LEFT! gtr !WAITSECS! set "WAITSECS=!LEFT!"
exit /b

rem =============================================================================================
rem  Keys
rem =============================================================================================
:start_hunt
if not "!MODE!"=="IDLE" exit /b
call :find_matlab_pid
if defined FOUNDPID (
    set "MPID=!FOUNDPID!"
    set "MODE=HAVE"
    set "OWN=0"
    call :nowsecs
    set "SESSAT=!NS!"
    call :say "MATLAB is already running here - watching it. Press R to release it."
    exit /b
)
if not defined MATLAB (
    call :say "MATLAB.exe not found - set MATLAB_EXE at the top of this file"
    exit /b
)
set "MODE=HUNT"
call :begin
call :say "Hunt started"
exit /b

:start_survey
if not "!MODE!"=="IDLE" exit /b
call :find_matlab_pid
if defined FOUNDPID (
    call :say "Close MATLAB first - survey mode starts and kills MATLAB itself"
    exit /b
)
if not defined MATLAB (
    call :say "MATLAB.exe not found - set MATLAB_EXE at the top of this file"
    exit /b
)
set "MODE=SURVEY"
call :begin
call :say "Survey started - one probe every %SURVEY_GAP% s. You never keep MATLAB in this mode."
exit /b

:begin
set "PHASE=WAIT"
set "PAUSED=0"
set "ATTEMPT=0"
call :stamp
set "HUNT=!STAMP!"
call :nowsecs
set "HUNTAT=!NS!"
set "WAITFROM=!NS!"
set "WAITSECS=0"
call :save_prefs
exit /b

:key_s
if "!MODE!"=="IDLE" goto :start_survey
if not "!MODE!"=="SURVEY" exit /b
if not "!PHASE!"=="WAIT" call :kill_launched
set "MODE=IDLE"
set "PHASE=WAIT"
set "PAUSED=0"
call :say "Survey stopped after !ATTEMPT! probes"
exit /b

:key_p
if "!MODE!"=="HUNT" goto :key_p_ok
if "!MODE!"=="SURVEY" goto :key_p_ok
exit /b
:key_p_ok
if "!PAUSED!"=="1" (
    set "PAUSED=0"
    call :say "Resumed"
) else (
    set "PAUSED=1"
    call :say "Paused - press P to resume"
)
exit /b

:key_r
if not "!MODE!"=="HAVE" exit /b
echo.
choice /c YN /n /m "  Release MATLAB? It closes and returns ALL licenses - save your work first. [Y/N] "
if errorlevel 2 exit /b
rem The License Acquisition window inside MATLAB watches for this file and exits MATLAB
>"%RELEASE%" echo release
rem ...and ask MATLAB's windows to close too (like clicking X), in case that window isn't open
taskkill /pid !MPID! /t >nul 2>&1
call :say "Asked MATLAB to close - all licenses go back when it exits. Check MATLAB for a save prompt."
exit /b

:key_k
if not "!MODE!"=="HAVE" exit /b
echo.
choice /c YN /n /m "  Force-kill MATLAB? Unsaved work is lost. [Y/N] "
if errorlevel 2 exit /b
taskkill /pid !MPID! /t /f >nul 2>&1
call :say "MATLAB force-killed"
exit /b

:key_d
if not exist "%HERE%\MATLABLicenseHunter.html" (
    call :say "Details page not found next to this file"
    exit /b
)
start "" "%HERE%\MATLABLicenseHunter.html"
call :say "Opened the details page - click Load LicenseData folder there for the newest numbers"
exit /b

:key_q
echo.
set "QMSG=This closes the hunter."
if "!MODE!"=="HUNT" set "QMSG=Hunting stops. A MATLAB that is still starting up gets closed."
if "!MODE!"=="SURVEY" set "QMSG=The survey stops. A MATLAB it started gets killed."
if "!MODE!"=="HAVE" set "QMSG=Only the hunter closes. MATLAB keeps running and keeps its licenses."
choice /c YN /n /m "  Quit? !QMSG! [Y/N] "
if errorlevel 2 exit /b
if "!MODE!"=="HUNT" if not "!PHASE!"=="WAIT" call :kill_launched
if "!MODE!"=="SURVEY" if not "!PHASE!"=="WAIT" call :kill_launched
set "QUIT=1"
exit /b

rem =============================================================================================
rem  MATLAB processes
rem =============================================================================================
:find_matlab_pid
rem FOUNDPID = a MATLAB.exe running as this user, if any
set "FOUNDPID="
for /f "tokens=2 delims=," %%p in ('tasklist /fo csv /nh /fi "imagename eq MATLAB.exe" /fi "username eq %ME%" 2^>nul') do (
    if not defined FOUNDPID set "FOUNDPID=%%~p"
)
exit /b

:pid_alive
set "ALIVE="
if not defined MPID exit /b
for /f "tokens=2 delims=," %%p in ('tasklist /fo csv /nh /fi "pid eq !MPID!" 2^>nul') do set "ALIVE=1"
exit /b

:scan_titles
rem LICERR = a window in this user's session is titled like a licensing error; MAINUP = MATLAB's
rem main window is up. (tasklist /v filtered by session is fast; by username it takes ~8 s.)
set "LICERR="
set "MAINUP="
if defined SESSIONID (
    tasklist /v /fo csv /nh /fi "session eq !SESSIONID!" /fi "windowtitle ne N/A" >"%TASKS%" 2>nul
) else (
    tasklist /v /fo csv /nh /fi "imagename eq MATLAB.exe" >"%TASKS%" 2>nul
)
findstr /i /c:"Licensing Error" /c:"License Manager Error" /c:"licensed number of users" /c:"License checkout failed" /c:"maximum number of users" "%TASKS%" >nul 2>&1 && set "LICERR=1"
findstr /i /c:"MATLAB R20" "%TASKS%" >nul 2>&1 && set "MAINUP=1"
exit /b

:kill_launched
rem Force-kills a MATLAB the hunter launched, then restores prefs (a kill mid-startup can leave
rem them half-written, which makes MATLAB crash on every later start)
if defined MPID taskkill /pid !MPID! /t /f >nul 2>&1
set "MPID="
for /l %%i in (1,1,10) do (
    call :find_matlab_pid
    if defined FOUNDPID ping -n 2 127.0.0.1 >nul
)
call :restore_prefs
exit /b

:save_prefs
set "SNAPOK="
if not defined PREFDIR exit /b
if not exist "!PREFDIR!" exit /b
robocopy "!PREFDIR!" "!SNAP!" /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul 2>&1
if errorlevel 8 (call :say "Could not back up MATLAB prefs before hunting") else (set "SNAPOK=1")
exit /b

:restore_prefs
if not defined SNAPOK exit /b
call :find_matlab_pid
if defined FOUNDPID exit /b
robocopy "!SNAP!" "!PREFDIR!" /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul 2>&1
if errorlevel 8 call :say "Could not restore MATLAB prefs after a forced close"
exit /b

rem =============================================================================================
rem  Logging (same CSV format as GrabMatlabLicense.ps1, so it all counts in the team stats)
rem =============================================================================================
:log_attempt
rem %1 result, %2 seconds, %3 detail (no commas)
call :stamp
if not exist "%ATT%" (>"%ATT%" echo Timestamp,User,Computer,Hunt,Result,Seconds,SeatsUsed,SeatsTotal,Detail)
>>"%ATT%" echo !NOW!,%USERNAME%,%COMPUTERNAME%,!HUNT!,%~1,%~2,,,%~3
exit /b

:say
set "CLK=%time: =0%"
echo   [!CLK:~0,5!] %~1
exit /b

:settitle
set "T=IDLE - press H to hunt, S to survey, Q to quit"
if "!MODE!"=="HAVE" (
    call :since !SESSAT!
    call :fmt !EL!
    set "T=YOU HAVE MATLAB - !DUR! - R release, K kill"
)
if "!MODE!"=="HUNT" set "T=HUNTING"
if "!MODE!"=="SURVEY" set "T=SURVEYING"
if "!MODE!"=="HUNT" goto :settitle_run
if "!MODE!"=="SURVEY" goto :settitle_run
title MATLAB License Hunter - !T!
exit /b
:settitle_run
call :since !HUNTAT!
call :fmt !EL!
set "T=!T! - #!ATTEMPT! - !DUR!"
if "!PAUSED!"=="1" (
    set "T=!T! - PAUSED, P to resume"
) else if "!PHASE!"=="WAIT" (
    call :since !WAITFROM!
    set /a "LEFT=WAITSECS-EL"
    if !LEFT! lss 0 set "LEFT=0"
    set "T=!T! - next launch in !LEFT!s"
) else if "!PHASE!"=="LAUNCH" (
    call :since !LAUNCHAT!
    set "T=!T! - launching, !EL!/%LAUNCH_TIMEOUT%s"
) else (
    set "T=!T! - got MATLAB, checking toolboxes"
)
title MATLAB License Hunter - !T!
exit /b

rem =============================================================================================
rem  Time helpers
rem =============================================================================================
:nowsecs
rem NS = seconds since midnight
set "TT=%time: =0%"
for /f "tokens=1-3 delims=:.," %%a in ("!TT!") do set /a "NS=(10%%a %% 100)*3600 + (10%%b %% 100)*60 + (10%%c %% 100)"
exit /b

:since
rem EL = seconds since %1 (a NS value), across midnight too
call :nowsecs
set /a "EL=NS-%~1"
if !EL! lss 0 set /a "EL+=86400"
exit /b

:fmt
rem DUR = %1 seconds as 45s / 3m05s / 1h20m
set /a "_h=%~1/3600, _m=(%~1 %% 3600)/60, _s=%~1 %% 60"
set "_mm=0!_m!"
set "_ss=0!_s!"
if !_h! gtr 0 (
    set "DUR=!_h!h!_mm:~-2!m"
) else if !_m! gtr 0 (
    set "DUR=!_m!m!_ss:~-2!s"
) else (
    set "DUR=!_s!s"
)
exit /b

:stamp
rem STAMP = yyyyMMddHHmmss and NOW = yyyy-MM-dd HH:mm:ss, local time
set "LDT="
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value 2^>nul ^| find "="') do set "LDT=%%a"
if defined LDT (
    set "STAMP=!LDT:~0,14!"
) else (
    call :stamp_fallback
)
set "NOW=!STAMP:~0,4!-!STAMP:~4,2!-!STAMP:~6,2! !STAMP:~8,2!:!STAMP:~10,2!:!STAMP:~12,2!"
exit /b

:stamp_fallback
rem No wmic (newer Windows 11): read %date% in this PC's date order (iDate 0=MDY 1=DMY 2=YMD)
set "D=%date%"
set "D=!D:/= !"
set "D=!D:-= !"
set "D=!D:.= !"
set "D=!D:,= !"
set "n=0"
for %%t in (!D!) do (
    set "nonnum="
    for /f "delims=0123456789" %%x in ("%%t") do set "nonnum=1"
    if not defined nonnum (
        set /a n+=1
        set "p!n!=%%t"
    )
)
set "IDATE=0"
for /f "tokens=3" %%a in ('reg query "HKCU\Control Panel\International" /v iDate 2^>nul ^| find /i "iDate"') do set "IDATE=%%a"
if "!IDATE!"=="1" (
    set "DD=!p1!" & set "MO=!p2!" & set "YY=!p3!"
) else if "!IDATE!"=="2" (
    set "YY=!p1!" & set "MO=!p2!" & set "DD=!p3!"
) else (
    set "MO=!p1!" & set "DD=!p2!" & set "YY=!p3!"
)
if "!YY:~2!"=="" set "YY=20!YY!"
set "MO=0!MO!"
set "DD=0!DD!"
set "TT=%time: =0%"
for /f "tokens=1-3 delims=:.," %%a in ("!TT!") do (
    set "HH=0%%a" & set "MI=0%%b" & set "SS=0%%c"
)
set "STAMP=!YY!!MO:~-2!!DD:~-2!!HH:~-2!!MI:~-2!!SS:~-2!"
exit /b

:end
popd 2>nul
exit /b
