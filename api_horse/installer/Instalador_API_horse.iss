# Instala e inicia o serviço Windows da API Horse (RFeed).
# Uso: .\install-service.ps1 -InstallDir "C:\Program Files\RSistemas\RFeed\ApiHorse"

param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,

    [string]$ServiceName = "ApiRFeed",
    [string]$DisplayName = "RFeed API Horse",
    [int]$Port = 3001,
    [switch]$SkipFirewall
)

$ErrorActionPreference = "Stop"

$InstallDir = $InstallDir.TrimEnd('\')
$ExePath = Join-Path $InstallDir "ApiRFeedWindows.exe"

if (-not (Test-Path $ExePath)) {
    throw "Executável não encontrado: $ExePath"
}

if (-not (Test-Path (Join-Path $InstallDir "web-admin\config.html"))) {
    throw "Painel web não encontrado em: $InstallDir\web-admin"
}

$IniExample = Join-Path $InstallDir "ApiConfig.ini.example"
$IniPath = Join-Path $InstallDir "ApiConfig.ini"
if (-not (Test-Path $IniPath) -and (Test-Path $IniExample)) {
    Copy-Item $IniExample $IniPath
    Write-Host "Criado ApiConfig.ini a partir do exemplo."
}

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Status -eq "Running") {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    & sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 1
}

$binPath = "`"$ExePath`""
& sc.exe create $ServiceName binPath= $binPath start= delayed-auto DisplayName= $DisplayName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "sc.exe create falhou (código $LASTEXITCODE)."
}

& sc.exe description $ServiceName "API REST RFeed (tablet) — porta HTTP $Port. Painel: http://127.0.0.1:$Port/config" | Out-Null

if (-not $SkipFirewall) {
    $ruleName = "RFeed API Horse TCP $Port"
    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    }
    New-NetFirewallRule -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -ErrorAction SilentlyContinue | Out-Null
}

Start-Service -Name $ServiceName
Write-Host "Serviço '$ServiceName' instalado e iniciado."
Write-Host "Painel: http://127.0.0.1:$Port/config"
