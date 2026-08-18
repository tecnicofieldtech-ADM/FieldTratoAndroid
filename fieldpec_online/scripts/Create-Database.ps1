#Requires -Version 5.1
<#
.SYNOPSIS
  Cria o banco PostgreSQL FieldPec Online no servidor (role + database + schema).

.DESCRIPTION
  1) Cria role/usuário e database (via create_database.sql, como superuser)
  2) Aplica sql/schema.sql no banco novo

.PARAMETER PgHost
  Host do Postgres (default: 127.0.0.1)

.PARAMETER Port
  Porta (default: 5432)

.PARAMETER SuperUser
  Usuário admin do Postgres (default: postgres)

.PARAMETER DbName
  Nome do banco (default: fieldpec_online)

.PARAMETER DbUser
  Usuário da aplicação (default: fieldpec)

.PARAMETER DbPassword
  Senha da aplicação (default: fieldpec) — altere em produção

.PARAMETER PsqlPath
  Caminho do psql.exe se não estiver no PATH

.EXAMPLE
  .\Create-Database.ps1

.EXAMPLE
  .\Create-Database.ps1 -PgHost 10.0.0.50 -DbPassword 'SenhaForte!'

.EXAMPLE
  $env:PGPASSWORD='postgres'; .\Create-Database.ps1 -SuperUser postgres
#>
[CmdletBinding()]
param(
  [string]$PgHost = "127.0.0.1",
  [int]$Port = 5432,
  [string]$SuperUser = "postgres",
  [string]$DbName = "fieldpec_online",
  [string]$DbUser = "fieldpec",
  [string]$DbPassword = "fieldpec",
  [string]$PsqlPath = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$sqlDir = Join-Path $rootDir "sql"
$createSql = Join-Path $sqlDir "create_database.sql"
$schemaSql = Join-Path $sqlDir "schema.sql"

if (-not (Test-Path $createSql)) { throw "Arquivo nao encontrado: $createSql" }
if (-not (Test-Path $schemaSql)) { throw "Arquivo nao encontrado: $schemaSql" }

function Find-Psql {
  param([string]$Explicit)
  if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }
  $cmd = Get-Command psql -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    "C:\Program Files\PostgreSQL\17\bin\psql.exe",
    "C:\Program Files\PostgreSQL\16\bin\psql.exe",
    "C:\Program Files\PostgreSQL\15\bin\psql.exe",
    "C:\Program Files\PostgreSQL\14\bin\psql.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  throw "psql nao encontrado. Instale o cliente PostgreSQL ou informe -PsqlPath."
}

$psql = Find-Psql -Explicit $PsqlPath
Write-Host "Usando psql: $psql" -ForegroundColor Cyan
Write-Host "Servidor: ${PgHost}:${Port}  SuperUser: $SuperUser" -ForegroundColor Cyan

# Senha do superuser: use $env:PGPASSWORD ou digite no prompt do psql
if (-not $env:PGPASSWORD) {
  Write-Host "Dica: defina `$env:PGPASSWORD='senha_do_postgres' antes de rodar para evitar prompt." -ForegroundColor Yellow
}

# Se o usuário pediu nomes/senha diferentes do SQL fixo, gera SQL temporário
$tempCreate = Join-Path $env:TEMP "fieldpec_create_database_$([guid]::NewGuid().ToString('N')).sql"
try {
  $createContent = Get-Content -Path $createSql -Raw -Encoding UTF8
  if ($DbUser -ne "fieldpec" -or $DbName -ne "fieldpec_online" -or $DbPassword -ne "fieldpec") {
    $createContent = $createContent `
      -replace "fieldpec_online", $DbName `
      -replace "PASSWORD 'fieldpec'", "PASSWORD '$($DbPassword -replace "'","''")'" `
      -replace "ROLE fieldpec", "ROLE $DbUser" `
      -replace "rolname = 'fieldpec'", "rolname = '$DbUser'" `
      -replace "CREATE ROLE fieldpec", "CREATE ROLE $DbUser" `
      -replace "ALTER ROLE fieldpec", "ALTER ROLE $DbUser" `
      -replace "OWNER fieldpec", "OWNER $DbUser" `
      -replace "TO fieldpec", "TO $DbUser" `
      -replace "role fieldpec", "role $DbUser"
  }
  Set-Content -Path $tempCreate -Value $createContent -Encoding UTF8

  Write-Host "`n[1/2] Criando role e database..." -ForegroundColor Green
  & $psql -h $PgHost -p $Port -U $SuperUser -d postgres -v ON_ERROR_STOP=1 -f $tempCreate
  if ($LASTEXITCODE -ne 0) { throw "Falha ao criar role/database (exit $LASTEXITCODE)." }

  Write-Host "`n[2/2] Aplicando schema em $DbName..." -ForegroundColor Green
  $prevPass = $env:PGPASSWORD
  $env:PGPASSWORD = $DbPassword
  try {
    & $psql -h $PgHost -p $Port -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -f $schemaSql
    if ($LASTEXITCODE -ne 0) { throw "Falha ao aplicar schema (exit $LASTEXITCODE)." }
  } finally {
    if ($null -eq $prevPass) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
    else { $env:PGPASSWORD = $prevPass }
  }

  Write-Host "`nConcluido." -ForegroundColor Green
  Write-Host "DATABASE_URL=postgres://${DbUser}:****@${PgHost}:${Port}/${DbName}"
  Write-Host "Teste: & `"$psql`" -h $PgHost -p $Port -U $DbUser -d $DbName -c `"\dt`""
}
finally {
  if (Test-Path $tempCreate) { Remove-Item $tempCreate -Force -ErrorAction SilentlyContinue }
}
