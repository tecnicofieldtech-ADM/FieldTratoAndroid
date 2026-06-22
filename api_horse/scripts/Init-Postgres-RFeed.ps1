#Requires -Version 5.1
<#
.SYNOPSIS
  Cria o banco PostgreSQL do RFeed e aplica todas as tabelas (import_* + imp_*).

.DESCRIPTION
  Usado pelo painel API Horse / next-api (importação de planilha + espelho BI).
  Requer psql no PATH (PostgreSQL client).

.EXAMPLE
  .\Init-Postgres-RFeed.ps1 -Interactive

.EXAMPLE
  .\Init-Postgres-RFeed.ps1 -PgSuperPassword "postgres" -AppDatabase "rfeed_web"
#>
param(
  [string] $PgHost = "127.0.0.1",
  [int] $PgPort = 5432,
  [string] $PgSuperUser = "postgres",
  [string] $PgSuperPassword = "",

  [string] $AppDatabase = "rfeed_web",
  [string] $PsqlExe = "",

  [switch] $Interactive,
  [switch] $SchemaOnly
)

$ErrorActionPreference = "Stop"

function Require-Exe([string] $Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Executável não encontrado no PATH: $Name (instale PostgreSQL client)" }
  return $cmd.Source
}

function Invoke-PsqlFile(
  [string] $Psql,
  [string] $Database,
  [string] $FilePath
) {
  $env:PGPASSWORD = $PgSuperPassword
  try {
    & $Psql -h $PgHost -p $PgPort -U $PgSuperUser -d $Database -v ON_ERROR_STOP=1 -f $FilePath
    if ($LASTEXITCODE -ne 0) { throw "psql falhou ao aplicar $FilePath (exit $LASTEXITCODE)" }
  }
  finally {
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  }
}

function Invoke-PsqlSql(
  [string] $Psql,
  [string] $Database,
  [string] $Sql
) {
  $env:PGPASSWORD = $PgSuperPassword
  try {
    & $Psql -h $PgHost -p $PgPort -U $PgSuperUser -d $Database -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "psql falhou (exit $LASTEXITCODE)" }
  }
  finally {
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  }
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$SchemaPath = Join-Path $RepoRoot "next-api\database\rfeed-pg-schema.sql"
if (-not (Test-Path -LiteralPath $SchemaPath)) {
  throw "Schema não encontrado: $SchemaPath"
}

if ($Interactive) {
  if ([string]::IsNullOrWhiteSpace($PgSuperPassword)) {
    $secure = Read-Host "Senha do PostgreSQL ($PgSuperUser)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $PgSuperPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  }
  $inDb = Read-Host "Nome do banco [$AppDatabase]"
  if (-not [string]::IsNullOrWhiteSpace($inDb)) { $AppDatabase = $inDb }
}

if ([string]::IsNullOrWhiteSpace($PgSuperPassword)) {
  throw "Informe -PgSuperPassword ou use -Interactive."
}

if ($AppDatabase -notmatch '^[a-zA-Z_][a-zA-Z0-9_]*$') {
  throw "Nome de banco inválido: $AppDatabase"
}

if ([string]::IsNullOrWhiteSpace($PsqlExe)) {
  $psql = Require-Exe "psql"
}
else {
  if (-not (Test-Path -LiteralPath $PsqlExe)) { throw "psql não encontrado: $PsqlExe" }
  $psql = $PsqlExe
}

Write-Host ">> PostgreSQL ${PgHost}:${PgPort} como $PgSuperUser"
Write-Host ">> Schema: $SchemaPath"

if (-not $SchemaOnly) {
  $checkSql = "SELECT 1 FROM pg_database WHERE datname = '$($AppDatabase.Replace("'", "''"))' LIMIT 1;"
  $env:PGPASSWORD = $PgSuperPassword
  try {
    $exists = (& $psql -h $PgHost -p $PgPort -U $PgSuperUser -d postgres -tAc $checkSql).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Não conectou em ${PgHost}:${PgPort}" }
  }
  finally {
    Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue
  }

  if ($exists -eq "1") {
    Write-Host ">> Banco '$AppDatabase' já existe."
  }
  else {
    Write-Host ">> Criando banco '$AppDatabase'..."
    $createSql = "CREATE DATABASE `"$AppDatabase`" OWNER `"$PgSuperUser`" ENCODING 'UTF8' TEMPLATE template0;"
    Invoke-PsqlSql -Psql $psql -Database "postgres" -Sql $createSql
  }
}

Write-Host ">> Aplicando tabelas (import_* + imp_*)..."
Invoke-PsqlFile -Psql $psql -Database $AppDatabase -FilePath $SchemaPath

Write-Host ""
Write-Host "OK — banco '$AppDatabase' pronto."
Write-Host "Configure no painel Horse (/config) ou next-api:"
Write-Host "  Host=$PgHost  Port=$PgPort  Database=$AppDatabase  User=$PgSuperUser"
