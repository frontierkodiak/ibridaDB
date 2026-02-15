#!/usr/bin/env bash
#
# post_carryover_elevation.sh
#
# Stopgap post-carryover sequence for ibrida-v0-r2:
#   1) (optional) wait for the r1->r2 carryover UPDATE to finish
#   2) fill remaining NULL observations.elevation_meters from elevation_raster
#   3) VACUUM ANALYZE observations
#
# This is intentionally pragmatic for current r2 completion.
# Robust batching/checkpointing/observability work is tracked in POL-466.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  post_carryover_elevation.sh [options]

Options:
  --db-name <name>         Target database (default: ibrida-v0-r2)
  --db-user <user>         Database user (default: postgres)
  --db-container <name>    Docker container running Postgres (default: ibridaDB)
  --poll-seconds <n>       Wait loop interval in seconds (default: 1800)
  --no-wait                Do not wait for carryover; fail if carryover is active
  --skip-vacuum            Skip final VACUUM ANALYZE
  --dry-run                Print checks, do not run fill/vacuum
  --with-stats             Run full-table pre/post stats (slow on large tables)
  -h, --help               Show this help

Examples:
  # Wait until carryover completes, then run fill + vacuum
  ./dbTools/admin/post_carryover_elevation.sh

  # Immediate sanity-check only
  ./dbTools/admin/post_carryover_elevation.sh --dry-run
EOF
}

DB_NAME="${DB_NAME:-ibrida-v0-r2}"
DB_USER="${DB_USER:-postgres}"
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
POLL_SECONDS="${POLL_SECONDS:-1800}"
WAIT_FOR_CARRYOVER=1
RUN_VACUUM=1
DRY_RUN=0
WITH_STATS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-name)
      DB_NAME="$2"
      shift 2
      ;;
    --db-user)
      DB_USER="$2"
      shift 2
      ;;
    --db-container)
      DB_CONTAINER="$2"
      shift 2
      ;;
    --poll-seconds)
      POLL_SECONDS="$2"
      shift 2
      ;;
    --no-wait)
      WAIT_FOR_CARRYOVER=0
      shift
      ;;
    --skip-vacuum)
      RUN_VACUUM=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --with-stats)
      WITH_STATS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if ! [[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || [[ "$POLL_SECONDS" -le 0 ]]; then
  echo "--poll-seconds must be a positive integer" >&2
  exit 2
fi

ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  echo "[$(ts)] $*"
}

psql_exec() {
  local sql="$1"
  docker exec "${DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -U "${DB_USER}" -d "${DB_NAME}" -At -c "${sql}"
}

carryover_active_count() {
  psql_exec "
    SELECT count(*)
    FROM pg_stat_activity
    WHERE pid <> pg_backend_pid()
      AND datname = '${DB_NAME}'
      AND state = 'active'
      AND query ILIKE '%UPDATE public.observations o%'
      AND query ILIKE '%FROM dblink(%'
      AND query ILIKE '%elevation_meters = s.elevation_meters%';
  "
}

print_full_stats() {
  local label="$1"
  log "${label} (full-table stats)"
  psql_exec "
    SELECT 'total_observations=' || count(*) FROM observations;
    SELECT 'null_elevation=' || count(*) FROM observations WHERE elevation_meters IS NULL;
    SELECT 'null_elevation_with_geom=' || count(*) FROM observations WHERE elevation_meters IS NULL AND geom IS NOT NULL;
    SELECT 'null_elevation_without_geom=' || count(*) FROM observations WHERE elevation_meters IS NULL AND geom IS NULL;
  "
}

log "Starting post-carryover elevation sequence on db=${DB_NAME} container=${DB_CONTAINER}"

if [[ "${WAIT_FOR_CARRYOVER}" -eq 1 ]]; then
  while true; do
    active="$(carryover_active_count)"
    if [[ "${active}" == "0" ]]; then
      log "Carryover query not active; continuing."
      break
    fi
    log "Carryover still active (${active} backend). Sleeping ${POLL_SECONDS}s..."
    sleep "${POLL_SECONDS}"
  done
else
  active="$(carryover_active_count)"
  if [[ "${active}" != "0" ]]; then
    log "Carryover is still active (${active} backend) and --no-wait was set; exiting."
    exit 3
  fi
fi

if [[ "${WITH_STATS}" -eq 1 ]]; then
  print_full_stats "Pre-fill stats:"
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "Dry-run mode enabled; skipping fill + vacuum."
  exit 0
fi

log "Filling remaining NULL elevations from elevation_raster..."
docker exec "${DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -U "${DB_USER}" -d "${DB_NAME}" <<'SQL'
\set ON_ERROR_STOP on
DO $$
DECLARE
  v_updated bigint;
BEGIN
  UPDATE observations o
  SET elevation_meters = ST_Value(er.rast, o.geom)::numeric(10,2)
  FROM elevation_raster er
  WHERE o.elevation_meters IS NULL
    AND o.geom IS NOT NULL
    AND ST_Intersects(er.rast, o.geom);

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RAISE NOTICE 'rows_updated=%', v_updated;
END $$;
SQL

if [[ "${RUN_VACUUM}" -eq 1 ]]; then
  log "Running VACUUM ANALYZE observations..."
  docker exec "${DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -U "${DB_USER}" -d "${DB_NAME}" -c "VACUUM ANALYZE observations;"
else
  log "Skipping VACUUM ANALYZE (--skip-vacuum)."
fi

if [[ "${WITH_STATS}" -eq 1 ]]; then
  print_full_stats "Post-fill stats:"
fi

log "Post-carryover elevation sequence complete."
