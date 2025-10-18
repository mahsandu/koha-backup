@echo off
setlocal EnableDelayedExpansion

REM Koha backup and download helper (no shutdown)
REM Usage: backup-download-no-shutdown.bat [test]
REM Notes:
REM  - "test": runs a dry-run; remote commands and downloads are NOT executed
REM This script logs to backups\backup_log.txt and never issues a remote shutdown.

REM Force no shutdown behavior
SET NO_SHUTDOWN=1

REM Reuse the main script by calling it with test flag if present
if /I "%~1"=="test" (
  call "%~dp0backup-download-shutdown.bat" test --no-shutdown
) else (
  call "%~dp0backup-download-shutdown.bat" --no-shutdown
)

exit /b %ERRORLEVEL%
