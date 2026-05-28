# API Horse (CG Pec) — RFeed

API REST em **Delphi + Horse** para o CG Pec (Firebird). Prioridade de deploy no cliente: um executável + `ApiConfig.ini`, sem Node/PostgreSQL.

## Estrutura

| Pasta | Uso |
|--------|-----|
| `CGPec/Source/` | Projeto Delphi (`dpr/ApiRFeed.dpr`), controllers, DM |
| `ServicoWindows/` | Variante serviço Windows |
| `installer/` | Instalador Inno Setup + scripts de serviço |
| `Deploy/` | Saída de build: copiar `ApiRFeed.exe` + `ApiConfig.ini` |

## Configuração

1. Copie `Deploy/ApiConfig.ini.example` → `Deploy/ApiConfig.ini` **ou** use o painel `/config` e **Salvar** (cria/atualiza o arquivo completo).
2. Formato gravado:

```ini
[CGPEC]
Server=127.0.0.1
User=SYSDBA
Password=masterkey
Port=3055
DB=C:\caminho\CGP_4_MALU.FDB

[POSTGRES]
Host=127.0.0.1
Port=5432
Database=rfeed_web
User=postgres
Password=postgres
Enabled=1
```

## Build (Delphi)

- **Executável:** `CGPec/Source/dpr/ApiRFeed.dproj` → Release Win32 → `Deploy/`
- **Serviço Windows:** `ServicoWindows/ApiRFeedWindows.dproj` → Release Win32 (post-build copia `web-admin\`)

## Instalador para o cliente (serviço)

Gera `RFeedApiHorse-Setup-1.0.0.exe` com exe, `web-admin`, `ApiConfig.ini`, serviço e firewall.

```powershell
cd api_horse\scripts
.\Build-Installer.ps1 -ExePath "C:\caminho\Win32\Release\ApiRFeedWindows.exe"
```

O instalador embute `Deploy\fbclient.dll` (**x86**). Não use a DLL 64-bit de `Program Files\Firebird`.

Detalhes: [installer/README.md](installer/README.md)

## Painel web (mesma UX da next-api)

Com a API rodando (`ApiRFeed.exe` ou serviço Windows):

| URL | Função |
|-----|--------|
| http://127.0.0.1:3001/config | Firebird + PostgreSQL + **monitor ao vivo** (rodapé da página) |
| http://127.0.0.1:3001/monitor | **Monitor ao vivo** do tablet (tela cheia; também `/requests`) |
| http://127.0.0.1:3001/health | Testar rotas GET/POST/PUT |

Logs gravados em `%ProgramData%\RFeed\logs\api-monitor\requests-YYYYMMDD.jsonl`.

Ao iniciar o app desktop, o navegador abre `/config` automaticamente.

**Deploy:** o painel é lido de `web-admin\` **na pasta do `.exe`** (não fica embutido no exe). Após alterar HTML no Git, copie ou recompile (post-build copia para `Deploy\`):

```powershell
cd api_horse\scripts
.\Copy-WebAdmin.ps1 -TargetDir "C:\ApiRFeed\Deploy"   # pasta onde está seu ApiRFeed.exe
```

No navegador use **Ctrl+F5** em `/config` para evitar cache.

## PostgreSQL (criar banco e tabelas)

Script PowerShell (requer `psql` no PATH):

```powershell
cd api_horse\scripts
.\Init-Postgres-RFeed.ps1 -Interactive
```

Ou com parâmetros:

```powershell
.\Init-Postgres-RFeed.ps1 -PgSuperPassword "sua_senha" -AppDatabase "rfeed_web"
```

Cria o banco `rfeed_web` (se não existir) e aplica `next-api/database/rfeed-pg-schema.sql` (`import_*` + `imp_*` para planilha e espelho BI).

Só reaplicar tabelas em banco existente: `.\Init-Postgres-RFeed.ps1 -SchemaOnly -PgSuperPassword "..."`


O app aponta para a URL base da API (mesmas rotas que a next-api). Em campo, use o IP da máquina onde a API Horse estiver rodando (porta **3001**).

## Espelho PostgreSQL (BI) — igual next-api

Cada GET/POST de sincronização pode ser espelhado nas tabelas `imp_*` do Postgres **em background**, sem atrasar a resposta ao tablet.

1. **next-api** rodando na mesma máquina (porta 3001). Ao salvar no painel Horse, o PostgreSQL é sincronizado automaticamente para a next-api (`activeClient` = **cgpec**).
2. No `ApiConfig.ini` do Horse:

```ini
[MIRROR]
Enabled=1
Url=http://127.0.0.1:3001/api/mirror/event
```

A Horse enfileira o pacote e um thread envia para `POST /api/mirror/event`, que reutiliza a mesma lógica `import-warehouse-sync` da next-api.

## GPS (trilhas do tablet)

O app envia lotes em `POST /Post/GpsTrack` (sessão + pontos + geo dos currais). A Horse valida, responde `200` e espelha o body para a next-api, que grava em `gps_track_session`, `gps_track_point` e `curral_geo` no Postgres.

Consultas para o front Next:

| Rota | Uso |
|------|-----|
| `GET /api/gps/sessions?idFazenda=&kind=&dataIni=&dataFim=` | Lista sessões |
| `GET /api/gps/tracks?sessionId=` | Polyline / pontos |
| `GET /api/gps/currais?idFazenda=` | Última posição por curral |

## next-api

A pasta `next-api/` permanece no repositório (BI/web, Postgres). Para instalação simples no cliente, prefira **api_horse** + next-api só para espelho/BI (pode rodar como serviço na mesma VM).
