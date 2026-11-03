@echo off
rem UNDERTOW launcher. Opens the game signed in as your Windows user name, so nobody types a callsign.
rem Keep this file next to undertow.html (and the files folder) and double-click it to play.
rem A web page cannot read the Windows user name itself, so this hands %USERNAME% to the page,
rem the same way the MATLAB License Hunter uses $env:USERNAME.
setlocal
set "PAGE=%~dp0undertow.html"
if not exist "%PAGE%" (
  echo undertow.html was not found next to this launcher.
  pause
  exit /b 1
)
set "URL=%PAGE:\=/%"
if "%URL:~0,2%"=="//" (set "URL=file:%URL%") else (set "URL=file:///%URL%")
rem Opening a file with "#..." on the end drops that part, so a small page in TEMP forwards to the game with it.
set "STUB=%TEMP%\undertow-launch.html"
> "%STUB%" echo ^<!doctype html^>^<meta charset="utf-8"^>^<title^>UNDERTOW^</title^>^<script^>location.replace(encodeURI("%URL%")+"#user="+encodeURIComponent("%USERNAME%"))^</script^>
start "" "%STUB%"
