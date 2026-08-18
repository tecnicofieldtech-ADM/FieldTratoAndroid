#Requires -Version 5.1
<#
.SYNOPSIS
  Atualiza a API no servidor a partir de um ZIP novo (sem apagar .env).

.EXAMPLE
  .\Update-Api.ps1 -ZipPath C:\Temp\fieldpec-online-api-20260806-1304.zip
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ZipPath,
  [string]$InstallDir = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $InstallDir) {
  $InstallDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

if (-not (Test-Path $ZipPath)) { throw "ZIP nao encontrado: $ZipPath" }
if (-not (Test-Path (Join-Path $InstallDir "api"))) {
  throw "InstallDir invalido (sem pasta api): $InstallDir"
}

$stage = Join-Path $env:TEMP ("fieldpec-update-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $stage | Out-Null

try {
  Expand-Archive -Path $ZipPath -DestinationPath $stage -Force

  $srcApi = Join-Path $stage "api"
  if (-not (Test-Path $srcApi)) {
    # ZIP pode ter uma pasta raiz extra
    $inner = Get-ChildItem $stage -Directory | Select-Object -First 1
    if ($inner) { $srcApi = Join-Path $inner.FullName "api" }
  }
  if (-not (Test-Path $srcApi)) { throw "ZIP sem pasta api/" }

  $dstApi = Join-Path $InstallDir "api"
  $envBackup = Join-Path $dstApi ".env"

  Write-Host "Parando processos node da API (se houver)..." -ForegroundColor Yellow
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "ApiFieldTratoAndroid|fieldpec-online|src\\index\.js|src/index\.js" } |
    ForEach-Object {
      Write-Host "  kill PID $($_.ProcessId)"
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

  # Preserva .env
  $tmpEnv = $null
  if (Test-Path $envBackup) {
    $tmpEnv = Join-Path $env:TEMP "fieldpec-env-backup.env"
    Copy-Item $envBackup $tmpEnv -Force
  }

  Write-Host "Copiando api/ (exceto node_modules)..." -ForegroundColor Cyan
  robocopy $srcApi $dstApi /E /XD node_modules /XF .env /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy falhou: $LASTEXITCODE" }

  if ($tmpEnv) {
    Copy-Item $tmpEnv $envBackup -Force
    Remove-Item $tmpEnv -Force -ErrorAction SilentlyContinue
  }

  # sql + deploy scripts
  foreach ($name in @("sql", "deploy")) {
    $s = Join-Path $stage $name
    if (-not (Test-Path $s)) {
      $inner = Get-ChildItem $stage -Directory | Select-Object -First 1
      if ($inner) { $s = Join-Path $inner.FullName $name }
    }
    if (Test-Path $s) {
      $d = Join-Path $InstallDir $name
      robocopy $s $d /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    }
  }

  . (Join-Path $scriptDir "Find-Node.ps1")
  $tools = Ensure-NodeOnPath
  Push-Location $dstApi
  try {
    Write-Host "npm install..." -ForegroundColor Green
    & $tools.Npm install --omit=dev
  } finally {
    Pop-Location
  }

  Write-Host ""
  Write-Host "Atualizacao concluida. Painel precisa de api\public\index.html:" -ForegroundColor Green
  Write-Host ("  " + (Test-Path (Join-Path $dstApi "public\index.html")))
  Write-Host "Inicie: .\deploy\windows\Start-Api.ps1"
  Write-Host "Abra:   http://127.0.0.1:3111/admin/ui/"
}
finally {
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
