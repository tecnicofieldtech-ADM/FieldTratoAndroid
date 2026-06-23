# Importacao de planilhas para API - Field Trato

Este documento define os dados minimos para o sistema funcionar e o contrato recomendado para importar planilhas na API.

## 1) Endpoints que o app consome no bootstrap

A API precisa responder em JSON (lista) para:

- GET /vagao/get/
- GET /fazenda/get
- GET /usuarios/get/{idFazenda}
- GET /baias/get/{idFazenda}
- GET /dietas/get/{idFazenda}
- GET /dietas_detalhes/get/{idFazenda}
- GET /previsao_trato/get/{idFazenda}/{dataYmd}

Observacao de backend alternativo:

- Quando backend=Fieldpec, o app tambem aceita sem idFazenda no path:
  - GET /usuarios/get
  - GET /baias/get
  - GET /dietas/get
  - GET /dietas_detalhes/get
  - GET /previsao_trato/get

## 2) Dados minimos para operacao

Para o app operar sem falhas no fluxo principal, garanta:

1. Pelo menos 1 fazenda.
2. Pelo menos 1 usuario para login.
3. Pelo menos 1 dieta para a fazenda selecionada.
4. Pelo menos 1 ingrediente em cada dieta (detalhes_dietas).
5. Previsao de trato para o dia (baias + trato + id_fornecimento + dieta).
6. Baias cadastradas para a fazenda.
7. Vagao cadastrado (recomendado; necessario para fluxo de carregamento/sync completo).

## 3) Estrutura das planilhas (abas)

Use os nomes de coluna canonicos abaixo para reduzir ambiguidade.

### 3.1 fazendas

Colunas:

- idfazenda (obrigatorio, texto, unico)
- fazenda (obrigatorio, texto)

Mapeamento API esperado:

- GET /fazenda/get retorna lista com idfazenda e fazenda.

### 3.2 usuarios

Colunas:

- id (obrigatorio, texto, unico)
- nome (obrigatorio, texto)
- usuario (obrigatorio, texto, usado no login)
- senha (obrigatorio, texto, usado no login)
- cargo (opcional, texto)
- idfazenda (obrigatorio para consistencia de dados)

Mapeamento API esperado:

- GET /usuarios/get/{idFazenda} retorna os usuarios da fazenda.

### 3.3 vagoes

Colunas:

- id (obrigatorio, texto, unico)
- nome (obrigatorio, texto)

Mapeamento API esperado:

- GET /vagao/get/ retorna lista com id e nome.

### 3.4 baias

Colunas:

- idbaia (obrigatorio, texto, unico)
- idlote (obrigatorio, texto)
- nomelocal (obrigatorio, texto)
- linha (obrigatorio, texto)
- ordemtrato (obrigatorio, inteiro >= 0)
- idfazenda (obrigatorio, texto)
- rfid (opcional, texto)

Mapeamento API esperado:

- GET /baias/get/{idFazenda} retorna itens de baia.

### 3.5 dietas

Colunas:

- iddieta (obrigatorio, texto, unico)
- nomedieta (obrigatorio, texto)
- tipodieta (opcional, texto)
- msdieta (opcional, numerico)
- idfazenda (obrigatorio, texto)

Mapeamento API esperado:

- GET /dietas/get/{idFazenda} retorna itens de dieta.

### 3.6 dietas_detalhes

Colunas:

- id (opcional, texto unico; se vazio, pode ser gerado pela API)
- iddieta (obrigatorio, texto)
- idinsumo (obrigatorio, texto)
- ingrediente (obrigatorio, texto)
- mnperc (obrigatorio, numerico, percentual do ingrediente)
- ordem (obrigatorio, inteiro >= 0)
- msinsumo (opcional, numerico)
- msinclusao (opcional, numerico)
- prepesagem (opcional, texto: S ou N)

Regra recomendada:

- Soma de mnperc por iddieta deve ser ~100 (aceitar pequena tolerancia).

Mapeamento API esperado:

- GET /dietas_detalhes/get/{idFazenda} retorna os itens de ingredientes por dieta.

### 3.7 previsao_trato

Colunas:

- id_fornecimento (obrigatorio, texto)
- data (obrigatorio, YYYY-MM-DD)
- id_baia (obrigatorio, texto)
- trato (obrigatorio, inteiro > 0)
- previsto_kg (obrigatorio, numerico >= 0)
- realizado_kg (opcional, numerico >= 0; default 0)
- id_racao (obrigatorio, texto; deve existir em dietas)
- id_fazenda (recomendado, texto)

Chave de negocio recomendada:

- (id_fornecimento, data, id_baia, trato)

Mapeamento API esperado:

- GET /previsao_trato/get/{idFazenda}/{dataYmd} retorna a previsao do dia.

## 4) Validacoes minimas na API de importacao

Validar em lote e retornar relatorio por linha:

1. IDs obrigatorios nao vazios.
2. Integridade referencial:
   - usuarios.idfazenda existe em fazendas
   - baias.idfazenda existe em fazendas
   - dietas.idfazenda existe em fazendas
   - dietas_detalhes.iddieta existe em dietas
   - previsao_trato.id_baia existe em baias
   - previsao_trato.id_racao existe em dietas
3. Tipos:
   - trato e ordemtrato inteiros
   - previsto_kg, realizado_kg, mnperc, msinsumo, msinclusao, msdieta numericos
4. Datas em formato YYYY-MM-DD.
5. Duplicidade por chave natural em cada aba.

## 5) Fluxo recomendado para API de importacao

Endpoint sugerido:

- POST /importacao/planilhas

Entrada:

- arquivo xlsx (multipart/form-data) ou JSON com abas.

Processamento:

1. Ler abas.
2. Validar tudo.
3. Se houver erro, nao aplicar nada (transacao unica) e retornar relatorio.
4. Se valido, fazer upsert nesta ordem:
   - fazendas
   - usuarios
   - vagoes
   - baias
   - dietas
   - dietas_detalhes
   - previsao_trato

Saida sugerida:

- total_processado por aba
- total_inserido
- total_atualizado
- erros[] com aba, linha, campo e mensagem

## 6) Payloads que a API tambem precisa aceitar (saida do app)

Para sincronizacao de retorno ao backend:

- POST /Post/GravaTag
- POST /Post/Fabricacao
- POST /Post/Fabricacao_Insumo
- POST /Post/Fornecimento

Observacoes:

- Numeros podem chegar com virgula decimal em alguns campos.
- Para /Post/Fabricacao no backend Fieldpec, pode chegar pacote com itens e fornecimentos juntos.

## 7) Checklist rapido de homologacao

1. Importar planilhas com dados de 1 fazenda.
2. Sincronizar no app.
3. Confirmar login com usuario importado.
4. Confirmar lista de dietas e ingredientes.
5. Confirmar previsao do dia visivel no fornecimento.
6. Criar e finalizar uma fabricacao.
7. Sincronizar e validar recebimento de /Post/* na API.
