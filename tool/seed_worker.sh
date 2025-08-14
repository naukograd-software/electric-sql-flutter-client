#!/usr/bin/env bash
set -euo pipefail

# --- Constants matching Electric's docker-compose.yaml ---
# See: https://github.com/electric-sql/electric/blob/main/website/public/docker-compose.yaml
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.yaml}
DB_SERVICE=${DB_SERVICE:-postgres}
DB_NAME=${DB_NAME:-electric}
DB_USER=${DB_USER:-postgres}
PGHOST=${PGHOST:-localhost}
PGPORT=${PGPORT:-54321}
PGUSER=${PGUSER:-${DB_USER}}
PGPASSWORD=${PGPASSWORD:-password}
TABLE=${TABLE:-public.widgets}
INTERVAL=${INTERVAL:-2}
USE_DOCKER=${USE_DOCKER:-1}

log() { echo "[seed-worker] $*"; }

run_psql() {
  local sql="$1"
  PGPASSWORD="${PGPASSWORD}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${DB_NAME}" -c "$sql"
}

log "compose=${COMPOSE_FILE} service=${DB_SERVICE} db=${DB_NAME} user=${DB_USER}"
log "table=${TABLE} interval=${INTERVAL}s docker=${USE_DOCKER}"

create_sql="CREATE TABLE IF NOT EXISTS ${TABLE} (id SERIAL PRIMARY KEY, name TEXT NOT NULL, priority INT NOT NULL DEFAULT 10);"
run_psql "${create_sql}" >/dev/null

cleanup() { log "Stopping..."; exit 0; }
trap cleanup INT TERM

while true; do
  now_ts=$(date +%s)
  name="bg-${now_ts}"
  sql="INSERT INTO ${TABLE} (name) VALUES ('${name}');"
  if run_psql "${sql}" >/dev/null; then
    log "inserted: ${name}"
  else
    log "insert failed, will retry" >&2
  fi
  sleep "${INTERVAL}"
done


