@echo off
REM Instalador do Conector FieldPec Online (eleva para Administrador)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Connector.ps1" %*
if errorlevel 1 pause
