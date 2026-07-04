# Instala APK no tablet SEM desinstalar (preserva SQLite, config e login).
# NUNCA use "flutter install" - ele desinstala antes e apaga os dados.
#
# Uso:
#   .\scripts\Install-Device.ps1
#   .\scripts\Install-Device.ps1 -SkipBuild
#   .\scripts\Install-Device.ps1 -DeviceId qgo74ld6hm89ofqk

param(
    [switch]$SkipBuild,
    [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$sdk = $env:ANDROID_HOME
if ([string]::IsNullOrWhiteSpace($sdk)) {
    $localProps = Join-Path $root "android\local.properties"
    if (Test-Path $localProps) {
        foreach ($line in Get-Content $localProps) {
            if ($line -match '^\s*sdk\.dir=(.+)$') {
                $sdk = $Matches[1].Trim() -replace '\\\\', '\'
                break
            }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($sdk)) {
    $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
}

$adb = Join-Path $sdk "platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    Write-Host "ERRO: adb nao encontrado em $adb" -ForegroundColor Red
    exit 1
}

if (-not $SkipBuild) {
    Write-Host "Compilando APK release..." -ForegroundColor Cyan
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$apk = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
    Write-Host "ERRO: APK nao encontrado: $apk" -ForegroundColor Red
    exit 1
}

$args = @("devices")
$devicesRaw = & $adb @args 2>&1 | Out-String
$devices = @()
foreach ($line in ($devicesRaw -split "`n")) {
    if ($line -match '^(\S+)\s+device') {
        $devices += $Matches[1]
    }
}

if ($devices.Count -eq 0) {
    Write-Host "ERRO: nenhum device Android conectado (USB + depuracao)." -ForegroundColor Red
    exit 1
}

$target = $DeviceId
if ([string]::IsNullOrWhiteSpace($target)) {
    if ($devices.Count -gt 1) {
        Write-Host "Varios devices:" -ForegroundColor Yellow
        $devices | ForEach-Object { Write-Host "  $_" }
        Write-Host "Use -DeviceId <id>" -ForegroundColor Yellow
        exit 1
    }
    $target = $devices[0]
}

Write-Host "Device: $target" -ForegroundColor Cyan
Write-Host "Instalando por cima (adb install -r) - dados preservados..." -ForegroundColor Cyan

$out = & $adb -s $target install -r $apk 2>&1
Write-Host $out

if ($LASTEXITCODE -ne 0) {
    if ($out -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match") {
        Write-Host ""
        Write-Host "Assinatura diferente do APK instalado." -ForegroundColor Red
        Write-Host "Desinstalar apaga TODOS os dados. Use o MESMO key.properties do APK anterior." -ForegroundColor Yellow
    }
    exit $LASTEXITCODE
}

Write-Host "OK: app atualizado sem desinstalar." -ForegroundColor Green
& $adb -s $target shell monkey -p com.rfeed.fieldtrato -c android.intent.category.LAUNCHER 1 | Out-Null
