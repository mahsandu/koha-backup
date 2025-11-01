@echo off
setlocal EnableExtensions

rem Koha backup user provisioning helper (Windows CMD)
rem - Prompts for server, root credentials, backup user details, optional SSH public key, and shutdown permission.
rem - Ensures PuTTY tools (plink.exe, pscp.exe) exist in tools/ (auto-downloads if missing).
rem - Uploads backup-user.sh and runs it remotely as root to create the restricted backup user.

set SCRIPT_DIR=%~dp0
set TOOLS_DIR=%SCRIPT_DIR%tools
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%" >nul 2>&1

set PLINK=%TOOLS_DIR%\plink.exe
set PSCP=%TOOLS_DIR%\pscp.exe
set PLINK_URL=https://the.earth.li/~sgtatham/putty/latest/w32/plink.exe
set PSCP_URL=https://the.earth.li/~sgtatham/putty/latest/w32/pscp.exe

if not exist "%PLINK%" (
  echo Downloading plink.exe...
  powershell -NoProfile -Command "Invoke-WebRequest -Uri '%PLINK_URL%' -OutFile '%PLINK%'" || goto :err_dl
)
if not exist "%PSCP%" (
  echo Downloading pscp.exe...
  powershell -NoProfile -Command "Invoke-WebRequest -Uri '%PSCP_URL%' -OutFile '%PSCP%'" || goto :err_dl
)

rem Parse arguments for non-interactive mode
set NONINTERACTIVE=0
set SERVER=
set ROOTUSER=
set ROOTPASS=
set BACKUPUSER=
set BACKUPPASS=
set ALLOWSHUTDOWN=
set PUBKEY=
set HOST_FINGERPRINT=

if "%~1"=="" goto :maybe_prompt

:parse_args
if /I "%~1"=="--help" goto :usage
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="/h" goto :usage
if /I "%~1"=="/help" goto :usage

if /I "%~1"=="--server" (
  set "SERVER=%~2"& set NONINTERACTIVE=1 & shift & shift & goto :parse_args
)
if /I "%~1"=="--root" (
  set "ROOTUSER=%~2"& set NONINTERACTIVE=1 & shift & shift & goto :parse_args
)
if /I "%~1"=="--rootpass" (
  set "ROOTPASS=%~2"& set NONINTERACTIVE=1 & shift & shift & goto :parse_args
)
if /I "%~1"=="--backup-user" (
  set "BACKUPUSER=%~2"& set NONINTERACTIVE=1 & shift & shift & goto :parse_args
)
if /I "%~1"=="--backup-pass" (
  set "BACKUPPASS=%~2"& set NONINTERACTIVE=1 & shift & shift & goto :parse_args
)
if /I "%~1"=="--pubkey" (
  set "PUBKEY=%~2"& set NONINTERACTIVE=1 & shift & shift & goto :parse_args
)
if /I "%~1"=="--no-shutdown" (
  set ALLOWSHUTDOWN=N& set NONINTERACTIVE=1 & shift & goto :parse_args
)
if /I "%~1"=="--hostkey" (
  set "HOST_FINGERPRINT=%~2"& set NONINTERACTIVE=1 & shift & shift & goto :parse_args
)
if not "%~1"=="" (
  echo Unknown option: %~1
  goto :usage
)

:maybe_prompt
if "%NONINTERACTIVE%"=="1" (
  if "%SERVER%"=="" echo ERROR: --server is required in non-interactive mode.& goto :usage_fail
  if "%ROOTUSER%"=="" set ROOTUSER=root
  if "%ROOTPASS%"=="" echo ERROR: --rootpass is required in non-interactive mode.& goto :usage_fail
  if "%BACKUPUSER%"=="" set BACKUPUSER=backup
  if "%ALLOWSHUTDOWN%"=="" set ALLOWSHUTDOWN=Y
) else (
  echo === Koha backup-user setup (interactive) ===
  set /p SERVER=Enter server IP/host: 
  if "%SERVER%"=="" (
    echo ERROR: Server host is required. This script must be run interactively or with flags.^& echo Use --help for non-interactive usage.
    goto :err
  )
  set /p ROOTUSER=Enter root username [root]: 
  if "%ROOTUSER%"=="" set ROOTUSER=root
  set /p ROOTPASS=Enter root password: 
  set /p BACKUPUSER=Backup username [backup]: 
  if "%BACKUPUSER%"=="" set BACKUPUSER=backup
  set /p BACKUPPASS=Backup password (leave blank to auto-generate): 
  set /p ALLOWSHUTDOWN=Allow shutdown rights? (Y/N) [Y]: 
  if "%ALLOWSHUTDOWN%"=="" set ALLOWSHUTDOWN=Y
  set /p PUBKEY=Optional path to SSH public key (.pub) to install (leave blank to skip): 
)

rem Generate password if blank (16 random chars from powershell)
if "%BACKUPPASS%"=="" (
  for /f "usebackq delims=" %%G in (`powershell -NoProfile -Command "$c=33..126|%% { [char]$_ };$r=1..16|%% { Get-Random -InputObject $c }; -join $r"`) do set BACKUPPASS=%%G
)

set USERATHOST=%ROOTUSER%@%SERVER%

rem Try TOFU discover host fingerprint (may fail; not fatal)
if not defined HOST_FINGERPRINT (
  for /f "usebackq tokens=*" %%L in (`"%PLINK%" -v -ssh %USERATHOST% -pw "%ROOTPASS%" exit 2^>^&1 ^| findstr /R /C:"SHA256:"`) do (
    for /f "tokens=2 delims=:]" %%M in ("%%L") do set HOST_FINGERPRINT=SHA256:%%M
  )
)
if "%NONINTERACTIVE%"=="0" if not defined HOST_FINGERPRINT (
  echo Could not auto-discover host fingerprint. You may paste it next.
  set /p HOST_FINGERPRINT=Enter SSH host fingerprint (format SHA256:... or leave blank to skip): 
)

set HOSTKEY_ARGS=
if defined HOST_FINGERPRINT set HOSTKEY_ARGS=-hostkey %HOST_FINGERPRINT%

rem Ensure backup-user.sh exists
if not exist "%SCRIPT_DIR%backup-user.sh" (
  echo ERROR: backup-user.sh not found in %SCRIPT_DIR%
  goto :err
)

rem Upload backup-user.sh
"%PSCP%" -batch %HOSTKEY_ARGS% -pw "%ROOTPASS%" "%SCRIPT_DIR%backup-user.sh" "%USERATHOST%:/tmp/backup-user.sh" || goto :err

rem If provided, upload public key
set USEKEY=0
if not "%PUBKEY%"=="" (
  if not exist "%PUBKEY%" (
    echo ERROR: Public key file not found: %PUBKEY%
    goto :err
  )
  "%PSCP%" -batch %HOSTKEY_ARGS% -pw "%ROOTPASS%" "%PUBKEY%" "%USERATHOST%:/tmp/backup_user_key.pub" || goto :err
  set USEKEY=1
)

rem Build remote command
set REMOTECMD=bash /tmp/backup-user.sh --user %BACKUPUSER% --password "%BACKUPPASS%"
if %USEKEY%==1 set REMOTECMD=%REMOTECMD% --ssh-key-file /tmp/backup_user_key.pub
for %%A in (%ALLOWSHUTDOWN%) do if /I "%%A"=="N" set REMOTECMD=%REMOTECMD% --no-shutdown

rem Run provisioning
"%PLINK%" -batch %HOSTKEY_ARGS% -pw "%ROOTPASS%" %USERATHOST% "%REMOTECMD%" || goto :err

rem Cleanup staged key file (optional)
if %USEKEY%==1 "%PLINK%" -batch %HOSTKEY_ARGS% -pw "%ROOTPASS%" %USERATHOST% "rm -f /tmp/backup_user_key.pub" >nul 2>&1

echo.
echo Backup user provisioned successfully.
exit /b 0

:err_dl
echo ERROR: Failed to download PuTTY tools. Check internet connectivity or download manually to tools\.
exit /b 1

:err_input
echo ERROR: Server host is required.
exit /b 1

:err
echo ERROR: Provisioning failed. Review the output above.
exit /b 1

:usage
echo.
echo Usage: setup-backup-user.bat [options]
echo.
echo Interactive mode: run without options and follow prompts.
echo.
echo Non-interactive options:
echo   --server HOST              Server IP or hostname  [required]
echo   --root USER                Root username          [default: root]
echo   --rootpass PASS            Root password          [required]
echo   --backup-user USER         Backup username        [default: backup]
echo   --backup-pass PASS         Backup password        [auto-generate if omitted]
echo   --pubkey PATH              Path to .pub file to install for backup user
echo   --no-shutdown              Do not grant shutdown rights
echo   --hostkey SHA256:...       SSH host fingerprint to trust (skips auto-discovery)
echo   --help                     Show this help
exit /b 0

:usage_fail
echo.
echo One or more required options were missing.
echo Use --help to see usage.
exit /b 1
