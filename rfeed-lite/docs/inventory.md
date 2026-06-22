# Fase 1 — Inventário do RFeed

Análise da estrutura existente em `c:\RSistemas\Git\RFeedFlutter` para planejar extração do RFeed Lite.

---

## 1.1 Estrutura raiz do projeto

```
RFeedFlutter/
├── lib/                    # App Flutter principal (RFeedX)
├── android/, ios/, ...     # Targets Flutter
├── api_horse/              # API Delphi Horse (CG Pec / FieldPec)
├── rfeed_pa/               # App pá carregadeira (espelho TCP)
├── docs/                   # Manuais operacionais
├── scripts/                # Build APK
├── next-api/               # (gitignored) Next.js BI — referência apenas
└── rfeed-lite/             # ← NOVO: plano de extração (este folder)
```

---

## 1.2 Tabela de inventário — Componentes

| Componente | Localização | Reaproveitamento (%) | Observação |
|------------|-------------|----------------------|------------|
| **Splash / boot** | `lib/pages/splash_page.dart` | 70% | Adaptar rota inicial e checagem de config |
| **Configuração** | `lib/pages/config_page.dart`, `lib/repo/config_repo.dart` | 40% | Remover CG Pec/FieldPec; adicionar URL SaaS + tenant |
| **Login** | `lib/pages/login_page.dart`, `lib/services/session_service.dart` | 50% | Trocar auth local por JWT remoto + cache offline |
| **Menu principal** | `lib/pages/menu_page.dart` | 60% | Remover estacionário/WiFi guard específicos |
| **Sync** | `lib/pages/sync_page.dart` | 45% | Novo pipeline NestJS; manter UX de progresso |
| **Grava tag RFID** | `lib/pages/grava_tag_page.dart`, `lib/repo/grava_tag_repo.dart` | 75% | CRUD tags → API Lite |
| **Fabricação — lista** | `lib/features/fabricacao/ui/fabricacao_list_page.dart` | 65% | Filtro data, status; desacoplar CG Pec |
| **Fabricação — nova** | `lib/features/fabricacao/ui/fabricacao_prefab_page.dart` | 70% | Previsão por trato; manter UX |
| **Fabricação — pesagem** | `lib/features/fabricacao/ui/fabricacao_weigh_page.dart` | 75% | Core operacional; forte reuso |
| **Fabricação — timer mistura** | `lib/features/fabricacao/ui/mistura_timer_page.dart` | 90% | Independente de ERP |
| **Fabricação — controller** | `lib/features/fabricacao/controller/fabricacao_controller.dart` | 55% | Remover mirror/estacionário; manter balança |
| **Fabricação — repo** | `lib/features/fabricacao/data/fabricacao_repo.dart` | 35% | SQL CG Pec-specific; reescrever queries |
| **Fabricação — create** | `lib/features/fabricacao/services/fabricacao_create_service.dart` | 50% | Lógica de ingredientes reutilizável |
| **Fornecimento — lista** | `lib/features/fornecimento/ui/fornecimento_list_page.dart` | 60% | Carregamento + trato |
| **Fornecimento — pré** | `lib/features/fornecimento/ui/fornecimento_pre_page.dart` | 70% | Setup por curral |
| **Fornecimento — pesagem** | `lib/features/fornecimento/ui/fornecimento_weigh_page.dart` | 75% | Mapa + balança + RFID |
| **Fornecimento — dashboard** | `lib/features/fornecimento/ui/fornecimento_dashboard_page.dart` | 55% | Mapa horizontal; adaptar dados |
| **Fornecimento — BI** | `lib/features/fornecimento/ui/fornecimento_bi_page.dart` | 30% | Depende de agregações server-side |
| **Fornecimento — controller** | `lib/features/fornecimento/controller/fornecimento_controller.dart` | 60% | Histerese, RFID, peso início/fim |
| **Fornecimento — repo/dao** | `lib/features/fornecimento/data/*` | 35% | Schema SQLite acoplado ao CG Pec |
| **Dashboard unificado** | `lib/features/dashboard/` | 25% | Reescrever com API NestJS |
| **Estacionário** | `lib/features/estacionario/` | **0%** | Fora de escopo Lite MVP |
| **Mirror PA** | `lib/helpers/mirror_service.dart`, `rfeed_pa/` | **0%** | Produto caminhão+PA exclusivo |
| **ApiService** | `lib/services/api_service.dart` | 25% | Endpoints Horse-specific |
| **OutboxSync** | `lib/services/outbox_sync.dart` | 50% | Padrão outbox reutilizável |
| **BootstrapSync** | `lib/services/bootstrap_sync.dart` | 40% | Download master data; novos endpoints |
| **SyncOrchestrator** | `lib/services/sync_orchestrator.dart` | 60% | Ordem upload→download mantida |
| **Auditoria fornecimento** | `lib/services/fornecimento_audit_service.dart` | 70% | Upload JSON audit → S3/API |
| **Config backup disco** | `lib/services/config_disk_backup.dart` | 80% | Utilitário genérico |
| **WiFi guard** | `lib/services/wifi_guard.dart` | 20% | Só necessário se mantiver estacionário |
| **ScaleComm** | `lib/helpers/scale_comm.dart` | **95%** | TCP Topcom/DG500/Alfa — copiar quase intacto |
| **RfidComm** | `lib/helpers/rfid_comm.dart` | **95%** | TCP EPC — copiar quase intacto |
| **BalancaParser** | `lib/features/fornecimento/services/balanca_parser.dart` | **90%** | Parsers de peso |
| **ScaleTcpService** | `lib/features/fornecimento/services/scale_tcp_service.dart` | 70% | Wrapper fino sobre ScaleComm |
| **RfidTcpService** | `lib/features/fornecimento/services/rfid_tcp_service.dart` | 70% | Wrapper fino sobre RfidComm |
| **MS percent utils** | `lib/utils/ms_percent.dart` | **85%** | Validação MS 0–100 |
| **SQLite AppDb** | `lib/db/app_db.dart` | 30% | v9 schema; migrar para Lite schema |
| **Widgets compartilhados** | `lib/widgets/scale_peso_highlight_card.dart`, `app_version_label.dart` | 85% | UI genérica |
| **API Horse — GET** | `api_horse/CGPec/Source/Controllers/Controllers.Get.pas` | 0% | Referência de contrato |
| **API Horse — POST** | `api_horse/CGPec/Source/Controllers/Controllers.Post.pas` | 0% | Referência de regras MS/acumulativo |
| **API Horse — Admin** | `api_horse/CGPec/Source/Controllers/Controllers.Admin.pas` | 10% | UX web-admin como inspiração |
| **Web-admin HTML** | `api_horse/web-admin/*.html` | 15% | Migrar para React/Next no Lite web |
| **BiMirror** | `api_horse/CGPec/Source/BiMirror/UBiMirror.pas` | 0% | Substituído por NestJS direto |
| **FieldPec** | `api_horse/FieldPec/` | 0% | Variante Firebird; não aplicável |

---

## 1.3 Telas mapeadas (Flutter)

| # | Tela | Rota | Arquivo |
|---|------|------|---------|
| 1 | Splash | `/` | `lib/pages/splash_page.dart` |
| 2 | Configuração | `/config` | `lib/pages/config_page.dart` |
| 3 | Login | `/login` | `lib/pages/login_page.dart` |
| 4 | Menu | `/menu` | `lib/pages/menu_page.dart` |
| 5 | Sync | `/sync` | `lib/pages/sync_page.dart` |
| 6 | Sobre | `/about` | `lib/pages/about_page.dart` |
| 7 | Grava Tag | `/grava-tag` | `lib/pages/grava_tag_page.dart` |
| 8 | Fab — lista | `/fabricacao` | `lib/features/fabricacao/ui/fabricacao_list_page.dart` |
| 9 | Fab — nova | `/fabricacao/nova` | `lib/features/fabricacao/ui/fabricacao_prefab_page.dart` |
| 10 | Fab — pesagem | `/fabricacao/pesagem` | `lib/features/fabricacao/ui/fabricacao_weigh_page.dart` |
| 11 | Fab — dashboard | (push) | `lib/features/fabricacao/ui/fabricacao_dashboard_page.dart` |
| 12 | Fab — timer mistura | (push) | `lib/features/fabricacao/ui/mistura_timer_page.dart` |
| 13 | Forn — lista | `/fornecimento` | `lib/features/fornecimento/ui/fornecimento_list_page.dart` |
| 14 | Forn — pré | `/fornecimento/pre` | `lib/features/fornecimento/ui/fornecimento_pre_page.dart` |
| 15 | Forn — pesagem | `/fornecimento/pesagem` | `lib/features/fornecimento/ui/fornecimento_weigh_page.dart` |
| 16 | Forn — dashboard | (push) | `lib/features/fornecimento/ui/fornecimento_dashboard_page.dart` |
| 17 | Forn — BI | (push) | `lib/features/fornecimento/ui/fornecimento_bi_page.dart` |
| 18 | Dashboard unificado | `/dashboard` | `lib/features/dashboard/ui/dashboard_unificado_page.dart` |
| 19 | Estacionário | `/carregamento-estacionario` | `lib/features/estacionario/ui/...` (**excluir Lite**) |

---

## 1.4 Serviços e repositórios

### Camada global (`lib/services/`, `lib/repo/`)

| Tipo | Arquivos | Função |
|------|----------|--------|
| HTTP | `api_service.dart` | Cliente Dio → Horse |
| Sync upload | `outbox_sync.dart` | FLAG_SYNC=0 → POST |
| Sync download | `bootstrap_sync.dart` | GET → SQLite |
| Orquestração | `sync_orchestrator.dart` | Pipeline ordenado |
| Sessão | `session_service.dart`, `session_repo.dart` | SharedPreferences |
| Config | `config_repo.dart` | Tabela CONFIG SQLite |
| Master data | `user_repo`, `fazenda_repo`, `dieta_repo`, `vagao_repo` | CRUD local |
| Audit | `fornecimento_audit_service.dart` | POST audit JSON |

### Camada feature

| Feature | Controllers | Repos/Data | Services |
|---------|-------------|------------|----------|
| Fabricação | `fabricacao_controller.dart` | `fabricacao_repo.dart`, `fabricacao_dashboard_repo.dart` | `fabricacao_create_service.dart` |
| Fornecimento | `fornecimento_controller.dart`, `fornecimento_dashboard_controller.dart` | `fornecimento_repo.dart`, `fornecimento_dao.dart`, `carregamento_dao.dart` | `scale_tcp_service`, `rfid_tcp_service`, `balanca_parser`, `fornecimento_api` |

---

## 1.5 Banco local SQLite (RFeed v9)

**Arquivo:** `rfeed_app.db` — **versão 9** (`lib/db/app_db.dart`)

| Grupo | Tabelas |
|-------|---------|
| Config | `CONFIG`, `ULTIMO_LOGIN`, `ESTACIONARIO_REDE` |
| Cadastro | `CADASTRO_USUARIO`, `CADASTRO_FAZENDAS`, `VAGAO`, `DIETA`, `DETALHES_DIETAS`, `DETALHES_BAIAS`, `GRAVA_TAG` |
| Previsão | `PREVISAO` (PK composta: ID_FORNECIMENTO, DATA, ID_BAIA, TRATO) |
| Fabricação | `CADASTRO_FABRICA_RACAO`, `DETALHES_FABRICA_RACAO` |
| Fornecimento | `CADASTRO_FORNECIMENTO`, `CARREGAMENTO` |

**Lite:** novo schema com `tenant_id`, `sync_status`, `server_id`, tabela `evento_geo`.

---

## 1.6 Sincronização (padrão atual)

```
SyncPage → SyncOrchestrator
  1. GET /GetTeste
  2. Upload: GRAVA_TAG → FABRICAÇÃO → FORNECIMENTO (OutboxSync)
  3. Download: usuarios → baias → dietas → detalhes → previsão (BootstrapSync)
```

Campos de controle: `FLAG_SYNC`, `SYNC` (tags). Formato decimal BR (vírgula) nos POSTs.

---

## 1.7 GPS / Geolocalização (estado atual)

| Item | Status no RFeed |
|------|-----------------|
| Trilha contínua | `POST /Post/GpsTrack` → espelho next-api → Postgres |
| Geo abrir/finalizar fab | **Não implementado** no tablet |
| Geo abrir/finalizar forn | **Não implementado** no tablet |
| Permissão location | Usada para **WiFi SSID** (`wifi_guard.dart`), não GPS |

**Lite:** implementar geo nos 4 marcos operacionais (requisito novo).

---

## 1.8 Integrações hardware

| Hardware | Protocolo | Arquivo principal | Modelos |
|----------|-----------|-------------------|---------|
| Balança | TCP socket | `lib/helpers/scale_comm.dart` | Topcom, DG500, Alfa, Raw |
| RFID | TCP socket | `lib/helpers/rfid_comm.dart` | Leitor genérico EPC |
| Config | SQLite CONFIG | `HOST_BALANCA`, `PORTA_BALANCA`, `HOST_RFID`, `PORTA_RFID` | — |

Modo manual: telas aceitam input numérico sem hardware conectado.

---

## 1.9 APIs backend (Horse — referência)

### GET (download)

| Endpoint | Dados |
|----------|-------|
| `/GetTeste` | Health |
| `/fazenda/get` | Fazendas |
| `/usuarios/get/:idfazenda` | Usuários |
| `/baias/get/:idfazenda` | Currais/baias + RFID |
| `/dietas/get/:idfazenda` | Dietas |
| `/dietasdetalhes/get/:idfazenda` | Ingredientes |
| `/previsaotrato/get/:idfazenda/:data` | Previsão |
| `/vagao/get` | Vagões/equipamentos |

### POST (upload)

| Endpoint | Dados |
|----------|-------|
| `/Post/Fabricacao` | Cabeçalho fabricação |
| `/Post/Fabricacao_Insumo` | Ingredientes pesados |
| `/Post/Fornecimento` | Entrega por curral |
| `/Post/GravaTag` | Associação RFID ↔ curral |
| `/Post/GpsTrack` | Trilha GPS |
| `/Post/FornecimentoAudit` | Dump JSON auditoria |

---

## 1.10 Classificação consolidada

| Categoria | Ação no Lite |
|-----------|--------------|
| **Reutilizar sem alterações** | `scale_comm`, `rfid_comm`, `ms_percent`, widgets UI genéricos, timer mistura |
| **Reutilizar com adaptações** | Telas fab/forn, controllers, outbox pattern, parsers balança |
| **Remover** | Estacionário, mirror PA, FieldPec switch, BiMirror, WiFi guard (MVP) |
| **Reescrever** | ApiService, repos SQL, bootstrap sync, auth, backend inteiro, schema DB |
