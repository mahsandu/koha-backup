@echo off
setlocal EnableDelayedExpansion

REM Koha backup, download, and optional shutdown helper (Windows .bat)
REM Usage: backup-download-shutdown.bat [test] [--no-shutdown]
REM Notes:
REM  - "test": runs a dry-run; remote commands and downloads are NOT executed
REM  - "--no-shutdown" or "no-shutdown": skip issuing a remote shutdown
REM This script logs to backups\backup_log.txt.

REM === CONFIGURATION (defaults; can be overridden via config.txt) ===
SET USERNAME=backup
SET PASSWORD=backup@12345
SET IP=10.10.10.10
SET INSTANCE=ils
SET HOST_FINGERPRINT=SHA256:zkRgpJmh+WcUyVvUonvhXTDZJVL5iIHlxDrfcY2RbQk
SET RETENTION_FILES=30
SET KOHA_BACKUP_PATH=

REM === Use the script folder as the local backup folder ===
SET SCRIPT_DIR=%~dp0
SET TOOLS_DIR=%SCRIPT_DIR%tools
SET BACKUP_FOLDER=%SCRIPT_DIR%backups
SET LOG_FILE=%BACKUP_FOLDER%\backup_log.txt

REM Load optional config file (key=value) located next to this script
set "CONFIG_FILE=%~dp0config.txt"
if exist "%CONFIG_FILE%" (
    set "CFG_SET_KOHA_PATH=0"
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
                if /I "!key!"=="INSTANCE" set "INSTANCE=!val!"
                if /I "!key!"=="HOST_FINGERPRINT" set "HOST_FINGERPRINT=!val!"
                if /I "!key!"=="RETENTION_FILES" set "RETENTION_FILES=!val!"
                if /I "!key!"=="NO_SHUTDOWN" set "NO_SHUTDOWN=!val!"
                if /I "!key!"=="KOHA_BACKUP_PATH" ( set "KOHA_BACKUP_PATH=!val!" & set "CFG_SET_KOHA_PATH=1" )
                if /I "!key!"=="PLINK_URL" set "PLINK_URL=!val!"
                if /I "!key!"=="PSCP_URL" set "PSCP_URL=!val!"
            )
        )
    )
    if not defined RETENTION_FILES set RETENTION_FILES=30
)

REM Backup path on server depends on instance name unless explicitly provided
if not defined KOHA_BACKUP_PATH set KOHA_BACKUP_PATH=/var/spool/koha/%INSTANCE%

REM PuTTY tools locations and download URLs
SET PLINK=%TOOLS_DIR%\plink.exe
SET PSCP=%TOOLS_DIR%\pscp.exe
if not defined PLINK_URL SET PLINK_URL=https://the.earth.li/~sgtatham/putty/latest/w32/plink.exe
if not defined PSCP_URL SET PSCP_URL=https://the.earth.li/~sgtatham/putty/latest/w32/pscp.exe
REM Known server fingerprint (can be overridden via config.txt)

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
if not exist "%TOOLS_DIR%" (
    mkdir "%TOOLS_DIR%"
)
if not exist "%BACKUP_FOLDER%" (
    mkdir "%BACKUP_FOLDER%"
)

echo [%date% %time%] === Starting Koha backup (test=%TEST_MODE%) === >> "%LOG_FILE%"
echo Current folder: %CD% >> "%LOG_FILE%"
echo Current script dir: %SCRIPT_DIR% >> "%LOG_FILE%"
echo Backup folder: %BACKUP_FOLDER% >> "%LOG_FILE%"
echo Log file: %LOG_FILE% >> "%LOG_FILE%"
echo Logging to: %LOG_FILE%

if "%TEST_MODE%"=="1" (
    echo [DRYRUN] Test mode active - no remote commands or downloads will run.
    echo [DRYRUN] Test mode active - no remote commands or downloads will run. >> "%LOG_FILE%"
)

REM Decide whether to skip backup generation based on latest file time (within last hour)
set "SKIP_BACKUP=0"
set "TMP_LATEST=%TEMP%\koha_latest_precheck.txt"
if "%TEST_MODE%"=="1" (
    echo ils-2025-10-13.sql.gz > "%TMP_LATEST%"
    echo ils-2025-10-13.tar.gz >> "%TMP_LATEST%"
) else (
    REM Use a shell wrapper and redirect stderr to the temp file so any remote error messages are captured.
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sh -lc 'ls -t %KOHA_BACKUP_PATH% 2>&1 | head -2'" > "%TMP_LATEST%" 2>&1
    echo [%date% %time%] ls command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    if not "%ERRORLEVEL%"=="0" (
        echo [%date% %time%] Remote ls produced errors, dumping remote output for debugging: >> "%LOG_FILE%"
        type "%TMP_LATEST%" >> "%LOG_FILE%" 2>&1
    )
)
set "LATEST_BACKUP1="
REM Pick the first valid filename that looks like a Koha backup (sql.gz or tar.gz). Ignore error text.
for /f "usebackq delims=" %%f in ("%TMP_LATEST%") do (
    echo %%f | findstr /i "\.tar\.gz \.sql\.gz" >nul
    if !ERRORLEVEL! EQU 0 (
        if not defined LATEST_BACKUP1 set "LATEST_BACKUP1=%%f"
    ) else (
        echo [%date% %time%] Ignoring non-backup line in precheck: %%f >> "%LOG_FILE%"
    )
)
if exist "%TMP_LATEST%" del "%TMP_LATEST%"
if not "%TEST_MODE%"=="1" if defined LATEST_BACKUP1 (
    set "FILE_DATE_HOUR="
    for /f "usebackq tokens=*" %%f in (`"%PLINK%" -batch -ssh %USERNAME%@%IP% -pw %PASSWORD% "date -r %KOHA_BACKUP_PATH%/%LATEST_BACKUP1% +%%Y-%%m-%%d %%H" 2^>nul`) do set "FILE_DATE_HOUR=%%f"
    set "CURRENT_DATE_HOUR="
    for /f "usebackq tokens=*" %%f in (`"%PLINK%" -batch -ssh %USERNAME%@%IP% -pw %PASSWORD% "date +%%Y-%%m-%%d %%H" 2^>nul`) do set "CURRENT_DATE_HOUR=%%f"
    if not "%FILE_DATE_HOUR%"=="" if "%FILE_DATE_HOUR%"=="%CURRENT_DATE_HOUR%" (
        set "SKIP_BACKUP=1"
        echo [%date% %time%] Backup generated within last hour, will skip generation. >> "%LOG_FILE%"
    )
)

REM === Ensure PuTTY tools exist or download them (skipped in test mode) ===
if "%TEST_MODE%"=="1" (
    echo [DRYRUN] Skipping plink/pscp downloads
) else (
    if not exist "%PLINK%" (
        echo [%date% %time%] plink.exe not found. Downloading...
        powershell -Command "Invoke-WebRequest -Uri '%PLINK_URL%' -OutFile '%PLINK%'"
    )

    if not exist "%PSCP%" (
        echo [%date% %time%] pscp.exe not found. Downloading...
        powershell -Command "Invoke-WebRequest -Uri '%PSCP_URL%' -OutFile '%PSCP%'"
    )
)

REM Check downloads (unless test mode)
if "%TEST_MODE%"=="0" (
    if not exist "%PLINK%" (
        echo [%date% %time%] ERROR: plink.exe missing! Exiting.
        exit /b 1
    )
    if not exist "%PSCP%" (
        echo [%date% %time%] ERROR: pscp.exe missing! Exiting.
        exit /b 1
    )
)

REM Ensure PuTTY knows the server host key (so plink/pscp won't fail in batch mode).
call :ensure_putty_hostkey

REM Run backup command remotely (unless skipping)
echo [%date% %time%] Running koha-run-backups on remote server... >> "%LOG_FILE%"
if "%TEST_MODE%"=="1" (
    echo [DRYRUN] "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw ****** "sudo /usr/sbin/koha-run-backups %INSTANCE%" >> "%LOG_FILE%"
    set "RC=0"
) else (
    if "%SKIP_BACKUP%"=="1" (
        echo Skipping backup generation. >> "%LOG_FILE%"
        set "RC=0"
    ) else (
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /usr/sbin/koha-run-backups %INSTANCE%"
        set "RC=%ERRORLEVEL%"
    )
)
echo [%date% %time%] Backup command RC: %RC% >> "%LOG_FILE%"

if not "%RC%"=="0" (
    echo [%date% %time%] ERROR: Remote backup command failed!
    exit /b 1
)

REM Find latest backup file names (two files: SQL and files)
echo [%date% %time%] Getting latest backup filenames... >> "%LOG_FILE%"
set "TMP_LATEST=%TEMP%\koha_latest.txt"
if "%TEST_MODE%"=="1" (
    echo ils-2025-10-13.sql.gz > "%TMP_LATEST%"
    echo ils-2025-10-13.tar.gz >> "%TMP_LATEST%"
) else (
    REM Use sh -lc so the pipe to head runs on the remote side and capture stderr into the temp file for debugging
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sh -lc 'ls -t %KOHA_BACKUP_PATH% 2>&1 | head -2'" > "%TMP_LATEST%" 2>&1
    echo [%date% %time%] ls command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    if not "%ERRORLEVEL%"=="0" (
        echo [%date% %time%] Remote ls produced errors, dumping remote output for debugging: >> "%LOG_FILE%"
        type "%TMP_LATEST%" >> "%LOG_FILE%" 2>&1
    )
)

REM Read the two filenames
set /a count=0
REM Use usebackq to allow filenames or paths with spaces and to ensure the temp file is read correctly
for /f "usebackq delims=" %%f in ("%TMP_LATEST%") do (
    REM Only accept lines that contain .tar.gz or .sql.gz (case-insensitive)
    echo %%f | findstr /i "\.tar\.gz \.sql\.gz" >nul
    if !ERRORLEVEL! EQU 0 (
    set /a count+=1
    if !count! EQU 1 set "LATEST_BACKUP1=%%f"
    if !count! EQU 2 set "LATEST_BACKUP2=%%f"
    ) else (
        echo [%date% %time%] Ignoring non-backup line: %%f >> "%LOG_FILE%"
    )
)
if exist "%TMP_LATEST%" del "%TMP_LATEST%"

echo [%date% %time%] Latest backups are: %LATEST_BACKUP1% and %LATEST_BACKUP2% >> "%LOG_FILE%"

REM If we didn't find any valid backup filenames, abort to avoid acting on error text.
if "%LATEST_BACKUP1%"=="" goto :no_valid_backups


REM Download both backups
for %%b in (%LATEST_BACKUP1% %LATEST_BACKUP2%) do (
    echo [%date% %time%] Copying backup %%b to temp location... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
    echo [DRYRUN] "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw ****** "sudo cp %KOHA_BACKUP_PATH%/%%~b /tmp/%%~b && sudo chmod 644 /tmp/%%~b" >> "%LOG_FILE%"
    ) else (
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo cp %KOHA_BACKUP_PATH%/%%~b /tmp/%%~b && sudo chmod 644 /tmp/%%~b" >> "%LOG_FILE%" 2>&1
        echo [%date% %time%] cp command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    )

    echo [%date% %time%] Downloading backup %%b... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
    echo [DRYRUN] "%PSCP%" -batch -hostkey %HOST_FINGERPRINT% -pw ****** "%USERNAME%@%IP%:/tmp/%%~b" "%BACKUP_FOLDER%" >> "%LOG_FILE%"
        set "RC=0"
    ) else (
    REM Attempt pscp download with one retry via subroutine
    call :pscp_fetch "%%~b"
    set "RC=%ERRORLEVEL%"
    )

    if not "%RC%"=="0" (
        echo [%date% %time%] ERROR: Failed to download backup %%b! >> "%LOG_FILE%"
        echo [%date% %time%] ERROR: Failed to download backup %%b!
        exit /b 1
    )
)

REM List downloaded files
echo [%date% %time%] Downloaded files in %BACKUP_FOLDER%: >> "%LOG_FILE%"
dir "%BACKUP_FOLDER%" /b >> "%LOG_FILE%" 2>&1

REM Cleanup old backups - keep only RETENTION_FILES newest .tar.gz
echo [%date% %time%] Cleaning old backups (keeping %RETENTION_FILES%)... >> "%LOG_FILE%"
for /f "skip=%RETENTION_FILES% delims=" %%f in ('dir "%BACKUP_FOLDER%" /b /a-d /o-d ^| findstr /i ".tar.gz"') do (
    echo Deleting %%f >> "%LOG_FILE%"
    del "%BACKUP_FOLDER%\%%f"
)

REM Shutdown remote server (disabled when NO_SHUTDOWN=1)
if "%NO_SHUTDOWN%"=="1" (
    echo [%date% %time%] NO_SHUTDOWN flag set; skipping remote shutdown. >> "%LOG_FILE%"
) else (
    echo [%date% %time%] Shutting down server... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
        echo [DRYRUN] "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw ****** "sudo /sbin/shutdown now" >> "%LOG_FILE%"
    ) else (
        REM Actual shutdown - kept as explicit action when NO_SHUTDOWN is not set
        "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /sbin/shutdown now"
        echo [%date% %time%] Shutdown command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    )
)

echo [%date% %time%] Backup completed successfully. >> "%LOG_FILE%"
echo [%date% %time%] Backup completed successfully.

echo Done. See log at: %LOG_FILE%

goto :eof

:no_valid_backups
echo [%date% %time%] ERROR: No valid backup filenames found in remote listing. Aborting. >> "%LOG_FILE%"
echo [%date% %time%] Remote ls output (for debugging): >> "%LOG_FILE%"
if exist "%TMP_LATEST%" type "%TMP_LATEST%" >> "%LOG_FILE%" 2>&1
exit /b 1


:pscp_fetch
REM usage: call :pscp_fetch "filename"
setlocal EnableDelayedExpansion
set "FETCH_NAME=%~1"
set "ATTEMPT=1"
set "MAX_ATTEMPTS=2"
set "FETCH_RC=1"
:pscp_fetch_loop
"%PSCP%" -batch -hostkey %HOST_FINGERPRINT% -pw %PASSWORD% "%USERNAME%@%IP%:/tmp/!FETCH_NAME!" "%BACKUP_FOLDER%" >> "%LOG_FILE%" 2>&1
set "FETCH_RC=%ERRORLEVEL%"
echo [%date% %time%] pscp attempt !ATTEMPT! for !FETCH_NAME! RC: !FETCH_RC! >> "%LOG_FILE%"
if exist "%BACKUP_FOLDER%\!FETCH_NAME!" (
    echo [%date% %time%] Downloaded file exists: %BACKUP_FOLDER%\!FETCH_NAME! >> "%LOG_FILE%"
    endlocal & exit /b 0
)
if !ATTEMPT! LSS !MAX_ATTEMPTS! (
    echo [%date% %time%] WARNING: Download missing after attempt !ATTEMPT! for !FETCH_NAME!; retrying... >> "%LOG_FILE%"
    set /a ATTEMPT+=1
    timeout /t 1 >nul
    goto :pscp_fetch_loop
)

REM Final fallback: if pscp failed due to host key confirmation in batch mode, retry once with -hostkey using known fingerprint
echo [%date% %time%] WARNING: pscp failed after %MAX_ATTEMPTS% attempts for !FETCH_NAME!, attempting fallback with known host fingerprint... >> "%LOG_FILE%"
"%PSCP%" -batch -hostkey %HOST_FINGERPRINT% -pw %PASSWORD% "%USERNAME%@%IP%:/tmp/!FETCH_NAME!" "%BACKUP_FOLDER%" >> "%LOG_FILE%" 2>&1
set "FETCH_RC=%ERRORLEVEL%"
echo [%date% %time%] pscp fallback with -hostkey RC: !FETCH_RC! >> "%LOG_FILE%"
if exist "%BACKUP_FOLDER%\!FETCH_NAME!" (
    echo [%date% %time%] Downloaded file exists after fallback: %BACKUP_FOLDER%\!FETCH_NAME! >> "%LOG_FILE%"
    endlocal & exit /b 0
)

echo [%date% %time%] ERROR: Download failed after fallback for !FETCH_NAME! >> "%LOG_FILE%"
endlocal & exit /b 1


:ensure_putty_hostkey
REM Auto-discover server host fingerprint using a single verbose plink run (TOFU).
REM This will set HOST_FINGERPRINT dynamically so subsequent plink/pscp calls can use -hostkey.
REM Security: this performs Trust-On-First-Use and is vulnerable to MITM on the first run.
if "%TEST_MODE%"=="1" (
    echo [%date% %time%] Test mode - skipping hostkey discovery. >> "%LOG_FILE%"
    goto :eof
)

set "TMP_PLINK_OUT=%TEMP%\plink_fingerprint.txt"
if exist "%TMP_PLINK_OUT%" del "%TMP_PLINK_OUT%"

REM Run plink once in verbose mode and capture stderr where plink prints the server key info.
"%PLINK%" -v -ssh -batch %USERNAME%@%IP% -pw %PASSWORD% exit 2> "%TMP_PLINK_OUT%" || rem

echo [%date% %time%] Captured plink verbose output to %TMP_PLINK_OUT% >> "%LOG_FILE%"

REM Try to extract a SHA256 fingerprint line. Look for 'SHA256:...' and output that token.
for /f "usebackq tokens=1,2,3* delims= " %%A in ("%TMP_PLINK_OUT%") do (
    echo %%A %%B %%C %%D | findstr /r "SHA256:[A-Za-z0-9+/=]*" >nul
    if !ERRORLEVEL! EQU 0 (
        REM extract the SHA256:... token
        for /f "tokens=1 delims= " %%x in ('echo %%A %%B %%C %%D ^| findstr /o /r "SHA256:[A-Za-z0-9+/=]*"') do (
            REM noop: placeholder to ensure nesting behaves
        )
    )
)

REM Pure-batch extraction: scan the verbose plink output for a token starting with SHA256:
set "DISCOVERED="
for /f "usebackq delims=" %%L in ("%TMP_PLINK_OUT%") do (
    echo %%L | findstr /c:"SHA256:" >nul
    if !ERRORLEVEL! EQU 0 (
        REM Split the line into space-separated tokens and find the token that begins with SHA256:
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
echo [%date% %time%] WARNING: Could not discover host fingerprint from plink output; plink output: >> "%LOG_FILE%"
type "%TMP_PLINK_OUT%" >> "%LOG_FILE%" 2>&1
del "%TMP_PLINK_OUT%" 2>nul || rem
goto :eof
@echo off
setlocal EnableDelayedExpansion

REM NOTE: On some remote shells the pipe to 'head' (and other shell features) may not be available
REM when invoked directly via plink. To avoid empty output we run the remote commands through
REM "sh -lc '... | head -2'" and redirect stderr into the temporary file so any server-side
REM error messages are captured in the logs for easier debugging.

REM Backup-download-shutdown helper (Windows .bat)
REM Usage: backup-download-shutdown.bat [test]
REM If "test" is passed as first argument, the script will do a dry-run and will not call plink/pscp.

REM === CONFIGURATION ===
SET USERNAME=backup
SET PASSWORD=backup@12345
SET IP=10.10.10.10
SET INSTANCE=ils

REM Backup path on server depends on instance name
SET KOHA_BACKUP_PATH=/var/spool/koha/%INSTANCE%

REM === Use the script folder as the local backup folder ===
SET SCRIPT_DIR=%~dp0
SET TOOLS_DIR=%SCRIPT_DIR%tools
SET BACKUP_FOLDER=%SCRIPT_DIR%backups
SET LOG_FILE=%BACKUP_FOLDER%\backup_log.txt

REM PuTTY tools locations and download URLs
SET PLINK=%TOOLS_DIR%\plink.exe
SET PSCP=%TOOLS_DIR%\pscp.exe
SET PLINK_URL=https://the.earth.li/~sgtatham/putty/latest/w32/plink.exe
SET PSCP_URL=https://the.earth.li/~sgtatham/putty/latest/w32/pscp.exe
REM Known server fingerprint (used as a fallback if batch mode host-key confirmation fails)
SET HOST_FINGERPRINT=SHA256:zkRgpJmh+WcUyVvUonvhXTDZJVL5iIHlxDrfcY2RbQk

REM Test mode?
SET TEST_MODE=0
IF /I "%~1"=="test" (SET TEST_MODE=1)

REM Optional flags: --no-shutdown or no-shutdown will prevent the script from issuing the remote shutdown.
SET NO_SHUTDOWN=0
IF /I "%~1"=="--no-shutdown" (SET NO_SHUTDOWN=1)
IF /I "%~1"=="no-shutdown" (SET NO_SHUTDOWN=1)
IF /I "%~2"=="--no-shutdown" (SET NO_SHUTDOWN=1)
IF /I "%~2"=="no-shutdown" (SET NO_SHUTDOWN=1)

REM Create directories if they don't exist
if not exist "%TOOLS_DIR%" (
    mkdir "%TOOLS_DIR%"
)
if not exist "%BACKUP_FOLDER%" (
    mkdir "%BACKUP_FOLDER%"
)

echo [%date% %time%] === Starting Koha backup (test=%TEST_MODE%) === >> "%LOG_FILE%"
echo Current folder: %CD% >> "%LOG_FILE%"
echo Current script dir: %SCRIPT_DIR% >> "%LOG_FILE%"
echo Backup folder: %BACKUP_FOLDER% >> "%LOG_FILE%"
echo Log file: %LOG_FILE% >> "%LOG_FILE%"
echo Logging to: %LOG_FILE%

if "%TEST_MODE%"=="1" (
    echo [DRYRUN] Test mode active - no remote commands or downloads will run.
    echo [DRYRUN] Test mode active - no remote commands or downloads will run. >> "%LOG_FILE%"
)

REM Ensure PuTTY knows the server host key (so plink/pscp won't fail in batch mode).
call :ensure_putty_hostkey


REM Decide whether to skip backup generation based on latest file time (within last hour)
set "SKIP_BACKUP=0"
set "TMP_LATEST=%TEMP%\koha_latest_precheck.txt"
if "%TEST_MODE%"=="1" (
    echo ils-2025-10-13.sql.gz > "%TMP_LATEST%"
    echo ils-2025-10-13.tar.gz >> "%TMP_LATEST%"
) else (
    REM Use a shell wrapper and redirect stderr to the temp file so any remote error messages are captured.
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sh -lc 'ls -t %KOHA_BACKUP_PATH% 2>&1 | head -2'" > "%TMP_LATEST%" 2>&1
    echo [%date% %time%] ls command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    if not "%ERRORLEVEL%"=="0" (
        echo [%date% %time%] Remote ls produced errors, dumping remote output for debugging: >> "%LOG_FILE%"
        type "%TMP_LATEST%" >> "%LOG_FILE%" 2>&1
    )
)
set "LATEST_BACKUP1="
REM Pick the first valid filename that looks like a Koha backup (sql.gz or tar.gz). Ignore error text.
for /f "usebackq delims=" %%f in ("%TMP_LATEST%") do (
    echo %%f | findstr /i "\.tar\.gz \.sql\.gz" >nul
    if !ERRORLEVEL! EQU 0 (
        if not defined LATEST_BACKUP1 set "LATEST_BACKUP1=%%f"
    ) else (
        echo [%date% %time%] Ignoring non-backup line in precheck: %%f >> "%LOG_FILE%"
    )
)
if exist "%TMP_LATEST%" del "%TMP_LATEST%"
if not "%TEST_MODE%"=="1" if defined LATEST_BACKUP1 (
    set "FILE_DATE_HOUR="
    for /f "usebackq tokens=*" %%f in (`"%PLINK%" -batch -ssh %USERNAME%@%IP% -pw %PASSWORD% "date -r %KOHA_BACKUP_PATH%/%LATEST_BACKUP1% +%%Y-%%m-%%d %%H" 2^>nul`) do set "FILE_DATE_HOUR=%%f"
    set "CURRENT_DATE_HOUR="
    for /f "usebackq tokens=*" %%f in (`"%PLINK%" -batch -ssh %USERNAME%@%IP% -pw %PASSWORD% "date +%%Y-%%m-%%d %%H" 2^>nul`) do set "CURRENT_DATE_HOUR=%%f"
    if not "%FILE_DATE_HOUR%"=="" if "%FILE_DATE_HOUR%"=="%CURRENT_DATE_HOUR%" (
        set "SKIP_BACKUP=1"
        echo [%date% %time%] Backup generated within last hour, will skip generation. >> "%LOG_FILE%"
    )
)

REM === Ensure PuTTY tools exist or download them (skipped in test mode) ===
if "%TEST_MODE%"=="1" (
    echo [DRYRUN] Skipping plink/pscp downloads
) else (
    if not exist "%PLINK%" (
        echo [%date% %time%] plink.exe not found. Downloading...
        powershell -Command "Invoke-WebRequest -Uri '%PLINK_URL%' -OutFile '%PLINK%'"
    )

    if not exist "%PSCP%" (
        echo [%date% %time%] pscp.exe not found. Downloading...
        powershell -Command "Invoke-WebRequest -Uri '%PSCP_URL%' -OutFile '%PSCP%'"
    )
)

REM Check downloads (unless test mode)
if "%TEST_MODE%"=="0" (
    if not exist "%PLINK%" (
        echo [%date% %time%] ERROR: plink.exe missing! Exiting.
        exit /b 1
    )
    if not exist "%PSCP%" (
        echo [%date% %time%] ERROR: pscp.exe missing! Exiting.
        exit /b 1
    )
)

REM Run backup command remotely (unless skipping)
echo [%date% %time%] Running koha-run-backups on remote server... >> "%LOG_FILE%"
if "%TEST_MODE%"=="1" (
    echo [DRYRUN] "%PLINK%" -batch -ssh -hostkey SHA256:eF2VUBsQv1DBooGjJOHW86BblmE/cC49NOKIaNLMFWA %USERNAME%@%IP% -pw ****** "sudo /usr/sbin/koha-run-backups %INSTANCE%" >> "%LOG_FILE%"
    set "RC=0"
) else (
    if "%SKIP_BACKUP%"=="1" (
        echo Skipping backup generation. >> "%LOG_FILE%"
        set "RC=0"
    ) else (
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /usr/sbin/koha-run-backups %INSTANCE%"
        set "RC=%ERRORLEVEL%"
    )
)
echo [%date% %time%] Backup command RC: %RC% >> "%LOG_FILE%"

if not "%RC%"=="0" (
    echo [%date% %time%] ERROR: Remote backup command failed!
    exit /b 1
)

REM Find latest backup file names (two files: SQL and files)
echo [%date% %time%] Getting latest backup filenames... >> "%LOG_FILE%"
set "TMP_LATEST=%TEMP%\koha_latest.txt"
if "%TEST_MODE%"=="1" (
    echo ils-2025-10-13.sql.gz > "%TMP_LATEST%"
    echo ils-2025-10-13.tar.gz >> "%TMP_LATEST%"
) else (
    REM Use sh -lc so the pipe to head runs on the remote side and capture stderr into the temp file for debugging
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sh -lc 'ls -t %KOHA_BACKUP_PATH% 2>&1 | head -2'" > "%TMP_LATEST%" 2>&1
    echo [%date% %time%] ls command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    if not "%ERRORLEVEL%"=="0" (
        echo [%date% %time%] Remote ls produced errors, dumping remote output for debugging: >> "%LOG_FILE%"
        type "%TMP_LATEST%" >> "%LOG_FILE%" 2>&1
    )
)

REM Read the two filenames
set /a count=0
REM Use usebackq to allow filenames or paths with spaces and to ensure the temp file is read correctly
for /f "usebackq delims=" %%f in ("%TMP_LATEST%") do (
    REM Only accept lines that contain .tar.gz or .sql.gz (case-insensitive)
    echo %%f | findstr /i "\.tar\.gz \.sql\.gz" >nul
    if !ERRORLEVEL! EQU 0 (
    set /a count+=1
    if !count! EQU 1 set "LATEST_BACKUP1=%%f"
    if !count! EQU 2 set "LATEST_BACKUP2=%%f"
    ) else (
        echo [%date% %time%] Ignoring non-backup line: %%f >> "%LOG_FILE%"
    )
)
if exist "%TMP_LATEST%" del "%TMP_LATEST%"

echo [%date% %time%] Latest backups are: %LATEST_BACKUP1% and %LATEST_BACKUP2% >> "%LOG_FILE%"

REM If we didn't find any valid backup filenames, abort to avoid acting on error text.
if "%LATEST_BACKUP1%"=="" goto :no_valid_backups


REM Download both backups
for %%b in (%LATEST_BACKUP1% %LATEST_BACKUP2%) do (
    echo [%date% %time%] Copying backup %%b to temp location... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
    echo [DRYRUN] "%PLINK%" -batch -ssh -hostkey SHA256:eF2VUBsQv1DBooGjJOHW86BblmE/cC49NOKIaNLMFWA %USERNAME%@%IP% -pw ****** "sudo cp %KOHA_BACKUP_PATH%/%%~b /tmp/%%~b && sudo chmod 644 /tmp/%%~b" >> "%LOG_FILE%"
    ) else (
    "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo cp %KOHA_BACKUP_PATH%/%%~b /tmp/%%~b && sudo chmod 644 /tmp/%%~b" >> "%LOG_FILE%" 2>&1
        echo [%date% %time%] cp command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    )

    echo [%date% %time%] Downloading backup %%b... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
    echo [DRYRUN] "%PSCP%" -batch -hostkey SHA256:eF2VUBsQv1DBooGjJOHW86BblmE/cC49NOKIaNLMFWA -pw ****** "%USERNAME%@%IP%:/tmp/%%~b" "%BACKUP_FOLDER%" >> "%LOG_FILE%"
        set "RC=0"
    ) else (
    REM Attempt pscp download with one retry via subroutine
    call :pscp_fetch "%%~b"
    set "RC=%ERRORLEVEL%"
    )

    if not "%RC%"=="0" (
        echo [%date% %time%] ERROR: Failed to download backup %%b! >> "%LOG_FILE%"
        echo [%date% %time%] ERROR: Failed to download backup %%b!
        exit /b 1
    )
)

REM List downloaded files
echo [%date% %time%] Downloaded files in %BACKUP_FOLDER%: >> "%LOG_FILE%"
dir "%BACKUP_FOLDER%" /b >> "%LOG_FILE%" 2>&1

REM Cleanup old backups - keep only 30 newest
echo [%date% %time%] Cleaning old backups... >> "%LOG_FILE%"
for /f "skip=30 delims=" %%f in ('dir "%BACKUP_FOLDER%" /b /a-d /o-d ^| findstr /i ".tar.gz"') do (
    echo Deleting %%f >> "%LOG_FILE%"
    del "%BACKUP_FOLDER%\%%f"
)

REM Shutdown remote server (disabled when NO_SHUTDOWN=1)
if "%NO_SHUTDOWN%"=="1" (
    echo [%date% %time%] NO_SHUTDOWN flag set; skipping remote shutdown. >> "%LOG_FILE%"
) else (
    echo [%date% %time%] Shutting down server... >> "%LOG_FILE%"
    if "%TEST_MODE%"=="1" (
        echo [DRYRUN] "%PLINK%" -batch -ssh -hostkey SHA256:eF2VUBsQv1DBooGjJOHW86BblmE/cC49NOKIaNLMFWA %USERNAME%@%IP% -pw ****** "sudo /sbin/shutdown now" >> "%LOG_FILE%"
    ) else (
        REM Actual shutdown - kept as explicit action when NO_SHUTDOWN is not set
        "%PLINK%" -batch -ssh -hostkey %HOST_FINGERPRINT% %USERNAME%@%IP% -pw %PASSWORD% "sudo /sbin/shutdown now"
        echo [%date% %time%] Shutdown command RC: %ERRORLEVEL% >> "%LOG_FILE%"
    )
)

echo [%date% %time%] Backup completed successfully. >> "%LOG_FILE%"
echo [%date% %time%] Backup completed successfully.

echo Done. See log at: %LOG_FILE%

goto :eof

:no_valid_backups
echo [%date% %time%] ERROR: No valid backup filenames found in remote listing. Aborting. >> "%LOG_FILE%"
echo [%date% %time%] Remote ls output (for debugging): >> "%LOG_FILE%"
if exist "%TMP_LATEST%" type "%TMP_LATEST%" >> "%LOG_FILE%" 2>&1
exit /b 1


:pscp_fetch
REM usage: call :pscp_fetch "filename"
setlocal EnableDelayedExpansion
set "FETCH_NAME=%~1"
set "ATTEMPT=1"
set "MAX_ATTEMPTS=2"
set "FETCH_RC=1"
:pscp_fetch_loop
"%PSCP%" -batch -hostkey %HOST_FINGERPRINT% -pw %PASSWORD% "%USERNAME%@%IP%:/tmp/!FETCH_NAME!" "%BACKUP_FOLDER%" >> "%LOG_FILE%" 2>&1
set "FETCH_RC=%ERRORLEVEL%"
echo [%date% %time%] pscp attempt !ATTEMPT! for !FETCH_NAME! RC: !FETCH_RC! >> "%LOG_FILE%"
if exist "%BACKUP_FOLDER%\!FETCH_NAME!" (
    echo [%date% %time%] Downloaded file exists: %BACKUP_FOLDER%\!FETCH_NAME! >> "%LOG_FILE%"
    endlocal & exit /b 0
)
if !ATTEMPT! LSS !MAX_ATTEMPTS! (
    echo [%date% %time%] WARNING: Download missing after attempt !ATTEMPT! for !FETCH_NAME!; retrying... >> "%LOG_FILE%"
    set /a ATTEMPT+=1
    timeout /t 1 >nul
    goto :pscp_fetch_loop
)

REM Final fallback: if pscp failed due to host key confirmation in batch mode, retry once with -hostkey using known fingerprint
echo [%date% %time%] WARNING: pscp failed after %MAX_ATTEMPTS% attempts for !FETCH_NAME!, attempting fallback with known host fingerprint... >> "%LOG_FILE%"
"%PSCP%" -batch -hostkey %HOST_FINGERPRINT% -pw %PASSWORD% "%USERNAME%@%IP%:/tmp/!FETCH_NAME!" "%BACKUP_FOLDER%" >> "%LOG_FILE%" 2>&1
set "FETCH_RC=%ERRORLEVEL%"
echo [%date% %time%] pscp fallback with -hostkey RC: !FETCH_RC! >> "%LOG_FILE%"
if exist "%BACKUP_FOLDER%\!FETCH_NAME!" (
    echo [%date% %time%] Downloaded file exists after fallback: %BACKUP_FOLDER%\!FETCH_NAME! >> "%LOG_FILE%"
    endlocal & exit /b 0
)

echo [%date% %time%] ERROR: Download failed after fallback for !FETCH_NAME! >> "%LOG_FILE%"
endlocal & exit /b 1


:ensure_putty_hostkey
REM Auto-discover server host fingerprint using a single verbose plink run (TOFU).
REM This will set HOST_FINGERPRINT dynamically so subsequent plink/pscp calls can use -hostkey.
REM Security: this performs Trust-On-First-Use and is vulnerable to MITM on the first run.
if "%TEST_MODE%"=="1" (
    echo [%date% %time%] Test mode - skipping hostkey discovery. >> "%LOG_FILE%"
    goto :eof
)

set "TMP_PLINK_OUT=%TEMP%\plink_fingerprint.txt"
if exist "%TMP_PLINK_OUT%" del "%TMP_PLINK_OUT%"

REM Run plink once in verbose mode and capture stderr where plink prints the server key info.
"%PLINK%" -v -ssh -batch %USERNAME%@%IP% -pw %PASSWORD% exit 2> "%TMP_PLINK_OUT%" || rem

echo [%date% %time%] Captured plink verbose output to %TMP_PLINK_OUT% >> "%LOG_FILE%"

REM Try to extract a SHA256 fingerprint line. Look for 'SHA256:...' and output that token.
for /f "usebackq tokens=1,2,3* delims= " %%A in ("%TMP_PLINK_OUT%") do (
    echo %%A %%B %%C %%D | findstr /r "SHA256:[A-Za-z0-9+/=]*" >nul
    if !ERRORLEVEL! EQU 0 (
        REM extract the SHA256:... token
        for /f "tokens=1 delims= " %%x in ('echo %%A %%B %%C %%D ^| findstr /o /r "SHA256:[A-Za-z0-9+/=]*"') do (
            REM noop: placeholder to ensure nesting behaves
        )
    )
)

REM Pure-batch extraction: scan the verbose plink output for a token starting with SHA256:
set "DISCOVERED="
for /f "usebackq delims=" %%L in ("%TMP_PLINK_OUT%") do (
    echo %%L | findstr /c:"SHA256:" >nul
    if !ERRORLEVEL! EQU 0 (
        REM Split the line into space-separated tokens and find the token that begins with SHA256:
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
echo [%date% %time%] WARNING: Could not discover host fingerprint from plink output; plink output: >> "%LOG_FILE%"
type "%TMP_PLINK_OUT%" >> "%LOG_FILE%" 2>&1
del "%TMP_PLINK_OUT%" 2>nul || rem
goto :eof


