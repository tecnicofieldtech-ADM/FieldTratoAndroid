# Gera APK release do RFeedX (mesmo applicationId para atualizar sem desinstalar).
# Requisitos: Flutter SDK, android/key.properties com o MESMO keystore do pacote anterior.
#
# Uso:
#   .\scripts\Build-ReleaseApk.ps1
#   .\scripts\Build-ReleaseApk.ps1 -SplitPerAbi

param(
  [switch]$SplitPerAbi
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$keyProps = Join-Path $root "android\key.properties"
if (-not (Test-Path $keyProps)) {
  Write-Host "ERRO: android/key.properties nao encontrado." -ForegroundColor Red
  Write-Host "Copie android/key.properties.example e use o mesmo keystore do APK ja enviado ao cliente."
  exit 1
}

$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -match 'version:\s*([0-9.]+)\+(\d+)') {
  Write-Host "Versao: $($Matches[1]) (build $($Matches[2]))" -ForegroundColor Cyan
}

Write-Host "applicationId: com.rfeed.rfeedx (nao altere para atualizar in-place)" -ForegroundColor Cyan

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$buildArgs = @("build", "apk", "--release")
if ($SplitPerAbi) {
  $buildArgs += "--split-per-abi"
}

flutter @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$versionName = "unknown"
$versionCode = "0"
if ($pubspec -match 'version:\s*([0-9.]+)\+(\d+)') {
  $versionName = $Matches[1]
  $versionCode = $Matches[2]
}

$outDir = Join-Path $root "build\app\outputs\flutter-apk"
$releaseDir = Join-Path $root "release"
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

$apkName = "RFeedX-$versionName-$versionCode.apk"
$destApk = Join-Path $releaseDir $apkName

Get-ChildItem $outDir -Filter "*.apk" | ForEach-Object {
  if ($_.Name -eq "app-release.apk") {
    Copy-Item $_.FullName $destApk -Force
    Write-Host "APK com versao: $destApk" -ForegroundColor Green
  }
}

Write-Host ""
Write-Host "APK(s) gerado(s) em:" -ForegroundColor Green
Get-ChildItem $outDir -Filter "*.apk" | ForEach-Object {
  Write-Host "  $($_.FullName)"
}
if (Test-Path $destApk) {
  Write-Host "  $destApk" -ForegroundColor Green
}
Write-Host ""
Write-Host "Instalacao no tablet (USB/debug):" -ForegroundColor Yellow
if (Test-Path $destApk) {
  Write-Host "  adb install -r release\$apkName"
} else {
  Write-Host "  adb install -r build\app\outputs\flutter-apk\app-release.apk"
}
Write-Host ""
Write-Host "Use o MESMO certificado (key.properties) do APK anterior; versionCode deve ser maior." -ForegroundColor Yellow
