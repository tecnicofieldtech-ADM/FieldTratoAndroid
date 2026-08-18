@echo off
setlocal EnableExtensions
REM Inicia a API no console (Ctrl+C para parar).
REM Uso (CMD):
REM   cd /d C:\ApiFieldTratoAndroid
REM   deploy\windows\Start-Api.cmd

set "ROOT=%~dp0..\.."
pushd "%ROOT%" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Api.ps1" -InstallDir "%CD%"
set "ERR=%ERRORLEVEL%"
popd >nul
exit /b %ERR%
