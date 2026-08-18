# FieldPec Online (opção A)

API nuvem com o **mesmo contrato** da Horse FieldPec + Postgres, e um **conector** no escritório que liga o FieldPec local à nuvem.

O **FieldTrato não muda**: Backend = `FieldPec`, só aponta Host/Porta para a API online.

```text
FieldPec (Firebird) ←→ Horse local :3001
         ↑↓ conector (escritório)
API FieldPec Online + Postgres (nuvem)
         ↑↓
FieldTrato (fazenda) — mesma sync de sempre
```

## Pastas

| Pasta | Função |
|--------|--------|
| `api/` | API REST compatível com FieldTrato (GET bootstrap + POST operacional) |
| `connector/` | Serviço/web no escritório: sobe master, puxa fab/fornec de volta |
| `sql/` | Schema + create database |
| `deploy/` | Empacota e instala a API no servidor online |
| `docker-compose.yml` | Postgres + API local para teste |

Guia de publicação da API: **[DEPLOY_API.md](./DEPLOY_API.md)**

```powershell
cd fieldpec_online\deploy
.\Pack-ApiDeploy.ps1
# Envie dist\fieldpec-online-api-*.zip ao servidor
```

**No servidor (CMD — Prompt de Comando):**

```bat
cd /d C:\ApiFieldTratoAndroid
deploy\windows\Install-Api.cmd 3111 "postgres://fieldpec:SUA_SENHA@127.0.0.1:5432/fieldpec_online" "TOKEN_FORTE"
deploy\windows\Start-Api.cmd
```

**No servidor (PowerShell — uma linha só):**

```powershell
cd C:\ApiFieldTratoAndroid
.\deploy\windows\Install-Api.ps1 -Port 3111 -DatabaseUrl 'postgres://fieldpec:SUA_SENHA@127.0.0.1:5432/fieldpec_online' -AdminToken 'TOKEN_FORTE'
.\deploy\windows\Start-Api.ps1
```


## 1) Criar o banco no servidor

No servidor com PostgreSQL instalado (cliente `psql` no PATH):

**Windows (PowerShell):**
```powershell
cd fieldpec_online\scripts
$env:PGPASSWORD = 'senha_do_superuser_postgres'
.\Create-Database.ps1
# Produção:
# .\Create-Database.ps1 -PgHost 127.0.0.1 -DbPassword 'SenhaForte!'
```

**Linux:**
```bash
cd fieldpec_online/scripts
chmod +x create-database.sh
export PGPASSWORD='senha_do_superuser_postgres'
./create-database.sh
# Produção:
# DB_PASSWORD='SenhaForte!' ./create-database.sh
```

Isso cria a role `fieldpec`, o database `fieldpec_online` e aplica `sql/schema.sql`.

SQL manual (só role+DB): `sql/create_database.sql` — depois `psql -U fieldpec -d fieldpec_online -f sql/schema.sql`.

## 2) Subir API + Postgres

```bash
cd fieldpec_online
docker compose up -d
```

Ou sem Docker (banco já criado no passo 1):

```bash
cd api
cp .env.example .env
npm install
# Se o schema ainda não foi aplicado: npm run db:init
npm start
```

Health do tablet: `GET /GetTeste`  
Admin: `GET /admin/health` (token em rotas `/admin/sync/*`)

## 2) FieldTrato na fazenda

Em **Configurações**:

- Backend: **FieldPec** (não cria opção “Online”)
- Host: hostname/IP da API nuvem
- Porta: porta publicada (ex. `3001` ou `443` atrás de reverse proxy)

## 3) Conector no escritório

Requisitos: Horse local rodando contra o Firebird do FieldPec.

```bash
cd connector
cp .env.example .env
# Ajuste LOCAL_HORSE_URL, CLOUD_API_URL, ADMIN_TOKEN
npm install
npm start
```

Abra `http://localhost:3080`:

1. **Testar conexões** — Horse local + API nuvem  
2. **Sincronizar agora** — push cadastros/previsão → nuvem; pull fab/fornec → POST no Horse local  

Sync automática a cada `SYNC_INTERVAL_SEC` (default 120).

### Variáveis do conector

| Variável | Significado |
|----------|-------------|
| `LOCAL_HORSE_URL` | Horse FieldPec no escritório |
| `CLOUD_API_URL` | API FieldPec Online |
| `ADMIN_TOKEN` | Mesmo token da API (`ADMIN_TOKEN`) |
| `ID_FAZENDA` | Opcional, para GETs com id na URL |
| `REPLAY_TO_LOCAL` | `1` = reenvia POST ao Horse ao puxar da nuvem |

## Endpoints principais (API)

Compatíveis com o app:

- `GET /fazenda/get`, `/usuarios/get`, `/baias/get`, `/dietas/get`, `/dietas_detalhes/get`, `/previsao_trato/get`, `/vagao/get`
- `POST /Post/Fabricacao`, `/Post/Fornecimento`, `/Post/GravaTag`, audits, GPS

Admin (Bearer `ADMIN_TOKEN`):

- `POST /admin/sync/master` — upsert cadastros/previsão  
- `GET /admin/sync/pending` — fab/fornec ainda não baixados no FieldPec  
- `POST /admin/sync/ack` — marca como puxados  

## Fluxo operacional

1. Escritório: lançamentos no FieldPec → Horse local.  
2. Conector sobe master para a nuvem.  
3. Tablet sincroniza com a nuvem (offline depois).  
4. Tablet sobe fabricação/fornecimento para a nuvem.  
5. Conector puxa pendentes e dá `POST` no Horse local → FieldPec.

## Segurança (produção)

- Troque `ADMIN_TOKEN`.  
- Exponha a API só via HTTPS.  
- Restrinja `/admin/*` (VPN ou IP allowlist).  
- Não use a senha default do Postgres do compose.

## Limitações do MVP

- Replay para o FieldPec depende do Horse local aceitar os mesmos POSTs (mesmo contrato).  
- Previsão no Horse FieldPec costuma ser do dia (`CURRENT_DATE`); o conector reenvia o que o GET local devolver.  
- Multi-tenant: coluna `cliente_codigo` em todas as tabelas + cadastro em `/admin` (Clientes).
  Conector usa `CLIENT_CODE`; FieldTrato usa `CLIENTE_CODIGO` (header `X-Client-Code`).
  Dados antigos migram para o código `DEMO` via `sql/migrate_tenant.sql` (`npm run db:init`).
- Dashboards Horse (`/dashboard/*`) não foram portados.
