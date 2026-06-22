# Remove o serviço Windows da API Horse.
param(
    [string]$InstallDir = "",
    [string]$ServiceName = "ApiRFeed",
    [int]$Port = 3001
)

$ErrorActionPreference = "SilentlyContinue"

if ($InstallDir) {
    $ExePath = Join-Path $InstallDir.TrimEnd('\') "ApiRFeedWindows.exe"
    if (Test-Path $ExePath) {
        & $ExePath /uninstall 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }
}

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq "Running") {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 3
    }
    & sc.exe delete $ServiceName | Out-Null
}

$ruleName = "RFeed API Horse TCP $Port"
Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

Write-Host "Serviço '$ServiceName' removido (se existia)."
