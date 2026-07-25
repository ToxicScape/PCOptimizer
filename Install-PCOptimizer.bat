@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

if exist "%SCRIPT_DIR%scripts\Install-PCOptimizer.ps1" (
  powershell -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Install-PCOptimizer.ps1"
  exit /b %errorlevel%
)

powershell -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue';" ^
  "$tmp = Join-Path $env:TEMP 'Install-PCOptimizer.ps1';" ^
  "Invoke-WebRequest -UseBasicParsing 'https://github.com/ToxicScape/PCOptimizer/releases/latest/download/Install-PCOptimizer.ps1' -OutFile $tmp;" ^
  "& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $tmp"
