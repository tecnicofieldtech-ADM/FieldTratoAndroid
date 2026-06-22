# Fase 8 — Rascunho OpenAPI REST

API REST proposta para o RFeed Lite (NestJS).  
Base URL: `https://api.rfeed-lite.com/api/v1` (SaaS) ou `https://{host}/api/v1` (on-premise).

---

## 8.1 Autenticação

Todas as rotas (exceto auth) requerem:

```
Authorization: Bearer {access_token}
X-Tenant-Id: {tenant_uuid}   # opcional se embutido no JWT
```

Sync mobile adicional:

```
X-Device-Id: tablet-001
X-Idempotency-Key: {uuid}    # POST operacionais
```

---

## 8.2 Auth

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/auth/login` | Login email/senha → JWT |
| POST | `/auth/refresh` | Refresh token |
| POST | `/auth/logout` | Invalidar refresh |
| GET | `/auth/me` | Usuário logado + tenant |

### POST `/auth/login`

**Request:**
```json
{
  "email": "operador@fazenda.com",
  "password": "senha123",
  "tenant_slug": "fazenda-veredas"
}
```

**Response 200:**
```json
{
  "access_token": "eyJhbG...",
  "refresh_token": "eyJhbG...",
  "expires_in": 3600,
  "user": {
    "id": "uuid",
    "nome": "João Operador",
    "perfil": "operador",
    "tenant_id": "uuid"
  }
}
```

---

## 8.3 Usuários

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/usuarios` | Listar (admin) |
| POST | `/usuarios` | Criar |
| GET | `/usuarios/:id` | Detalhe |
| PUT | `/usuarios/:id` | Atualizar |
| DELETE | `/usuarios/:id` | Desativar |

---

## 8.4 Fazendas

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/fazendas` | Listar |
| POST | `/fazendas` | Criar |
| GET | `/fazendas/:id` | Detalhe |
| PUT | `/fazendas/:id` | Atualizar |

---

## 8.5 Currais

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/currais` | Listar (`?fazenda_id=&ativo=true`) |
| POST | `/currais` | Criar |
| GET | `/currais/:id` | Detalhe |
| PUT | `/currais/:id` | Atualizar |
| PUT | `/currais/:id/tag` | Associar RFID |
| DELETE | `/currais/:id/tag` | Remover tag |
| GET | `/currais/por-tag/:epc` | Busca por EPC |

### PUT `/currais/:id/tag`

**Request:**
```json
{
  "epc": "E200001234567890"
}
```

---

## 8.6 Dietas

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/dietas` | Listar (`?fazenda_id=`) |
| POST | `/dietas` | Criar |
| GET | `/dietas/:id` | Detalhe |
| PUT | `/dietas/:id` | Atualizar |
| GET | `/dietas/:id/ingredientes` | Ingredientes da dieta |
| PUT | `/dietas/:id/ingredientes` | Substituir ingredientes |

---

## 8.7 Previsões

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/previsoes` | Listar (`?fazenda_id=&data=&trato=&dieta_id=`) |
| POST | `/previsoes` | Criar unitária |
| POST | `/previsoes/batch` | Criar/atualizar lote |
| POST | `/previsoes/import` | Upload Excel (multipart) |
| GET | `/previsoes/resumo` | Previsto vs realizado agregado |
| DELETE | `/previsoes/:id` | Remover |

### POST `/previsoes/batch`

**Request:**
```json
{
  "items": [
    {
      "fazenda_id": "uuid",
      "curral_id": "uuid",
      "dieta_id": "uuid",
      "data": "2026-06-09",
      "trato": 1,
      "previsto_kg": 1250.5
    }
  ]
}
```

**Response:**
```json
{
  "created": 45,
  "updated": 12,
  "errors": []
}
```

---

## 8.8 Fabricações

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/fabricacoes` | Listar (`?data=&status=&fazenda_id=`) |
| POST | `/fabricacoes` | Criar batida |
| GET | `/fabricacoes/:id` | Detalhe + itens |
| PUT | `/fabricacoes/:id` | Atualizar header |
| POST | `/fabricacoes/:id/finalizar` | Finalizar batida |
| POST | `/fabricacoes/:id/itens` | Registrar pesagem ingrediente |
| GET | `/fabricacoes/:id/itens` | Listar ingredientes |

### POST `/fabricacoes`

**Request:**
```json
{
  "fazenda_id": "uuid",
  "dieta_id": "uuid",
  "trato": 2,
  "data": "2026-06-09",
  "qtd_prevista_kg": 3500,
  "equipamento_id": "uuid",
  "device_id": "tablet-001",
  "evento_geo_inicio": {
    "latitude": -16.6799123,
    "longitude": -49.2550456,
    "accuracy": 8.5,
    "timestamp": "2026-06-09T06:15:00.000Z"
  }
}
```

### POST `/fabricacoes/:id/itens`

**Request:**
```json
{
  "ingrediente_id": "uuid",
  "ordem": 3,
  "qtd_realizada_kg": 450.75,
  "hora_inicio": "2026-06-09T06:20:00.000Z",
  "hora_fim": "2026-06-09T06:25:30.000Z"
}
```

### Webhook `fabricacao.finalizada`

```json
{
  "event": "fabricacao.finalizada",
  "tenant_id": "uuid",
  "timestamp": "2026-06-09T06:45:00.000Z",
  "data": {
    "fabricacao_id": "uuid",
    "dieta_nome": "Terminação 18% PB",
    "trato": 2,
    "qtd_realizada_kg": 3480.5,
    "ms_realizada": 62.3,
    "fazenda_id": "uuid"
  }
}
```

---

## 8.9 Fornecimentos

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/fornecimentos` | Listar (`?data=&trato=&curral_id=`) |
| POST | `/fornecimentos` | Registrar entrega |
| GET | `/fornecimentos/:id` | Detalhe |
| GET | `/fornecimentos/sessoes` | Sessões agrupadas (dashboard) |

### POST `/fornecimentos`

**Request:**
```json
{
  "carregamento_id": "uuid",
  "fabricacao_id": "uuid",
  "curral_id": "uuid",
  "dieta_id": "uuid",
  "trato": 2,
  "data": "2026-06-09",
  "realizado_kg": 320.5,
  "peso_inicio_kg": 12500.0,
  "peso_fim_kg": 12179.5,
  "origem": "rfid",
  "device_id": "tablet-001",
  "evento_geo_inicio": {
    "latitude": -16.6801000,
    "longitude": -49.2548000,
    "accuracy": 15.0,
    "timestamp": "2026-06-09T08:10:00.000Z"
  },
  "evento_geo_fim": {
    "latitude": -16.6800500,
    "longitude": -49.2547500,
    "accuracy": 12.0,
    "timestamp": "2026-06-09T08:18:45.000Z"
  }
}
```

**Response 200 (normal):**
```json
{
  "id": "uuid",
  "realizado_kg": 320.5,
  "realizado_acumulado_kg": 640.5,
  "ms_realizada": 62.3,
  "modo": "acumulativo"
}
```

**Response 200 (ponto corte):**
```json
{
  "id": null,
  "ignorado_ponto_corte": true,
  "ponto_corte_kg": 50,
  "realizado_kg": 30,
  "modo": "ignorado_ponto_corte"
}
```

---

## 8.10 Eventos Geo

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/eventos-geo` | Registro unitário |
| GET | `/eventos-geo` | Listar (`?tipo=&data_ini=&data_fim=&fazenda_id=`) |
| GET | `/mapas/operacoes` | GeoJSON para Leaflet |

### GET `/mapas/operacoes?fazenda_id=&data=2026-06-09`

**Response (GeoJSON):**
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { "type": "Point", "coordinates": [-49.255, -16.680] },
      "properties": {
        "tipo": "FORNECIMENTO_FIM",
        "curral_nome": "Curral 12",
        "referencia_id": "uuid",
        "accuracy": 12.0,
        "timestamp": "2026-06-09T08:18:45.000Z"
      }
    }
  ]
}
```

---

## 8.11 Sync (mobile)

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/sync/bootstrap` | Download cadastros + previsão |
| POST | `/sync/batch` | Upload operações pendentes |
| GET | `/sync/status` | Status último sync por device |

### GET `/sync/bootstrap?fazenda_id=&data=2026-06-09&since=2026-06-08T00:00:00Z`

**Response:**
```json
{
  "server_time": "2026-06-09T10:00:00.000Z",
  "currais": [...],
  "dietas": [...],
  "ingredientes": [...],
  "dieta_ingredientes": [...],
  "previsoes": [...],
  "equipamentos": [...],
  "tenant_settings": {
    "fornecimento_acumulativo": true,
    "ponto_corte_fornecimento_kg": 50
  }
}
```

### POST `/sync/batch`

**Request:**
```json
{
  "device_id": "tablet-001",
  "fabricacoes": [...],
  "fabricacao_itens": [...],
  "fornecimentos": [...],
  "eventos_geo": [...],
  "tags": [...]
}
```

**Response:**
```json
{
  "accepted": {
    "fabricacoes": 2,
    "fornecimentos": 15,
    "eventos_geo": 30
  },
  "errors": [
    {
      "entity": "fornecimento",
      "local_id": "local-uuid",
      "code": "DUPLICATE",
      "message": "Já sincronizado"
    }
  ],
  "server_ids": {
    "local-uuid-1": "server-uuid-1"
  }
}
```

---

## 8.12 Import Excel

| Método | Path | Descrição |
|--------|------|-----------|
| POST | `/import/previsao` | Upload `.xlsx` previsão |
| GET | `/import/previsao/template` | Download template |
| GET | `/import/jobs/:id` | Status job import |

---

## 8.13 Dashboard

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/dashboard/resumo` | KPIs dia (`?fazenda_id=&data=`) |
| GET | `/dashboard/fabricacao` | Detalhe fabricações |
| GET | `/dashboard/fornecimento` | Detalhe fornecimentos |
| GET | `/dashboard/previsao-realizado` | Por trato/curral |

---

## 8.14 Equipamentos

| Método | Path | Descrição |
|--------|------|-----------|
| GET | `/equipamentos` | Listar |
| POST | `/equipamentos` | Criar |
| PUT | `/equipamentos/:id` | Atualizar |

---

## 8.15 Integração externa (API Key)

Header adicional para ERPs:

```
X-Api-Key: {tenant_api_key}
```

Endpoints disponíveis com API Key:
- `POST /previsoes/batch`
- `GET /previsoes`
- `GET /fornecimentos`
- `GET /fabricacoes`
- Webhooks configuráveis em `POST /tenant/webhooks`

---

## 8.16 Códigos de erro padrão

| HTTP | Code | Descrição |
|------|------|-----------|
| 400 | `VALIDATION_ERROR` | Payload inválido |
| 401 | `UNAUTHORIZED` | Token inválido/expirado |
| 403 | `FORBIDDEN` | Sem permissão |
| 404 | `NOT_FOUND` | Recurso não encontrado |
| 409 | `DUPLICATE` | Idempotency key duplicada |
| 422 | `BUSINESS_RULE` | Regra negócio (MS inválida, etc.) |
| 429 | `RATE_LIMIT` | Throttle API Key |
| 500 | `INTERNAL` | Erro interno |

**Formato erro:**
```json
{
  "error": {
    "code": "BUSINESS_RULE",
    "message": "MS deve estar entre 0 e 100",
    "details": { "field": "ms_realizada", "value": 105 }
  }
}
```

---

## 8.17 Compatibilidade RFeed Horse (referência)

| Horse (RFeed) | Lite equivalente |
|---------------|------------------|
| `GET /GetTeste` | `GET /health` |
| `GET /fazenda/get` | `GET /fazendas` |
| `GET /usuarios/get/:idfazenda` | `GET /usuarios` |
| `GET /baias/get/:idfazenda` | `GET /currais?fazenda_id=` |
| `GET /previsaotrato/get/:id/:data` | `GET /previsoes?fazenda_id=&data=` |
| `POST /Post/Fabricacao` | `POST /fabricacoes` |
| `POST /Post/Fabricacao_Insumo` | `POST /fabricacoes/:id/itens` |
| `POST /Post/Fornecimento` | `POST /fornecimentos` |
| `POST /Post/GravaTag` | `PUT /currais/:id/tag` |
| `POST /Post/GpsTrack` | `POST /eventos-geo` (modelo diferente) |

---

## 8.18 OpenAPI spec

Gerar spec formal com:

```bash
# NestJS + @nestjs/swagger
npm run build
# → swagger.json em /api/docs
```

Tags Swagger: `Auth`, `Usuarios`, `Currais`, `Dietas`, `Previsoes`, `Fabricacoes`, `Fornecimentos`, `EventosGeo`, `Sync`, `Import`, `Dashboard`.
