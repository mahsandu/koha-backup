@echo off
REM Double-clickable launcher for Koha backup+shutdown PowerShell script.
REM Edit HOST/PORT/USER/INSTANCE/LOCALROOT below as required.
set HOST=45.114.85.234
set PORT=3022
set USER=root
set INSTANCE=mubassir
set LOCALROOT=J:\\koha-backup
set REMOTEOUT=/root/koha-backups

nREM Resolve script path (script expected in same folder)
set SCRIPT_DIR=%~dp0
set PS1=%SCRIPT_DIR%koha-backup-and-shutdown.ps1
if not exist "%PS1%" (
  echo PowerShell script not found: %PS1%
  pause
  exit /b 2
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Host %HOST% -Port %PORT% -User %USER% -Instance %INSTANCE% -LocalRoot "%LOCALROOT%" -RemoteOutDir "%REMOTEOUT%"
