# Instala e inicia o serviço Windows da API Horse (RFeed).
# Uso: .\install-service.ps1 -InstallDir "C:\Program Files\RSistemas\RFeed\ApiHorse"

param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,

    [string]$ServiceName = "ApiRFeed",
    [string]$DisplayName = "RFeed API Horse",
    [int]$Port = 3001,
    [switch]$SkipFirewall
)

$LogFile = Join-Path $InstallDir "install-service.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    try {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Host $Message
}

try {
    $ErrorActionPreference = "Stop"
    $InstallDir = $InstallDir.TrimEnd('\')
    $ExePath = Join-Path $InstallDir "ApiRFeedWindows.exe"

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }

    Write-Log "InstallDir: $InstallDir"

    if (-not (Test-Path $ExePath)) {
        throw "Executável não encontrado: $ExePath"
    }

    if (-not (Test-Path (Join-Path $InstallDir "web-admin\config.html"))) {
        throw "Painel web não encontrado em: $InstallDir\web-admin"
    }

    $IniExample = Join-Path $InstallDir "ApiConfig.ini.example"
    $IniPath = Join-Path $InstallDir "ApiConfig.ini"
    if (-not (Test-Path $IniPath) -and (Test-Path $IniExample)) {
        Copy-Item $IniExample $IniPath
        Write-Log "Criado ApiConfig.ini a partir do exemplo."
    }

    # Remove serviço antigo (se existir)
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "Removendo serviço existente '$ServiceName'..."
        if ($existing.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
        & $ExePath /uninstall 2>&1 | ForEach-Object { Write-Log $_ }
        Start-Sleep -Seconds 1
        & sc.exe delete $ServiceName 2>&1 | ForEach-Object { Write-Log $_ }
        Start-Sleep -Seconds 2
    }

    # Método 1: instalador nativo Delphi (recomendado para TService)
    Write-Log "Instalando via ApiRFeedWindows.exe /install ..."
    $installProc = Start-Process -FilePath $ExePath -ArgumentList "/install" -Wait -PassThru -NoNewWindow
    if ($installProc.ExitCode -ne 0) {
        Write-Log "Aviso: /install retornou código $($installProc.ExitCode). Tentando sc.exe..."
        $scOut = & sc.exe create $ServiceName "binPath= `"$ExePath`"" "start= delayed-auto" "DisplayName= `"$DisplayName`"" 2>&1
        $scOut | ForEach-Object { Write-Log $_ }
        if ($LASTEXITCODE -ne 0) {
            throw "sc.exe create falhou (código $LASTEXITCODE). Saída: $scOut"
        }
        & sc.exe description $ServiceName "API REST RFeed (tablet) porta $Port" 2>&1 | Out-Null
    } else {
        Write-Log "Serviço registrado com /install (Delphi)."
    }

    Start-Sleep -Seconds 1
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        throw "Serviço '$ServiceName' não apareceu no Windows após instalação. Veja $LogFile"
    }
    Write-Log "Serviço encontrado: $($svc.DisplayName) [$($svc.Status)]"

    if (-not $SkipFirewall) {
        try {
            $ruleName = "RFeed API Horse TCP $Port"
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName $ruleName `
                -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
                -ErrorAction Stop | Out-Null
            Write-Log "Firewall: porta $Port liberada."
        } catch {
            Write-Log "Aviso: não foi possível criar regra de firewall: $($_.Exception.Message)"
        }
    }

    try {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Write-Log "Serviço iniciado com sucesso."
    } catch {
        Write-Log "AVISO: serviço instalado mas não iniciou: $($_.Exception.Message)"
        Write-Log "Verifique ApiConfig.ini, fbclient.dll e o Visualizador de Eventos (Application)."
        exit 0
    }

    Write-Log "Painel: http://127.0.0.1:$Port/config"
    exit 0
} catch {
    Write-Log "ERRO: $($_.Exception.Message)"
    exit 1
}
