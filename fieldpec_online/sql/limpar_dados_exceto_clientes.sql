-- ============================================================
-- Limpa dados do banco FieldPec Online
-- PRESERVA: tabela clientes (cadastro multi-tenant)
-- Apaga: cadastros, previsão, operações, logs, sync_meta
-- Rodar no DBeaver no banco da API (ex.: Teste_Field_Trato_Android)
-- ============================================================

BEGIN;

-- Filhos primeiro
TRUNCATE TABLE fabricacao_itens RESTART IDENTITY CASCADE;

TRUNCATE TABLE fabricacoes RESTART IDENTITY CASCADE;
TRUNCATE TABLE fornecimentos RESTART IDENTITY CASCADE;
TRUNCATE TABLE grava_tags RESTART IDENTITY CASCADE;
TRUNCATE TABLE audits RESTART IDENTITY CASCADE;
TRUNCATE TABLE gps_tracks RESTART IDENTITY CASCADE;
TRUNCATE TABLE request_logs RESTART IDENTITY CASCADE;

TRUNCATE TABLE previsao_trato CASCADE;
TRUNCATE TABLE dietas_detalhes CASCADE;
TRUNCATE TABLE dietas CASCADE;
TRUNCATE TABLE baias CASCADE;
TRUNCATE TABLE vagoes CASCADE;
TRUNCATE TABLE usuarios CASCADE;
TRUNCATE TABLE fazendas CASCADE;

TRUNCATE TABLE sync_meta CASCADE;

COMMIT;

-- Conferência (clientes deve permanecer)
SELECT 'clientes' AS tabela, count(*)::int AS n FROM clientes
UNION ALL SELECT 'fazendas', count(*)::int FROM fazendas
UNION ALL SELECT 'usuarios', count(*)::int FROM usuarios
UNION ALL SELECT 'baias', count(*)::int FROM baias
UNION ALL SELECT 'dietas', count(*)::int FROM dietas
UNION ALL SELECT 'dietas_detalhes', count(*)::int FROM dietas_detalhes
UNION ALL SELECT 'previsao_trato', count(*)::int FROM previsao_trato
UNION ALL SELECT 'fabricacoes', count(*)::int FROM fabricacoes
UNION ALL SELECT 'fornecimentos', count(*)::int FROM fornecimentos
UNION ALL SELECT 'request_logs', count(*)::int FROM request_logs
ORDER BY 1;
