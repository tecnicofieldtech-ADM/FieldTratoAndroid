-- Log de requisições HTTP (painel admin) — multi-tenant
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

ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS cliente_codigo TEXT;
