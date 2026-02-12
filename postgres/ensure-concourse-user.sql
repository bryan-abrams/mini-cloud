-- Ensure concourse role exists (idempotent). Run against database 'postgres'.
-- Usage: docker exec -i postgres psql -U gitea -d postgres -f - < postgres/ensure-concourse-user.sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'concourse') THEN
    CREATE ROLE concourse WITH LOGIN PASSWORD 'concourse';
  END IF;
END
$$;
