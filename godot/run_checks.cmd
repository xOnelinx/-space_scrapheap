@echo off
rem Политика PowerShell по умолчанию не пускает .ps1. Обход только для этого прогона.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_checks.ps1"
exit /b %ERRORLEVEL%
