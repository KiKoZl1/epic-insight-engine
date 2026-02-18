@echo off
setlocal

cd /d "%~dp0.."
title SQL Runner (psql)

REM Examples:
REM   scripts\run-sql.bat -Query "select now();"
REM   scripts\run-sql.bat -File migration_artifacts\sql\11_fk_validate.sql

powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\sql.ps1 %*

endlocal

