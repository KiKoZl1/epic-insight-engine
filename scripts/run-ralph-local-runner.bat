@echo off
setlocal

if "%SUPABASE_URL%"=="" (
  if "%VITE_SUPABASE_URL%"=="" (
    echo Missing SUPABASE_URL ^(or VITE_SUPABASE_URL^)
    exit /b 1
  )
)

if "%SUPABASE_SERVICE_ROLE_KEY%"=="" (
  echo Missing SUPABASE_SERVICE_ROLE_KEY
  exit /b 1
)

node scripts\ralph_local_runner.mjs %*

endlocal
