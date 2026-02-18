@echo off
setlocal

if "%FIRECRAWL_API_KEY%"=="" (
  echo Missing FIRECRAWL_API_KEY
  echo.
  echo Set it first:
  echo   set FIRECRAWL_API_KEY=fc-xxxx
  echo.
  exit /b 1
)

node scripts\firecrawl_fngg_probe.mjs %*

endlocal
