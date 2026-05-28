# Monta a pasta installer\payload para o Inno Setup.
# Uso:
#   .\Stage-InstallerPayload.ps1 -ExePath "C:\...\ApiRFeedWindows.exe"
#   .\Stage-InstallerPayload.ps1   # tenta achar o .exe automaticamente
#
# fbclient.dll: ApiRFeedWindows é Win32 (x86). Usa primeiro api_horse\Deploy\fbclient.dll
# (x86 no repositório). -FirebirdDir só como fallback; deve ser pasta Firebird 32-bit.

param(
    [string]$ExePath = "",

    [string]$FirebirdDir = "",
    [string]$PayloadDir = "",
    [switch]$SkipFirebird
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
if (-not $PayloadDir) {
    $PayloadDir = Join-Path $Root "installer\payload"
}

function Find-ApiExe {
    param([string]$Hint)
    $candidates = @()
    if ($Hint) { $candidates += $Hint }

    $bases = @(
        "C:\RSistemas\Aplicativos\RFeedAutomacao\API\ServicoWindows",
        (Join-Path $Root "ServicoWindows"),
        (Join-Path $Root "Deploy")
    )
    foreach ($base in $bases) {
        if (-not $base) { continue }
        $candidates += @(
            (Join-Path $base "Win32\Release\ApiRFeedWindows.exe"),
            (Join-Path $base "Win32\Debug\ApiRFeedWindows.exe"),
            (Join-Path $base "ApiRFeedWindows.exe")
        )
    }

    $seen = @{}
    foreach ($p in $candidates) {
        if (-not $p -or $seen.ContainsKey($p)) { continue }
        $seen[$p] = $true
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    return $null
}

function Get-DllMachineType {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
    switch ($machine) {
        0x014c { return 'x86' }
        0x8664 { return 'x64' }
        default { return ("unknown-0x{0:X}" -f $machine) }
    }
}

function Test-DllIsX86 {
    param([string]$Path)
    return (Get-DllMachineType $Path) -eq 'x86'
}

function Copy-FbClientX86 {
    param(
        [string]$SourcePath,
        [string]$DestDir,
        [string]$Label
    )
    if (-not (Test-Path $SourcePath)) { return $false }
    $arch = Get-DllMachineType $SourcePath
    if ($arch -ne 'x86') {
        Write-Warning "Ignorado $Label ($SourcePath): arquitetura $arch; ApiRFeedWindows exige x86."
        return $false
    }
    Copy-Item $SourcePath (Join-Path $DestDir "fbclient.dll") -Force
    Write-Host "Incluído: fbclient.dll x86 de $Label ($SourcePath)"
    return $true
}

function Find-FirebirdFbClientX86 {
    $candidates = @()
    if ($FirebirdDir -and (Test-Path $FirebirdDir)) {
        $candidates += (Resolve-Path $FirebirdDir).Path
    }
    $roots = @(
        "${env:ProgramFiles(x86)}\Firebird",
        "${env:ProgramFiles}\Firebird"
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $subs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
        foreach ($sub in $subs) {
            $dll = Join-Path $sub.FullName "fbclient.dll"
            if ((Test-Path $dll) -and (Test-DllIsX86 $dll)) {
                $candidates += $sub.FullName
            }
        }
        $dllRoot = Join-Path $root "fbclient.dll"
        if ((Test-Path $dllRoot) -and (Test-DllIsX86 $dllRoot)) {
            $candidates += $root
        }
    }
    foreach ($dir in $candidates) {
        $dll = Join-Path $dir "fbclient.dll"
        if ((Test-Path $dll) -and (Test-DllIsX86 $dll)) {
            return $dll
        }
    }
    return $null
}

if (-not $ExePath) {
    $ExePath = Find-ApiExe ""
} elseif (-not (Test-Path $ExePath)) {
    $found = Find-ApiExe $ExePath
    if ($found) {
        Write-Host "Usando: $found"
        $ExePath = $found
    }
} else {
    $ExePath = (Resolve-Path $ExePath).Path
}

if (-not $ExePath -or -not (Test-Path $ExePath)) {
    throw @"
ApiRFeedWindows.exe não encontrado.

Compile ServicoWindows\ApiRFeedWindows.dproj (Win32 Release ou Debug) e informe o caminho:

  .\Stage-InstallerPayload.ps1 -ExePath 'C:\caminho\ApiRFeedWindows.exe'

Pastas verificadas (exemplos):
  ...\ServicoWindows\Win32\Debug\ApiRFeedWindows.exe
  ...\ServicoWindows\Win32\Release\ApiRFeedWindows.exe
"@
}

$WebAdminSrc = Join-Path $Root "web-admin"
$IniExample = Join-Path $Root "Deploy\ApiConfig.ini.example"

if (-not (Test-Path $WebAdminSrc)) {
    throw "web-admin não encontrado: $WebAdminSrc"
}

if (Test-Path $PayloadDir) {
    Remove-Item $PayloadDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $PayloadDir "web-admin") | Out-Null

Write-Host "Exe: $ExePath"
Copy-Item $ExePath (Join-Path $PayloadDir "ApiRFeedWindows.exe") -Force
Copy-Item "$WebAdminSrc\*" (Join-Path $PayloadDir "web-admin") -Recurse -Force

if (Test-Path $IniExample) {
    Copy-Item $IniExample (Join-Path $PayloadDir "ApiConfig.ini.example") -Force
} else {
    Write-Warning "ApiConfig.ini.example não encontrado em Deploy\"
}

$ExeDir = Split-Path $ExePath -Parent
foreach ($dll in @("ib_util.dll", "msvcp140.dll", "vcruntime140.dll")) {
    $src = Join-Path $ExeDir $dll
    if (Test-Path $src) {
        Copy-Item $src $PayloadDir -Force
        Write-Host "Incluído: $dll (pasta do exe)"
    }
}

$fbCopied = $false
$deployFb = Join-Path $Root "Deploy\fbclient.dll"
if (Copy-FbClientX86 -SourcePath $deployFb -DestDir $PayloadDir -Label "api_horse\Deploy") {
    $fbCopied = $true
} else {
    $exeFb = Join-Path $ExeDir "fbclient.dll"
    if (Copy-FbClientX86 -SourcePath $exeFb -DestDir $PayloadDir -Label "pasta do exe") {
        $fbCopied = $true
    }
}

if (-not $fbCopied -and -not $SkipFirebird) {
    $fbDll = Find-FirebirdFbClientX86
    if ($fbDll) {
        if (Copy-FbClientX86 -SourcePath $fbDll -DestDir $PayloadDir -Label "Firebird") {
            $fbCopied = $true
        }
    }
}

if (-not $fbCopied) {
    Write-Warning @"
fbclient.dll x86 NÃO incluído no pacote.
Coloque fbclient.dll Win32 em api_horse\Deploy\ ou informe -FirebirdDir com instalação Firebird 32-bit.
NÃO use C:\Program Files\Firebird\... 64-bit — ApiRFeedWindows é Win32.
"@
} elseif (Test-Path (Join-Path $PayloadDir "fbclient.dll")) {
    $arch = Get-DllMachineType (Join-Path $PayloadDir "fbclient.dll")
    Write-Host "Verificado payload fbclient.dll: $arch"
}

Get-ChildItem $PayloadDir | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "Payload pronto: $PayloadDir"
