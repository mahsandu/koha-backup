@echo off
setlocal EnableDelayedExpansion

REM Koha ALL instances backup and download with shutdown
REM Discovers all enabled instances via "koha-list --enabled" and downloads backups for each

SET SCRIPT_DIR=%~dp0
SET TOOLS_DIR=%SCRIPT_DIR%tools
SET BACKUP_ROOT=%SCRIPT_DIR%backups
SET LOG_FILE=%BACKUP_ROOT%\backup_log.txt

REM Load config
SET USERNAME=backup
SET PASSWORD=backup@12345
SET IP=10.10.10.10
SET HOST_FINGERPRINT=
SET RETENTION_FILES=30

if exist "%SCRIPT_DIR%config.txt" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%SCRIPT_DIR%config.txt") do (
        set "key=%%A"
        set "val=%%B"
        if /I "!key!"=="USERNAME" set "USERNAME=!val!"
        if /I "!key!"=="PASSWORD" set "PASSWORD=!val!"
        if /I "!key!"=="IP" set "IP=!val!"
        if /I "!key!"=="HOST_FINGERPRINT" set "HOST_FINGERPRINT=!val!"
        if /I "!key!"=="RETENTION_FILES" set "RETENTION_FILES=!val!"
    )
)

SET PLINK=%TOOLS_DIR%\plink.exe
SET PSCP=%TOOLS_DIR%\pscp.exe

if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%BACKUP_ROOT%" mkdir "%BACKUP_ROOT%"

echo [%date% %time%] === Koha ALL instances backup with shutdown === >> "%LOG_FILE%"
echo Starting Koha backup for all enabled instances...

REM Discover enabled instances
echo Discovering enabled Koha instances...
"%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "koha-list --enabled" > "%TEMP%\instances.txt" 2>&1
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
"%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /sbin/shutdown now"
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
"%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /usr/sbin/koha-run-backups %INST%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo WARNING: Backup command failed for %INST%
    goto :eof
)

REM Get latest 2 backup files
"%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "ls -t %REMOTE_PATH% | head -2" > "%TEMP%\files_%INST%.txt" 2>&1

REM Download each backup file
for /f "usebackq delims=" %%F in ("%TEMP%\files_%INST%.txt") do (
    set "FNAME=%%F"
    echo !FNAME! | findstr /i ".gz" >nul
    if !ERRORLEVEL! EQU 0 (
        echo Downloading !FNAME!...
        "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo cp %REMOTE_PATH%/!FNAME! /tmp/!FNAME! && sudo chmod 644 /tmp/!FNAME!" >> "%LOG_FILE%" 2>&1
        "%PSCP%" -batch -hostkey %HOST_FINGERPRINT% -pw %PASSWORD% %USERNAME%@%IP%:/tmp/!FNAME! "%BACKUP_FOLDER%\" >> "%LOG_FILE%" 2>&1
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
