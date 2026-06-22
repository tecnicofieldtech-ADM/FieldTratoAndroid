# Compila ApiRFeedWindows (serviço) e atualiza Deploy\ + web-admin.
# Uso:
#   .\Build-ApiRFeedWindows.ps1
#   .\Build-ApiRFeedWindows.ps1 -RestartService

param(
    [switch]$RestartService
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Proj = Join-Path $Root "ServicoWindows\ApiRFeedWindows.dproj"
$OutExe = Join-Path $Root "ServicoWindows\Win32\Release\ApiRFeedWindows.exe"
$DeployExe = Join-Path $Root "Deploy\ApiRFeedWindows.exe"
$WebAdminSrc = Join-Path $Root "web-admin"
$DeployWeb = Join-Path $Root "Deploy\web-admin"
$ReleaseWeb = Join-Path $Root "ServicoWindows\Win32\Release\web-admin"
$ServiceName = "ApiRFeed"

function Stop-ApiService {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "Parando servico $ServiceName..." -ForegroundColor Yellow
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    $procId = (Get-NetTCPConnection -LocalPort 3001 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1).OwningProcess
    if ($procId) {
        Write-Host "Encerrando processo na porta 3001 (PID $procId)..." -ForegroundColor Yellow
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Start-ApiService {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "Iniciando servico $ServiceName..." -ForegroundColor Cyan
        Start-Service -Name $ServiceName
    }
}

Stop-ApiService

$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat"
if (-not (Test-Path $rsvars)) {
    Write-Host "ERRO: Delphi rsvars.bat nao encontrado. Compile pelo IDE: ApiRFeedWindows.dproj Release Win32." -ForegroundColor Red
    exit 1
}

Write-Host "Compilando Release Win32..." -ForegroundColor Cyan
$msbuildArgs = @(
    "`"$Proj`"",
    "/p:Config=Release",
    "/p:Platform=Win32",
    "/t:Build",
    "/p:DCC_ExeOutput=.\Win32\Release",
    "/p:PostBuildEventUseInBuild=false"
) -join " "
cmd /c "`"$rsvars`" && msbuild $msbuildArgs"
if (-not (Test-Path $OutExe)) {
    Write-Host "ERRO: build falhou - $OutExe nao gerado." -ForegroundColor Red
    exit 1
}

foreach ($dst in @($ReleaseWeb, $DeployWeb)) {
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item "$WebAdminSrc\*" $dst -Recurse -Force
}

Copy-Item $OutExe $DeployExe -Force

Write-Host "OK: $DeployExe" -ForegroundColor Green
Write-Host "OK: web-admin em Deploy\web-admin" -ForegroundColor Green

if ($RestartService) {
    Start-ApiService
    Start-Sleep -Seconds 3
    & (Join-Path $PSScriptRoot "Test-DashboardFabricacao.ps1")
}

Write-Host ""
Write-Host "No cliente: pare o servico ApiRFeed, copie ApiRFeedWindows.exe e web-admin para a pasta de instalacao e reinicie." -ForegroundColor Yellow
