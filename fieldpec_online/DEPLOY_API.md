# Deploy da API FieldPec Online (servidor na nuvem)

Pacote com a API Node + scripts de instalação. O banco Postgres já deve existir
(use `scripts/Create-Database.ps1` ou `scripts/create-database.sh`).

## O que enviar ao servidor

Na máquina de desenvolvimento:

```powershell
cd C:\RSistemas\Git\FieldTrato\fieldpec_online\deploy
.\Pack-ApiDeploy.ps1
```

Gera: `fieldpec_online\dist\fieldpec-online-api-YYYYMMDD-HHMM.zip`

Envie o ZIP ao servidor e extraia (ex.: `C:\FieldPecOnline` ou `/opt/fieldpec-online`).

Conteúdo do pacote:

```text
api/                 código da API
sql/                 schema (já aplicado se o banco foi criado)
deploy/windows/      instalação Windows
deploy/linux/        instalação Linux
DEPLOY_API.md
LEIA-ME.txt
```

## Pré-requisitos no servidor

1. **PostgreSQL** com banco `fieldpec_online` e usuário `fieldpec` (já criado).
2. **Node.js 18+** ([nodejs.org](https://nodejs.org) ou pacote da distro).
3. Firewall liberando a porta da API (ex. **3001**), ou reverse proxy HTTPS (443).

## Windows

Use o **Prompt de Comando (CMD)** ou o **PowerShell**. Não cole o comando com `` ` `` no CMD — isso é continuação de linha só do PowerShell.

### Opção A — CMD (mais simples)

```bat
cd /d C:\ApiFieldTratoAndroid

deploy\windows\Install-Api.cmd 3111 "postgres://fieldpec:SUA_SENHA@127.0.0.1:5432/fieldpec_online" "TOKEN_FORTE"

deploy\windows\Start-Api.cmd
```

### Opção B — PowerShell (uma linha, sem `` ` ``)

```powershell
cd C:\ApiFieldTratoAndroid
.\deploy\windows\Install-Api.ps1 -Port 3111 -DatabaseUrl 'postgres://fieldpec:SUA_SENHA@127.0.0.1:5432/fieldpec_online' -AdminToken 'TOKEN_FORTE'
.\deploy\windows\Start-Api.ps1
```

Teste:

```bat
curl http://127.0.0.1:3111/GetTeste
```

Ou no PowerShell: `Invoke-RestMethod http://127.0.0.1:3111/GetTeste`

Instalar como serviço (sobe com o Windows) — precisa do [NSSM](https://nssm.cc/download):

```powershell
.\deploy\windows\Install-Service.ps1 -NssmPath C:\Tools\nssm\win64\nssm.exe
```

Remover serviço: `.\deploy\windows\Uninstall-Service.ps1`


## Linux

```bash
cd /opt/fieldpec-online
sudo bash deploy/linux/install-api.sh \
  --port 3001 \
  --database-url 'postgres://fieldpec:SUA_SENHA@127.0.0.1:5432/fieldpec_online' \
  --token 'TOKEN_FORTE_AQUI'
```

```bash
curl http://127.0.0.1:3001/GetTeste
systemctl status fieldpec-online-api
```

## Configuração (`api/.env`)

| Variável | Exemplo | Uso |
|----------|---------|-----|
| `PORT` | `3001` | Porta HTTP |
| `HOST` | `0.0.0.0` | Escuta em todas as interfaces |
| `DATABASE_URL` | `postgres://fieldpec:Senha@127.0.0.1:5432/fieldpec_online` | Banco |
| `ADMIN_TOKEN` | token longo | Conector / rotas `/admin/*` |

## Painel web (homologação)

Com a API no ar abra:

```text
http://IP:3111/admin/ui/
```

(ou `http://IP:3111/` — redireciona)

| Aba | Função |
|-----|--------|
| Checklist | O que falta antes do FieldTrato |
| Configuração | Edita `api/.env` (PORT, DB, token) |
| Testar métodos | GET/POST do contrato Horse |
| Conferência | Vê cadastros e fab/fornecimento recebidos |
| Logs | Histórico das requisições |

## FieldTrato (fazenda)

- Backend: **FieldPec**
- Host: IP ou domínio do servidor
- Porta: `3001` (ou `443` se usar HTTPS no proxy)

## Conector (escritório)

No `.env` do conector:

```env
CLOUD_API_URL=http://IP_OU_DOMINIO:3001
ADMIN_TOKEN=TOKEN_FORTE_AQUI
```

## HTTPS (recomendado)

Coloque nginx/Caddy/IIS na frente apontando para `http://127.0.0.1:3001` e publique 443.
O FieldTrato usa Host + Porta; com HTTPS normalmente Host=`api.seudominio.com` e Porta=`443`.

## Checklist rápido

- [ ] `GET /GetTeste` responde OK
- [ ] `GET /admin/health` (sem token) responde ok
- [ ] `GET /admin/stats` com `Authorization: Bearer TOKEN` responde JSON
- [ ] Postgres acessível só na rede interna / localhost
- [ ] `ADMIN_TOKEN` diferente do default
- [ ] Porta liberada no firewall / security group
