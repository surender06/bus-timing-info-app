@echo off
cd /d "%~dp0"
start "Bus Backend" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
timeout /t 2 >nul
start http://localhost:4173/
