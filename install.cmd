@echo off
setlocal
title DnDFox installer

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-DnDFox.ps1"
set "DNDFOX_EXIT=%ERRORLEVEL%"

echo.
if not "%DNDFOX_EXIT%"=="0" (
  echo DnDFox installation failed with exit code %DNDFOX_EXIT%.
) else (
  echo DnDFox installation completed.
)
pause
exit /b %DNDFOX_EXIT%
