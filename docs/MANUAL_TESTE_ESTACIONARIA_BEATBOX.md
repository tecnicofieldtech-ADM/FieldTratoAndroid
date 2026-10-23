# Manual de teste — Estacionária (BeatBox)

Versão do app recomendada: **1.0.25+** (ou superior).  
Atualizar o APK **na estacionária e no vagão**.

---

## 1. Preparação

### Tablets

| Papel | Configuração |
|-------|----------------|
| **Estacionária (BeatBox)** | Menu → Config → Tipo de trabalho = **Estacionário** |
| **Vagão (distribuidor)** | Menu → Config → Tipo de trabalho = **Distribuidor** |

Opcional na estacionária:
- **Nome da estacionária** (ex.: Misturador 01) — aparece na busca do vagão.

### Rede

1. Coloque estacionária e vagão na **mesma Wi‑Fi**.
2. Na estacionária, abra o **Menu** e confira se o **Bridge** está **ON** (porta padrão **8080**).
3. Se o Bridge estiver OFF, o vagão não encontra a estação.

---

## 2. Teste rápido — Discovery (busca na rede)

**Na estacionária:** Menu aberto, Bridge ON.

**No vagão:**
1. Login → Menu → **Carregamento**.
2. Selecione a aba **BeatBox**.
3. Aguarde a busca (ou toque **Buscar novamente**).

**Esperado:**
- Aparece a estacionária com nome e IP.
- Se houver 2 estações, as duas aparecem.
- Toque **Selecionar** em uma (não escolhe sozinho).

**Se não achar ninguém:**
- Use **Informar IP manualmente** (IP do tablet da BeatBox + porta **8080**).
- Confirme Wi‑Fi, Bridge ON e que o AP não bloqueia comunicação entre tablets.

---

## 3. Teste A — Carga parcial (continuar fabricação no vagão)

### Na estacionária
1. Faça uma fabricação e deixe-a **pendente para o caminhão**  
   (começou na BeatBox e falta terminar no vagão).
2. Bridge ON.

### No vagão
1. BeatBox → buscar → selecionar a estação.
2. Na lista, a carga deve mostrar algo como **“Continuar no vagão”**.
3. Toque **Continuar** / **Carregar** → confirme.
4. O app reserva a carga (**claim**), importa e abre a tela de **carregamento da ração** (pesagem) e depois a **continuação da fabricação** (ingredientes restantes).

**Esperado:**
- Abre fluxo de **continuar fabricação** (não vai direto a só “distribuir”).
- Após concluir, a carga some da lista da estação.

---

## 4. Teste B — Carga já fabricada (pronta na BeatBox)

### Na estacionária
1. Finalize a fabricação **completa** na BeatBox  
   (`FAB_STATUS` finalizada + `FINALIZADA=1`, ainda não carregada pelo vagão).
2. Bridge ON.

### No vagão
1. BeatBox → selecionar a estação.
2. A carga deve mostrar **“Fabricação concluída”**.
3. Toque **Carregar**.

**Esperado:**
- **Não** reabre a lista de ingredientes para fabricar de novo.
- Abre a tela de **peso carregado no vagão** (transferência física da ração).
- Informe / capture o peso na balança do vagão.
- Depois pode seguir para **fornecimento**.

**Importante:** peso fabricado na estação ≠ peso da balança do vagão. A pesagem no vagão é a transferência real.

---

## 5. Teste de concorrência (2 vagões)

1. Estação com **uma** carga na lista.
2. Vagão 1 e Vagão 2 abrem a mesma lista.
3. Os dois tocam **Carregar/Continuar** quase ao mesmo tempo.

**Esperado:**
- **Um** consegue.
- O outro vê **“Em uso por outro vagão”** e **não** importa a carga.

---

## 6. Teste de abandono (lease ~3 minutos)

1. Vagão 1: claim (iniciar receber) e **não** conclui / fecha o fluxo sem ACK.
2. Esperar cerca de **3 minutos**.
3. Vagão 2: tentar a mesma carga.

**Esperado:** após o tempo, Vagão 2 consegue reservar.

---

## 7. Teste de troca de estação

1. Vagão recebe carga da **Estação A**.
2. Volta na lista de estações (sem ir em Config).
3. Seleciona **Estação B** e recebe outra carga.

**Esperado:** funciona sem alterar configuração permanente de IP da estação.

---

## 8. Teste IP manual

1. Na BeatBox do vagão → **Informar IP manualmente**.
2. Digite o IP do tablet estacionário e porta **8080**.
3. Conectar → listar cargas → carregar.

**Esperado:** mesmo fluxo da discovery, sem depender do broadcast UDP.

---

## 9. Checklist de aceite (cliente)

| # | Cenário | OK? |
|---|---------|-----|
| 1 | Bridge ON na estacionária | ☐ |
| 2 | Vagão encontra a estação (ou IP manual) | ☐ |
| 3 | Carga parcial → continua fabricação no vagão | ☐ |
| 4 | Carga finalizada → só transferência / peso no vagão | ☐ |
| 5 | Dois vagões → só um assume a carga | ☐ |
| 6 | Após receber, carga some da lista da estação | ☐ |
| 7 | Fornecimento funciona depois da carga pronta | ☐ |
| 8 | Troca de estação sem mexer em Config | ☐ |

---

## 10. Problemas comuns

| Sintoma | O que verificar |
|---------|------------------|
| Nenhuma estacionária encontrada | Mesma Wi‑Fi; Bridge ON; tentar IP manual |
| Lista de cargas vazia | Fabricação com status correto e ainda não carregada (`CARREGADA=0`) |
| “Em uso por outro vagão” | Outro tablet já reservou; esperar ~3 min ou o outro concluir/liberar |
| Pede login toda vez que abre | Comportamento esperado na versão 1.0.25+ |
| Estação antiga sem claim | IP manual pode funcionar no modo legado, **sem** proteção de concorrência |

---

## 11. O que não precisa para este teste

- Atualizar a **API do servidor** (Horse/nuvem) — o handoff é **tablet ↔ tablet** na rede local.
- Cadastrar IP fixo da estação no Config do vagão (opcional; discovery/IP manual bastam).

---

## Referência técnica (equipe)

- Discovery UDP porta **19091**
- Bridge HTTP porta **8080**
- Docs: `ESTACIONARIO_DISCOVERY.md`, `ESTACIONARIO_CLAIM.md`, `ESTACIONARIO_HANDOFF_MODES.md`
