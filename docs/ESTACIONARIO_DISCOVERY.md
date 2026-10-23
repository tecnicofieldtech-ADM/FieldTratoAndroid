# Estacionário — Discovery UDP (Etapa A+B)

## Objetivo

Permitir que o **vagão** encontre e selecione estacionárias na rede local **sem** cadastrar `CONFIG.STATION_BASE_URL` obrigatoriamente.

Claim/lease e publicação de carga `FINALIZADA` **não** fazem parte desta etapa.

## Identidade

| Campo | Onde | Quando gera | Formato |
|-------|------|-------------|---------|
| `CONFIG.STATION_ID` | Estacionária (`TIPO_TRABALHO=1`) | Uma vez, se vazio | UUID v4 |
| `CONFIG.STATION_NAME` | Estacionária | Manual (fallback: `NOME_VAGAO` / "Estacionária") | texto |
| `CONFIG.TRUCK_DEVICE_ID` | Vagão (`TIPO_TRABALHO=2`) | Uma vez, se vazio | UUID v4 |

**Não confundir com `ORIGIN_DEVICE`:**

- `ORIGIN_DEVICE` = papel lógico da carga (`ESTACIONARIO` / `CAMINHAO` / `ROTORMIX`)
- `STATION_ID` = identidade física/lógica do tablet estacionário

## Bridge HTTP (identidade)

Porta HTTP padrão: **8080**.

`GET /health` e `GET /` passam a incluir (sem remover campos existentes):

```json
{
  "ok": true,
  "service": "RFEED_STATION",
  "stationId": "<uuid>",
  "name": "Misturador 01",
  "port": 8080,
  "version": 1,
  "tipoTrabalho": 1
}
```

## Discovery UDP

| Item | Valor |
|------|-------|
| Porta | **19091** |
| Protocolo | JSON versionado v1 |
| Pedido | `{ "type": "RFEED_DISCOVER_STATION", "version": 1 }` |
| Resposta | `{ "type": "RFEED_STATION", "version": 1, "stationId", "name", "port" }` |

- O **host efetivo** é o endereço remoto do datagrama UDP (não o campo `ip` do JSON).
- Broadcast: `255.255.255.255` + broadcast `/24` das interfaces IPv4 ativas.
- Janela de escuta padrão: **2 segundos**.
- Deduplicação por `stationId`.
- Respostas sem `stationId`, porta inválida ou `version != 1` são ignoradas.

O **responder UDP** sobe junto com o Bridge HTTP e é fechado no `stop()` do Bridge (sem socket órfão).

## UI (vagão)

Rota/tela: carregamento estacionário (BeatBox).

1. Ao abrir: "Buscando estacionárias..."
2. Lista "Estacionárias disponíveis" — usuário **seleciona** (não auto-escolhe a primeira)
3. Ações: **Buscar novamente** / **Informar IP manualmente**
4. Após seleção: valida `/health`, lista `/carregamentos`, reutiliza fluxo de importação atual
5. Voltar à lista permite trocar de estação **sem** gravar `STATION_BASE_URL`

### Fallback IP manual

- Host + porta (default **8080**)
- Valida `/health` antes de seguir
- Bridge antigo **sem** `stationId`: identidade temporária de sessão `manual:<host>:<port>` (compatibilidade)
- Discovery novo **exige** `stationId` válido

### Recentes (`ESTACIONARIO_REDE`)

- Cache opcional (último IP / nome / `stationId`)
- **Não** é fonte obrigatória; discovery funciona com tabela vazia
- UI diferencia "encontrada agora" vs "recente" (recente offline não parece online)

### `STATION_BASE_URL` / `STATION_WIFI_SSID`

- `STATION_BASE_URL`: mantido para compatibilidade / fallback legado; **não** sobrescrito pela seleção dinâmica
- `STATION_WIFI_SSID`: não é identidade da estação; não bloqueia listar múltiplas estações na mesma rede

## Logs

- `DISCOVERY_START`
- `DISCOVERY_RESPONSE`
- `DISCOVERY_TIMEOUT`
- `STATION_SELECTED`
- `STATION_MANUAL`

Sem credenciais.

## Etapas seguintes

- Claim/lease: [`ESTACIONARIO_CLAIM.md`](./ESTACIONARIO_CLAIM.md)
- Handoff parcial vs finalizada: [`ESTACIONARIO_HANDOFF_MODES.md`](./ESTACIONARIO_HANDOFF_MODES.md)

## Android

Permissões já presentes e suficientes para UDP broadcast unicast-style:

- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `ACCESS_WIFI_STATE`

`CHANGE_WIFI_MULTICAST_STATE` / `MulticastLock` **não** foram adicionados (broadcast UDP simples).

## Testes

Arquivo: `test/station_discovery_test.dart` (casos 1–15 + loopback A+B).
