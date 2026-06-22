# Instalador — RFeed API Horse (serviço Windows)

Gera um **setup.exe** para o cliente com:

- `ApiRFeedWindows.exe` (serviço)
- `web-admin\` (painel `/config`, `/monitor`, `/health`)
- `ApiConfig.ini.example` (vira `ApiConfig.ini` na 1ª instalação)
- `fbclient.dll` **Win32 (x86)** de `api_horse\Deploy\` (obrigatório para o serviço)
- Instalação do serviço **ApiRFeed** + regra de firewall TCP **3001**
- Atalhos no menu Iniciar

## Pré-requisitos (máquina de build)

1. Compilar **ApiRFeedWindows** em **Release | Win32**.
2. [Inno Setup 6](https://jrsoftware.org/isdl.php) (opcional; sem ele, use só o `payload` manual).

## Gerar o instalador

```powershell
cd c:\RSistemas\Git\RFeedFlutter\api_horse\scripts

# Usa api_horse\Deploy\fbclient.dll (x86) automaticamente
.\Build-Installer.ps1

# Ou informe o .exe manualmente:
.\Build-Installer.ps1 -ExePath "C:\...\Win32\Release\ApiRFeedWindows.exe"
```

**`fbclient.dll`:** o serviço **ApiRFeedWindows** é compilado em **Win32 (x86)**. O payload usa `api_horse\Deploy\fbclient.dll`. Não use a DLL de `C:\Program Files\Firebird\...` (64-bit) — gera erro *Library has unsupported architecture [x64]. Required [x86]*. Fallback opcional: `-FirebirdDir` apontando para Firebird **32-bit** (`Program Files (x86)\Firebird\...`).

Saída: `api_horse\installer\output\RFeedApiHorse-Setup-1.0.0.exe`

## Só montar payload (sem Inno)

```powershell
.\Stage-InstallerPayload.ps1 -ExePath "C:\...\ApiRFeedWindows.exe"
```

Copie `installer\payload` + `install-service.ps1` para o servidor e execute:

```powershell
.\install-service.ps1 -InstallDir "C:\Program Files\RSistemas\RFeed\ApiHorse"
```

## No cliente

| Item | Valor |
|------|--------|
| Pasta padrão | `C:\Program Files\RSistemas\RFeed\ApiHorse` |
| Serviço | `ApiRFeed` (exibição: RFeed API Horse) |
| Painel | http://127.0.0.1:3001/config |
| Config | `ApiConfig.ini` na pasta de instalação |

Após instalar, edite Firebird/PostgreSQL no painel ou no INI e **reinicie o serviço** se trocar `ActiveClient` (CGPec ↔ FieldPec).

### Corrigir `fbclient.dll` x64 na instalação existente

Se o serviço falhar com *unsupported architecture [x64]. Required [x86]*, copie a DLL do repositório (PowerShell **como administrador**):

```powershell
Copy-Item "C:\RSistemas\Git\RFeedFlutter\api_horse\Deploy\fbclient.dll" `
  "C:\Program Files\RSistemas\RFeed\ApiHorse\fbclient.dll" -Force
Restart-Service ApiRFeed
```

## Desinstalar

Painel “Adicionar ou remover programas” **ou**:

```powershell
cd "C:\Program Files\RSistemas\RFeed\ApiHorse"
.\uninstall-service.ps1
```
