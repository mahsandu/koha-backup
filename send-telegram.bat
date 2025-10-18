@echo off

REM Separate Telegram sender script
REM Usage: send-telegram.bat "message to send"

REM Telegram config - set these or pass as environment variables
if "%TELEGRAM_BOT_TOKEN%"=="" set TELEGRAM_BOT_TOKEN=8446194682:AAFd1ZG8ww8UUh-GivzIG2fuKnINOlg05NA
if "%TELEGRAM_CHAT_ID%"=="" set TELEGRAM_CHAT_ID=6614159660

if "%~1"=="" (
    echo Usage: %0 "message to send"
    exit /b 1
)

REM Use PowerShell to send the message
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "param([string]$m); $token='%TELEGRAM_BOT_TOKEN%'; $chatId='%TELEGRAM_CHAT_ID%'; try { Invoke-RestMethod -Uri ('https://api.telegram.org/bot'+$token+'/sendMessage') -Method Post -Body @{ chat_id=$chatId; text=$m } } catch { Write-Host 'Telegram send failed:' $_.Exception.Message }" -ArgumentList "%~1" >nul 2>&1

exit /b 0