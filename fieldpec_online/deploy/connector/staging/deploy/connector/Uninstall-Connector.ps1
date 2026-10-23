#Requires -Version 5.1
<#
.SYNOPSIS
  Remove o servico e (opcionalmente) a pasta do Conector FieldPec Online.
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "C:\FieldPecConnector",
  [string]$ServiceName = "FieldPecOnlineConnector",
  [switch]$RemoveFiles
)

$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  $args = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSCommandPath`"",
    "-InstallDir", "`"$InstallDir`"",
    "-ServiceName", "`"$ServiceName`""
  )
  if ($RemoveFiles) { $args += "-RemoveFiles" }
  Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $args -Wait
  exit $LASTEXITCODE
}

function Find-Nssm {
  foreach ($c in @(
      (Join-Path $InstallDir "tools\nssm\win64\nssm.exe"),
      "C:\Tools\nssm\win64\nssm.exe",
      "$env:ProgramFiles\nssm\nssm.exe"
    )) {
    if (Test-Path $c) { return $c }
  }
  $cmd = Get-Command nssm -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

$nssm = Find-Nssm
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $nssm) {
  Write-Host "Parando e removendo servico $ServiceName ..." -ForegroundColor Yellow
  & $nssm stop $ServiceName confirm 2>$null | Out-Null
  Start-Sleep -Seconds 1
  & $nssm remove $ServiceName confirm 2>$null | Out-Null
} elseif ($svc) {
  Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
  sc.exe delete $ServiceName | Out-Null
}

$desktop = [Environment]::GetFolderPath("Desktop")
$lnk = Join-Path $desktop "FieldPec Conector.lnk"
if (Test-Path $lnk) { Remove-Item $lnk -Force }
$programs = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\FieldPec Online"
if (Test-Path $programs) { Remove-Item $programs -Recurse -Force -ErrorAction SilentlyContinue }

if ($RemoveFiles -and (Test-Path $InstallDir)) {
  Write-Host "Removendo pasta $InstallDir ..." -ForegroundColor Yellow
  Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Conector desinstalado." -ForegroundColor Green
