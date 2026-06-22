# Gera o instalador RFeedApiHorse-Setup-x.x.exe (Inno Setup).
# Requer: ApiRFeedWindows.exe compilado (Win32) e Inno Setup 6 (opcional).
#
# Exemplos:
#   .\Build-Installer.ps1
#   .\Build-Installer.ps1 -ExePath "...\Win32\Debug\ApiRFeedWindows.exe"
#   .\Build-Installer.ps1 -FirebirdDir "D:\Firebird\Firebird_4_0"
#   .\Build-Installer.ps1 -SkipFirebird

param(
    [string]$ExePath = "",

    [string]$FirebirdDir = "",
    [string]$Version = "1.0.0",
    [switch]$SkipFirebird
)

$ErrorActionPreference = "Stop"
$ScriptsDir = $PSScriptRoot
$InstallerDir = Join-Path (Split-Path $ScriptsDir -Parent) "installer"
$IssFile = Join-Path $InstallerDir "RFeedApiHorse.iss"
$OutDir = Join-Path $InstallerDir "output"

$stageArgs = @{}
if ($ExePath) { $stageArgs["ExePath"] = $ExePath }
if ($FirebirdDir) { $stageArgs["FirebirdDir"] = $FirebirdDir }
if ($SkipFirebird) { $stageArgs["SkipFirebird"] = $true }

& (Join-Path $ScriptsDir "Stage-InstallerPayload.ps1") @stageArgs

$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "ISCC.exe"
) | Where-Object { $_ -eq "ISCC.exe" -or (Test-Path $_) } | Select-Object -First 1

if (-not $iscc) {
    Write-Host ""
    Write-Host "Inno Setup (ISCC.exe) não encontrado."
    Write-Host "1. Instale: https://jrsoftware.org/isdl.php"
    Write-Host "2. Abra no IDE: $IssFile"
    Write-Host "   (payload já está em installer\payload)"
    Write-Host ""
    Write-Host "Ou zip installer\payload e use install-service.ps1 no cliente."
    exit 0
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
& $iscc "/DMyAppVersion=$Version" $IssFile

if ($LASTEXITCODE -eq 0) {
    $setup = Get-ChildItem $OutDir -Filter "RFeedApiHorse-Setup-*.exe" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($setup) {
        Write-Host ""
        Write-Host "Instalador gerado: $($setup.FullName)"
    }
} else {
    throw "ISCC falhou com código $LASTEXITCODE"
}
