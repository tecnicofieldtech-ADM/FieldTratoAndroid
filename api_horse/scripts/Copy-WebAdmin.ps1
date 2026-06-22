# Copia web-admin para a pasta do ApiRFeed.exe em execução.
# Uso: .\Copy-WebAdmin.ps1 -TargetDir "C:\ApiRFeed\Deploy"

param(
    [string]$TargetDir = (Join-Path $PSScriptRoot "..\Deploy")
)

$Source = Join-Path $PSScriptRoot "..\web-admin"
$Dest = Join-Path $TargetDir "web-admin"

if (-not (Test-Path $Source)) {
    Write-Error "Origem não encontrada: $Source"
    exit 1
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Copy-Item -Path (Join-Path $Source "*") -Destination $Dest -Recurse -Force
Write-Host "OK: $Source -> $Dest"
Write-Host "Abra http://127.0.0.1:3001/config com Ctrl+F5 (sem cache)."
