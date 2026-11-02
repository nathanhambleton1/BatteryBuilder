@echo off
rem Double-click launcher for GrabMatlabLicense.ps1 (works from a network drive / UNC path too)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GrabMatlabLicense.ps1" %*
if errorlevel 1 pause
