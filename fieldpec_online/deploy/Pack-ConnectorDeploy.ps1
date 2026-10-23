#Requires -Version 5.1
<#
.SYNOPSIS
  Empacota o conector FieldPec Online + instalador Windows (servico NSSM).

.EXAMPLE
  .\Pack-ConnectorDeploy.ps1
  # Gera: fieldpec_online\dist\fieldpec-online-connector-YYYYMMDD-HHMM.zip
#>
[CmdletBinding()]
param([string]$OutDir = "")

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
$connDir = Join-Path $root "connector"
$deployConn = Join-Path $scriptDir "connector"
$findNode = Join-Path $scriptDir "windows\Find-Node.ps1"

if (-not $OutDir) { $OutDir = Join-Path $root "dist" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$zipPath = Join-Path $OutDir "fieldpec-online-connector-$stamp.zip"
$stage = Join-Path $env:TEMP "fieldpec-conn-pack-$stamp"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Host "Copiando connector..." -ForegroundColor Cyan
robocopy $connDir (Join-Path $stage "connector") /E /XD node_modules /XF .env sync-log.txt /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy connector falhou" }

Write-Host "Copiando instalador..." -ForegroundColor Cyan
$stageDeploy = Join-Path $stage "deploy\connector"
New-Item -ItemType Directory -Force -Path $stageDeploy | Out-Null
Copy-Item (Join-Path $deployConn "Install-Connector.ps1") $stageDeploy -Force
Copy-Item (Join-Path $deployConn "Uninstall-Connector.ps1") $stageDeploy -Force
Copy-Item (Join-Path $deployConn "Install-Connector.cmd") $stageDeploy -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stage "deploy\windows") | Out-Null
Copy-Item $findNode (Join-Path $stage "deploy\windows\Find-Node.ps1") -Force

# NSSM embutido
$nssmDest = Join-Path $stage "tools\nssm\win64"
New-Item -ItemType Directory -Force -Path $nssmDest | Out-Null
$localNssm = Join-Path $root "tools\nssm\win64\nssm.exe"
if (Test-Path $localNssm) {
  Copy-Item $localNssm $nssmDest -Force
  Write-Host "NSSM local copiado." -ForegroundColor DarkGreen
}
else {
  Write-Host "Baixando NSSM 2.24..." -ForegroundColor Cyan
  $tmp = Join-Path $env:TEMP ("nssm-pack-" + $stamp)
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zipN = Join-Path $tmp "nssm.zip"
  $ok = $false
  foreach ($u in @(
      "https://nssm.cc/release/nssm-2.24.zip",
      "https://github.com/nssm/nssm/releases/download/v2.24/nssm-2.24.zip"
    )) {
    try {
      Invoke-WebRequest -Uri $u -OutFile $zipN -UseBasicParsing -TimeoutSec 120
      $ok = $true
      break
    }
    catch {
      Write-Host ("  " + $u + " falhou") -ForegroundColor DarkYellow
    }
  }
  if ($ok) {
    Expand-Archive -Path $zipN -DestinationPath $tmp -Force
    $exe = Get-ChildItem -Path $tmp -Recurse -Filter "nssm.exe" |
      Where-Object { $_.FullName -match '\\win64\\nssm\.exe$' } |
      Select-Object -First 1
    if ($exe) {
      Copy-Item $exe.FullName (Join-Path $nssmDest "nssm.exe") -Force
      $cache = Join-Path $root "tools\nssm\win64"
      New-Item -ItemType Directory -Force -Path $cache | Out-Null
      Copy-Item $exe.FullName (Join-Path $cache "nssm.exe") -Force
      Write-Host "NSSM embutido no pacote." -ForegroundColor DarkGreen
    }
    else {
      Write-Host "AVISO: nssm.exe nao encontrado no ZIP - instalador tentara baixar na hora." -ForegroundColor Yellow
    }
  }
  else {
    Write-Host "AVISO: nao foi possivel baixar NSSM agora - instalador tentara baixar na hora." -ForegroundColor Yellow
  }
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Copy-Item (Join-Path $root "DEPLOY_CONECTOR.md") (Join-Path $stage "DEPLOY_CONECTOR.md") -ErrorAction SilentlyContinue
Copy-Item (Join-Path $connDir "DEPLOY_CONECTOR.md") (Join-Path $stage "DEPLOY_CONECTOR.md") -Force -ErrorAction SilentlyContinue

$installCmd = @"
@echo off
cd /d "%~dp0"
echo Instalando Conector FieldPec Online (Administrador)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\connector\Install-Connector.ps1"
if errorlevel 1 pause
"@
Set-Content -Path (Join-Path $stage "INSTALAR.cmd") -Value $installCmd -Encoding ASCII

$leia = @"
FieldPec Online - Conector (cliente)
====================================

INSTALACAO (recomendada)
1. Extraia este ZIP em qualquer pasta temporaria
2. Clique com o botao direito em INSTALAR.cmd -> Executar como administrador
   (ou abra deploy\connector\Install-Connector.cmd)
3. O instalador:
   - copia para C:\FieldPecConnector
   - instala Node.js se necessario
   - roda npm install
   - registra o servico Windows "FieldPecOnlineConnector"
   - inicia o servico e abre http://127.0.0.1:3080

APOS INSTALAR
1. No painel web: Configuracao
2. Informe CLOUD_API_URL, CLIENT_CODE e caminho do FB_DATABASE (.FDB)
3. REPLAY_TO_LOCAL = 1 para gravar fabricacao/fornecimento no Field
4. Salvar

DESINSTALAR
  deploy\connector\Uninstall-Connector.ps1
  (ou atalho no Menu Iniciar)

Guia: DEPLOY_CONECTOR.md
"@
Set-Content -Path (Join-Path $stage "LEIA-ME.txt") -Value $leia -Encoding UTF8

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
Remove-Item $stage -Recurse -Force
Write-Host ""
Write-Host "Pacote gerado:" -ForegroundColor Green
Write-Host "  $zipPath"
Write-Host "Envie o ZIP ao cliente e peca para executar INSTALAR.cmd como Administrador."
