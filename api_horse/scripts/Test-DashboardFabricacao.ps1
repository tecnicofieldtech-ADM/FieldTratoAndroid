# Testa rotas do dashboard de fabricação (API Horse na porta 3001).
# Uso: .\Test-DashboardFabricacao.ps1
#      .\Test-DashboardFabricacao.ps1 -DataIni 2026-05-01 -DataFim 2026-05-28

param(
    [string]$BaseUrl = "http://127.0.0.1:3001",
    [string]$DataIni = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd"),
    [string]$DataFim = (Get-Date).ToString("yyyy-MM-dd")
)

$q = "data_ini=$DataIni&data_fim=$DataFim"
$paths = @(
    @{ Path = "/dashboard/fabricacao"; Json = $false },
    @{ Path = "/dashboard/fabricacao/resumo?$q"; Json = $true },
    @{ Path = "/dashboard/fabricacao/insumos?$q"; Json = $true },
    @{ Path = "/dashboard/fabricacao/fornecimento?$q"; Json = $true }
)

$listening = Get-NetTCPConnection -LocalPort 3001 -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Write-Host "ERRO: nada escutando na porta 3001. Suba ApiRFeed.exe (Deploy ou F9 no Delphi)." -ForegroundColor Red
    exit 1
}

Write-Host "API em $BaseUrl | periodo $DataIni .. $DataFim`n"
$ok = $true
foreach ($item in $paths) {
    $uri = $BaseUrl + $item.Path
    try {
        $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 120
        Write-Host "[OK $($r.StatusCode)] $($item.Path)" -ForegroundColor Green
        if ($item.Json) {
            $len = $r.Content.Length
            $snippet = if ($len -gt 200) { $r.Content.Substring(0, 200) + "..." } else { $r.Content }
            Write-Host "  JSON ($len bytes): $snippet"
        }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        Write-Host "[FALHA $code] $($item.Path)" -ForegroundColor Red
        if ($code -eq 404) {
            Write-Host "  Recompile ApiRFeed no Delphi (Controllers.Get/Admin) e rode de novo." -ForegroundColor Yellow
        }
        $ok = $false
    }
}

if ($ok) {
    Write-Host "`nPainel: $BaseUrl/dashboard/fabricacao" -ForegroundColor Cyan
}
exit $(if ($ok) { 0 } else { 1 })
