# Diagnóstico do mapa de fornecimento (API local + opcional SQLite do tablet)
param(
    [string]$ApiBase = "http://127.0.0.1:3001",
    [string]$IdFazenda = "2ADD0017-ADAB-40B6-99DD-A27AC3DF632D",
    [string]$Data = (Get-Date -Format "yyyy-MM-dd"),
    [int]$Trato = 1,
    [string]$IdDietaCarregamento = "",
    [string]$SqliteDb = ""
)

function Get-JsonList($uri) {
    $r = Invoke-RestMethod -Uri $uri -TimeoutSec 120
    if ($null -eq $r) { return @() }
    if ($r -is [System.Array]) { return @($r) }
    return @($r)
}

Write-Host "=== Diagnóstico Mapa Fornecimento ===" -ForegroundColor Cyan
Write-Host "API: $ApiBase"
Write-Host "Fazenda: $IdFazenda"
Write-Host "Data: $Data | Trato: $Trato"
Write-Host ""

$baias = Get-JsonList "$ApiBase/baias/get/$IdFazenda"
$prev = Get-JsonList "$ApiBase/previsao_trato/get/$IdFazenda/$Data"
$tRows = @($prev | Where-Object { [int]$_.trato -eq $Trato })

Write-Host "BAIAS (API): $($baias.Count)"
Write-Host "PREVISAO (API): total=$($prev.Count) trato$Trato=$($tRows.Count)"

$byDieta = $tRows | Group-Object idDieta | Sort-Object Count -Descending
Write-Host ""
Write-Host "Por dieta (trato $Trato):" -ForegroundColor Yellow
$byDieta | ForEach-Object {
    $withPrev = @($_.Group | Where-Object { [double]$_.previsto -gt 0 }).Count
    Write-Host ("  {0} currais | previsto>0={1} | idDieta={2}" -f $_.Count, $withPrev, $_.Name)
}

$dietaAlvo = $IdDietaCarregamento
if ([string]::IsNullOrWhiteSpace($dietaAlvo) -and $byDieta.Count -gt 0) {
    $dietaAlvo = $byDieta[0].Name
    Write-Host ""
    Write-Host "Usando dieta com mais currais: $dietaAlvo" -ForegroundColor DarkYellow
}

if (-not [string]::IsNullOrWhiteSpace($dietaAlvo)) {
    $filtrado = @($tRows | Where-Object { $_.idDieta -eq $dietaAlvo })
    $joinOk = 0
    $joinFail = 0
    $prevZero = 0
    $samples = @()

    foreach ($p in $filtrado) {
        $b = $baias | Where-Object { $_.idBaia -eq $p.id } | Select-Object -First 1
        if ($b) { $joinOk++ } else { $joinFail++ }
        if ([double]$p.previsto -le 0) { $prevZero++ }
        if ($samples.Count -lt 5) {
            $samples += [PSCustomObject]@{
                curral = if ($b) { $b.nomeLocal } else { "SEM_JOIN" }
                previsto = $p.previsto
                idBaia = $p.id
                idFornecimento = $p.idFornecimento
            }
        }
    }

    Write-Host ""
    Write-Host "Filtro dieta carregamento ($dietaAlvo):" -ForegroundColor Yellow
    Write-Host "  currais=$($filtrado.Count) join_ok=$joinOk join_fail=$joinFail previsto_zero=$prevZero"
    Write-Host "  Amostra:"
    $samples | Format-Table -AutoSize

    if ($joinFail -gt 0) {
        Write-Host "PROBLEMA: PREVISAO.id não bate com baias.idBaia" -ForegroundColor Red
    }
    if ($prevZero -gt 0) {
        Write-Host "PROBLEMA: API retorna previsto=0 para alguns currais" -ForegroundColor Red
    }
    if ($filtrado.Count -gt 0 -and $joinOk -eq $filtrado.Count -and $prevZero -eq 0) {
        Write-Host "API OK para esta dieta. Se o tablet falha, o SQLite local esta desatualizado - sincronize ou reabra o dashboard." -ForegroundColor Green
    }
}

if (-not [string]::IsNullOrWhiteSpace($SqliteDb)) {
    if (-not (Test-Path $SqliteDb)) {
        Write-Host "SQLite não encontrado: $SqliteDb" -ForegroundColor Red
        exit 1
    }
    $sqlite3 = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (-not $sqlite3) {
        Write-Host "sqlite3 não instalado. Copie rfeed_app.db e instale sqlite3 ou use DB Browser." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "=== SQLite: $SqliteDb ===" -ForegroundColor Cyan
    $q1 = "SELECT COUNT(*) FROM PREVISAO WHERE substr(DATA,1,10)='$Data' AND TRATO=$Trato;"
    $q2 = "SELECT COUNT(*) FROM DETALHES_BAIAS;"
    $q3 = @"
SELECT p.ID_BAIA, db.NOME_LOCAL, p.PREVISTO_KG, p.ID_RACAO
FROM PREVISAO p
LEFT JOIN DETALHES_BAIAS db ON TRIM(db.ID)=TRIM(p.ID_BAIA)
WHERE substr(p.DATA,1,10)='$Data' AND p.TRATO=$Trato
LIMIT 10;
"@
    Write-Host "PREVISAO trato $Trato :"
    & sqlite3 $SqliteDb $q1
    Write-Host "DETALHES_BAIAS :"
    & sqlite3 $SqliteDb $q2
    Write-Host "Amostra join:"
    & sqlite3 -header -column $SqliteDb $q3
}

Write-Host ""
Write-Host "Concluido." -ForegroundColor Cyan
