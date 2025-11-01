@echo off
REM Launcher for multi-instance backup WITH server shutdown
call "%~dp0with-shutdown\backup-all-instances.bat" %*
