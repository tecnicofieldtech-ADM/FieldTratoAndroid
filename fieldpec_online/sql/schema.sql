-- FieldPec Online — schema Postgres multi-tenant
-- Isolamento por cliente_codigo (mesmo API + mesmo banco, N clientes).

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

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

-- Cadastros (master)
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
  previsto_cadastro DOUBLE PRECISION,
  realizado DOUBLE PRECISION DEFAULT 0,
  ultimo_trato INTEGER DEFAULT 0,
  id_fazenda TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (cliente_codigo, id_fornecimento, data, id_baia, trato)
);

CREATE INDEX IF NOT EXISTS idx_previsao_cliente_data
  ON previsao_trato (cliente_codigo, data);
CREATE INDEX IF NOT EXISTS idx_previsao_cliente_fazenda
  ON previsao_trato (cliente_codigo, id_fazenda);

ALTER TABLE previsao_trato
  ADD COLUMN IF NOT EXISTS previsto_cadastro DOUBLE PRECISION;

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

CREATE UNIQUE INDEX IF NOT EXISTS uq_fab_cliente_handoff
  ON fabricacoes (cliente_codigo, handoff_id)
  WHERE handoff_id IS NOT NULL AND handoff_id <> '';
CREATE UNIQUE INDEX IF NOT EXISTS uq_fab_cliente_id_local
  ON fabricacoes (cliente_codigo, id_local)
  WHERE id_local IS NOT NULL AND id_local <> '';
CREATE INDEX IF NOT EXISTS idx_fab_pending
  ON fabricacoes (cliente_codigo, pulled_to_fieldpec)
  WHERE pulled_to_fieldpec = FALSE;

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

CREATE INDEX IF NOT EXISTS idx_forn_pending
  ON fornecimentos (cliente_codigo, pulled_to_fieldpec)
  WHERE pulled_to_fieldpec = FALSE;

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

CREATE INDEX IF NOT EXISTS idx_request_logs_created ON request_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_request_logs_path ON request_logs (path);
CREATE INDEX IF NOT EXISTS idx_request_logs_cliente ON request_logs (cliente_codigo);

-- Modo Planilha
CREATE TABLE IF NOT EXISTS planilha_importacoes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_codigo TEXT NOT NULL REFERENCES clientes(codigo),
  versao_layout INTEGER NOT NULL DEFAULT 1,
  arquivo_nome TEXT,
  arquivo_hash TEXT,
  fazenda_codigo TEXT,
  descricao TEXT,
  status TEXT NOT NULL DEFAULT 'ok',
  totais JSONB NOT NULL DEFAULT '{}'::jsonb,
  erros JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_planilha_cliente_hash
  ON planilha_importacoes (cliente_codigo, arquivo_hash)
  WHERE arquivo_hash IS NOT NULL AND arquivo_hash <> '';

CREATE INDEX IF NOT EXISTS idx_planilha_cliente_created
  ON planilha_importacoes (cliente_codigo, created_at DESC);

ALTER TABLE fornecimentos
  ADD COLUMN IF NOT EXISTS id_cadastro TEXT;
ALTER TABLE fornecimentos
  ADD COLUMN IF NOT EXISTS importacao_id UUID;
ALTER TABLE fornecimentos
  ADD COLUMN IF NOT EXISTS peso_inicio DOUBLE PRECISION;
ALTER TABLE fornecimentos
  ADD COLUMN IF NOT EXISTS peso_fim DOUBLE PRECISION;

ALTER TABLE fabricacoes
  ADD COLUMN IF NOT EXISTS importacao_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS uq_forn_cliente_id_cadastro
  ON fornecimentos (cliente_codigo, id_cadastro)
  WHERE id_cadastro IS NOT NULL AND id_cadastro <> '';

