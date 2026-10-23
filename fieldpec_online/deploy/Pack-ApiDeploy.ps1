#Requires -Version 5.1
<#
.SYNOPSIS
  Empacota a API FieldPec Online para enviar ao servidor (zip).

.EXAMPLE
  .\Pack-ApiDeploy.ps1
  # Gera: fieldpec_online\dist\fieldpec-online-api-YYYYMMDD.zip
#>
[CmdletBinding()]
param(
  [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
$apiDir = Join-Path $root "api"
$sqlDir = Join-Path $root "sql"
$deployWin = Join-Path $scriptDir "windows"
$deployLinux = Join-Path $scriptDir "linux"

if (-not $OutDir) {
  $OutDir = Join-Path $root "dist"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$zipName = "fieldpec-online-api-$stamp.zip"
$zipPath = Join-Path $OutDir $zipName
$stage = Join-Path $env:TEMP "fieldpec-api-pack-$stamp"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# Copia API (sem node_modules e sem .env)
$stageApi = Join-Path $stage "api"
New-Item -ItemType Directory -Force -Path $stageApi | Out-Null
robocopy $apiDir $stageApi /E /XD node_modules test scripts /XF .env /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falhou ao copiar api (exit $LASTEXITCODE)" }

# SQL + scripts de deploy + criacao do banco
Copy-Item -Recurse $sqlDir (Join-Path $stage "sql")
New-Item -ItemType Directory -Force -Path (Join-Path $stage "deploy") | Out-Null
Copy-Item -Recurse $deployWin (Join-Path $stage "deploy\windows")
Copy-Item -Recurse $deployLinux (Join-Path $stage "deploy\linux")

$scriptsSrc = Join-Path $root "scripts"
$stageScripts = Join-Path $stage "scripts"
New-Item -ItemType Directory -Force -Path $stageScripts | Out-Null
Copy-Item (Join-Path $scriptsSrc "Create-Database.ps1") $stageScripts
Copy-Item (Join-Path $scriptsSrc "create-database.sh") $stageScripts

$deployDoc = Join-Path $root "DEPLOY_API.md"
if (Test-Path $deployDoc) {
  Copy-Item $deployDoc (Join-Path $stage "DEPLOY_API.md")
}

$manualPlanilha = Join-Path (Split-Path -Parent $root) "docs\MANUAL_MODO_PLANILHA.md"
if (Test-Path $manualPlanilha) {
  Copy-Item $manualPlanilha (Join-Path $stage "MANUAL_MODO_PLANILHA.md")
}

# README curto no pacote
@"
FieldPec Online API — pacote de deploy (modo Planilha)
=====================================================

O cliente precisa ter instalado ANTES (nao vai neste ZIP):
  - PostgreSQL 14+
  - Node.js 18+  (https://nodejs.org)
  - Liberar a porta da API no firewall (ex. 3111 ou 3001)

1. Extraia este ZIP no servidor (ex.: C:\ApiFieldTratoAndroid)
2. Crie o banco (PowerShell, com senha do superuser postgres):
     `$env:PGPASSWORD = 'SENHA_POSTGRES'`
     .\scripts\Create-Database.ps1
3. Instale e suba a API (CMD):
     deploy\windows\Install-Api.cmd 3111 "postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online" "TOKEN_FORTE"
     deploy\windows\Start-Api.cmd
4. Abra o painel: http://IP:3111/admin/ui/
5. Cadastre o cliente (licenca), importe a planilha, aponte o tablet.

NAO envie o conector neste modo — o FieldTrato usa Backend = Planilha.

Guia de instalacao da API: DEPLOY_API.md
Manual do modo Planilha:   MANUAL_MODO_PLANILHA.md
"@ | Set-Content -Path (Join-Path $stage "LEIA-ME.txt") -Encoding UTF8

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
Remove-Item $stage -Recurse -Force

Write-Host "Pacote gerado:" -ForegroundColor Green
Write-Host "  $zipPath"
Write-Host "Envie este ZIP ao servidor e siga DEPLOY_API.md / LEIA-ME.txt"
