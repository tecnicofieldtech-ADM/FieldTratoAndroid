# Gera AAB release do Field Trato para Google Play (applicationId: com.rfeed.fieldtrato).
#
# Uso:
#   .\scripts\Build-ReleaseBundle.ps1
#   .\scripts\Build-ReleaseBundle.ps1 -SkipClean

param(
  [switch]$SkipClean
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$keyProps = Join-Path $root "android\key.properties"
if (-not (Test-Path $keyProps)) {
  Write-Host "ERRO: android/key.properties nao encontrado." -ForegroundColor Red
  Write-Host "Copie android/key.properties.example e preencha com o upload keystore."
  exit 1
}

$pubspec = Get-Content "pubspec.yaml" -Raw
$versionName = "unknown"
$versionCode = "0"
if ($pubspec -match 'version:\s*([0-9.]+)\+(\d+)') {
  $versionName = $Matches[1]
  $versionCode = $Matches[2]
  Write-Host "Versao: $versionName (build $versionCode)" -ForegroundColor Cyan
}

Write-Host "applicationId: com.rfeed.fieldtrato" -ForegroundColor Cyan

if (-not $SkipClean) {
  flutter clean
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$bundleSrc = Join-Path $root "build\app\outputs\bundle\release\app-release.aab"
$releaseDir = Join-Path $root "releases"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$bundleName = "FieldTrato-$versionName-build$versionCode.aab"
$bundleDest = Join-Path $releaseDir $bundleName

if (Test-Path $bundleSrc) {
  Copy-Item $bundleSrc $bundleDest -Force
  Write-Host ""
  Write-Host "AAB gerado:" -ForegroundColor Green
  Write-Host "  $bundleSrc"
  Write-Host "  $bundleDest" -ForegroundColor Green
  Write-Host ""
  Write-Host "Envie $bundleName no Play Console (Producao ou teste interno)." -ForegroundColor Yellow
} else {
  Write-Host "ERRO: AAB nao encontrado em $bundleSrc" -ForegroundColor Red
  exit 1
}
