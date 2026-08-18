@echo off
setlocal EnableExtensions
REM Instala a API FieldPec Online (chama o PowerShell).
REM Uso (CMD):
REM   cd /d C:\ApiFieldTratoAndroid
REM   deploy\windows\Install-Api.cmd 3111 "postgres://fieldpec:SENHA@127.0.0.1:5432/fieldpec_online" "TOKEN_FORTE"

set "ROOT=%~dp0..\.."
pushd "%ROOT%" >nul

set "PORT=%~1"
if "%PORT%"=="" set "PORT=3001"

set "DBURL=%~2"
if "%DBURL%"=="" set "DBURL=postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online"

set "TOKEN=%~3"
if "%TOKEN%"=="" set "TOKEN=open"

echo Instalando API...
echo   Pasta: %CD%
echo   Porta: %PORT%

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Api.ps1" -InstallDir "%CD%" -Port %PORT% -DatabaseUrl "%DBURL%" -AdminToken "%TOKEN%"
set "ERR=%ERRORLEVEL%"
popd >nul
exit /b %ERR%
