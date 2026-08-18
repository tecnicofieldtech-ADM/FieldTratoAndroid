# Reinicia ApiRFeed na porta 3001 (lê Port= do ApiConfig.ini ao lado deste script).
$ErrorActionPreference = "Stop"
$deployDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $deployDir

$port = 3001
$iniPath = Join-Path $deployDir "ApiConfig.ini"
if (Test-Path $iniPath) {
  $m = Select-String -Path $iniPath -Pattern '^\s*Port\s*=\s*(\d+)\s*$' | Select-Object -First 1
  if ($m) { $port = [int]$m.Matches[0].Groups[1].Value }
}

Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object {
    $procId = $_.OwningProcess
    if ($procId) {
      Write-Host "Encerrando PID $procId na porta $port"
      Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
    }
  }

Start-Sleep -Seconds 2
$exe = Join-Path $deployDir "ApiRFeed.exe"
if (-not (Test-Path $exe)) { throw "ApiRFeed.exe nao encontrado em $deployDir" }

Write-Host "Iniciando $exe"
Start-Process -FilePath $exe -WorkingDirectory $deployDir
Start-Sleep -Seconds 4

try {
  $cfg = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/config" -Method GET
  Write-Host "activeClient=$($cfg.activeClient) loadedRoutesClient=$($cfg.loadedRoutesClient) routesRestartRequired=$($cfg.routesRestartRequired)"
} catch {
  Write-Warning "API ainda nao respondeu em http://127.0.0.1:$port — aguarde alguns segundos."
}
