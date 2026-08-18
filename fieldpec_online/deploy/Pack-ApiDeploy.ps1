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
robocopy $apiDir $stageApi /E /XD node_modules /XF .env /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falhou ao copiar api (exit $LASTEXITCODE)" }

# SQL + scripts de deploy
Copy-Item -Recurse $sqlDir (Join-Path $stage "sql")
New-Item -ItemType Directory -Force -Path (Join-Path $stage "deploy") | Out-Null
Copy-Item -Recurse $deployWin (Join-Path $stage "deploy\windows")
Copy-Item -Recurse $deployLinux (Join-Path $stage "deploy\linux")
$deployDoc = Join-Path $root "DEPLOY_API.md"
if (Test-Path $deployDoc) {
  Copy-Item $deployDoc (Join-Path $stage "DEPLOY_API.md")
}

# README curto no pacote
@"
FieldPec Online API — pacote de deploy
=====================================

1. Extraia este ZIP no servidor (ex.: C:\FieldPecOnline ou /opt/fieldpec-online)
2. Windows:  deploy\windows\Install-Api.ps1
3. Linux:    bash deploy/linux/install-api.sh
4. Edite api\.env (DATABASE_URL, ADMIN_TOKEN, PORT)
5. Inicie o servico / processo

Guia completo: DEPLOY_API.md
"@ | Set-Content -Path (Join-Path $stage "LEIA-ME.txt") -Encoding UTF8

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
Remove-Item $stage -Recurse -Force

Write-Host "Pacote gerado:" -ForegroundColor Green
Write-Host "  $zipPath"
Write-Host "Envie este ZIP ao servidor e siga DEPLOY_API.md / LEIA-ME.txt"
