@echo off
setlocal EnableDelayedExpansion

REM Koha ALL instances backup and download with shutdown
REM Discovers all enabled instances via "koha-list --enabled" and downloads backups for each

SET SCRIPT_DIR=%~dp0
SET ROOT_DIR=%SCRIPT_DIR%..
SET TOOLS_DIR=%ROOT_DIR%\tools
SET BACKUP_ROOT=%ROOT_DIR%\backups
SET LOG_FILE=%BACKUP_ROOT%\backup_log.txt
SET CONFIG_FILE=%ROOT_DIR%\config.txt

REM Load config
SET USERNAME=backup
SET PASSWORD=backup@12345
SET IP=10.10.10.10
SET HOST_FINGERPRINT=
SET RETENTION_FILES=30

if exist "%CONFIG_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
        set "line=%%A"
        REM Skip comment lines
        if not "!line:~0,1!"=="#" if not "!line:~0,1!"==";" (
            set "key=%%A"
            set "val=%%B"
            if /I "!key!"=="USERNAME" set "USERNAME=!val!"
            if /I "!key!"=="PASSWORD" set "PASSWORD=!val!"
            if /I "!key!"=="IP" set "IP=!val!"
            if /I "!key!"=="HOST_FINGERPRINT" set "HOST_FINGERPRINT=!val!"
            if /I "!key!"=="RETENTION_FILES" set "RETENTION_FILES=!val!"
        )
    )
)

SET PLINK=%TOOLS_DIR%\plink.exe
SET PSCP=%TOOLS_DIR%\pscp.exe
SET "HOSTKEY_ARG="
if not "%HOST_FINGERPRINT%"=="" set "HOSTKEY_ARG=-hostkey %HOST_FINGERPRINT%"

if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%BACKUP_ROOT%" mkdir "%BACKUP_ROOT%"

REM Ensure host key is discovered
call :ensure_putty_hostkey
if not "%HOST_FINGERPRINT%"=="" set "HOSTKEY_ARG=-hostkey %HOST_FINGERPRINT%"

REM Download tools if missing
if not exist "%PLINK%" (
    echo Downloading plink.exe...
    powershell -Command "Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/latest/w32/plink.exe' -OutFile '%PLINK%'"
)
if not exist "%PSCP%" (
    echo Downloading pscp.exe...
    powershell -Command "Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/latest/w32/pscp.exe' -OutFile '%PSCP%'"
)

echo [%date% %time%] === Koha ALL instances backup with shutdown === >> "%LOG_FILE%"
echo Starting Koha backup for all enabled instances...

REM Discover enabled instances
echo Discovering enabled Koha instances...
"%PLINK%" -batch -ssh %HOSTKEY_ARG% %USERNAME%@%IP% -pw %PASSWORD% "koha-list --enabled" > "%TEMP%\instances.txt" 2>&1
if errorlevel 1 (
    echo ERROR: Failed to discover instances
    type "%TEMP%\instances.txt"
    exit /b 1
)

REM Process each instance
for /f "usebackq delims=" %%I in ("%TEMP%\instances.txt") do (
    call :process_instance "%%I"
)
del "%TEMP%\instances.txt"

REM Shutdown server
echo Shutting down server...
"%PLINK%" -batch -ssh %HOSTKEY_ARG% %USERNAME%@%IP% -pw %PASSWORD% "sudo /sbin/shutdown now"
echo [%date% %time%] Shutdown command sent >> "%LOG_FILE%"

echo.
echo Backup completed. See log: %LOG_FILE%
exit /b 0


:process_instance
set "INST=%~1"
echo.
echo === Processing instance: %INST% ===
echo [%date% %time%] Processing instance: %INST% >> "%LOG_FILE%"

set "BACKUP_FOLDER=%BACKUP_ROOT%\%INST%"
set "REMOTE_PATH=/var/spool/koha/%INST%"

if not exist "%BACKUP_FOLDER%" mkdir "%BACKUP_FOLDER%"

REM Run backup
echo Running backup for %INST%...
"%PLINK%" -batch -ssh %HOSTKEY_ARG% %USERNAME%@%IP% -pw %PASSWORD% "sudo /usr/sbin/koha-run-backups %INST%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo WARNING: Backup command failed for %INST%
    goto :eof
)

REM Get latest 2 backup files
"%PLINK%" -batch -ssh %HOSTKEY_ARG% %USERNAME%@%IP% -pw %PASSWORD% "ls -t %REMOTE_PATH% | head -2" > "%TEMP%\files_%INST%.txt" 2>&1

REM Download each backup file
for /f "usebackq delims=" %%F in ("%TEMP%\files_%INST%.txt") do (
    set "FNAME=%%F"
    echo !FNAME! | findstr /i ".gz" >nul
    if !ERRORLEVEL! EQU 0 (
        echo Downloading !FNAME!...
        "%PLINK%" -batch -ssh %HOSTKEY_ARG% %USERNAME%@%IP% -pw %PASSWORD% "sudo cp %REMOTE_PATH%/!FNAME! /tmp/!FNAME! && sudo chmod 644 /tmp/!FNAME!" >> "%LOG_FILE%" 2>&1
        "%PSCP%" -batch %HOSTKEY_ARG% -pw %PASSWORD% %USERNAME%@%IP%:/tmp/!FNAME! "%BACKUP_FOLDER%" >> "%LOG_FILE%" 2>&1
        if exist "%BACKUP_FOLDER%\!FNAME!" (
            echo   Downloaded: !FNAME!
        ) else (
            echo   WARNING: Failed to download !FNAME!
        )
    )
)
del "%TEMP%\files_%INST%.txt"

REM Cleanup old backups
for /f "skip=%RETENTION_FILES% delims=" %%F in ('dir "%BACKUP_FOLDER%" /b /a-d /o-d 2^>nul ^| findstr /i ".tar.gz"') do (
    del "%BACKUP_FOLDER%\%%F"
    echo [%date% %time%] %INST%: Deleted old backup %%F >> "%LOG_FILE%"
)

goto :eof


:ensure_putty_hostkey
REM Check if HOST_FINGERPRINT is already set
if not "%HOST_FINGERPRINT%"=="" goto :eof

echo Discovering SSH host key fingerprint (first time only)...
REM Use plink in verbose mode to capture host key, pipe stderr to stdout
set "TEMPFP=%TEMP%\fingerprint_ai.txt"
"%PLINK%" -v -batch -ssh %USERNAME%@%IP% -pw %PASSWORD% exit 2>&1 | findstr /c:"SHA256:" > "%TEMPFP%"

REM Extract the fingerprint from verbose output
for /f "tokens=2 delims=: " %%A in ('findstr /c:"SHA256:" "%TEMPFP%"') do (
    for /f "tokens=1" %%B in ("%%A") do (
        set "HOST_FINGERPRINT=SHA256:%%B"
        echo Discovered fingerprint: SHA256:%%B
        goto :__found_fp_ai
    )
)

:__no_fp_ai
echo WARNING: Could not auto-discover host key fingerprint
echo Please add HOST_FINGERPRINT=... to config.txt manually
del "%TEMPFP%" 2>nul
goto :eof

:__found_fp_ai
REM Cleanup temp file
del "%TEMPFP%" 2>nul
goto :eof
