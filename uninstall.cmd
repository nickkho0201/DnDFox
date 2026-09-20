@echo off
setlocal
title DnDFox uninstaller

if exist "%~dp0scripts\Uninstall-DnDFox.ps1" (
  set "DNDFOX_SCRIPT=%~dp0scripts\Uninstall-DnDFox.ps1"
) else (
  set "DNDFOX_SCRIPT=%~dp0Uninstall-DnDFox.ps1"
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DNDFOX_SCRIPT%"
set "DNDFOX_EXIT=%ERRORLEVEL%"

echo.
if not "%DNDFOX_EXIT%"=="0" (
  echo DnDFox removal failed with exit code %DNDFOX_EXIT%.
) else (
  echo DnDFox was removed.
)
pause
exit /b %DNDFOX_EXIT%
