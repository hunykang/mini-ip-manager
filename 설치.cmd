@echo off
rem Mini IP Manager installer.
rem Keep this file ASCII-only: cmd misreads non-ASCII text depending on the console code page.
rem The Korean messages and the shortcut are in install.ps1.
setlocal
set "APPDIR=%~dp0"

rem 1. Remove the "downloaded from the internet" mark from the files
powershell -NoProfile -Command "Get-ChildItem -LiteralPath $env:APPDIR -Recurse | Unblock-File"

rem 2. Check that this PC allows PowerShell scripts
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-ExecutionPolicy"') do set "POLICY=%%i"
if /i "%POLICY%"=="Restricted" goto blocked
if /i "%POLICY%"=="AllSigned" goto blocked

rem 3. Create the desktop shortcut
powershell -NoProfile -File "%APPDIR%install.ps1"
set "RC=%errorlevel%"
pause
exit /b %RC%

:blocked
echo.
echo  PowerShell scripts are blocked on this PC (execution policy: %POLICY%).
echo  Opening README.md - see the section about the execution policy.
start "" notepad "%APPDIR%README.md"
pause
exit /b 1
