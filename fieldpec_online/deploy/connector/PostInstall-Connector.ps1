#Requires -Version 5.1
<#
.SYNOPSIS
  Pos-instalacao chamada pelo Inno Setup (arquivos ja estao em InstallDir).
  Garante Node, npm install, servico NSSM e abre o painel.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InstallDir,
  [string]$ServiceName = "FieldPecOnlineConnector",
  [int]$Port = 3080,
  [switch]$SkipBrowser
)

$ErrorActionPreference = "Stop"
$InstallDir = $InstallDir.TrimEnd("\")
$connectorDir = Join-Path $InstallDir "connector"
$findNode = Join-Path $InstallDir "deploy\windows\Find-Node.ps1"
if (-not (Test-Path $findNode)) {
  throw "Find-Node.ps1 nao encontrado em $findNode"
}
. $findNode

function Write-Step($msg) {
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor Cyan
}

function Find-Nssm {
  foreach ($c in @(
      (Join-Path $InstallDir "tools\nssm\win64\nssm.exe"),
      "C:\Tools\nssm\win64\nssm.exe"
    )) {
    if (Test-Path $c) { return (Resolve-Path $c).Path }
  }
  $cmd = Get-Command nssm -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Ensure-Nssm {
  $found = Find-Nssm
  if ($found) { return $found }
  Write-Step "Baixando NSSM..."
  $tmp = Join-Path $env:TEMP ("nssm-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp "nssm.zip"
  Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 120
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $exe = Get-ChildItem -Path $tmp -Recurse -Filter "nssm.exe" |
    Where-Object { $_.FullName -match '\\win64\\nssm\.exe$' } |
    Select-Object -First 1
  if (-not $exe) { throw "nssm.exe win64 nao encontrado." }
  $dest = Join-Path $InstallDir "tools\nssm\win64"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item $exe.FullName (Join-Path $dest "nssm.exe") -Force
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  return (Join-Path $dest "nssm.exe")
}

function Ensure-Node {
  try { return Ensure-NodeOnPath } catch { }

  Write-Step "Instalando Node.js LTS..."
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    & winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent
    Start-Sleep -Seconds 3
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($machinePath, $userPath, $env:Path) -join ";"
    return Ensure-NodeOnPath
  }

  $msi = Join-Path $env:TEMP "node-lts.msi"
  Invoke-WebRequest -Uri "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi" -OutFile $msi -UseBasicParsing -TimeoutSec 300
  $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
  if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
    throw "Falha ao instalar Node.js (exit $($p.ExitCode))"
  }
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = @($machinePath, $userPath, $env:Path) -join ";"
  return Ensure-NodeOnPath
}

if (-not (Test-Path (Join-Path $connectorDir "package.json"))) {
  throw "connector\package.json nao encontrado em $InstallDir"
}

$envPath = Join-Path $connectorDir ".env"
if (-not (Test-Path $envPath)) {
  $ex = Join-Path $connectorDir ".env.example"
  if (Test-Path $ex) { Copy-Item $ex $envPath -Force }
}
if (Test-Path $envPath) {
  $envText = Get-Content $envPath -Raw
  if ($envText -match "(?m)^CONNECTOR_PORT=") {
    $envText = [regex]::Replace($envText, "(?m)^CONNECTOR_PORT=.*$", "CONNECTOR_PORT=$Port")
  }
  else {
    $envText = $envText.TrimEnd() + "`r`nCONNECTOR_PORT=$Port`r`n"
  }
  Set-Content -Path $envPath -Value $envText -Encoding UTF8
}

Write-Step "Node.js..."
$tools = Ensure-Node
Write-Host "Node: $($tools.Node)"

Write-Step "npm install..."
Push-Location $connectorDir
try {
  & $tools.Npm install --omit=dev
  if ($LASTEXITCODE -ne 0) { throw "npm install falhou ($LASTEXITCODE)" }
}
finally { Pop-Location }

Write-Step "Servico Windows..."
$nssm = Ensure-Nssm
$logsDir = Join-Path $connectorDir "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
  & $nssm stop $ServiceName confirm 2>$null | Out-Null
  Start-Sleep -Seconds 1
  & $nssm remove $ServiceName confirm 2>$null | Out-Null
  Start-Sleep -Seconds 1
}

& $nssm install $ServiceName $tools.Node "src\index.js" | Out-Null
& $nssm set $ServiceName AppDirectory $connectorDir | Out-Null
& $nssm set $ServiceName DisplayName "FieldPec Online Conector" | Out-Null
& $nssm set $ServiceName Description "Conector FieldPec (Firebird) <-> API nuvem FieldTrato" | Out-Null
& $nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
& $nssm set $ServiceName AppStdout (Join-Path $logsDir "stdout.log") | Out-Null
& $nssm set $ServiceName AppStderr (Join-Path $logsDir "stderr.log") | Out-Null
& $nssm set $ServiceName AppRotateFiles 1 | Out-Null
& $nssm set $ServiceName AppRotateBytes 10485760 | Out-Null

& $nssm start $ServiceName | Out-Null
Start-Sleep -Seconds 2

# Atalho Abrir-Painel
$abrir = Join-Path $InstallDir "Abrir-Painel.cmd"
Set-Content -Path $abrir -Value "@echo off`r`nstart http://127.0.0.1:$Port/`r`n" -Encoding ASCII

if (-not $SkipBrowser) {
  Start-Process "http://127.0.0.1:$Port/"
}

Write-Host "Pos-instalacao OK. Servico: $ServiceName" -ForegroundColor Green
