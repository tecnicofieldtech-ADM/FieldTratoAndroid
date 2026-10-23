# Estacionário — Claim / Lease (Etapa D)

## Objetivo

Garantir que **apenas um vagão** assuma uma carga estacionária por vez.

Fluxo:

```
AVAILABLE → CLAIMED → IMPORTADO (SQLite local) → ACK → CARREGADA
```

Abandono:

```
CLAIMED → lease expira → AVAILABLE
```

Claim é **concorrência**, não estado zootécnico. `FAB_STATUS` / `FLOW_MODE` / `HANDOFF_ID` / `ORIGIN_DEVICE` **não mudam**.

## Identidade

- Chave do claim: `CONFIG.TRUCK_DEVICE_ID` (UUID v4)
- Não usar IP, hostname, usuário ou nome do vagão como chave

## Persistência (estação)

Migration **v18** em `CADASTRO_FABRICA_RACAO`:

| Campo | Tipo |
|-------|------|
| `CLAIM_DEVICE_ID` | TEXT NULL |
| `CLAIM_AT` | TEXT (ISO-8601) NULL |
| `CLAIM_EXPIRES_AT` | TEXT (ISO-8601) NULL |

## Lease

- Constante: `StationClaim.claimLeaseDuration` = **3 minutos**
- Relógio **somente da estação** define `CLAIM_AT` / `CLAIM_EXPIRES_AT`
- Expirado quando `CLAIM_EXPIRES_AT <= now` (lazy, sem job)

## Estados derivados

| Status | Condição |
|--------|----------|
| `available` | `CARREGADA=0` e (sem claim ou lease expirado) |
| `claimedByMe` | claim do mesmo `truckDeviceId`, lease válido |
| `claimed` | claim de outro device, lease válido |
| consumido | `CARREGADA=1` (some da lista) |

## Atomicidade

`UPDATE` condicional dentro de `transaction`:

```sql
UPDATE ... SET CLAIM_* = ...
WHERE id/handoff
  AND CARREGADA = 0
  AND (claim vazio OR expires <= now OR claim = truck)
```

`changes == 1` → sucesso; `0` → conflito / indisponível.

## Endpoints

### POST `/carregamentos/:id/claim`

Body: `{ "truckDeviceId": "<uuid>" }`

- `:id` = ID local **ou** `HANDOFF_ID`
- 200: `{ ok, handoffId, claimedBy, claimExpiresAt, alreadyOwned }`
- 409: `{ ok:false, code:"ALREADY_CLAIMED", claimExpiresAt }`
- 400 / 404 conforme validação

Mesmo device: renovação idempotente (`alreadyOwned: true`).

### POST `/carregamentos/:id/release`

Body: `{ "truckDeviceId": "<uuid>" }`

- Só o dono libera
- Já livre → 200 idempotente
- Outro device → 409

### POST `/carregamentos/:id/ack`

Body: `{ "truckDeviceId": "<uuid>" }` (Bridge novo)

- Exige claim do mesmo truck
- `CARREGADA=1` + limpa `CLAIM_*` numa transação
- Já `CARREGADA=1` → 200 idempotente (`alreadyAcked`)
- Body sem UUID válido → modo legado (ACK sem exigir claim)

### GET `/carregamentos?truckDeviceId=`

Itens incluem:

- `claimStatus`: `available` | `claimedByMe` | `claimed`
- `claimExpiresAt`

Lista (Etapa E): `STATUS=1`, `CARREGADA=0` e
(`FAB_STATUS=PENDENTE_CAMINHAO`+`FINALIZADA=0` **ou** `FAB_STATUS=FINALIZADA`+`FINALIZADA=1`).
Ver [`ESTACIONARIO_HANDOFF_MODES.md`](./ESTACIONARIO_HANDOFF_MODES.md).

## Fluxo do vagão

1. `POST /claim`
2. `GET` detalhe
3. Importar SQLite local
4. Só então `POST /ack`

Falha no import → `POST /release` (sem ACK). Se rede cair, lease expira.

Falha no ACK após import → retry seguro (dedupe por `HANDOFF_ID` + ACK idempotente).

## Bridge legado

Se `/claim` retornar 404 de rota inexistente:

- log `CLAIM_UNSUPPORTED_LEGACY_BRIDGE`
- fluxo antigo: import → ack
- **sem** proteção de concorrência

## Fora de escopo

- Etapa E (publicar `FINALIZADA`)
- Heartbeat contínuo
- Autenticação complexa na LAN
