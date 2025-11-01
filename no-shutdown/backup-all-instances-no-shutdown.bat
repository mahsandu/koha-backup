@echo off
setlocal EnableDelayedExpansion

REM Koha ALL instances backup and download WITHOUT shutdown
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

REM Download tools if missing
if not exist "%PLINK%" (
    echo Downloading plink.exe...
    powershell -Command "Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/latest/w32/plink.exe' -OutFile '%PLINK%'"
)
if not exist "%PSCP%" (
    echo Downloading pscp.exe...
    powershell -Command "Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/latest/w32/pscp.exe' -OutFile '%PSCP%'"
)

REM Attempt to auto-discover/verify host fingerprint (TOFU) so batch mode won't fail
call :ensure_putty_hostkey
if not "%HOST_FINGERPRINT%"=="" set "HOSTKEY_ARG=-hostkey %HOST_FINGERPRINT%"

echo [%date% %time%] === Koha ALL instances backup (no shutdown) === >> "%LOG_FILE%"
echo Starting Koha backup for all enabled instances (no shutdown)...

REM Discover enabled instances
echo Discovering enabled Koha instances...
echo [%date% %time%] Running: plink -batch -ssh %HOSTKEY_ARG% %USERNAME%@%IP% koha-list --enabled >> "%LOG_FILE%"
"%PLINK%" -batch -ssh %HOSTKEY_ARG% %USERNAME%@%IP% -pw %PASSWORD% "koha-list --enabled" > "%TEMP%\instances.txt" 2>&1
if errorlevel 1 (
    echo ERROR: Failed to discover instances
    echo. >> "%LOG_FILE%"
    echo [%date% %time%] ERROR: koha-list command failed >> "%LOG_FILE%"
    type "%TEMP%\instances.txt" >> "%LOG_FILE%"
    type "%TEMP%\instances.txt"
    exit /b 1
)

REM Process each instance
for /f "usebackq delims=" %%I in ("%TEMP%\instances.txt") do (
    call :process_instance "%%I"
)
del "%TEMP%\instances.txt"

echo.
echo [%date% %time%] Backup completed (no shutdown). >> "%LOG_FILE%"
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
REM Auto-discover server host fingerprint using a single verbose plink run (TOFU).
REM This updates HOST_FINGERPRINT if a SHA256 token is detected in plink output.
set "TMP_PLINK_OUT=%TEMP%\plink_ai_hostkey.txt"
if exist "%TMP_PLINK_OUT%" del "%TMP_PLINK_OUT%"

"%PLINK%" -v -ssh %USERNAME%@%IP% -pw %PASSWORD% exit 2> "%TMP_PLINK_OUT%" || rem
echo [%date% %time%] Captured plink verbose output for hostkey at %TMP_PLINK_OUT% >> "%LOG_FILE%"

set "DISCOVERED="
for /f "usebackq delims=" %%L in ("%TMP_PLINK_OUT%") do (
    echo %%L | findstr /c:"SHA256:" >nul
    if !ERRORLEVEL! EQU 0 (
        for %%T in (%%L) do (
            set "tok=%%T"
            if "!tok:~0,7!"=="SHA256:" set "DISCOVERED=!tok!"
        )
        if defined DISCOVERED goto :__found_fp_ns
    )
)
goto :__no_fp_ns

:__found_fp_ns
set "HOST_FINGERPRINT=%DISCOVERED%"
echo [%date% %time%] Discovered/updated host fingerprint: %HOST_FINGERPRINT% >> "%LOG_FILE%"
del "%TMP_PLINK_OUT%" 2>nul
goto :eof

:__no_fp_ns
echo [%date% %time%] NOTE: Could not auto-discover host fingerprint; will proceed with configured value. >> "%LOG_FILE%"
del "%TMP_PLINK_OUT%" 2>nul
goto :eof

