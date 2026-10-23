# Helper compartilhado — localiza node.exe / npm.cmd no Windows
function Find-NodeJs {
  param([string]$Prefer = "")

  # Atualiza PATH da sessao com Machine+User (PowerShell novo as vezes nao pega)
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($machinePath -or $userPath) {
    $env:Path = @($machinePath, $userPath, $env:Path) -join ";"
  }

  if ($Prefer -and (Test-Path $Prefer)) {
    return (Resolve-Path $Prefer).Path
  }

  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }

  $candidates = @(
    "$env:ProgramFiles\nodejs\node.exe",
    "${env:ProgramFiles(x86)}\nodejs\node.exe",
    "$env:LOCALAPPDATA\Programs\node\node.exe",
    "C:\Program Files\nodejs\node.exe",
    "C:\nodejs\node.exe"
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { return $c }
  }

  # Busca rasa em Program Files
  foreach ($root in @("$env:ProgramFiles", "${env:ProgramFiles(x86)}")) {
    if (-not $root) { continue }
    $hit = Get-ChildItem -Path $root -Filter "node.exe" -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\nodejs\\node\.exe$' } |
      Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }

  return $null
}

function Find-Npm {
  param([string]$NodeExe)

  $cmd = Get-Command npm -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }

  if ($NodeExe) {
    $dir = Split-Path -Parent $NodeExe
    foreach ($name in @("npm.cmd", "npm.exe")) {
      $p = Join-Path $dir $name
      if (Test-Path $p) { return $p }
    }
  }

  foreach ($c in @(
      "$env:ProgramFiles\nodejs\npm.cmd",
      "C:\Program Files\nodejs\npm.cmd"
    )) {
    if (Test-Path $c) { return $c }
  }
  return $null
}

function Ensure-NodeOnPath {
  $node = Find-NodeJs
  if (-not $node) {
    throw "Node.js nao encontrado. Instale Node 18+ (https://nodejs.org) ou reabra o PowerShell apos instalar."
  }
  $dir = Split-Path -Parent $node
  if ($env:Path -notlike "*$dir*") {
    $env:Path = "$dir;$env:Path"
  }
  $npm = Find-Npm -NodeExe $node
  return @{ Node = $node; Npm = $npm; Dir = $dir }
}
