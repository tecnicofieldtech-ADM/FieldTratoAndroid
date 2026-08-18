#Requires -Version 5.1
<#
.SYNOPSIS
  Instala a API como servico Windows via NSSM (sobe com o Windows).

.NOTES
  Baixe NSSM: https://nssm.cc/download
  Extraia nssm.exe em C:\Tools\nssm\win64\nssm.exe (ou informe -NssmPath)

.EXAMPLE
  .\Install-Service.ps1 -NssmPath C:\Tools\nssm\win64\nssm.exe
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "",
  [string]$ServiceName = "FieldPecOnlineApi",
  [string]$NssmPath = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "Find-Node.ps1")
if (-not $InstallDir) {
  $InstallDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
}
$apiDir = Join-Path $InstallDir "api"

$tools = Ensure-NodeOnPath
$node = $tools.Node
if (-not (Test-Path (Join-Path $apiDir "src\index.js"))) {
  throw "API nao encontrada em $apiDir"
}

function Find-Nssm([string]$Explicit) {
  if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }
  $cmd = Get-Command nssm -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($c in @(
      "C:\Tools\nssm\win64\nssm.exe",
      "C:\nssm\win64\nssm.exe",
      "$env:ProgramFiles\nssm\nssm.exe"
    )) {
    if (Test-Path $c) { return $c }
  }
  throw "NSSM nao encontrado. Baixe em https://nssm.cc/download e use -NssmPath."
}

$nssm = Find-Nssm $NssmPath
Write-Host "NSSM: $nssm" -ForegroundColor Cyan

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "Removendo servico existente $ServiceName ..." -ForegroundColor Yellow
  & $nssm stop $ServiceName confirm 2>$null
  & $nssm remove $ServiceName confirm
  Start-Sleep -Seconds 1
}

& $nssm install $ServiceName $node "src\index.js"
& $nssm set $ServiceName AppDirectory $apiDir
& $nssm set $ServiceName DisplayName "FieldPec Online API"
& $nssm set $ServiceName Description "API nuvem FieldPec (contrato Horse) para FieldTrato"
& $nssm set $ServiceName Start SERVICE_AUTO_START
& $nssm set $ServiceName AppStdout (Join-Path $apiDir "logs\stdout.log")
& $nssm set $ServiceName AppStderr (Join-Path $apiDir "logs\stderr.log")
& $nssm set $ServiceName AppRotateFiles 1
& $nssm set $ServiceName AppRotateBytes 10485760

New-Item -ItemType Directory -Force -Path (Join-Path $apiDir "logs") | Out-Null

& $nssm start $ServiceName
Start-Sleep -Seconds 2
Get-Service $ServiceName | Format-List Name, Status, StartType

Write-Host "Servico instalado. Teste: Invoke-RestMethod http://127.0.0.1:3001/GetTeste" -ForegroundColor Green
Write-Host "Parar:   nssm stop $ServiceName"
Write-Host "Remover: nssm remove $ServiceName confirm"
