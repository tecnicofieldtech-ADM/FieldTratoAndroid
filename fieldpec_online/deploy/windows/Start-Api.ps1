#Requires -Version 5.1
<#
.SYNOPSIS
  Inicia a API FieldPec Online em foreground (console).

.EXAMPLE
  .\Start-Api.ps1
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "",
  [string]$NodePath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "Find-Node.ps1")

if (-not $InstallDir) {
  $InstallDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
}
$apiDir = Join-Path $InstallDir "api"
$envFile = Join-Path $apiDir ".env"

if (-not (Test-Path $apiDir)) { throw "api nao encontrada: $apiDir" }
if (-not (Test-Path $envFile)) {
  throw ".env nao encontrado. Rode Install-Api.ps1 primeiro."
}

$tools = Ensure-NodeOnPath
if ($NodePath) {
  $tools = @{ Node = (Find-NodeJs -Prefer $NodePath); Npm = (Find-Npm -NodeExe (Find-NodeJs -Prefer $NodePath)); Dir = (Split-Path -Parent (Find-NodeJs -Prefer $NodePath)) }
  $env:Path = "$($tools.Dir);$env:Path"
}

Write-Host "Node: $($tools.Node)" -ForegroundColor Cyan
Write-Host "Iniciando API em $apiDir ..." -ForegroundColor Cyan
Write-Host "Painel: http://127.0.0.1:<PORT>/admin/ui/" -ForegroundColor Yellow
Write-Host "Ctrl+C para parar." -ForegroundColor Yellow

Set-Location $apiDir
if ($tools.Npm) {
  & $tools.Npm start
} else {
  & $tools.Node "src\index.js"
}
