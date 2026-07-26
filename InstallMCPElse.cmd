@echo off
setlocal

rem NOTE: escape ")" as "^)" inside if-blocks, or cmd ends the block early.
where pwsh >nul 2>&1
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh^) が見つかりません。PowerShell 7 を導入してから再実行してください。
    set "deployExitCode=1"
    goto :finish
)

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0installMCPElse.ps1"

:finish
if not defined deployExitCode set "deployExitCode=%errorlevel%"
echo.
if not "%deployExitCode%"=="0" echo Install failed with exit code %deployExitCode%.
pause
exit /b %deployExitCode%
