@echo off
setlocal

where pwsh >nul 2>&1
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-pm-skills.ps1" -Target Both
    if errorlevel 1 goto :finish
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-unity-cli.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-pm-skills.ps1" -Target Both
    if errorlevel 1 goto :finish
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-unity-cli.ps1"
)

:finish
set "deployExitCode=%errorlevel%"
echo.
if not "%deployExitCode%"=="0" echo Install failed with exit code %deployExitCode%.
pause
exit /b %deployExitCode%
