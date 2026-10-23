#Requires -Version 5.1
<#
.SYNOPSIS
  Prepara arquivos e compila o instalador .exe com Inno Setup 6.

.EXAMPLE
  .\Pack-ConnectorSetup.ps1
  # Gera: fieldpec_online\dist\FieldPec-Conector-Setup-1.0.0.exe
#>
[CmdletBinding()]
param(
  [string]$OutDir = "",
  [string]$Version = "1.0.0",
  [string]$IsccPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
$connDir = Join-Path $root "connector"
$deployConn = Join-Path $scriptDir "connector"
$iss = Join-Path $deployConn "FieldPecConnector.iss"
$staging = Join-Path $deployConn "staging"

if (-not $OutDir) { $OutDir = Join-Path $root "dist" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $IsccPath) {
  foreach ($c in @(
      "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
      "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )) {
    if (Test-Path $c) { $IsccPath = $c; break }
  }
}
if (-not $IsccPath -or -not (Test-Path $IsccPath)) {
  throw "Inno Setup 6 (ISCC.exe) nao encontrado. Instale: https://jrsoftware.org/isinfo.php"
}

Write-Host "Limpando staging..." -ForegroundColor Cyan
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

Write-Host "Copiando connector..." -ForegroundColor Cyan
robocopy $connDir (Join-Path $staging "connector") /E /XD node_modules /XF .env sync-log.txt *.zip /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy connector falhou" }

Write-Host "Copiando scripts de instalacao..." -ForegroundColor Cyan
$stageDeploy = Join-Path $staging "deploy\connector"
New-Item -ItemType Directory -Force -Path $stageDeploy | Out-Null
Copy-Item (Join-Path $deployConn "PostInstall-Connector.ps1") $stageDeploy -Force
Copy-Item (Join-Path $deployConn "Uninstall-Connector.ps1") $stageDeploy -Force
Copy-Item (Join-Path $deployConn "Install-Connector.ps1") $stageDeploy -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $staging "deploy\windows") | Out-Null
Copy-Item (Join-Path $scriptDir "windows\Find-Node.ps1") (Join-Path $staging "deploy\windows\Find-Node.ps1") -Force

# NSSM
$nssmDest = Join-Path $staging "tools\nssm\win64"
New-Item -ItemType Directory -Force -Path $nssmDest | Out-Null
$localNssm = Join-Path $root "tools\nssm\win64\nssm.exe"
if (-not (Test-Path $localNssm)) {
  Write-Host "Baixando NSSM..." -ForegroundColor Cyan
  $tmp = Join-Path $env:TEMP ("nssm-setup-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zipN = Join-Path $tmp "nssm.zip"
  Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $zipN -UseBasicParsing -TimeoutSec 120
  Expand-Archive -Path $zipN -DestinationPath $tmp -Force
  $exe = Get-ChildItem -Path $tmp -Recurse -Filter "nssm.exe" |
    Where-Object { $_.FullName -match '\\win64\\nssm\.exe$' } |
    Select-Object -First 1
  if (-not $exe) { throw "nssm.exe nao encontrado" }
  $cache = Join-Path $root "tools\nssm\win64"
  New-Item -ItemType Directory -Force -Path $cache | Out-Null
  Copy-Item $exe.FullName (Join-Path $cache "nssm.exe") -Force
  $localNssm = Join-Path $cache "nssm.exe"
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Copy-Item $localNssm $nssmDest -Force

# Abrir-Painel placeholder (PostInstall sobrescreve se precisar)
Set-Content -Path (Join-Path $staging "Abrir-Painel.cmd") -Value "@echo off`r`nstart http://127.0.0.1:3080/`r`n" -Encoding ASCII

Copy-Item (Join-Path $connDir "DEPLOY_CONECTOR.md") (Join-Path $staging "DEPLOY_CONECTOR.md") -Force -ErrorAction SilentlyContinue

# Atualiza versao no .iss
$issText = Get-Content $iss -Raw
$issText = [regex]::Replace($issText, '#define MyAppVersion "[^"]*"', "#define MyAppVersion `"$Version`"")
Set-Content -Path $iss -Value $issText -Encoding UTF8

Write-Host "Compilando Inno Setup..." -ForegroundColor Cyan
Write-Host "  ISCC: $IsccPath"
& $IsccPath $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC falhou com codigo $LASTEXITCODE" }

$exeOut = Join-Path $OutDir "FieldPec-Conector-Setup-$Version.exe"
if (-not (Test-Path $exeOut)) {
  # Inno OutputDir relativo ao .iss = deploy/connector/../../dist
  $alt = Get-ChildItem $OutDir -Filter "FieldPec-Conector-Setup-*.exe" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($alt) { $exeOut = $alt.FullName }
}

Write-Host ""
Write-Host "Instalador gerado:" -ForegroundColor Green
Write-Host "  $exeOut"
Write-Host "Distribua este .exe ao cliente (Executar como administrador)."
