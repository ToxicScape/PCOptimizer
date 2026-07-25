@echo off
setlocal
powershell -WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCOptimizer.GUI.ps1"
