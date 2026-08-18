-- =============================================================================
-- FieldPec Online — cria ROLE + DATABASE no PostgreSQL
-- Executar como superuser (ex.: postgres) conectado ao banco "postgres":
--
--   psql -U postgres -h 127.0.0.1 -d postgres -f create_database.sql
--
-- Depois aplique o schema no banco novo:
--   psql -U fieldpec -h 127.0.0.1 -d fieldpec_online -f schema.sql
--
-- Ou use o script Create-Database.ps1 / create-database.sh (faz os dois passos).
--
-- Variáveis padrão (altere se necessário antes de rodar):
--   DB_NAME=fieldpec_online
--   DB_USER=fieldpec
--   DB_PASSWORD=fieldpec
-- =============================================================================

\set ON_ERROR_STOP on

-- Role (login)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fieldpec') THEN
    CREATE ROLE fieldpec LOGIN PASSWORD 'fieldpec';
    RAISE NOTICE 'Role fieldpec criada.';
  ELSE
    RAISE NOTICE 'Role fieldpec já existe.';
  END IF;
END
$$;

-- Permissões básicas
ALTER ROLE fieldpec WITH LOGIN;
-- Descomente para trocar a senha em servidores já existentes:
-- ALTER ROLE fieldpec WITH PASSWORD 'fieldpec';

-- Database (CREATE DATABASE não pode rodar dentro de DO/transação)
SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_database WHERE datname = 'fieldpec_online')
    THEN 'SELECT 1 -- database fieldpec_online já existe'
  ELSE 'CREATE DATABASE fieldpec_online OWNER fieldpec ENCODING ''UTF8'' LC_COLLATE ''C'' LC_CTYPE ''C'' TEMPLATE template0'
END AS cmd
\gexec

GRANT ALL PRIVILEGES ON DATABASE fieldpec_online TO fieldpec;

\echo
\echo OK: role fieldpec + database fieldpec_online prontos.
\echo Próximo passo: aplicar schema.sql no banco fieldpec_online.
