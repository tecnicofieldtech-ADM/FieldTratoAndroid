-- Migração multi-tenant para bancos já existentes (sem cliente_codigo).
-- Idempotente: pode rodar mais de uma vez.
-- Dados atuais vão para o cliente DEMO.

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

-- Helper: adiciona coluna se não existir
DO $$
BEGIN
  -- fazendas
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='fazendas') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='fazendas' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE fazendas ADD COLUMN cliente_codigo TEXT;
      UPDATE fazendas SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE fazendas ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE fazendas DROP CONSTRAINT IF EXISTS fazendas_pkey;
      ALTER TABLE fazendas ADD PRIMARY KEY (cliente_codigo, idfazenda);
      ALTER TABLE fazendas
        DROP CONSTRAINT IF EXISTS fazendas_cliente_codigo_fkey;
      ALTER TABLE fazendas
        ADD CONSTRAINT fazendas_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- usuarios
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='usuarios') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='usuarios' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE usuarios ADD COLUMN cliente_codigo TEXT;
      UPDATE usuarios SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE usuarios ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE usuarios DROP CONSTRAINT IF EXISTS usuarios_pkey;
      ALTER TABLE usuarios ADD PRIMARY KEY (cliente_codigo, id);
      ALTER TABLE usuarios
        ADD CONSTRAINT usuarios_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- vagoes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='vagoes') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='vagoes' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE vagoes ADD COLUMN cliente_codigo TEXT;
      UPDATE vagoes SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE vagoes ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE vagoes DROP CONSTRAINT IF EXISTS vagoes_pkey;
      ALTER TABLE vagoes ADD PRIMARY KEY (cliente_codigo, id);
      ALTER TABLE vagoes
        ADD CONSTRAINT vagoes_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- baias
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='baias') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='baias' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE baias ADD COLUMN cliente_codigo TEXT;
      UPDATE baias SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE baias ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE baias DROP CONSTRAINT IF EXISTS baias_pkey;
      ALTER TABLE baias ADD PRIMARY KEY (cliente_codigo, id_baia);
      ALTER TABLE baias
        ADD CONSTRAINT baias_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- dietas
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dietas') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='dietas' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE dietas ADD COLUMN cliente_codigo TEXT;
      UPDATE dietas SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE dietas ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE dietas DROP CONSTRAINT IF EXISTS dietas_pkey;
      ALTER TABLE dietas ADD PRIMARY KEY (cliente_codigo, id);
      ALTER TABLE dietas
        ADD CONSTRAINT dietas_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- dietas_detalhes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dietas_detalhes') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='dietas_detalhes' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE dietas_detalhes ADD COLUMN cliente_codigo TEXT;
      UPDATE dietas_detalhes SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE dietas_detalhes ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE dietas_detalhes DROP CONSTRAINT IF EXISTS dietas_detalhes_pkey;
      ALTER TABLE dietas_detalhes ADD PRIMARY KEY (cliente_codigo, id);
      ALTER TABLE dietas_detalhes
        ADD CONSTRAINT dietas_detalhes_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- previsao_trato
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='previsao_trato') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='previsao_trato' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE previsao_trato ADD COLUMN cliente_codigo TEXT;
      UPDATE previsao_trato SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE previsao_trato ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE previsao_trato DROP CONSTRAINT IF EXISTS previsao_trato_pkey;
      ALTER TABLE previsao_trato
        ADD PRIMARY KEY (cliente_codigo, id_fornecimento, data, id_baia, trato);
      ALTER TABLE previsao_trato
        ADD CONSTRAINT previsao_trato_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- fabricacoes
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='fabricacoes') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='fabricacoes' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE fabricacoes ADD COLUMN cliente_codigo TEXT;
      UPDATE fabricacoes SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE fabricacoes ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE fabricacoes
        ADD CONSTRAINT fabricacoes_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
      DROP INDEX IF EXISTS uq_fab_handoff;
      DROP INDEX IF EXISTS uq_fab_id_local;
      CREATE UNIQUE INDEX IF NOT EXISTS uq_fab_cliente_handoff
        ON fabricacoes (cliente_codigo, handoff_id)
        WHERE handoff_id IS NOT NULL AND handoff_id <> '';
      CREATE UNIQUE INDEX IF NOT EXISTS uq_fab_cliente_id_local
        ON fabricacoes (cliente_codigo, id_local)
        WHERE id_local IS NOT NULL AND id_local <> '';
    END IF;
  END IF;

  -- fornecimentos
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='fornecimentos') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='fornecimentos' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE fornecimentos ADD COLUMN cliente_codigo TEXT;
      UPDATE fornecimentos SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
      ALTER TABLE fornecimentos ALTER COLUMN cliente_codigo SET NOT NULL;
      ALTER TABLE fornecimentos
        ADD CONSTRAINT fornecimentos_cliente_codigo_fkey
        FOREIGN KEY (cliente_codigo) REFERENCES clientes(codigo);
    END IF;
  END IF;

  -- grava_tags / audits / gps / request_logs
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='grava_tags') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='grava_tags' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE grava_tags ADD COLUMN cliente_codigo TEXT REFERENCES clientes(codigo);
      UPDATE grava_tags SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='audits') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='audits' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE audits ADD COLUMN cliente_codigo TEXT REFERENCES clientes(codigo);
      UPDATE audits SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='gps_tracks') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='gps_tracks' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE gps_tracks ADD COLUMN cliente_codigo TEXT REFERENCES clientes(codigo);
      UPDATE gps_tracks SET cliente_codigo = 'DEMO' WHERE cliente_codigo IS NULL;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='request_logs') THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name='request_logs' AND column_name='cliente_codigo'
    ) THEN
      ALTER TABLE request_logs ADD COLUMN cliente_codigo TEXT;
    END IF;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_previsao_cliente_data
  ON previsao_trato (cliente_codigo, data);
CREATE INDEX IF NOT EXISTS idx_fab_pending
  ON fabricacoes (cliente_codigo, pulled_to_fieldpec)
  WHERE pulled_to_fieldpec = FALSE;
CREATE INDEX IF NOT EXISTS idx_forn_pending
  ON fornecimentos (cliente_codigo, pulled_to_fieldpec)
  WHERE pulled_to_fieldpec = FALSE;
CREATE INDEX IF NOT EXISTS idx_request_logs_cliente ON request_logs (cliente_codigo);
