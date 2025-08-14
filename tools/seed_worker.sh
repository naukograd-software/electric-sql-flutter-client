#!/usr/bin/env bash
set -euo pipefail

# Config (override via env)
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.yaml}
DB_SERVICE=${DB_SERVICE:-postgres}
DB_NAME=${DB_NAME:-postgres}
DB_USER=${DB_USER:-postgres}
TABLE=${TABLE:-widgets}
INTERVAL=${INTERVAL:-2}

# Local psql settings (used when not running via docker)
PGHOST=${PGHOST:-localhost}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-${DB_USER}}
# PGPASSWORD can be provided from env if needed

log() { echo "[seed-worker] $*"; }

run_psql() {
  # $1 = SQL
  if [[ "${USE_DOCKER:-auto}" != "0" ]] && command -v docker >/dev/null 2>&1; then
    if docker compose -f "${COMPOSE_FILE}" ps "${DB_SERVICE}" >/dev/null 2>&1; then
      docker compose -f "${COMPOSE_FILE}" exec -T "${DB_SERVICE}" \
        psql -U "${DB_USER}" -d "${DB_NAME}" -c "$1"
      return $?
    fi
  fi
  # Local psql fallback
  PGPASSWORD="${PGPASSWORD:-}" psql -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${DB_NAME}" -c "$1"
}

log "Target table: ${TABLE} (db=${DB_NAME} user=${DB_USER})"
log "Interval: ${INTERVAL}s"

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


