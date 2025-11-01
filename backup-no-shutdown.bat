@echo off
REM Launcher for multi-instance backup WITHOUT server shutdown
call "%~dp0no-shutdown\backup-all-instances-no-shutdown.bat" %*
