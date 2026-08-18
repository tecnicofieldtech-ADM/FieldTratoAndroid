#Requires -Version 5.1
<#
.SYNOPSIS
  Remove o servico Windows FieldPec Online API (NSSM).
#>
[CmdletBinding()]
param(
  [string]$ServiceName = "FieldPecOnlineApi",
  [string]$NssmPath = ""
)

$ErrorActionPreference = "Stop"

function Find-Nssm([string]$Explicit) {
  if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }
  $cmd = Get-Command nssm -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($c in @(
      "C:\Tools\nssm\win64\nssm.exe",
      "C:\nssm\win64\nssm.exe"
    )) {
    if (Test-Path $c) { return $c }
  }
  throw "NSSM nao encontrado."
}

$nssm = Find-Nssm $NssmPath
& $nssm stop $ServiceName confirm 2>$null
& $nssm remove $ServiceName confirm
Write-Host "Servico $ServiceName removido." -ForegroundColor Green
