@echo off
setlocal
set SCRIPT_DIR=%~dp0
node "%SCRIPT_DIR%export_supabase_tables.mjs" %*
endlocal

