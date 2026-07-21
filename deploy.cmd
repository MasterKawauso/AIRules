@echo off
setlocal

where pwsh >nul 2>&1
if %errorlevel% equ 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1"
)

set "deployExitCode=%errorlevel%"
echo.
if not "%deployExitCode%"=="0" echo Deploy failed with exit code %deployExitCode%.
pause
exit /b %deployExitCode%
