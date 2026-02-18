@echo off
setlocal
cd /d "%~dp0.."

echo Running Epic Discovery API Spike...
echo Output will be saved under scripts\_out\spike_*
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\epic_discovery_api_spike.ps1

set EC=%ERRORLEVEL%
echo.
if not "%EC%"=="0" (
  echo Script failed with exit code %EC%.
)
pause
exit /b %EC%

