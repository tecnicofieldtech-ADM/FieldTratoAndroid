# Manual — modo Planilha (FieldTrato)

Este guia explica **como funciona** a importação de planilha, **o que instalar no cliente** e o **passo a passo** do escritório até o tablet na fazenda.

O modo Planilha é uma opção do FieldTrato **sem FieldPec e sem TGC**. Os cadastros (fazenda, usuários, vagão, currais, dietas e previsão do trato) entram por um arquivo Excel (`.xlsx`). O tablet baixa esses dados, opera offline e devolve fabricação e fornecimento para a mesma API. Depois você exporta o resultado em outra planilha.

---

## 1. O que é o modo Planilha

No FieldTrato existem três backends:

| No tablet | Valor interno | Origem dos cadastros |
|-----------|---------------|----------------------|
| FieldPec | 0 | API Horse / FieldPec Online |
| Outros (TGC) | 2 | API TGC |
| **Planilha** | **3** | Excel importado nesta API |

No modo Planilha:

1. O escritório preenche um Excel no layout oficial.
2. O Excel é importado na API (painel `/admin/ui/`).
3. A API guarda os cadastros no **PostgreSQL** e marca uma **carga ativa** (`importacao_id`).
4. O tablet, com Backend = **Planilha**, sincroniza esses cadastros.
5. Operador/motorista fabricam e fornecem (online ou offline).
6. Na próxima sync, fabricação e fornecimento sobem para a API **amarrados à carga em que foram criados**.
7. O escritório exporta a carga e recebe um Excel com o realizado.

Não é necessário Horse, Firebird, FieldPec nem o **conector** do escritório.

```text
  Excel (.xlsx)  →  importar  →  API + PostgreSQL
                                      ↑↓  Wi-Fi
                                 FieldTrato (tablet)
                                      ↓
                           fabricação / fornecimento
                                      ↓
                              exportar Excel da carga
```

---

## 2. Como a importação funciona (por baixo)

### 2.1 Carga ativa

Cada importação bem-sucedida gera um identificador único (`importacao_id`, um UUID).

- A **carga ativa** do cliente é a última importação válida (ou a mesma de novo, se o arquivo for idêntico).
- O tablet, na sync, chama `GET /GetTeste` e grava esse id em `CONFIG.IMPORTACAO_ID`.
- Toda fabricação e todo fornecimento **congelam** o id **no momento em que a operação é criada**. Se depois você importar outra planilha, as operações antigas continuam na carga velha; só as novas usam a carga nova.

### 2.2 Arquivo igual × arquivo diferente

A API calcula o hash SHA-256 do `.xlsx`:

- **Mesmo arquivo** (nenhuma célula mudou): não cria carga nova; reativa a carga já existente (`reused: true`).
- **Qualquer alteração** (mesmo uma letra no nome da dieta): carga **nova**, vira a ativa.

### 2.3 Transação

Se alguma aba estiver inválida, **nada é gravado**. A API devolve a lista de erros (aba, linha, campo, mensagem). Corrija o Excel e importe de novo.

### 2.4 Multi-cliente

Cada fazenda/cliente usa um **código** (o da licença, ex. `2411141`). Esse código:

- é cadastrado na aba **Clientes** do painel;
- vai na aba **CONFIGURACAO** do Excel (`CLIENTE_CODIGO`);
- é o mesmo campo **Código do cliente** no tablet.

A API isola os dados pelo header `X-Client-Code`. Um tablet configurado com o código A não vê cadastros do código B.

### 2.5 Previsão do dia

O `GET /previsao_trato/get` **sem data na URL** devolve só a previsão de **hoje**. No Excel, a coluna `data` da aba `PREVISAO_TRATO` deve ser o dia em que o tablet vai operar (`AAAA-MM-DD`). Se a planilha estiver com data de ontem, o fornecimento no app aparece vazio.

---

## 3. O que precisa instalar no cliente

Há dois lados: **servidor** (escritório ou nuvem) e **tablet** (fazenda).

### 3.1 Servidor (obrigatório)

| Item | Para quê | Observação |
|------|----------|------------|
| Computador Windows ou Linux sempre ligado (ou VM na nuvem) | Hospeda a API | Precisa de IP fixo na LAN ou domínio |
| **PostgreSQL 14+** | Banco dos cadastros e das operações | Banco `fieldpec_online`, usuário `fieldpec` |
| **Node.js 18+** | Roda a API | [nodejs.org](https://nodejs.org) |
| Pacote da **API FieldPec Online** | O serviço HTTP | ZIP gerado por `Pack-ApiDeploy.ps1` |
| Firewall | Liberar a porta da API | Ex.: **3111** ou **3001** (a mesma do tablet) |
| (Recomendado) HTTPS | nginx / Caddy / IIS na frente | Porta 443 no tablet |

**Não precisa** no modo Planilha:

- FieldPec, Firebird, Horse
- Conector do escritório
- Docker (opcional só para teste interno)

### 3.2 Escritório (operação)

| Item | Para quê |
|------|----------|
| Navegador (Chrome, Edge) | Painel `http://IP:PORTA/admin/ui/` |
| Excel ou LibreOffice | Preencher o template `.xlsx` |
| Código de **licença ativa** | Cadastro do cliente na API (GeLicenca) |

### 3.3 Fazenda (tablet)

| Item | Para quê |
|------|----------|
| Tablet Android (recomendado 8"+) | App FieldTrato |
| APK **FieldTrato** atual | Versão com backend Planilha (3) |
| Wi-Fi na mesma rede da API **ou** acesso à internet até o servidor | Só para sync; operação pode ser offline |
| Balança (Topcon, etc.) **ou** simulador local para treino | Pesagem |
| (Opcional) RFID | Identificar curral; dá para usar o **Mapa** |

Depuração USB (ADB) é só para suporte técnico, não para o cliente final.

### 3.4 Rede

- Tablet e API na **mesma LAN**: no tablet use o IP do PC/servidor (ex. `192.168.15.10`).
- API na **nuvem**: Host = domínio (ex. `api.seudominio.com`), Porta = `443` se for HTTPS.
- O tablet precisa alcançar `http://HOST:PORTA/GetTeste` na hora da sync.

---

## 4. Passo a passo — instalar o servidor

Resumo do pacote oficial: `fieldpec_online/DEPLOY_API.md`.

### 4.1 Criar o banco

No servidor, com `psql` no PATH:

**Windows (PowerShell)**

```powershell
cd fieldpec_online\scripts
$env:PGPASSWORD = 'senha_do_superuser_postgres'
.\Create-Database.ps1
```

**Linux**

```bash
cd fieldpec_online/scripts
export PGPASSWORD='senha_do_superuser_postgres'
./create-database.sh
```

Isso cria a role `fieldpec`, o database `fieldpec_online` e aplica o schema.

### 4.2 Instalar e subir a API (Windows)

Exemplo com porta **3111** (pode ser outra, desde que o tablet use a mesma):

```bat
cd /d C:\ApiFieldTratoAndroid
deploy\windows\Install-Api.cmd 3111 "postgres://fieldpec:SUA_SENHA@127.0.0.1:5432/fieldpec_online" "TOKEN_FORTE"
deploy\windows\Start-Api.cmd
```

Para subir com o Windows, instale como serviço (NSSM) — ver `DEPLOY_API.md`.

### 4.3 Conferir

No próprio servidor:

```bat
curl http://127.0.0.1:3111/GetTeste
```

Deve responder algo como: `{"OK ":"Sevidor Online"}`.

No navegador de outro PC da rede:

```text
http://IP_DO_SERVIDOR:3111/admin/ui/
```

(ou `http://IP:3111/` — redireciona para o painel)

### 4.4 Arquivo `api/.env` (referência)

| Variável | Exemplo | Uso |
|----------|---------|-----|
| `PORT` | `3111` | Porta HTTP |
| `HOST` | `0.0.0.0` | Escuta na rede |
| `DATABASE_URL` | `postgres://fieldpec:Senha@127.0.0.1:5432/fieldpec_online` | Banco |
| `ADMIN_TOKEN` | token longo | Painel / rotas admin. `open` = sem Bearer (só homologação) |
| `LICENSE_VALIDATE` | `1` | `1` = só cadastra cliente com licença **Ativa** |

Em produção: `ADMIN_TOKEN` forte, Postgres só na rede interna, API atrás de HTTPS.

---

## 5. Passo a passo — cadastrar o cliente na API

1. Abra `http://IP:PORTA/admin/ui/`.
2. Aba **Clientes**.
3. Informe o **código da licença** (o mesmo que o tablet vai usar).
4. (Opcional) Nome amigável.
5. **Validar licença** — precisa estar **Ativa** na GeLicenca.
6. **Salvar cliente**.
7. No topo do painel, no filtro **Cliente**, selecione esse código. **Toda importação e todo export usam o cliente selecionado.**

O código da planilha (`CLIENTE_CODIGO`) tem que ser **igual** a este cadastro.

---

## 6. Passo a passo — montar a planilha

### 6.1 Baixar o template

No painel, aba **Planilha** → **Baixar template**.

Arquivo: `FieldTrato_Template.xlsx` (layout versão **1**).

**Não apague abas nem a linha de cabeçalho.** Não troque os nomes das abas. Pode apagar as linhas de exemplo e colocar os dados reais.

As 8 abas obrigatórias:

1. `CONFIGURACAO`
2. `FAZENDAS`
3. `USUARIOS`
4. `VAGOES`
5. `BAIAS`
6. `DIETAS`
7. `DIETA_ITENS`
8. `PREVISAO_TRATO`

### 6.2 Aba CONFIGURACAO

Duas colunas: `CHAVE` e `VALOR`.

| CHAVE | O que colocar |
|-------|----------------|
| `VERSAO_LAYOUT` | `1` |
| `CLIENTE_CODIGO` | Mesmo código do painel / tablet (ex. `2411141`) |
| `FAZENDA_CODIGO` | Código da fazenda principal (ex. `F001`) — deve existir em `FAZENDAS` |
| `DESCRICAO` | Texto livre (ex. `Carga 07/09/2026`) |
| `DATA_GERACAO` | Data da geração, `AAAA-MM-DD` |

### 6.3 Demais abas (mínimo para o app funcionar)

Precisa ter, no mínimo:

- 1 fazenda
- 1 usuário (login + senha)
- 1 vagão
- 1 baia (curral)
- 1 dieta com pelo menos 1 ingrediente
- previsão de trato **do dia da operação**

#### FAZENDAS

| Coluna | Obrigatório | Exemplo |
|--------|-------------|---------|
| `idfazenda` | sim | `F001` |
| `fazenda` | sim | `Fazenda Modelo` |

#### USUARIOS

| Coluna | Obrigatório | Exemplo |
|--------|-------------|---------|
| `id` | sim | `U001` |
| `nome` | sim | `Operador 1` |
| `usuario` | sim (login no tablet) | `operador1` |
| `senha` | sim | `123456` |
| `cargo` | não | `Operador` |
| `idfazenda` | sim | `F001` |

`usuario` + `senha` são o que o operador digita no login. Evite dois usuários com o **mesmo login**.

#### VAGOES

| Coluna | Obrigatório | Exemplo |
|--------|-------------|---------|
| `id` | sim | `V001` |
| `nome` | sim | `Vagão 01` |

#### BAIAS

| Coluna | Obrigatório | Exemplo |
|--------|-------------|---------|
| `idbaia` | sim | `B001` |
| `idlote` | sim | `L001` |
| `nomelocal` | sim | `Curral 01` |
| `linha` | sim | `1` |
| `ordemtrato` | sim (número ≥ 0) | `1` |
| `idfazenda` | sim | `F001` |
| `rfid` | não | EPC da tag, se usar RFID |

#### DIETAS

| Coluna | Obrigatório | Exemplo |
|--------|-------------|---------|
| `iddieta` | sim | `D001` |
| `nomedieta` | sim | `Dieta Crescimento` |
| `tipodieta` | não | `Crescimento` |
| `msdieta` | não (número) | `55.5` |
| `idfazenda` | sim | `F001` |

#### DIETA_ITENS

| Coluna | Obrigatório | Exemplo |
|--------|-------------|---------|
| `id` | não (a API gera se vazio) | `DD001` |
| `iddieta` | sim | `D001` |
| `idinsumo` | sim | `I001` |
| `ingrediente` | sim | `Milho` |
| `mnperc` | sim (número, % MN) | `60` |
| `ordem` | sim (número ≥ 0) | `1` |
| `msinsumo` | não | `88` |
| `msinclusao` | não | `60` |
| `prepesagem` | não | `N` ou `S` |

`prepesagem = S`: no tablet o ingrediente abre diálogo de peso digitado (pré-pesado), sem exigir a balança naquele item.

A soma de `mnperc` por dieta deve fechar perto de 100.

#### PREVISAO_TRATO

| Coluna | Obrigatório | Exemplo |
|--------|-------------|---------|
| `id_fornecimento` | sim | `FORN001` |
| `data` | sim `AAAA-MM-DD` | `2026-09-07` |
| `id_baia` | sim | `B001` |
| `trato` | sim (inteiro > 0) | `1` |
| `previsto_kg` | sim | `2500` |
| `realizado_kg` | não (default 0) | `0` |
| `id_racao` | sim (iddieta) | `D001` |
| `id_fazenda` | recomendado | `F001` |

Chave de negócio: `id_fornecimento` + `data` + `id_baia` + `trato`.

### 6.4 Regras que a importação valida

- IDs não vazios e sem duplicata na aba.
- Fazenda citada em usuários, baias e dietas existe em `FAZENDAS`.
- Item de dieta aponta para uma dieta existente.
- Previsão aponta para baia e dieta existentes.
- Números e datas no formato certo.
- `CLIENTE_CODIGO` da planilha igual ao cliente selecionado no painel.

Datas: use `AAAA-MM-DD`. Números aceitam vírgula ou ponto.

---

## 7. Passo a passo — importar a planilha

1. Painel → filtro **Cliente** = código da fazenda.
2. Aba **Planilha**.
3. **Baixar template** (se ainda não tiver).
4. Preencha e salve como `.xlsx` (não use `.xls` antigo).
5. Escolha o arquivo → **Importar**.
6. Leia o resultado:
   - sucesso: aparece `importacao_id` e totais (fazendas, usuários, vagões, baias, dietas, itens, previsão);
   - arquivo idêntico ao anterior: `reused` — carga antiga reativada;
   - erro: nada gravado — corrija a linha indicada e importe de novo.
7. Na tabela **Importações**, a carga ativa fica visível. Use **Exportar** nela depois que o tablet subir operações.

Enquanto o tablet ainda tiver fabricação/fornecimento **pendentes** (não sincronizados), você **pode** importar uma carga nova. As pendentes sobem com o id **antigo**. Só operações criadas **depois** da próxima sync usam a carga nova.

---

## 8. Passo a passo — configurar o tablet

Instale o APK FieldTrato. Na primeira abertura cai em **Configuração**.

1. **IP Servidor Dados** — IP ou domínio da API (ex. `192.168.15.10` ou `api.seudominio.com`).
2. **Porta** — a mesma da API (ex. `3111`). O padrão do app é `3001`; mude se o servidor não for 3001.
3. **Código do cliente** — o da licença / painel / Excel (`CLIENTE_CODIGO`).
4. **Back-end** — **Planilha** (não deixe FieldPec).
5. **Operação** — Rotormix, Estacionário ou Distribuidor, conforme o equipamento.
6. **Baixa Vagão** — deve listar os vagões da planilha. Selecione o correto.
7. **Baixa Fazendas** — selecione a fazenda da planilha.
8. **Balança** — modelo real, **ou** ligue **Simulador local (sem balança)** para treino.
9. **Confirmar** — o app valida o código na API, baixa usuários e vai para o login.

Se o código estiver errado ou o cliente não estiver cadastrado, o Confirmar falha.

Login: `usuario` e `senha` da aba `USUARIOS`.

### 8.1 Primeira sincronização

No menu: **Sincronização** → **Sincronizar Agora**.

Isso:

- testa o servidor (`/GetTeste`) e grava a carga ativa;
- baixa fazendas, usuários, vagões, baias, dietas, ingredientes e previsão de **hoje**;
- envia fabricação/fornecimento pendentes, se houver.

Depois disso o tablet pode trabalhar **offline**. Ligue o Wi-Fi de novo só para sincronizar.

### 8.2 Rede “FieldTrato*”

Ao abrir Fabricação/Fornecimento o app pode pedir uma Wi-Fi cujo nome começa com `FieldTrato`. Na fazenda, se a rede tiver outro nome, use **Continuar** para seguir (já testado). Para operar só no vagão, o ideal é a Wi-Fi do equipamento.

---

## 9. Passo a passo — dia a dia na fazenda

1. **De manhã (com Wi-Fi):** sync, conferir previsão do dia.
2. **Fabricação:** Nova fabricação → dieta + trato → Fabricar → pesar insumos (balança ou simulador) → finalizar.
3. **Fornecimento:** escolher trato → curral (RFID ou **Mapa**) → descarregar até o previsto → Salvar (ou pulo automático, se estiver ligado).
4. **No fim do turno (com Wi-Fi):** Sincronização de novo. Pendentes devem ir a zero.
5. **No escritório:** painel → Planilha → **Exportar** na carga correspondente.

A fabricação e o fornecimento sobem com o `importacao_id` **congelado na criação**. Trocar a planilha no escritório **não reescreve** o que já foi feito no tablet.

---

## 10. Passo a passo — nova planilha (troca de carga)

Use quando mudar dieta, previsão do dia seguinte, usuários, etc.

1. No tablet, sincronize tudo que estiver pendente (recomendado). Se não sincronizar, as pendentes ainda sobem, mas amarradas à carga **antiga**.
2. Ajuste o Excel (mude pelo menos uma célula se quiser carga nova).
3. Confira `PREVISAO_TRATO.data` = **hoje** (ou o dia em que o tablet vai operar).
4. Importe no painel com o **mesmo cliente**.
5. No tablet, **Sincronizar Agora**.
6. O app passa a usar a carga nova. Operações já existentes continuam na carga velha.
7. Exporte **cada** carga se precisar do realizado separado.

---

## 11. Exportar o resultado

No painel, aba **Planilha**, na linha da carga → exportar.

O `.xlsx` traz, entre outras:

| Aba | Conteúdo |
|-----|----------|
| RESUMO | Totais da carga |
| FABRICACOES | Cabeçalhos daquela carga |
| FABRICACAO_ITENS | Itens da fabricação daquela carga |
| FORNECIMENTOS | Fornecimentos daquela carga |
| AUDITORIA | Eventos da carga |

Só entram operações com `importacao_id` **igual** ao da carga. Operação sem id (legado) **não entra em nenhum export**.

O cliente precisa estar selecionado no filtro do painel; senão o export recusa.

---

## 12. Checklist rápido (cliente)

**Servidor**

- [ ] PostgreSQL no ar, banco `fieldpec_online`
- [ ] Node 18+ e API instalada
- [ ] `GET /GetTeste` responde
- [ ] Painel abre em `http://IP:PORTA/admin/ui/`
- [ ] Porta liberada no firewall
- [ ] Cliente cadastrado com licença ativa

**Planilha**

- [ ] Template layout 1, 8 abas
- [ ] `CLIENTE_CODIGO` = código do painel
- [ ] Previsão com a **data de hoje** (dia da operação)
- [ ] Importação com sucesso / carga ativa visível

**Tablet**

- [ ] APK FieldTrato com opção **Planilha**
- [ ] Host + porta iguais aos da API
- [ ] Código do cliente preenchido
- [ ] Backend = Planilha
- [ ] Vagão e fazenda baixados e selecionados
- [ ] Sync ok; login com usuário da planilha
- [ ] Depois da operação, sync de novo e pendentes = 0

---

## 13. Problemas comuns

| Sintoma | Causa típica | O que fazer |
|---------|--------------|-------------|
| Confirmar: código inválido | Cliente não cadastrado ou código diferente | Painel → Clientes; conferir o campo no tablet |
| Tablet não acha o servidor | IP/porta errados, firewall, API parada | Testar `GetTeste` no PC; ping no IP |
| Baixa Vagão/Fazendas vazia | Planilha não importada ou cliente errado | Importar de novo com o filtro de cliente certo |
| Login não entra | Usuário/senha da aba `USUARIOS` | Conferir login duplicado |
| Fornecimento sem curral | Previsão com data ≠ hoje | Ajustar `PREVISAO_TRATO.data` e reimportar |
| Fabricação não finaliza | Peso 0 / balança sem dados | Conferir modelo da balança ou ligar o simulador |
| Export da carga nova veio vazio | Operações ainda na carga antiga | Exportar a carga A; sync depois de criar ops na B |
| Importação recusada | Abas/colunas/IDs | Ler aba, linha e campo no log do painel |
| Dois clientes no mesmo tablet | Código misturado | Um código por aparelho; não misturar FieldPec e Planilha no mesmo fluxo |

---

## 14. Papel de cada ponta (resumo)

| Quem | Faz |
|------|-----|
| TI / implantação | Instala Postgres + Node + API, libera porta, cadastra cliente |
| Escritório | Preenche Excel, importa, exporta o realizado |
| Fazenda | Configura tablet em Planilha, sincroniza, fabrica, fornece, sincroniza de novo |

A planilha **substitui** o FieldPec neste modo: ela é a origem dos cadastros. O tablet continua sendo o lugar da operação de campo.
