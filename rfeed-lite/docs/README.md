# RFeed Lite — Plano de Extração e Reaproveitamento

> **Documento gerado a partir da análise do repositório RFeed em produção.**  
> O RFeed atual **não foi alterado**. Toda a documentação vive em `/rfeed-lite`.

## Objetivo

Definir como extrair e reutilizar o máximo possível do **RFeed** (Flutter + API Horse + integrações CG Pec) para acelerar o desenvolvimento do **RFeed Lite** — produto separado, multi-tenant, PostgreSQL próprio, sem dependência obrigatória do CG Pec.

## Visão do RFeed Lite

| Aspecto | RFeed (atual) | RFeed Lite |
|---------|---------------|------------|
| ERP | CG Pec / FieldPec (Firebird) | PostgreSQL próprio |
| Deploy | On-premise (exe + tablet) | SaaS ou On-premise |
| Multi-empresa | Por fazenda no CG Pec | `tenant_id` em todas as tabelas |
| Hardware | Balança + RFID TCP (opcional na prática) | Manual **ou** balança + RFID |
| Entrada de dados | Sync CG Pec + tablet | Web + Excel + API REST + tablet |
| Geolocalização | Trilha GPS contínua (server-side) | Geo nos marcos abrir/finalizar fab/forn |
| Backend | Delphi Horse | **NestJS** (proposto) |

## Índice da documentação

| Fase | Documento | Descrição |
|------|-----------|-----------|
| 1 | [inventory.md](./inventory.md) | Inventário completo do RFeed |
| 2 | [cgpec_dependencies.md](./cgpec_dependencies.md) | Dependências CG Pec a desacoplar |
| 3 | [../architecture/architecture_rfeed_lite.md](../architecture/architecture_rfeed_lite.md) | Arquitetura alvo |
| 4 | [folder_structure.md](./folder_structure.md) | Estrutura de pastas proposta |
| 5 | [../migration/module_extraction.md](../migration/module_extraction.md) | Extração por módulo |
| 6 | [../database/database_model.md](../database/database_model.md) | Modelo PostgreSQL |
| 7 | [../architecture/geolocation_strategy.md](../architecture/geolocation_strategy.md) | Estratégia de geolocalização |
| 8 | [openapi_draft.md](./openapi_draft.md) | Rascunho OpenAPI REST |
| 9 | [../migration/migration_roadmap.md](../migration/migration_roadmap.md) | Roadmap em sprints |

## Resumo executivo da análise

### Reaproveitamento estimado global

| Camada | Reaproveitamento | Estratégia |
|--------|------------------|------------|
| **Hardware (balança/RFID)** | **85–95%** | Copiar `scale_comm.dart`, `rfid_comm.dart`, parsers |
| **UI/UX Flutter (fab/forn)** | **50–65%** | Adaptar telas; remover CG Pec e estacionário |
| **Domínio (regras operacionais)** | **40–55%** | Histerese, tratos, previsão, acumulativo |
| **SQLite offline** | **30–40%** | Novo schema; manter padrão outbox |
| **Sync/API client** | **20–30%** | Reescrever para NestJS + JWT |
| **API Horse (Delphi)** | **0%** no Lite | Referência de contratos e regras |
| **Estacionário / PA / Mirror** | **0%** no MVP Lite | Fora de escopo v1 |

### Decisão arquitetural principal

**Não evoluir o RFeed in-place.** Criar monorepo `rfeed-lite/` com:

- `mobile/` — Flutter extraído e limpo
- `backend/` — NestJS + PostgreSQL + S3
- `web/` — Backoffice (cadastros, import Excel, mapas Leaflet)
- `docs/` — Esta documentação

O RFeed permanece intacto para clientes CG Pec existentes.

## Próximos passos recomendados

1. Validar escopo do MVP (manual + sync + geo marcos).
2. Scaffold NestJS + schema PostgreSQL (Sprint 1).
3. Extrair `scale_comm` / `rfid_comm` para pacote Dart compartilhado.
4. Implementar API auth + CRUD tenant/fazenda/curral.
5. Portar fluxo fornecimento manual como primeiro fluxo de campo.

---

*Gerado em: junho/2026 — baseado no código em `main` (RFeed 1.0.13+2022).*
