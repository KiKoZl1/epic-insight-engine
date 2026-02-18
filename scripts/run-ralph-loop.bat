@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ralph_loop.ps1 %*
exit /b %ERRORLEVEL%
