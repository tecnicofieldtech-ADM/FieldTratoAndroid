@echo off
chcp 65001 >nul
cd /d "%~dp0"

where node >nul 2>&1
if errorlevel 1 (
  echo Instale o Node.js LTS em https://nodejs.org e rode este arquivo de novo.
  pause
  exit /b 1
)

echo.
echo  Simulador PTM AV40/AV50 - FieldTrato
echo  Painel no navegador:  http://localhost:8787
echo  TCP da balanca:       porta 8899
echo  Deixe esta janela aberta enquanto o tablet estiver conectado.
echo.
node server.mjs
echo.
pause
