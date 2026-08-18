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

## Instalação no cliente

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
| **Configuração** | URL da API AWS, Firebird (.FDB, user, senha), fazenda, intervalo |
| **Status** | Último resultado e config ativa |

Salvar na aba Configuração grava o arquivo `connector/.env`.

## Config mínima

- **CLOUD_API_URL** = `http://IP_AWS:3111` (ou HTTPS do domínio)  
- **SOURCE_MODE** = `firebird`  
- **FB_DATABASE** = caminho do `.FDB` no PC do cliente  
- **ADMIN_TOKEN** = `open` (ou o token da API)  
- **REPLAY_TO_LOCAL** = `0` até existir retorno direto ao Firebird  

## FieldTrato

Backend **FieldPec** · Host = API AWS · Porta = **3111**
