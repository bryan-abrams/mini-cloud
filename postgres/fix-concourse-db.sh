#!/bin/sh
# Create concourse user and database in existing Postgres (safe if init ran after volume existed).
# Run once from repo root: ./postgres/fix-concourse-db.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Ensuring concourse role exists..."
docker exec -i postgres psql -U gitea -d postgres < "$SCRIPT_DIR/ensure-concourse-user.sql"
echo "Ensuring concourse database exists..."
docker exec postgres psql -U gitea -d postgres -c "CREATE DATABASE concourse OWNER concourse" 2>/dev/null || true
echo "Done. Restart concourse-web: docker compose restart concourse-web"
