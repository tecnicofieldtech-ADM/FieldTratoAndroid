-- ============================================================
-- FieldPec Online — criar/atualizar tabelas (rodar no DBeaver)
-- Banco: o mesmo do .env da API (ex.: Teste_Field_Trato_Android)
-- Pode executar várias vezes (idempotente).
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1) Clientes (multi-tenant)
CREATE TABLE IF NOT EXISTS clientes (
  codigo TEXT PRIMARY KEY,
  nome TEXT NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  token TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO clientes (codigo, nome, ativo)
VALUES ('DEMO', 'Cliente demonstração', TRUE)
ON CONFLICT (codigo) DO NOTHING;

-- 2) Se as tabelas já existem sem cliente_codigo, migra para DEMO
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='fazendas')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='fazendas' AND column_name='cliente_codigo') THEN
    ALTER TABLE fazendas ADD COLUMN cliente_codigo TEXT;
    UPDATE fazendas SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE fazendas ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE fazendas DROP CONSTRAINT IF EXISTS fazendas_pkey;
    ALTER TABLE fazendas ADD PRIMARY KEY (cliente_codigo, idfazenda);
    ALTER TABLE fazendas DROP CONSTRAINT IF EXISTS fazendas_cliente_codigo_fkey;
    ALTER TABLE fazendas ADD CONSTRAINT fazendas_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='usuarios')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='usuarios' AND column_name='cliente_codigo') THEN
    ALTER TABLE usuarios ADD COLUMN cliente_codigo TEXT;
    UPDATE usuarios SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE usuarios ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuarios_pkey;
    ALTER TABLE usuarios ADD PRIMARY KEY (cliente_codigo, id);
    ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuarios_cliente_codigo_fkey;
    ALTER TABLE usuarios ADD CONSTRAINT usuarios_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='vagoes')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='vagoes' AND column_name='cliente_codigo') THEN
    ALTER TABLE vagoes ADD COLUMN cliente_codigo TEXT;
    UPDATE vagoes SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE vagoes ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE vagoes DROP CONSTRAINT IF EXISTS vagoes_pkey;
    ALTER TABLE vagoes ADD PRIMARY KEY (cliente_codigo, id);
    ALTER TABLE vagoes DROP CONSTRAINT IF EXISTS vagoes_cliente_codigo_fkey;
    ALTER TABLE vagoes ADD CONSTRAINT vagoes_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='baias')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='baias' AND column_name='cliente_codigo') THEN
    ALTER TABLE baias ADD COLUMN cliente_codigo TEXT;
    UPDATE baias SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE baias ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE baias DROP CONSTRAINT IF EXISTS baias_pkey;
    ALTER TABLE baias ADD PRIMARY KEY (cliente_codigo, id_baia);
    ALTER TABLE baias DROP CONSTRAINT IF EXISTS baias_cliente_codigo_fkey;
    ALTER TABLE baias ADD CONSTRAINT baias_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='dietas')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='dietas' AND column_name='cliente_codigo') THEN
    ALTER TABLE dietas ADD COLUMN cliente_codigo TEXT;
    UPDATE dietas SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE dietas ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE dietas DROP CONSTRAINT IF EXISTS dietas_pkey;
    ALTER TABLE dietas ADD PRIMARY KEY (cliente_codigo, id);
    ALTER TABLE dietas DROP CONSTRAINT IF EXISTS dietas_cliente_codigo_fkey;
    ALTER TABLE dietas ADD CONSTRAINT dietas_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='dietas_detalhes')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='dietas_detalhes' AND column_name='cliente_codigo') THEN
    ALTER TABLE dietas_detalhes ADD COLUMN cliente_codigo TEXT;
    UPDATE dietas_detalhes SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE dietas_detalhes ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE dietas_detalhes DROP CONSTRAINT IF EXISTS dietas_detalhes_pkey;
    ALTER TABLE dietas_detalhes ADD PRIMARY KEY (cliente_codigo, id);
    ALTER TABLE dietas_detalhes DROP CONSTRAINT IF EXISTS dietas_detalhes_cliente_codigo_fkey;
    ALTER TABLE dietas_detalhes ADD CONSTRAINT dietas_detalhes_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='previsao_trato')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='previsao_trato' AND column_name='cliente_codigo') THEN
    ALTER TABLE previsao_trato ADD COLUMN cliente_codigo TEXT;
    UPDATE previsao_trato SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE previsao_trato ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE previsao_trato DROP CONSTRAINT IF EXISTS previsao_trato_pkey;
    ALTER TABLE previsao_trato ADD PRIMARY KEY (cliente_codigo, id_fornecimento, data, id_baia, trato);
    ALTER TABLE previsao_trato DROP CONSTRAINT IF EXISTS previsao_trato_cliente_codigo_fkey;
    ALTER TABLE previsao_trato ADD CONSTRAINT previsao_trato_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='fabricacoes')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='fabricacoes' AND column_name='cliente_codigo') THEN
    ALTER TABLE fabricacoes ADD COLUMN cliente_codigo TEXT;
    UPDATE fabricacoes SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE fabricacoes ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE fabricacoes DROP CONSTRAINT IF EXISTS fabricacoes_cliente_codigo_fkey;
    ALTER TABLE fabricacoes ADD CONSTRAINT fabricacoes_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    DROP INDEX IF EXISTS uq_fab_handoff;
    DROP INDEX IF EXISTS uq_fab_id_local;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='fornecimentos')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='fornecimentos' AND column_name='cliente_codigo') THEN
    ALTER TABLE fornecimentos ADD COLUMN cliente_codigo TEXT;
    UPDATE fornecimentos SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    ALTER TABLE fornecimentos ALTER COLUMN cliente_codigo SET NOT NULL;
    ALTER TABLE fornecimentos DROP CONSTRAINT IF EXISTS fornecimentos_cliente_codigo_fkey;
    ALTER TABLE fornecimentos ADD CONSTRAINT fornecimentos_cliente_codigo_fkey FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='grava_tags')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='grava_tags' AND column_name='cliente_codigo') THEN
    ALTER TABLE grava_tags ADD COLUMN cliente_codigo TEXT;
    UPDATE grava_tags SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='audits')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audits' AND column_name='cliente_codigo') THEN
    ALTER TABLE audits ADD COLUMN cliente_codigo TEXT;
    UPDATE audits SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='gps_tracks')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='gps_tracks' AND column_name='cliente_codigo') THEN
    ALTER TABLE gps_tracks ADD COLUMN cliente_codigo TEXT;
    UPDATE gps_tracks SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='request_logs')
     AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='request_logs' AND column_name='cliente_codigo') THEN
    ALTER TABLE request_logs ADD COLUMN cliente_codigo TEXT;
  END IF;
END $$;

-- 3) Cria tabelas que ainda não existem (banco novo)
CREATE TABLE IF NOT EXISTS fazendas (
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  idfazenda TEXT NOT NULL,
  fazenda TEXT NOT NULL,
  cliente TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, idfazenda)
);

CREATE TABLE IF NOT EXISTS usuarios (
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id TEXT NOT NULL,
  nome TEXT NOT NULL,
  usuario TEXT NOT NULL,
  senha TEXT NOT NULL DEFAULT '',
  cargo TEXT,
  idfazenda TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, id)
);

CREATE TABLE IF NOT EXISTS vagoes (
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id TEXT NOT NULL,
  nome TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, id)
);

CREATE TABLE IF NOT EXISTS baias (
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id_baia TEXT NOT NULL,
  id_lote TEXT,
  nome_local TEXT,
  linha TEXT,
  ordem_trato INTEGER DEFAULT 0,
  id_fazenda TEXT,
  rfid TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, id_baia)
);

CREATE TABLE IF NOT EXISTS dietas (
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id TEXT NOT NULL,
  id_fazenda TEXT,
  nome_dieta TEXT NOT NULL,
  tipo_dieta TEXT,
  status TEXT,
  liberado TEXT,
  id_usuario TEXT,
  mn_total DOUBLE PRECISION,
  data_registro DATE,
  ms_dieta DOUBLE PRECISION,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, id)
);

CREATE TABLE IF NOT EXISTS dietas_detalhes (
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id TEXT NOT NULL,
  id_dieta TEXT NOT NULL,
  id_insumo TEXT,
  nome_dieta TEXT,
  tipo_dieta TEXT,
  ingrediente TEXT,
  ms_insumo DOUBLE PRECISION,
  ms_inclusao DOUBLE PRECISION,
  mn_perc DOUBLE PRECISION,
  ordem INTEGER DEFAULT 0,
  pre_pesagem TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, id)
);

CREATE TABLE IF NOT EXISTS previsao_trato (
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id_fornecimento TEXT NOT NULL,
  data DATE NOT NULL,
  id_baia TEXT NOT NULL,
  trato INTEGER NOT NULL,
  id_dieta TEXT,
  previsto DOUBLE PRECISION DEFAULT 0,
  previsto_original DOUBLE PRECISION,
  previsto_recalculado DOUBLE PRECISION,
  realizado DOUBLE PRECISION DEFAULT 0,
  ultimo_trato INTEGER DEFAULT 0,
  id_fazenda TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, id_fornecimento, data, id_baia, trato)
);

CREATE TABLE IF NOT EXISTS fabricacoes (
  id BIGSERIAL PRIMARY KEY,
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id_local TEXT,
  handoff_id TEXT,
  id_fazenda TEXT,
  id_dieta TEXT,
  data_fab DATE,
  id_usuario TEXT,
  id_operador TEXT,
  id_vagao TEXT,
  qtde_prevista DOUBLE PRECISION,
  qtde_realizada DOUBLE PRECISION,
  ms_prevista DOUBLE PRECISION,
  ms_realizada DOUBLE PRECISION,
  hora_inicio TEXT,
  hora_fim TEXT,
  lote_fabricacao TEXT,
  payload JSONB NOT NULL,
  pulled_to_fieldpec BOOLEAN NOT NULL DEFAULT FALSE,
  pulled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fabricacao_itens (
  id BIGSERIAL PRIMARY KEY,
  fabricacao_id BIGINT NOT NULL REFERENCES fabricacoes(id) ON DELETE CASCADE,
  id_local TEXT,
  id_insumo TEXT,
  qtde_prevista DOUBLE PRECISION,
  qtde_realizada DOUBLE PRECISION,
  ms_insumo DOUBLE PRECISION,
  hora_ini TEXT,
  hora_fim TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS fornecimentos (
  id BIGSERIAL PRIMARY KEY,
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  id_fornecimento TEXT,
  id_fabricacao_local TEXT,
  handoff_id_fabricacao TEXT,
  id_baia TEXT,
  id_racao TEXT,
  data_forn DATE,
  trato INTEGER,
  realizado DOUBLE PRECISION,
  ms_dieta_realizada DOUBLE PRECISION,
  id_usuario_lancamento TEXT,
  id_tratador TEXT,
  id_dieta_realizada TEXT,
  hora_inicio TEXT,
  hora_fim TEXT,
  lote_fabricacao TEXT,
  payload JSONB NOT NULL,
  pulled_to_fieldpec BOOLEAN NOT NULL DEFAULT FALSE,
  pulled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS grava_tags (
  id BIGSERIAL PRIMARY KEY,
  cliente_codigo TEXT REFERENCES clientes(codigo),
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audits (
  id BIGSERIAL PRIMARY KEY,
  cliente_codigo TEXT REFERENCES clientes(codigo),
  tipo TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gps_tracks (
  id BIGSERIAL PRIMARY KEY,
  cliente_codigo TEXT REFERENCES clientes(codigo),
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sync_meta (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS request_logs (
  id BIGSERIAL PRIMARY KEY,
  cliente_codigo TEXT,
  method TEXT NOT NULL,
  path TEXT NOT NULL,
  status_code INTEGER,
  duration_ms DOUBLE PRECISION,
  remote_ip TEXT,
  request_body JSONB,
  response_preview TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_fab_cliente_handoff
  ON fabricacoes (cliente_codigo, handoff_id)
  WHERE handoff_id IS NOT NULL AND handoff_id <> '';
CREATE UNIQUE INDEX IF NOT EXISTS uq_fab_cliente_id_local
  ON fabricacoes (cliente_codigo, id_local)
  WHERE id_local IS NOT NULL AND id_local <> '';
CREATE INDEX IF NOT EXISTS idx_fab_pending
  ON fabricacoes (cliente_codigo, pulled_to_fieldpec)
  WHERE pulled_to_fieldpec = FALSE;
CREATE INDEX IF NOT EXISTS idx_forn_pending
  ON fornecimentos (cliente_codigo, pulled_to_fieldpec)
  WHERE pulled_to_fieldpec = FALSE;
CREATE INDEX IF NOT EXISTS idx_previsao_cliente_data
  ON previsao_trato (cliente_codigo, data);
CREATE INDEX IF NOT EXISTS idx_request_logs_created ON request_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_request_logs_path ON request_logs (path);
CREATE INDEX IF NOT EXISTS idx_request_logs_cliente ON request_logs (cliente_codigo);

-- Conferência rápida
SELECT 'clientes' AS tabela, count(*)::int AS n FROM clientes
UNION ALL SELECT 'fazendas', count(*)::int FROM fazendas
UNION ALL SELECT 'usuarios', count(*)::int FROM usuarios
UNION ALL SELECT 'baias', count(*)::int FROM baias;
