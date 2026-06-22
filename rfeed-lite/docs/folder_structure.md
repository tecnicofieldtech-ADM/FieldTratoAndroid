# Fase 4 — Estrutura de Pastas do RFeed Lite

Proposta de monorepo separado do RFeed atual.

---

## 4.1 Visão geral

```
rfeed-lite/
├── mobile/                 # App Flutter (tablet campo)
├── backend/                # NestJS API
├── web/                    # Backoffice web
├── packages/               # Pacotes Dart compartilhados (opcional)
│   └── hardware/           # scale_comm + rfid_comm extraídos
├── docs/                   # Documentação (esta análise)
├── architecture/           # Diagramas e decisões
├── database/               # Schema, migrations, seeds
├── migration/              # Planos de extração e roadmap
├── docker/                 # docker-compose on-premise
├── scripts/                # CI/CD, setup, import templates
└── README.md
```

---

## 4.2 Mobile (`mobile/`)

```
mobile/
├── pubspec.yaml
├── android/
├── assets/
└── lib/
    ├── main.dart
    ├── app.dart                    # MaterialApp, rotas, tema
    │
    ├── core/                       # Infraestrutura transversal
    │   ├── config/
    │   │   ├── app_config.dart     # URL API, tenant slug
    │   │   └── device_profile.dart # balança/RFID habilitados
    │   ├── database/
    │   │   ├── app_database.dart   # SQLite singleton
    │   │   ├── migrations/       # v1, v2, ...
    │   │   └── tables/           # Definições de tabelas
    │   ├── network/
    │   │   ├── api_client.dart     # Dio + JWT interceptor
    │   │   ├── auth_interceptor.dart
    │   │   └── sync_client.dart    # Batch upload/download
    │   ├── sync/
    │   │   ├── outbox_queue.dart   # Fila de envio
    │   │   ├── bootstrap_sync.dart # Download cadastros
    │   │   └── sync_orchestrator.dart
    │   ├── auth/
    │   │   ├── auth_service.dart
    │   │   ├── token_storage.dart  # Secure storage
    │   │   └── session.dart
    │   ├── geo/
    │   │   ├── geo_capture_service.dart
    │   │   └── geo_repository.dart
    │   └── utils/
    │       ├── ms_percent.dart     # ← copiado do RFeed
    │       └── formatters.dart
    │
    ├── data/                       # Implementações de repositório
    │   ├── repositories/
    │   │   ├── fabricacao_repository_impl.dart
    │   │   ├── fornecimento_repository_impl.dart
    │   │   ├── curral_repository_impl.dart
    │   │   └── previsao_repository_impl.dart
    │   └── datasources/
    │       ├── local/              # SQLite DAOs
    │       └── remote/             # API calls
    │
    ├── domain/                     # Contratos e modelos puros
    │   ├── entities/
    │   │   ├── fabricacao.dart
    │   │   ├── fornecimento.dart
    │   │   ├── curral.dart
    │   │   └── evento_geo.dart
    │   ├── repositories/           # Interfaces abstratas
    │   └── usecases/
    │       ├── criar_fabricacao.dart
    │       ├── finalizar_fornecimento.dart
    │       └── sincronizar_pendentes.dart
    │
    ├── features/                   # UI por feature (vertical slice)
    │   ├── auth/
    │   │   └── ui/login_page.dart
    │   ├── config/
    │   │   └── ui/config_page.dart
    │   ├── sync/
    │   │   └── ui/sync_page.dart
    │   ├── menu/
    │   │   └── ui/menu_page.dart
    │   ├── fabricacao/
    │   │   ├── ui/
    │   │   │   ├── fabricacao_list_page.dart    # ← adaptar RFeed
    │   │   │   ├── fabricacao_prefab_page.dart
    │   │   │   ├── fabricacao_weigh_page.dart
    │   │   │   └── mistura_timer_page.dart
    │   │   └── controller/
    │   │       └── fabricacao_controller.dart
    │   ├── fornecimento/
    │   │   ├── ui/
    │   │   │   ├── fornecimento_list_page.dart
    │   │   │   ├── fornecimento_pre_page.dart
    │   │   │   ├── fornecimento_weigh_page.dart
    │   │   │   └── fornecimento_dashboard_page.dart
    │   │   └── controller/
    │   │       └── fornecimento_controller.dart
    │   └── tags/
    │       └── ui/grava_tag_page.dart
    │
    └── shared/                     # Widgets e hardware reutilizáveis
        ├── hardware/
        │   ├── scale_comm.dart     # ← copiado do RFeed (95%)
        │   ├── rfid_comm.dart      # ← copiado do RFeed (95%)
        │   └── balanca_parser.dart # ← copiado do RFeed
        └── widgets/
            ├── scale_peso_card.dart
            ├── app_version_label.dart
            └── loading_overlay.dart
```

### Explicação das pastas mobile

| Pasta | Responsabilidade |
|-------|------------------|
| `core/` | Infra que não é feature: DB, rede, sync, auth, geo |
| `data/` | Implementação concreta dos repositórios (local + remote) |
| `domain/` | Entidades e contratos — **sem Flutter, sem SQLite** |
| `features/` | UI + controller por módulo de negócio |
| `shared/` | Widgets e drivers hardware compartilhados |

---

## 4.3 Backend (`backend/`)

```
backend/
├── package.json
├── nest-cli.json
├── tsconfig.json
├── docker-compose.yml
├── .env.example
└── src/
    ├── main.ts
    ├── app.module.ts
    ├── common/
    │   ├── guards/
    │   ├── interceptors/
    │   ├── filters/
    │   └── decorators/
    ├── config/
    ├── database/
    │   ├── migrations/
    │   └── seeds/
    └── modules/
        ├── auth/
        ├── tenant/
        ├── usuario/
        ├── fazenda/
        ├── curral/
        ├── tag-rfid/
        ├── dieta/
        ├── ingrediente/
        ├── previsao/
        ├── fabricacao/
        ├── fornecimento/
        ├── evento-geo/
        ├── equipamento/
        ├── sync/
        ├── import/
        └── dashboard/
```

---

## 4.4 Web (`web/`)

```
web/
├── package.json
└── src/
    ├── app/                        # Next.js App Router
    │   ├── (auth)/login/
    │   ├── (dashboard)/
    │   │   ├── currais/
    │   │   ├── dietas/
    │   │   ├── previsoes/
    │   │   ├── fabricacoes/
    │   │   ├── fornecimentos/
    │   │   ├── import/             # Upload Excel
    │   │   └── mapa/               # Leaflet
    │   └── api/                    # BFF opcional
    ├── components/
    │   ├── map/                    # Leaflet wrapper
    │   ├── tables/
    │   └── forms/
    └── lib/
        └── api-client.ts
```

---

## 4.5 Pacote hardware compartilhado (opcional)

```
packages/hardware/
├── pubspec.yaml
└── lib/
    ├── scale_comm.dart
    ├── rfid_comm.dart
    └── balanca_parser.dart
```

Permite usar os mesmos drivers no RFeed (via path dependency) e no Lite sem duplicação.

---

## 4.6 Mapeamento RFeed → Lite

| RFeed (`lib/`) | Lite (`mobile/lib/`) |
|----------------|----------------------|
| `helpers/scale_comm.dart` | `shared/hardware/scale_comm.dart` |
| `helpers/rfid_comm.dart` | `shared/hardware/rfid_comm.dart` |
| `features/fornecimento/services/balanca_parser.dart` | `shared/hardware/balanca_parser.dart` |
| `utils/ms_percent.dart` | `core/utils/ms_percent.dart` |
| `db/app_db.dart` | `core/database/app_database.dart` (schema novo) |
| `services/outbox_sync.dart` | `core/sync/outbox_queue.dart` |
| `services/api_service.dart` | `core/network/api_client.dart` |
| `features/fabricacao/ui/*` | `features/fabricacao/ui/*` (adaptado) |
| `features/fornecimento/ui/*` | `features/fornecimento/ui/*` (adaptado) |
| `features/estacionario/*` | **Não migrar** |
| `helpers/mirror_service.dart` | **Não migrar** |

---

## 4.7 Convenções

| Aspecto | Convenção |
|---------|-----------|
| IDs | UUID v4 everywhere |
| Datas API | ISO 8601 UTC |
| Datas UI | dd/MM/yyyy (pt-BR) |
| Pesos | `DECIMAL(12,3)` kg, vírgula só na UI |
| Tenant | Sempre via JWT, nunca query param exposto |
| Sync | `sync_status`: `pending`, `synced`, `error` |
| Testes | `*_test.dart` / `*.spec.ts` colocated |
