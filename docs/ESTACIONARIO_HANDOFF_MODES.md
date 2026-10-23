# Estacionário — Handoff Modes (Etapa E)

## Auditoria dos status reais

| Campo | Significado |
|-------|-------------|
| `STATUS` | Registro ativo (`1`) vs cancelado/excluído (`≠1`) |
| `CARREGADA` | Handoff assumido pelo vagão (`1` some da lista do bridge) — **não** significa “fabricação terminou” |
| `FAB_STATUS` | `0` EM_ANDAMENTO · `1` PENDENTE_CAMINHAO · `2` FINALIZADA |
| `FINALIZADA` | Flag booleana complementar (`1` = fabricação concluída) |
| `FLOW_MODE` | Config da estação (`0` fullOnStation · `1` startStationFinishTruck) — **não alterado** nesta etapa |

### Estados publicáveis

**A — Parcial (continuar no vagão)**

- `STATUS=1`
- `CARREGADA=0`
- `FAB_STATUS=1` (PENDENTE_CAMINHAO)
- `FINALIZADA=0`

**B — Fabricação concluída na estação**

- `STATUS=1`
- `CARREGADA=0`
- `FAB_STATUS=2` (FINALIZADA)
- `FINALIZADA=1`

Estados inconsistentes (ex.: `FAB_STATUS=1` + `FINALIZADA=1`) **não** são publicados.

## Por que a finalizada não aparecia

`listDisponiveis` filtrava apenas `FAB_STATUS = PENDENTE_CAMINHAO`.

## handoffMode (derivado, não persistido)

| Valor API | Quando | Após import no vagão |
|-----------|--------|----------------------|
| `CONTINUE_FABRICATION` | Parcial | `FabricacaoRecebimentoPesoCaminhaoPage` → completa ingredientes (`FabricacaoWeighPage`) |
| `FABRICATION_COMPLETE` | Finalizada na estação | `FabricacaoCarregamentoVagaoPage` — pesagem física da transferência; **não** refaz ingredientes |

`claimStatus` e `handoffMode` são ortogonais:

- claim = quem pode pegar
- handoffMode = o que fazer depois

## Transferência física (item crítico)

`FABRICATION_COMPLETE` **não** significa “ir direto ao curral”.

A ração pronta na BeatBox ainda precisa ser transferida fisicamente ao vagão.  
`FabricacaoCarregamentoVagaoPage` registra `PESO_CARREGADO` na balança do vagão (auditoria misturador vs vagão) e então oferece abrir o fornecimento.

Peso fabricado (`PESO_FABRICADO` / `QTD_REALIZADA`) ≠ peso físico atual da balança do vagão.

## Nome escolhido

`FABRICATION_COMPLETE` (em vez de `READY_TO_DISTRIBUTE`) para evitar a leitura errada de “já pode distribuir sem receber a carga”.

Aliases aceitos no cliente: `LOAD_READY`, `READY_TO_DISTRIBUTE`.

## Claim / ACK

Ambos os modos exigem: lista → claim → import → ack (Etapa D).
