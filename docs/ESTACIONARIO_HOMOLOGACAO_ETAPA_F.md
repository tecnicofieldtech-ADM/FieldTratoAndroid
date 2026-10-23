# FieldTrato — Etapa F — Homologação integrada (tablets reais)

**Data do gate automatizado:** 2026-10-05  
**Versão APK:** `1.0.24+106`  
**Artefato:** `build/app/outputs/flutter-apk/app-release.apk`  
**Funcionalidade nova nesta etapa:** nenhuma (somente homologação).

---

## Veredito

| Gate | Status |
|------|--------|
| `flutter test` (59) | **PASS** |
| `flutter build apk --release` | **PASS** |
| Homologação em tablets Android reais | **PENDENTE** — nenhum device Android conectado nesta máquina (`flutter devices` só Windows/Chrome/Edge; `adb` não no PATH) |
| **GO / NO-GO piloto cliente** | **NO-GO** até checklist de campo abaixo ser preenchido com evidências |

Critério de GO (obrigatório em hardware):

1. Estação A → parcial → vagão continua fabricação  
2. Estação B → finalizada → vagão só transferência física (`FabricacaoCarregamentoVagaoPage`)  
3. Dois vagões → mesma carga → só um claim  
4. Queda de Wi‑Fi não perde operação; ACK recuperável; sem duplicar `HANDOFF_ID`; troca de estação sem Config  

---

## Checklist de campo (preencher)

### Devices / rede

| # | Item | Resultado | Evidência |
|---|------|-----------|-----------|
| 1 | Devices usados | | modelo / papel (estação/vagão) |
| 2 | Android de cada device | | versão |
| 3 | Rede utilizada | | SSID / AP / isolamento de cliente? |

### Discovery / rede

| # | Item | OK? | Notas |
|---|------|-----|-------|
| 4 | Discovery A/B (nomes, IPs, sem duplicar, troca A→B) | ☐ | logs `DISCOVERY_*` / `STATION_SELECTED` |
| 5 | AP sem broadcast → IP manual funciona | ☐ | |
| 14 | IP da estação muda → mesmo `STATION_ID`, IP novo | ☐ | cache não força IP antigo |
| 15 | Recentes offline ≠ “encontrada agora” | ☐ | falha controlada ao conectar |
| 16 | Bridge legado sem `/claim` via IP manual | ☐ | log `CLAIM_UNSUPPORTED_LEGACY_BRIDGE` |

### Fluxos de carga

| # | Item | OK? | Notas |
|---|------|-----|-------|
| 6 | Parcial `CONTINUE_FABRICATION` | ☐ | abre `FabricacaoRecebimentoPesoCaminhaoPage` |
| 7 | Completa `FABRICATION_COMPLETE` | ☐ | **não** reabre ingredientes |
| 8 | Transferência física / `PESO_CARREGADO` ≠ peso fabricado | ☐ | |
| 9 | Fornecimento pós-carga (1+ curral) | ☐ | sem regressão |

### Concorrência / resiliência

| # | Item | OK? | Notas |
|---|------|-----|-------|
| 10 | Concorrência A/B claim | ☐ | perdedor “Em uso…” |
| 11 | Lease (~3 min) → B consegue | ☐ | tempo observado: ___ |
| 12 | Release após falha pré-persistência | ☐ | |
| 13 | Queda Wi‑Fi pós-import pré-ACK | ☐ | SQLite + retry ACK |
| 11b | ACK perdido → retry idempotente | ☐ | sem duplicar fab |
| 15b | Restart app em pontos do fluxo | ☐ | |
| 13b | Troca estação A→B sem Config | ☐ | `STATION_BASE_URL` intacto |

### Hardware / regressão

| # | Item | OK? | Notas |
|---|------|-----|-------|
| 17 | Balança real (2 modes) | ☐ | vs simulador |
| 18 | RFID no fornecimento | ☐ | |
| 20 | Smoke Rotormix / Estacionário / Distribuidor / Híbrido | ☐ | |
| 20b | Smoke FieldPec / TGC / Planilha | ☐ | |

### Bugs / build

| # | Item | Resultado |
|---|------|-----------|
| 20 | Bugs encontrados | |
| 21 | Correções realizadas | *(nenhuma nesta Etapa F — sem feature nova)* |
| 22 | `flutter test` | **59 passed** (2026-10-05) |
| 23 | Build release | **OK** — ver hash abaixo |
| 24 | GO / NO-GO | **NO-GO** até itens 4–13 + GO criteria |

---

## Gate automatizado (esta máquina)

```
flutter test     → 59 passed
flutter build apk --release → OK
versão           → 1.0.24+106
```

SHA256 do APK: `BE4AA3F7B51849731F1761576D1DC8F67ABB078E207A97039475A877F9ADE840`  
Tamanho: ~57,6 MB (60 442 809 bytes)

### Logs a coletar em campo (sem senhas)

`DISCOVERY_START` · `DISCOVERY_RESPONSE` · `STATION_SELECTED` · claim · release · ack · `handoffMode` · `HANDOFF_ID`

---

## Setup mínimo sugerido

| Papel | Config |
|-------|--------|
| Estação A/B | `TIPO_TRABALHO=1`, Bridge ON, `STATION_NAME` distinto |
| Vagão 1/2 | `TIPO_TRABALHO=2`, mesma LAN Wi‑Fi |

Mínimo aceitável: **1 estação + 2 vagões** (concorrência).

---

## Como promover a GO

1. Instalar APK `1.0.24+106` nos tablets.  
2. Executar checklist (itens 4–13 e critérios GO).  
3. Anexar prints/logs.  
4. Atualizar este arquivo: veredito → **GO** e data.  

Não iniciar nova funcionalidade após GO.
