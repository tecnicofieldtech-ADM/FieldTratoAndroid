# RFeed Lite

Produto separado do **RFeed** (CG Pec), construído por extração e reaproveitamento seletivo do código existente.

> ⚠️ Esta pasta **não altera** o RFeed em produção. É apenas documentação e plano de implementação.

## Documentação

| Documento | Descrição |
|-----------|-----------|
| [docs/README.md](docs/README.md) | Índice e resumo executivo |
| [docs/inventory.md](docs/inventory.md) | Inventário completo do RFeed |
| [docs/cgpec_dependencies.md](docs/cgpec_dependencies.md) | Dependências CG Pec |
| [docs/folder_structure.md](docs/folder_structure.md) | Estrutura de pastas proposta |
| [docs/openapi_draft.md](docs/openapi_draft.md) | Rascunho API REST |
| [architecture/architecture_rfeed_lite.md](architecture/architecture_rfeed_lite.md) | Arquitetura alvo |
| [architecture/geolocation_strategy.md](architecture/geolocation_strategy.md) | Estratégia geo |
| [database/database_model.md](database/database_model.md) | Modelo PostgreSQL |
| [migration/module_extraction.md](migration/module_extraction.md) | Extração por módulo |
| [migration/migration_roadmap.md](migration/migration_roadmap.md) | Roadmap 6 sprints |

## Status

| Fase | Status |
|------|--------|
| Análise e documentação | ✅ Concluída |
| Scaffold código | ⏳ Pendente |
| MVP | ⏳ Pendente |

## Próximo passo

Executar **Sprint 1** conforme [migration/migration_roadmap.md](migration/migration_roadmap.md):

1. `docker-compose up` (NestJS + PostgreSQL)
2. Copiar `scale_comm.dart` / `rfid_comm.dart` para `packages/hardware/`
3. Migrations iniciais

## Reaproveitamento estimado

| Camada | % |
|--------|---|
| Hardware (balança/RFID) | 90–95% |
| UI Flutter (fab/forn) | 50–65% |
| Padrão offline/sync | 40–50% |
| Backend | 0% (NestJS greenfield) |

---

*RSistemas — junho/2026*
