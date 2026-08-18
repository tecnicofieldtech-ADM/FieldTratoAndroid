# Manual de Espelhamento de Dados

## Escopo
Este manual descreve como funciona o espelhamento entre o **RFeedX (caminhão)** e o app da **pá carregadeira (RFeed PA)**, incluindo formato do payload JSON enviado via socket.

## Visão geral da comunicação
- Origem dos dados: RFeedX (`lib/features/fabricacao/controller/fabricacao_controller.dart`)
- Transporte: TCP socket, JSON por linha (`\n`)
- Destino dos dados: RFeed PA (`rfeed_pa/lib/features/espelho/controller/pa_client_controller.dart`)
- Porta padrão: `9000`
- Direção principal: RFeedX -> Pá (estado de fabricação)

## Topologia e configuração
1. No RFeedX, configure apenas `PORTA_ESPELHO` (padrão `9000`).
2. O RFeedX abre um **servidor TCP** em `0.0.0.0:PORTA_ESPELHO`.
3. Na pá, cadastre o vagão com o **IP do tablet do caminhão** e a mesma porta.
4. A pá conecta como **cliente TCP** no IP/porta do vagão.
5. Múltiplas PAs podem conectar simultaneamente ao mesmo vagão.

## Protocolo (nível de transporte)
- Cada mensagem deve ser um objeto JSON válido em **uma única linha**.
- Cada linha termina com `\n`.
- Exemplo de frame no fio:

```text
{"t":"state","stream":"fabricacao_resumo",...}\n
```

## Tipos de mensagens
### 1) `state` (estado da fabricação)
É a mensagem principal para atualizar a tela da pá.

Campos usados no payload atual:
- `t`: tipo da mensagem (`"state"`)
- `stream`: atualmente `"fabricacao_resumo"` (a pá aceita também `"fabricacao"` por compatibilidade)
- `fabId`, `trato`, `dieta`, `finalizada`
- `auto`: estado do auto pulo
- `scale`: estado da balança
- `atual`: ingrediente atual
- `prox`: próximo ingrediente (ou `null`)
- `ts`: timestamp ISO-8601

Exemplo realista de payload `state`:

```json
{
  "t": "state",
  "stream": "fabricacao_resumo",
  "fabId": "d8f8a6d2-0c8b-4f0d-b1ae-93430f7a52f1",
  "trato": 3,
  "dieta": "Lote Leite 1",
  "finalizada": 0,
  "auto": {
    "enabled": 1,
    "countdown": 7,
    "fromPos": 2,
    "toPos": 3,
    "ts": "2026-02-20T10:45:20.110Z"
  },
  "scale": {
    "connected": 1,
    "receiving": 1,
    "weight": 2840,
    "lastAt": "2026-02-20T10:45:20.051Z",
    "raw": "ST,GS,+002840kg"
  },
  "atual": {
    "nome": "Silagem de milho",
    "prev": 3200,
    "real": 2840,
    "falta": 360,
    "prePesado": 0,
    "pos": 2,
    "total": 8
  },
  "prox": {
    "nome": "Farelo de soja",
    "prev": 540,
    "prePesado": 1
  },
  "ts": "2026-02-20T10:45:20.111Z"
}
```

### 2) `event` (evento de processo)
Usado para eventos de controle, como auto pulo e finalização.

Exemplo de payload `event`:

```json
{
  "t": "event",
  "stream": "fabricacao",
  "type": "auto_pulo",
  "fabId": "d8f8a6d2-0c8b-4f0d-b1ae-93430f7a52f1",
  "trato": 3,
  "ts": "2026-02-20T10:45:20.112Z",
  "seconds": 8,
  "fromPos": 2,
  "toPos": 3,
  "atual": "Silagem de milho",
  "prox": "Farelo de soja"
}
```

## Regras importantes no lado da pá
- Só processa mensagens com `stream` igual a `fabricacao` ou `fabricacao_resumo`.
- Mensagens inválidas ou JSON quebrado são ignorados.
- Há filtro anti-flicker por ingrediente (`pos`) e modo pré-pesado.
- Quando `auto.enabled=1` e `auto.countdown>0`, o bloqueio anti-flicker é relaxado para atualizar contador em tempo real.
- `lastState` é atualizado apenas para mensagens aceitas.

## Comandos de controle (retorno para o RFeedX)
O RFeedX está preparado para receber estes comandos por socket:
- `{"t":"next"}`: avança ingrediente
- `{"t":"prev"}`: volta ingrediente
- `{"t":"ping"}`: responde com `{"t":"pong"}` (tratado no servidor)
- `{"t":"req_state","stream":"fabricacao_resumo"}`: pede reenvio do último estado (cache no servidor ou estado atual da fabricação)

Observação: no código atual da pá, o foco principal está em receber e exibir estados; envio desses comandos depende de implementação de UI/ação de comando.

## Frequência e deduplicação
- O RFeedX envia `state` quando há alteração relevante (deduplicação por hash estável).
- Em pontos críticos, envia com `force=true` (ex.: mudança de ingrediente, auto pulo, finalização).
- A pá envia keepalive periódico (`ping`) para manter a sessão TCP ativa.

## Checklist rápido de validação em campo
1. Confirmar `PORTA_ESPELHO` no RFeedX (normalmente `9000`).
2. Confirmar IP do tablet do vagão cadastrado na pá, com a mesma porta.
3. Verificar se a pá está com o vagão/alvo ativo correto.
4. Confirmar que os payloads chegam em JSON por linha com `\n`.
5. Validar se `stream` está em `fabricacao_resumo` ou `fabricacao`.

## Referências no código
- RFeedX: `lib/helpers/mirror_service.dart`
- RFeedX: `lib/helpers/mirror_server.dart`
- RFeedX: `lib/features/fabricacao/controller/fabricacao_controller.dart`
- Pá: `rfeed_pa/lib/features/espelho/controller/pa_client_controller.dart`
