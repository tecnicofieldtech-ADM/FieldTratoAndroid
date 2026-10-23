# Conector web FieldPec → API AWS

Roda **na máquina do cliente** (onde está o Firebird do FieldPec).  
A **API** fica na **AWS**. Interface 100% web — configura banco, sobe e baixa dados.

```text
[Cliente]                              [AWS]
Firebird FieldPec (.FDB)
        │
 Conector web :3080  ──HTTPS/HTTP──►  API FieldPec Online :3111
 (config + subir/baixar)                     │
                                      FieldTrato (fazenda)
```

## Instalador .exe (Inno Setup)

Na máquina de desenvolvimento (com [Inno Setup 6](https://jrsoftware.org/isinfo.php)):

```powershell
cd C:\RSistemas\Git\FieldTrato\fieldpec_online\deploy
.\Pack-ConnectorSetup.ps1
```

Gera: `fieldpec_online\dist\FieldPec-Conector-Setup-1.0.0.exe`

No cliente: execute o `.exe` como **Administrador**. O setup instala em `C:\FieldPecConnector`, configura Node/npm, registra o serviço Windows e abre o painel.

## Instalação via ZIP (alternativa)

Na máquina de desenvolvimento, gere o ZIP:

```powershell
cd C:\RSistemas\Git\FieldTrato\fieldpec_online\deploy
.\Pack-ConnectorDeploy.ps1
```

No PC do cliente:

1. Extraia o ZIP  
2. Clique com o botão direito em **`INSTALAR.cmd`** → **Executar como administrador**  
3. O instalador:
   - copia para `C:\FieldPecConnector`
   - instala **Node.js** se faltar
   - roda `npm install`
   - registra o serviço Windows **`FieldPecOnlineConnector`** (NSSM, sobe com o Windows)
   - inicia o serviço e abre **http://127.0.0.1:3080**

Desinstalar: `deploy\connector\Uninstall-Connector.ps1` (atalho no Menu Iniciar).

### Instalação manual (alternativa)

1. Extraia o ZIP do conector  
2. Node.js 18+ instalado  
3. Firebird client (`fbclient.dll`) no PATH se necessário  

```powershell
cd C:\FieldPecConnector\connector
copy .env.example .env
npm install
npm start
```

Abra: **http://localhost:3080**

## Na tela web

| Aba | Função |
|-----|--------|
| **Subir / Baixar** | Botões Subir (FieldPec→AWS), Baixar (AWS→pendências), testar conexões |
| **Acompanhar** | Lista fab/fornecimento na nuvem: pendente vs. já baixado ao Field (com insumos da fab) |
| **Configuração** | URL da API AWS, Firebird (.FDB, user, senha), fazenda, intervalo |
| **Status** | Último resultado e config ativa |

Salvar na aba Configuração grava o arquivo `connector/.env`.

## Config mínima

- **CLOUD_API_URL** = `http://IP_AWS:3111` (ou HTTPS do domínio)  
- **SOURCE_MODE** = `firebird`  
- **FB_DATABASE** = caminho do `.FDB` no PC do cliente  
- **ADMIN_TOKEN** = `open` (ou o token da API)  
- **REPLAY_TO_LOCAL** = `1` para o **Baixar** gravar fab/forn direto no Firebird (sem Horse). Use `0` só para consultar a nuvem.

### Baixar → Field

1. Aba **Acompanhar**: veja pendentes (tablet → nuvem).  
2. Configuração: `REPLAY_TO_LOCAL=1` e Salvar.  
3. **Baixar agora** ou **Acompanhar → Enviar para o Field**: grava `FABRICACAO` / `FABRICACAO_INSUMOS` e atualiza `FORNECIMENTO_CONF` no `.FDB`, depois dá ack na nuvem.  
4. Acompanhar: itens passam a **Já no Field**.  

## FieldTrato

Backend **FieldPec** · Host = API AWS · Porta = **3111**
