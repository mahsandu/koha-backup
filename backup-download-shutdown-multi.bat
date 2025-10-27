@echo off
setlocal EnableDelayedExpansion

REM Koha backup, download, and optional shutdown helper (Windows .bat) - MULTI-INSTANCE version
REM Usage: backup-download-shutdown-multi.bat [test] [--no-shutdown]
REM Notes:
REM  - "test": runs a dry-run; remote commands and downloads are NOT executed
REM  - "--no-shutdown" or "no-shutdown": skip issuing a remote shutdown
REM This script discovers all enabled Koha instances via "koha-list --enabled"
REM and downloads backups for each instance to backups\<instance>\ folders.

REM === CONFIGURATION (defaults; can be overridden via config.txt) ===
SET USERNAME=backup
SET PASSWORD=backup@12345
SET IP=10.10.10.10
SET HOST_FINGERPRINT=SHA256:zkRgpJmh+WcUyVvUonvhXTDZJVL5iIHlxDrfcY2RbQk
SET RETENTION_FILES=30

REM === Use the script folder as the local backup folder ===
SET SCRIPT_DIR=%~dp0
SET TOOLS_DIR=%SCRIPT_DIR%tools
SET BACKUP_ROOT=%SCRIPT_DIR%backups
SET LOG_FILE=%BACKUP_ROOT%\backup_log.txt

REM Load optional config file (key=value) located next to this script
set "CONFIG_FILE=%~dp0config.txt"
if exist "%CONFIG_FILE%" (
    for /f "usebackq delims=" %%L in ("%CONFIG_FILE%") do (
        set "line=%%L"
        if not "!line!"=="" if not "!line:~0,1!"=="#" if not "!line:~0,1!"==";" (
            for /f "tokens=1,* delims==" %%A in ("!line!") do (
                set "key=%%~A"
                set "val=%%~B"
                for /f "tokens=* delims= " %%K in ("!key!") do set "key=%%K"
                for /f "tokens=* delims= " %%V in ("!val!") do set "val=%%V"
                if /I "!key!"=="USERNAME" set "USERNAME=!val!"
                if /I "!key!"=="PASSWORD" set "PASSWORD=!val!"
                if /I "!key!"=="IP" set "IP=!val!"
                if /I "!key!"=="HOST_FINGERPRINT" set "HOST_FINGERPRINT=!val!"
                if /I "!key!"=="RETENTION_FILES" set "RETENTION_FILES=!val!"
                if /I "!key!"=="NO_SHUTDOWN" set "NO_SHUTDOWN=!val!"
                if /I "!key!"=="PLINK_URL" set "PLINK_URL=!val!"
                if /I "!key!"=="PSCP_URL" set "PSCP_URL=!val!"
            )
        )
    )
)
if not defined RETENTION_FILES set RETENTION_FILES=30

REM PuTTY tools locations and download URLs
SET PLINK=%TOOLS_DIR%\plink.exe
SET PSCP=%TOOLS_DIR%\pscp.exe
if not defined PLINK_URL SET PLINK_URL=https://the.earth.li/~sgtatham/putty/latest/w32/plink.exe
if not defined PSCP_URL SET PSCP_URL=https://the.earth.li/~sgtatham/putty/latest/w32/pscp.exe

REM Test mode? (CLI args override config)
SET TEST_MODE=0
IF /I "%~1"=="test" (SET TEST_MODE=1)

REM Optional flags: --no-shutdown or no-shutdown will prevent the script from issuing the remote shutdown.
if not defined NO_SHUTDOWN SET NO_SHUTDOWN=0
IF /I "%~1"=="--no-shutdown" (SET NO_SHUTDOWN=1)
IF /I "%~1"=="no-shutdown" (SET NO_SHUTDOWN=1)
IF /I "%~2"=="--no-shutdown" (SET NO_SHUTDOWN=1)
IF /I "%~2"=="no-shutdown" (SET NO_SHUTDOWN=1)

REM Create directories if they don't exist
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%BACKUP_ROOT%" mkdir "%BACKUP_ROOT%"

echo [%date% %time%] === Starting Koha multi-instance backup (test=%TEST_MODE%) === >> "%LOG_FILE%"
echo Current folder: %CD% >> "%LOG_FILE%"
echo Backup root: %BACKUP_ROOT% >> "%LOG_FILE%"
echo Logging to: %LOG_FILE%

if "%TEST_MODE%"=="1" (
    echo [DRYRUN] Test mode active - no remote commands or downloads will run.
    echo [DRYRUN] Test mode active - no remote commands or downloads will run. >> "%LOG_FILE%"
)

REM === Ensure PuTTY tools exist or download them (skipped in test mode) ===
if "%TEST_MODE%"=="1" (
    echo [DRYRUN] Skipping plink/pscp downloads
) else (
    if not exist "%PLINK%" (
        echo [%date% %time%] plink.exe not found. Downloading... >> "%LOG_FILE%"
        powershell -Command "Invoke-WebRequest -Uri '%PLINK_URL%' -OutFile '%PLINK%'"
    )
    if not exist "%PSCP%" (
        echo [%date% %time%] pscp.exe not found. Downloading... >> "%LOG_FILE%"
        powershell -Command "Invoke-WebRequest -Uri '%PSCP_URL%' -OutFile '%PSCP%'"
    )
)

REM Check downloads (unless test mode)
if "%TEST_MODE%"=="0" (
    if not exist "%PLINK%" (
        echo [%date% %time%] ERROR: plink.exe missing! Exiting. >> "%LOG_FILE%"
        exit /b 1
    )
    if not exist "%PSCP%" (
        echo [%date% %time%] ERROR: pscp.exe missing! Exiting. >> "%LOG_FILE%"
        exit /b 1
    )
)

REM Ensure PuTTY knows the server host key (so plink/pscp won't fail in batch mode).
call :ensure_putty_hostkey

REM === Discover all enabled Koha instances ===
echo [%date% %time%] Discovering enabled Koha instances... >> "%LOG_FILE%"
set "TMP_INSTANCES=%TEMP%\koha_instances.txt"
if "%TEST_MODE%"=="1" (
    echo ils > "%TMP_INSTANCES%"
    echo library >> "%TMP_INSTANCES%"
) else (
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "koha-list --enabled" > "%TMP_INSTANCES%" 2>&1
    if !ERRORLEVEL! NEQ 0 (
        echo [%date% %time%] ERROR: Failed to run koha-list --enabled >> "%LOG_FILE%"
        type "%TMP_INSTANCES%" >> "%LOG_FILE%"
        del "%TMP_INSTANCES%"
        exit /b 1
    )
)

set "INSTANCE_COUNT=0"
for /f "usebackq delims=" %%I in ("%TMP_INSTANCES%") do (
    set /a INSTANCE_COUNT+=1
)
echo [%date% %time%] Found %INSTANCE_COUNT% enabled instance(s). >> "%LOG_FILE%"

if %INSTANCE_COUNT% EQU 0 (
    echo [%date% %time%] ERROR: No enabled instances found! >> "%LOG_FILE%"
    del "%TMP_INSTANCES%"
    exit /b 1
)

REM === Process each instance ===
for /f "usebackq delims=" %%I in ("%TMP_INSTANCES%") do (
    set "INSTANCE=%%I"
    echo.
    echo [%date% %time%] ========== Processing instance: !INSTANCE! ========== >> "%LOG_FILE%"
    echo Processing instance: !INSTANCE!
    
    REM Set paths for this instance
    set "KOHA_BACKUP_PATH=/var/spool/koha/!INSTANCE!"
    set "BACKUP_FOLDER=%BACKUP_ROOT%\!INSTANCE!"
    
    REM Create instance-specific backup folder
    if not exist "!BACKUP_FOLDER!" mkdir "!BACKUP_FOLDER!"
    
    REM Check if backup exists within last hour (skip if yes)
    set "SKIP_BACKUP=0"
    set "TMP_LATEST=%TEMP%\koha_latest_!INSTANCE!_precheck.txt"
    if "%TEST_MODE%"=="1" (
        echo !INSTANCE!-2025-10-13.sql.gz > "!TMP_LATEST!"
        echo !INSTANCE!-2025-10-13.tar.gz >> "!TMP_LATEST!"
    ) else (
        "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sh -lc 'ls -t !KOHA_BACKUP_PATH! 2>&1 | head -2'" > "!TMP_LATEST!" 2>&1
    )
    
    set "LATEST_BACKUP1="
    for /f "usebackq delims=" %%F in ("!TMP_LATEST!") do (
        echo %%F | findstr /i "\.tar\.gz \.sql\.gz" >nul
        if !ERRORLEVEL! EQU 0 if not defined LATEST_BACKUP1 set "LATEST_BACKUP1=%%F"
    )
    if exist "!TMP_LATEST!" del "!TMP_LATEST!"
    
    if not "%TEST_MODE%"=="1" if defined LATEST_BACKUP1 (
        set "FILE_DATE_HOUR="
        for /f "usebackq tokens=*" %%f in (`"%PLINK%" -batch -ssh %USERNAME%@%IP% -pw %PASSWORD% "date -r !KOHA_BACKUP_PATH!/!LATEST_BACKUP1! +%%Y-%%m-%%d %%H" 2^>nul`) do set "FILE_DATE_HOUR=%%f"
        set "CURRENT_DATE_HOUR="
        for /f "usebackq tokens=*" %%f in (`"%PLINK%" -batch -ssh %USERNAME%@%IP% -pw %PASSWORD% "date +%%Y-%%m-%%d %%H" 2^>nul`) do set "CURRENT_DATE_HOUR=%%f"
        if not "!FILE_DATE_HOUR!"=="" if "!FILE_DATE_HOUR!"=="!CURRENT_DATE_HOUR!" (
            set "SKIP_BACKUP=1"
            echo [%date% %time%] !INSTANCE!: Backup generated within last hour, will skip generation. >> "%LOG_FILE%"
        )
    )
    
    REM Run backup command for this instance
    echo [%date% %time%] !INSTANCE!: Running koha-run-backups... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
        echo [DRYRUN] koha-run-backups !INSTANCE! >> "%LOG_FILE%"
        set "RC=0"
    ) else (
        if "!SKIP_BACKUP!"=="1" (
            echo [%date% %time%] !INSTANCE!: Skipping backup generation. >> "%LOG_FILE%"
            set "RC=0"
        ) else (
            "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /usr/sbin/koha-run-backups !INSTANCE!"
            set "RC=!ERRORLEVEL!"
        )
    )
    echo [%date% %time%] !INSTANCE!: Backup command RC: !RC! >> "%LOG_FILE%"
    
    if not "!RC!"=="0" (
        echo [%date% %time%] ERROR: !INSTANCE!: Remote backup command failed! >> "%LOG_FILE%"
        echo ERROR: Backup failed for instance !INSTANCE!
        REM Continue with other instances
        goto :next_instance
    )
    
    REM Find latest backup file names (two files: SQL and files)
    echo [%date% %time%] !INSTANCE!: Getting latest backup filenames... >> "%LOG_FILE%"
    set "TMP_LATEST=%TEMP%\koha_latest_!INSTANCE!.txt"
    if "%TEST_MODE%"=="1" (
        echo !INSTANCE!-2025-10-13.sql.gz > "!TMP_LATEST!"
        echo !INSTANCE!-2025-10-13.tar.gz >> "!TMP_LATEST!"
    ) else (
        "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sh -lc 'ls -t !KOHA_BACKUP_PATH! 2>&1 | head -2'" > "!TMP_LATEST!" 2>&1
        if !ERRORLEVEL! NEQ 0 (
            echo [%date% %time%] !INSTANCE!: Remote ls produced errors: >> "%LOG_FILE%"
            type "!TMP_LATEST!" >> "%LOG_FILE%" 2>&1
        )
    )
    
    REM Read the two filenames
    set /a count=0
    set "LATEST_BACKUP1="
    set "LATEST_BACKUP2="
    for /f "usebackq delims=" %%F in ("!TMP_LATEST!") do (
        echo %%F | findstr /i "\.tar\.gz \.sql\.gz" >nul
        if !ERRORLEVEL! EQU 0 (
            set /a count+=1
            if !count! EQU 1 set "LATEST_BACKUP1=%%F"
            if !count! EQU 2 set "LATEST_BACKUP2=%%F"
        ) else (
            echo [%date% %time%] !INSTANCE!: Ignoring non-backup line: %%F >> "%LOG_FILE%"
        )
    )
    if exist "!TMP_LATEST!" del "!TMP_LATEST!"
    
    echo [%date% %time%] !INSTANCE!: Latest backups are: !LATEST_BACKUP1! and !LATEST_BACKUP2! >> "%LOG_FILE%"
    
    if "!LATEST_BACKUP1!"=="" (
        echo [%date% %time%] ERROR: !INSTANCE!: No valid backup filenames found! >> "%LOG_FILE%"
        echo ERROR: No valid backups found for instance !INSTANCE!
        goto :next_instance
    )
    
    REM Download both backups for this instance
    for %%b in (!LATEST_BACKUP1! !LATEST_BACKUP2!) do (
        if not "%%b"=="" (
            echo [%date% %time%] !INSTANCE!: Copying backup %%b to temp location... >> "%LOG_FILE%"
            if "%TEST_MODE%"=="1" (
                echo [DRYRUN] sudo cp !KOHA_BACKUP_PATH!/%%b /tmp/%%b ^&^& sudo chmod 644 /tmp/%%b >> "%LOG_FILE%"
            ) else (
                "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo cp !KOHA_BACKUP_PATH!/%%b /tmp/%%b && sudo chmod 644 /tmp/%%b" >> "%LOG_FILE%" 2>&1
            )
            
            echo [%date% %time%] !INSTANCE!: Downloading backup %%b... >> "%LOG_FILE%"
            if "%TEST_MODE%"=="1" (
                echo [DRYRUN] pscp download %%b to !BACKUP_FOLDER! >> "%LOG_FILE%"
                set "DL_RC=0"
            ) else (
                "%PSCP%" -batch -hostkey %HOST_FINGERPRINT% -pw %PASSWORD% "%USERNAME%@%IP%:/tmp/%%b" "!BACKUP_FOLDER!" >> "%LOG_FILE%" 2>&1
                set "DL_RC=!ERRORLEVEL!"
            )
            
            if not "!DL_RC!"=="0" (
                echo [%date% %time%] ERROR: !INSTANCE!: Failed to download backup %%b! >> "%LOG_FILE%"
                echo ERROR: Failed to download %%b for instance !INSTANCE!
            ) else (
                echo [%date% %time%] !INSTANCE!: Downloaded %%b successfully. >> "%LOG_FILE%"
            )
        )
    )
    
    REM Cleanup old backups for this instance - keep only RETENTION_FILES newest .tar.gz
    echo [%date% %time%] !INSTANCE!: Cleaning old backups (keeping %RETENTION_FILES%)... >> "%LOG_FILE%"
    for /f "skip=%RETENTION_FILES% delims=" %%F in ('dir "!BACKUP_FOLDER!" /b /a-d /o-d 2^>nul ^| findstr /i ".tar.gz"') do (
        echo [%date% %time%] !INSTANCE!: Deleting %%F >> "%LOG_FILE%"
        del "!BACKUP_FOLDER!\%%F"
    )
    
    :next_instance
)

del "%TMP_INSTANCES%"

REM Shutdown remote server (disabled when NO_SHUTDOWN=1)
if "%NO_SHUTDOWN%"=="1" (
    echo [%date% %time%] NO_SHUTDOWN flag set; skipping remote shutdown. >> "%LOG_FILE%"
) else (
    echo [%date% %time%] Shutting down server... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
        echo [DRYRUN] sudo /sbin/shutdown now >> "%LOG_FILE%"
    ) else (
        "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /sbin/shutdown now"
        echo [%date% %time%] Shutdown command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    )
)

echo.
echo [%date% %time%] Multi-instance backup completed. >> "%LOG_FILE%"
echo Multi-instance backup completed.
echo Done. See log at: %LOG_FILE%

goto :eof


:ensure_putty_hostkey
REM Auto-discover server host fingerprint using a single verbose plink run (TOFU).
if "%TEST_MODE%"=="1" (
    echo [%date% %time%] Test mode - skipping hostkey discovery. >> "%LOG_FILE%"
    goto :eof
)

set "TMP_PLINK_OUT=%TEMP%\plink_fingerprint.txt"
if exist "%TMP_PLINK_OUT%" del "%TMP_PLINK_OUT%"

"%PLINK%" -v -ssh -batch %USERNAME%@%IP% -pw %PASSWORD% exit 2> "%TMP_PLINK_OUT%" || rem
echo [%date% %time%] Captured plink verbose output for hostkey discovery. >> "%LOG_FILE%"

set "DISCOVERED="
for /f "usebackq delims=" %%L in ("%TMP_PLINK_OUT%") do (
    echo %%L | findstr /c:"SHA256:" >nul
    if !ERRORLEVEL! EQU 0 (
        for %%T in (%%L) do (
            set "tok=%%T"
            if "!tok:~0,7!"=="SHA256:" (
                set "DISCOVERED=!tok!"
            )
        )
        if defined DISCOVERED goto :__found_fp
    )
)
goto :__no_fp

:__found_fp
set "HOST_FINGERPRINT=%DISCOVERED%"
echo [%date% %time%] Discovered host fingerprint: %HOST_FINGERPRINT% >> "%LOG_FILE%"
del "%TMP_PLINK_OUT%" 2>nul || rem
goto :eof

:__no_fp
echo [%date% %time%] WARNING: Could not discover host fingerprint from plink output. >> "%LOG_FILE%"
del "%TMP_PLINK_OUT%" 2>nul || rem
goto :eof
