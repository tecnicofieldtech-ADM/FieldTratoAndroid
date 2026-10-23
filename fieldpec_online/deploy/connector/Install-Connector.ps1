#Requires -Version 5.1
<#
.SYNOPSIS
  Instala o Conector FieldPec Online no PC do cliente:
  - copia arquivos
  - garante Node.js 18+
  - npm install
  - registra serviço Windows (NSSM)
  - inicia o serviço e abre o painel no navegador

.EXAMPLE
  # Como Administrador, a partir da pasta extraída do ZIP:
  .\deploy\connector\Install-Connector.ps1

  .\deploy\connector\Install-Connector.ps1 -InstallDir "C:\FieldPecConnector"
#>
[CmdletBinding()]
param(
  [string]$InstallDir = "C:\FieldPecConnector",
  [string]$ServiceName = "FieldPecOnlineConnector",
  [int]$Port = 3080,
  [switch]$SkipBrowser,
  [switch]$SkipNodeInstall
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Elevação admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Solicitando privilegios de Administrador..." -ForegroundColor Yellow
  $args = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSCommandPath`"",
    "-InstallDir", "`"$InstallDir`"",
    "-ServiceName", "`"$ServiceName`"",
    "-Port", "$Port"
  )
  if ($SkipBrowser) { $args += "-SkipBrowser" }
  if ($SkipNodeInstall) { $args += "-SkipNodeInstall" }
  Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $args -Wait
  exit $LASTEXITCODE
}

. (Join-Path (Split-Path -Parent $scriptDir) "windows\Find-Node.ps1")

function Write-Step($msg) {
  Write-Host ""
  Write-Host "==> $msg" -ForegroundColor Cyan
}

function Find-Nssm {
  $bundled = Join-Path $scriptDir "..\..\tools\nssm\win64\nssm.exe"
  $bundled2 = Join-Path $scriptDir "tools\nssm\win64\nssm.exe"
  $fromRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptDir)) "tools\nssm\win64\nssm.exe"
  foreach ($c in @(
      $bundled, $bundled2, $fromRoot,
      (Join-Path $InstallDir "tools\nssm\win64\nssm.exe"),
      "C:\Tools\nssm\win64\nssm.exe",
      "$env:ProgramFiles\nssm\nssm.exe"
    )) {
    if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
  }
  $cmd = Get-Command nssm -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Ensure-Nssm {
  $found = Find-Nssm
  if ($found) { return $found }

  Write-Step "Baixando NSSM (gerenciador de servico Windows)..."
  $tmp = Join-Path $env:TEMP ("nssm-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp "nssm.zip"
  # Espelho oficial / release estável
  $urls = @(
    "https://nssm.cc/release/nssm-2.24.zip",
    "https://github.com/nssm/nssm/releases/download/v2.24/nssm-2.24.zip"
  )
  $ok = $false
  foreach ($u in $urls) {
    try {
      Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 120
      $ok = $true
      break
    } catch {
      Write-Host "  falhou $u : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
  }
  if (-not $ok) {
    throw "Nao foi possivel baixar NSSM. Coloque nssm.exe em tools\nssm\win64\ e rode de novo."
  }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $exe = Get-ChildItem -Path $tmp -Recurse -Filter "nssm.exe" |
    Where-Object { $_.FullName -match '\\win64\\nssm\.exe$' } |
    Select-Object -First 1
  if (-not $exe) { throw "nssm.exe win64 nao encontrado no ZIP baixado." }

  $destDir = Join-Path $InstallDir "tools\nssm\win64"
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Copy-Item $exe.FullName (Join-Path $destDir "nssm.exe") -Force
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  return (Join-Path $destDir "nssm.exe")
}

function Ensure-Node {
  try {
    return Ensure-NodeOnPath
  } catch {
    if ($SkipNodeInstall) { throw }
  }

  Write-Step "Node.js nao encontrado. Instalando Node.js LTS..."
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    & winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent
    Start-Sleep -Seconds 3
    return Ensure-NodeOnPath
  }

  $msi = Join-Path $env:TEMP "node-lts.msi"
  $nodeUrl = "https://nodejs.org/dist/v22.14.0/node-v22.14.0-x64.msi"
  Write-Host "Baixando $nodeUrl ..."
  Invoke-WebRequest -Uri $nodeUrl -OutFile $msi -UseBasicParsing -TimeoutSec 300
  Write-Host "Instalando MSI (silencioso)..."
  $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
  if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
    throw "Falha ao instalar Node.js (msiexec exit $($p.ExitCode))"
  }
  # Atualiza PATH da sessao
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = @($machinePath, $userPath, $env:Path) -join ";"
  return Ensure-NodeOnPath
}

function New-Shortcut([string]$Path, [string]$Target, [string]$Args = "", [string]$WorkDir = "") {
  $w = New-Object -ComObject WScript.Shell
  $s = $w.CreateShortcut($Path)
  $s.TargetPath = $Target
  if ($Args) { $s.Arguments = $Args }
  if ($WorkDir) { $s.WorkingDirectory = $WorkDir }
  $s.Save()
}

# --- Localiza pasta "connector" de origem (ZIP extraido ou repo) ---
$candidates = @(
  (Join-Path (Split-Path -Parent (Split-Path -Parent $scriptDir)) "connector"),
  (Join-Path (Split-Path -Parent $scriptDir) "connector"),
  (Join-Path $PSScriptRoot "..\..\connector"),
  (Get-Location).Path
)
$srcConnector = $null
foreach ($c in $candidates) {
  $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($c)
  if (Test-Path (Join-Path $resolved "package.json")) {
    $pkg = Get-Content (Join-Path $resolved "package.json") -Raw -ErrorAction SilentlyContinue
    if ($pkg -match "fieldpec-online-connector") {
      $srcConnector = $resolved
      break
    }
  }
  if (Test-Path (Join-Path $resolved "connector\package.json")) {
    $srcConnector = Join-Path $resolved "connector"
    break
  }
}
if (-not $srcConnector) {
  throw "Pasta connector nao encontrada. Execute o instalador a partir do ZIP extraido."
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Conector FieldPec Online — Instalador" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Origem : $srcConnector"
Write-Host "Destino: $InstallDir"
Write-Host "Servico: $ServiceName"
Write-Host "Porta  : $Port"

Write-Step "Copiando arquivos..."
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$dstConnector = Join-Path $InstallDir "connector"
# Preserva .env se ja existir
$envBackup = $null
$envPath = Join-Path $dstConnector ".env"
if (Test-Path $envPath) {
  $envBackup = Join-Path $env:TEMP ("fieldpec-conn-env-" + [guid]::NewGuid().ToString("N") + ".env")
  Copy-Item $envPath $envBackup -Force
}

robocopy $srcConnector $dstConnector /E /XD node_modules /XF .env /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falhou: $LASTEXITCODE" }

# Copia scripts de deploy/tools junto
$packRoot = Split-Path -Parent $srcConnector
foreach ($name in @("deploy", "tools")) {
  $s = Join-Path $packRoot $name
  if (Test-Path $s) {
    $d = Join-Path $InstallDir $name
    robocopy $s $d /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
  }
}

if ($envBackup -and (Test-Path $envBackup)) {
  Copy-Item $envBackup $envPath -Force
  Remove-Item $envBackup -Force -ErrorAction SilentlyContinue
  Write-Host "  .env anterior preservado." -ForegroundColor DarkGreen
} elseif (-not (Test-Path $envPath)) {
  $ex = Join-Path $dstConnector ".env.example"
  if (Test-Path $ex) {
    Copy-Item $ex $envPath -Force
    Write-Host "  .env criado a partir de .env.example — configure CLOUD_API_URL, CLIENT_CODE e FB_DATABASE no painel." -ForegroundColor Yellow
  }
}

# Porta no .env
if (Test-Path $envPath) {
  $envText = Get-Content $envPath -Raw
  if ($envText -match "(?m)^CONNECTOR_PORT=") {
    $envText = [regex]::Replace($envText, "(?m)^CONNECTOR_PORT=.*$", "CONNECTOR_PORT=$Port")
  } else {
    $envText = $envText.TrimEnd() + "`r`nCONNECTOR_PORT=$Port`r`n"
  }
  Set-Content -Path $envPath -Value $envText -Encoding UTF8
}

Write-Step "Verificando Node.js..."
$tools = Ensure-Node
Write-Host "  Node: $($tools.Node)"
Write-Host "  Npm : $($tools.Npm)"

Write-Step "npm install..."
Push-Location $dstConnector
try {
  & $tools.Npm install --omit=dev
  if ($LASTEXITCODE -ne 0) { throw "npm install falhou ($LASTEXITCODE)" }
} finally {
  Pop-Location
}

Write-Step "Configurando NSSM / servico Windows..."
$nssm = Ensure-Nssm
Write-Host "  NSSM: $nssm"
$logsDir = Join-Path $dstConnector "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "  Removendo servico existente..." -ForegroundColor Yellow
  & $nssm stop $ServiceName confirm 2>$null | Out-Null
  Start-Sleep -Seconds 1
  & $nssm remove $ServiceName confirm 2>$null | Out-Null
  Start-Sleep -Seconds 1
}

& $nssm install $ServiceName $tools.Node "src\index.js" | Out-Null
& $nssm set $ServiceName AppDirectory $dstConnector | Out-Null
& $nssm set $ServiceName DisplayName "FieldPec Online Conector" | Out-Null
& $nssm set $ServiceName Description "Conector FieldPec (Firebird) <-> API nuvem FieldTrato" | Out-Null
& $nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
& $nssm set $ServiceName AppStdout (Join-Path $logsDir "stdout.log") | Out-Null
& $nssm set $ServiceName AppStderr (Join-Path $logsDir "stderr.log") | Out-Null
& $nssm set $ServiceName AppRotateFiles 1 | Out-Null
& $nssm set $ServiceName AppRotateBytes 10485760 | Out-Null
& $nssm set $ServiceName AppEnvironmentExtra "NODE_ENV=production" | Out-Null

Write-Step "Iniciando servico..."
& $nssm start $ServiceName | Out-Null
Start-Sleep -Seconds 3
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
  Write-Host "  Status: $($svc.Status) ($($svc.StartType))" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Yellow' })
} else {
  Write-Host "  Aviso: servico nao encontrado apos install." -ForegroundColor Yellow
}

# Atalhos
Write-Step "Criando atalhos..."
$url = "http://127.0.0.1:$Port/"
$desktop = [Environment]::GetFolderPath("Desktop")
$programs = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\FieldPec Online"
New-Item -ItemType Directory -Force -Path $programs | Out-Null
New-Shortcut -Path (Join-Path $desktop "FieldPec Conector.lnk") -Target "cmd.exe" -Args "/c start $url" -WorkDir $dstConnector
New-Shortcut -Path (Join-Path $programs "FieldPec Conector.lnk") -Target "cmd.exe" -Args "/c start $url" -WorkDir $dstConnector
New-Shortcut -Path (Join-Path $programs "Desinstalar Conector.lnk") -Target "powershell.exe" `
  -Args "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallDir 'deploy\connector\Uninstall-Connector.ps1')`" -InstallDir `"$InstallDir`"" `
  -WorkDir $InstallDir

# Copia uninstall para InstallDir se veio do pack
$unSrc = Join-Path $scriptDir "Uninstall-Connector.ps1"
$unDstDir = Join-Path $InstallDir "deploy\connector"
New-Item -ItemType Directory -Force -Path $unDstDir | Out-Null
if (Test-Path $unSrc) {
  Copy-Item $unSrc (Join-Path $unDstDir "Uninstall-Connector.ps1") -Force
}
Copy-Item $PSCommandPath (Join-Path $unDstDir "Install-Connector.ps1") -Force -ErrorAction SilentlyContinue

if (-not $SkipBrowser) {
  Write-Step "Abrindo painel $url ..."
  Start-Process $url
}

Write-Host ""
Write-Host "Instalacao concluida." -ForegroundColor Green
Write-Host "  Painel : $url"
Write-Host "  Pasta  : $InstallDir"
Write-Host "  Servico: $ServiceName (sobe com o Windows)"
Write-Host ""
Write-Host "Proximos passos no painel:" -ForegroundColor Yellow
Write-Host "  1) Configuracao: CLOUD_API_URL, CLIENT_CODE, FB_DATABASE"
Write-Host "  2) REPLAY_TO_LOCAL = 1 para gravar fab/forn no Field"
Write-Host "  3) Salvar e usar Subir / Baixar / Acompanhar"
Write-Host ""
