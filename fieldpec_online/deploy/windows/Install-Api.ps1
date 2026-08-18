#Requires -Version 5.1
<#
.SYNOPSIS
  Instala a API FieldPec Online no servidor Windows (Node deps + .env).

.PARAMETER InstallDir
  Pasta raiz do pacote extraído (onde estão api/, sql/, deploy/).
  Default: pasta pai de deploy\windows (raiz do pacote).

.PARAMETER Port
  Porta HTTP da API (default 3001).

.PARAMETER DatabaseUrl
  Connection string Postgres.
  Default: postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online

.PARAMETER AdminToken
  Token das rotas /admin/* (troque em produção).

.EXAMPLE
  cd C:\FieldPecOnline
  .\deploy\windows\Install-Api.ps1 -AdminToken 'MeuTokenSeguro' -DatabaseUrl 'postgres://fieldpec:Senha@127.0.0.1:5432/fieldpec_online'
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "",
  [int]$Port = 3001,
  [string]$DatabaseUrl = "postgres://fieldpec:fieldpec@127.0.0.1:5432/fieldpec_online",
  [string]$AdminToken = "open"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $InstallDir) {
  # deploy\windows -> deploy -> raiz do pacote
  $InstallDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
}

$apiDir = Join-Path $InstallDir "api"
$envExample = Join-Path $apiDir ".env.example"
$envFile = Join-Path $apiDir ".env"

if (-not (Test-Path $apiDir)) {
  throw "Pasta api nao encontrada em: $InstallDir"
}

. (Join-Path $scriptDir "Find-Node.ps1")
$tools = Ensure-NodeOnPath
if (-not $tools.Npm) {
  throw "npm nao encontrado ao lado do Node. Reinstale o Node.js com a opcao 'Add to PATH'."
}

Write-Host "Node: $($tools.Node) ($(& $tools.Node -v))" -ForegroundColor Cyan
Write-Host "Instalando em: $apiDir" -ForegroundColor Cyan

Push-Location $apiDir
try {
  if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
      Copy-Item $envExample $envFile
    } else {
      @"
PORT=$Port
HOST=0.0.0.0
DATABASE_URL=$DatabaseUrl
ADMIN_TOKEN=$AdminToken
"@ | Set-Content -Path $envFile -Encoding UTF8
    }
  }

  # Atualiza chaves no .env
  $lines = Get-Content $envFile
  $map = @{
    PORT = "$Port"
    HOST = "0.0.0.0"
    DATABASE_URL = $DatabaseUrl
    ADMIN_TOKEN = $AdminToken
  }
  $keysDone = @{}
  $newLines = foreach ($line in $lines) {
    if ($line -match '^\s*#') { $line; continue }
    if ($line -match '^\s*$') { $line; continue }
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=') {
      $k = $Matches[1]
      if ($map.ContainsKey($k)) {
        $keysDone[$k] = $true
        "$k=$($map[$k])"
        continue
      }
    }
    $line
  }
  foreach ($k in $map.Keys) {
    if (-not $keysDone.ContainsKey($k)) {
      $newLines += "$k=$($map[$k])"
    }
  }
  $newLines | Set-Content -Path $envFile -Encoding UTF8

  Write-Host "npm install..." -ForegroundColor Green
  & $tools.Npm install --omit=dev
  if ($LASTEXITCODE -ne 0) { throw "npm install falhou." }

  Write-Host "Testando conexao com o banco (db:init idempotente)..." -ForegroundColor Green
  & $tools.Npm run db:init
  if ($LASTEXITCODE -ne 0) {
    Write-Host "AVISO: db:init falhou. Confira DATABASE_URL e se o Postgres esta acessivel." -ForegroundColor Yellow
  }
}
finally {
  Pop-Location
}

Write-Host ""
Write-Host "Instalacao concluida." -ForegroundColor Green
Write-Host "  .env     : $envFile"
Write-Host "  Iniciar  : .\deploy\windows\Start-Api.ps1"
Write-Host "  Servico  : .\deploy\windows\Install-Service.ps1  (requer NSSM)"
Write-Host "  Health   : http://127.0.0.1:$Port/GetTeste"
