#!/usr/bin/env bash
#
# post_carryover_elevation.sh
#
# Resumable post-carryover elevation fill for ibrida-v0-r2:
#   1) (optional) wait for r1->r2 carryover UPDATE to finish
#   2) run batched workers with FOR UPDATE SKIP LOCKED
#   3) checkpoint progress in admin.elevation_fill_* tables
#   4) (optional) VACUUM ANALYZE observations
#
# This script is suitable for both full runs and calibration runs.
# POL-466 tracks follow-on automation and further optimization.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  post_carryover_elevation.sh [options]

Core options:
  --db-name <name>            Target database (default: ibrida-v0-r2)
  --db-user <user>            Database user (default: postgres)
  --db-container <name>       Docker container running Postgres (default: ibridaDB)
  --run-id <id>               Run identifier for resume/status (default: auto-generated)
  --workers <n>               Worker count (default: 4)
  --batch-size <n>            Rows claimed per worker batch (default: 5000)
  --poll-seconds <n>          Status poll interval while workers run (default: 300)

Control options:
  --no-wait                   Do not wait for carryover; fail if carryover is active
  --skip-vacuum               Skip final VACUUM ANALYZE
  --target-updated-rows <n>   Stop once rows_updated >= n (calibration mode)
  --max-batches <n>           Stop once total batches_completed >= n
  --resume                    Resume/continue existing run-id (default)
  --no-resume                 Fail if run-id already exists
  --status                    Print status and exit (use with optional --run-id)
  --dry-run                   Validate checks and print current state only
  --with-stats                Print full table stats pre/post (slow on large tables)
  -h, --help                  Show this help

Examples:
  # Full resumable run (waits for carryover if needed)
  ./dbTools/admin/post_carryover_elevation.sh --workers 6 --batch-size 4000

  # 100k updated-row calibration run without vacuum
  ./dbTools/admin/post_carryover_elevation.sh \
    --run-id calib-100k-20260227 \
    --target-updated-rows 100000 \
    --skip-vacuum

  # Status for latest run
  ./dbTools/admin/post_carryover_elevation.sh --status

  # Status for a specific run
  ./dbTools/admin/post_carryover_elevation.sh --status --run-id calib-100k-20260227
EOF
}

DB_NAME="${DB_NAME:-ibrida-v0-r2}"
DB_USER="${DB_USER:-postgres}"
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
POLL_SECONDS="${POLL_SECONDS:-300}"
WORKERS="${WORKERS:-4}"
BATCH_SIZE="${BATCH_SIZE:-5000}"
RUN_ID="${RUN_ID:-}"
WAIT_FOR_CARRYOVER=1
RUN_VACUUM=1
WITH_STATS=0
DRY_RUN=0
STATUS_ONLY=0
RESUME=1
TARGET_UPDATED_ROWS=""
MAX_BATCHES=""
FINALIZED=0

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
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    --workers)
      WORKERS="$2"
      shift 2
      ;;
    --batch-size)
      BATCH_SIZE="$2"
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
    --target-updated-rows)
      TARGET_UPDATED_ROWS="$2"
      shift 2
      ;;
    --max-batches)
      MAX_BATCHES="$2"
      shift 2
      ;;
    --resume)
      RESUME=1
      shift
      ;;
    --no-resume)
      RESUME=0
      shift
      ;;
    --status)
      STATUS_ONLY=1
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
if ! [[ "$WORKERS" =~ ^[0-9]+$ ]] || [[ "$WORKERS" -le 0 ]]; then
  echo "--workers must be a positive integer" >&2
  exit 2
fi
if ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || [[ "$BATCH_SIZE" -le 0 ]]; then
  echo "--batch-size must be a positive integer" >&2
  exit 2
fi
if [[ -n "$TARGET_UPDATED_ROWS" ]] && { ! [[ "$TARGET_UPDATED_ROWS" =~ ^[0-9]+$ ]] || [[ "$TARGET_UPDATED_ROWS" -le 0 ]]; }; then
  echo "--target-updated-rows must be a positive integer" >&2
  exit 2
fi
if [[ -n "$MAX_BATCHES" ]] && { ! [[ "$MAX_BATCHES" =~ ^[0-9]+$ ]] || [[ "$MAX_BATCHES" -le 0 ]]; }; then
  echo "--max-batches must be a positive integer" >&2
  exit 2
fi

ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  echo "[$(ts)] $*"
}

die() {
  echo "[$(ts)] ERROR: $*" >&2
  exit 1
}

ensure_run_id() {
  if [[ -z "$RUN_ID" ]]; then
    RUN_ID="elev-fill-$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  if ! [[ "$RUN_ID" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    die "--run-id contains unsupported characters. Allowed: [A-Za-z0-9._:-]"
  fi
}

docker_psql() {
  local app_name="$1"
  shift
  docker exec -i -e PGAPPNAME="${app_name}" "${DB_CONTAINER}" psql -X -q -v ON_ERROR_STOP=1 -U "${DB_USER}" -d "${DB_NAME}" "$@"
}

psql_value() {
  local sql="$1"
  local app_name="${2:-elevation-fill:control}"
  docker_psql "${app_name}" -At -c "${sql}"
}

carryover_active_count() {
  psql_value "
    SELECT count(*)
    FROM pg_stat_activity
    WHERE pid <> pg_backend_pid()
      AND datname = '${DB_NAME}'
      AND state = 'active'
      AND query ILIKE '%UPDATE public.observations o%'
      AND query ILIKE '%FROM dblink(%'
      AND query ILIKE '%elevation_meters = s.elevation_meters%';
  " "elevation-fill:control"
}

print_full_stats() {
  local label="$1"
  log "${label} (full-table stats)"
  docker_psql "elevation-fill:control" -At <<'SQL'
SELECT 'total_observations=' || count(*) FROM observations;
SELECT 'null_elevation=' || count(*) FROM observations WHERE elevation_meters IS NULL;
SELECT 'null_elevation_with_geom=' || count(*) FROM observations WHERE elevation_meters IS NULL AND geom IS NOT NULL;
SELECT 'null_elevation_without_geom=' || count(*) FROM observations WHERE elevation_meters IS NULL AND geom IS NULL;
SQL
}

ensure_metadata_tables() {
  docker_psql "elevation-fill:control" <<'SQL' >/dev/null
SET client_min_messages = warning;
CREATE SCHEMA IF NOT EXISTS admin;

CREATE TABLE IF NOT EXISTS admin.elevation_fill_runs (
  run_id text PRIMARY KEY,
  db_name text NOT NULL,
  host text NOT NULL,
  state text NOT NULL CHECK (state IN ('running', 'completed', 'failed', 'stopped')),
  workers integer NOT NULL,
  batch_size integer NOT NULL,
  target_updated_rows bigint,
  max_batches bigint,
  initial_remaining bigint NOT NULL,
  claimed_rows bigint NOT NULL DEFAULT 0,
  rows_updated bigint NOT NULL DEFAULT 0,
  rows_excluded bigint NOT NULL DEFAULT 0,
  batches_completed bigint NOT NULL DEFAULT 0,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  last_heartbeat timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS admin.elevation_fill_batches (
  batch_id bigserial PRIMARY KEY,
  run_id text NOT NULL REFERENCES admin.elevation_fill_runs(run_id) ON DELETE CASCADE,
  worker_id integer NOT NULL,
  batch_no bigint NOT NULL,
  claimed_rows integer NOT NULL,
  updated_rows integer NOT NULL,
  excluded_rows integer NOT NULL,
  duration_ms integer NOT NULL,
  started_at timestamptz NOT NULL,
  finished_at timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS elevation_fill_batches_run_id_idx
  ON admin.elevation_fill_batches (run_id, batch_id);

CREATE INDEX IF NOT EXISTS elevation_fill_batches_run_started_idx
  ON admin.elevation_fill_batches (run_id, started_at);

CREATE TABLE IF NOT EXISTS admin.elevation_fill_queue (
  run_id text NOT NULL REFERENCES admin.elevation_fill_runs(run_id) ON DELETE CASCADE,
  observation_uuid uuid NOT NULL,
  state text NOT NULL CHECK (state IN ('pending', 'claimed', 'done', 'excluded')),
  worker_id integer,
  claimed_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id, observation_uuid)
);

CREATE INDEX IF NOT EXISTS elevation_fill_queue_state_idx
  ON admin.elevation_fill_queue (run_id, state, observation_uuid);

CREATE TABLE IF NOT EXISTS admin.elevation_fill_exclusions (
  run_id text NOT NULL REFERENCES admin.elevation_fill_runs(run_id) ON DELETE CASCADE,
  observation_uuid uuid NOT NULL,
  reason text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id, observation_uuid)
);
SQL
}

mark_run_state() {
  local new_state="$1"
  docker_psql "elevation-fill:control" -c "
    UPDATE admin.elevation_fill_runs
    SET state = '${new_state}',
        finished_at = now(),
        last_heartbeat = now(),
        updated_at = now()
    WHERE run_id = '${RUN_ID}';
  " >/dev/null
  FINALIZED=1
}

print_status() {
  local target_run="$1"
  local row

  if [[ -z "$target_run" ]]; then
    docker_psql "elevation-fill:control" -x -c "
      SELECT run_id, state, workers, batch_size, target_updated_rows, max_batches,
             initial_remaining, claimed_rows, rows_updated, rows_excluded,
             batches_completed, started_at, finished_at, last_heartbeat
      FROM admin.elevation_fill_runs
      ORDER BY started_at DESC
      LIMIT 10;
    "
    return 0
  fi

  row="$(psql_value "
    SELECT run_id, state, workers, batch_size,
           COALESCE(target_updated_rows, -1),
           COALESCE(max_batches, -1),
           initial_remaining, claimed_rows, rows_updated, rows_excluded, batches_completed,
           EXTRACT(EPOCH FROM (COALESCE(finished_at, now()) - started_at))::bigint
      FROM admin.elevation_fill_runs
     WHERE run_id = '${target_run}';
  " "elevation-fill:control")"

  if [[ -z "$row" ]]; then
    die "No run found with run_id=${target_run}"
  fi

  IFS='|' read -r run_id state workers batch_size target_rows max_batches initial_remaining claimed_rows rows_updated rows_excluded batches_completed elapsed_sec <<<"${row}"

  local processed remaining progress_pct rate active_workers recent
  processed=$((rows_updated + rows_excluded))
  remaining=$((initial_remaining - processed))
  if (( remaining < 0 )); then
    remaining=0
  fi
  progress_pct="$(awk -v processed="${processed}" -v total="${initial_remaining}" 'BEGIN { if (total > 0) printf "%.2f", (processed * 100.0 / total); else printf "0.00"; }')"
  rate="$(awk -v updated="${rows_updated}" -v elapsed="${elapsed_sec}" 'BEGIN { if (elapsed > 0) printf "%.2f", (updated * 1.0 / elapsed); else printf "0.00"; }')"
  active_workers="$(psql_value "
    SELECT count(*)
    FROM pg_stat_activity
    WHERE datname = '${DB_NAME}'
      AND application_name LIKE 'elevation-fill:${target_run}:w%';
  " "elevation-fill:control")"

  recent="$(psql_value "
    WITH b AS (
      SELECT claimed_rows, updated_rows, excluded_rows, started_at, finished_at
      FROM admin.elevation_fill_batches
      WHERE run_id = '${target_run}'
        AND started_at >= now() - interval '30 minutes'
    ),
    s AS (
      SELECT count(*) AS batch_count,
             sum(claimed_rows)::bigint AS claimed_rows,
             sum(updated_rows)::bigint AS updated_rows,
             sum(excluded_rows)::bigint AS excluded_rows,
             min(started_at) AS t0,
             max(finished_at) AS t1
      FROM b
    )
    SELECT COALESCE(batch_count,0),
           COALESCE(round(updated_rows/NULLIF(EXTRACT(EPOCH FROM (t1 - t0)),0),2),0),
           COALESCE(round((updated_rows + excluded_rows)/NULLIF(EXTRACT(EPOCH FROM (t1 - t0)),0),2),0)
    FROM s;
  " "elevation-fill:control")"
  IFS='|' read -r recent_batches recent_updated_rps recent_processed_rps <<<"${recent}"
  recent_batches="${recent_batches:-0}"
  recent_updated_rps="${recent_updated_rps:-0}"
  recent_processed_rps="${recent_processed_rps:-0}"

  log "run=${run_id} state=${state} active_workers=${active_workers} workers_cfg=${workers} batch_size=${batch_size}"
  log "updated=${rows_updated} excluded=${rows_excluded} claimed=${claimed_rows} batches=${batches_completed} processed=${processed}/${initial_remaining} (${progress_pct}%) est_remaining=${remaining}"
  log "elapsed_sec=${elapsed_sec} updated_rows_per_sec=${rate} target_updated_rows=${target_rows} max_batches=${max_batches}"
  log "recent_window=30m recent_batches=${recent_batches} recent_updated_rows_per_sec=${recent_updated_rps} recent_processed_rows_per_sec=${recent_processed_rps}"
}

run_exists() {
  local count
  count="$(psql_value "SELECT count(*) FROM admin.elevation_fill_runs WHERE run_id = '${RUN_ID}';" "elevation-fill:control")"
  [[ "$count" == "1" ]]
}

run_should_stop() {
  local should
  should="$(psql_value "
    SELECT CASE
             WHEN state <> 'running' THEN 1
             WHEN target_updated_rows IS NOT NULL AND rows_updated >= target_updated_rows THEN 1
             WHEN max_batches IS NOT NULL AND batches_completed >= max_batches THEN 1
             ELSE 0
           END
      FROM admin.elevation_fill_runs
     WHERE run_id = '${RUN_ID}';
  " "elevation-fill:${RUN_ID}:control")"
  [[ "$should" == "1" ]]
}

create_or_resume_run() {
  local host_name initial_remaining queue_rows reclaimed_rows
  host_name="$(hostname)"

  if run_exists; then
    if [[ "$RESUME" -eq 0 ]]; then
      die "Run ${RUN_ID} already exists and --no-resume was set"
    fi
    log "Resuming existing run ${RUN_ID}"
    queue_rows="$(psql_value "
      SELECT count(*) FROM admin.elevation_fill_queue WHERE run_id = '${RUN_ID}';
    " "elevation-fill:${RUN_ID}:control")"

    if [[ "${queue_rows}" == "0" ]]; then
      log "No queue rows found for run ${RUN_ID}; backfilling queue from remaining NULL+geom observations..."
      docker_psql "elevation-fill:${RUN_ID}:control" -c "
        INSERT INTO admin.elevation_fill_queue (run_id, observation_uuid, state)
        SELECT '${RUN_ID}', o.observation_uuid, 'pending'
        FROM observations o
        WHERE o.elevation_meters IS NULL
          AND o.geom IS NOT NULL
        ON CONFLICT (run_id, observation_uuid) DO NOTHING;
      " >/dev/null
      queue_rows="$(psql_value "
        SELECT count(*) FROM admin.elevation_fill_queue WHERE run_id = '${RUN_ID}';
      " "elevation-fill:${RUN_ID}:control")"
    fi

    reclaimed_rows="$(psql_value "
      WITH reclaimed AS (
        UPDATE admin.elevation_fill_queue
        SET state = 'pending',
            worker_id = NULL,
            claimed_at = NULL,
            updated_at = now()
        WHERE run_id = '${RUN_ID}'
          AND state = 'claimed'
        RETURNING 1
      )
      SELECT count(*) FROM reclaimed;
    " "elevation-fill:${RUN_ID}:control")"

    if [[ "${reclaimed_rows}" != "0" ]]; then
      log "Re-queued ${reclaimed_rows} stale claimed rows for run ${RUN_ID}"
    fi

    docker_psql "elevation-fill:${RUN_ID}:control" -c "
      UPDATE admin.elevation_fill_runs
      SET state = 'running',
          workers = ${WORKERS},
          batch_size = ${BATCH_SIZE},
          target_updated_rows = ${TARGET_UPDATED_ROWS:-NULL},
          max_batches = ${MAX_BATCHES:-NULL},
          finished_at = NULL,
          initial_remaining = GREATEST(initial_remaining, ${queue_rows}),
          last_heartbeat = now(),
          updated_at = now()
      WHERE run_id = '${RUN_ID}';
    " >/dev/null
    return 0
  fi

  docker_psql "elevation-fill:${RUN_ID}:control" -c "
    INSERT INTO admin.elevation_fill_runs (
      run_id, db_name, host, state, workers, batch_size, target_updated_rows, max_batches,
      initial_remaining, last_heartbeat
    )
    VALUES (
      '${RUN_ID}', '${DB_NAME}', '${host_name}', 'running', ${WORKERS}, ${BATCH_SIZE},
      ${TARGET_UPDATED_ROWS:-NULL}, ${MAX_BATCHES:-NULL}, 0, now()
    );
  " >/dev/null

  log "Building run queue from NULL+geom observations (one-time step)..."
  docker_psql "elevation-fill:${RUN_ID}:control" -c "
    INSERT INTO admin.elevation_fill_queue (run_id, observation_uuid, state)
    SELECT '${RUN_ID}', o.observation_uuid, 'pending'
    FROM observations o
    WHERE o.elevation_meters IS NULL
      AND o.geom IS NOT NULL
    ON CONFLICT (run_id, observation_uuid) DO NOTHING;
  " >/dev/null

  initial_remaining="$(psql_value "
    SELECT count(*) FROM admin.elevation_fill_queue WHERE run_id = '${RUN_ID}';
  " "elevation-fill:${RUN_ID}:control")"

  docker_psql "elevation-fill:${RUN_ID}:control" -c "
    UPDATE admin.elevation_fill_runs
    SET initial_remaining = ${initial_remaining},
        updated_at = now(),
        last_heartbeat = now()
    WHERE run_id = '${RUN_ID}';
  " >/dev/null

  log "Created run ${RUN_ID} with initial_remaining=${initial_remaining}"
}

worker_loop() {
  local worker_id="$1"
  local batch_no=0
  local claimed updated excluded batch_result start_ms end_ms duration_ms

  while true; do
    if run_should_stop; then
      break
    fi

    start_ms="$(date +%s%3N)"
    batch_result="$(psql_value "
      WITH picked AS (
        SELECT q.observation_uuid
        FROM admin.elevation_fill_queue q
        WHERE q.run_id = '${RUN_ID}'
          AND q.state = 'pending'
        ORDER BY q.observation_uuid
        LIMIT ${BATCH_SIZE}
        FOR UPDATE SKIP LOCKED
      ),
      resolved AS (
        SELECT p.observation_uuid, v.elev
        FROM picked p
        JOIN observations o
          ON o.observation_uuid = p.observation_uuid
        LEFT JOIN LATERAL (
          SELECT ST_Value(er.rast, o.geom)::numeric(10,2) AS elev
          FROM elevation_raster er
          WHERE ST_Intersects(er.rast, o.geom)
          LIMIT 1
        ) v ON true
      ),
      updated AS (
        UPDATE observations o
        SET elevation_meters = r.elev
        FROM resolved r
        WHERE o.observation_uuid = r.observation_uuid
          AND r.elev IS NOT NULL
          AND o.elevation_meters IS NULL
        RETURNING o.observation_uuid
      ),
      mark_done AS (
        UPDATE admin.elevation_fill_queue q
        SET state = 'done',
            finished_at = now(),
            updated_at = now()
        FROM updated u
        WHERE q.run_id = '${RUN_ID}'
          AND q.observation_uuid = u.observation_uuid
        RETURNING q.observation_uuid
      ),
      mark_excluded AS (
        UPDATE admin.elevation_fill_queue q
        SET state = 'excluded',
            finished_at = now(),
            updated_at = now()
        FROM resolved r
        LEFT JOIN updated u
          ON u.observation_uuid = r.observation_uuid
        JOIN observations o_now
          ON o_now.observation_uuid = r.observation_uuid
        WHERE q.run_id = '${RUN_ID}'
          AND q.observation_uuid = r.observation_uuid
          AND u.observation_uuid IS NULL
          AND o_now.elevation_meters IS NULL
        RETURNING q.observation_uuid
      ),
      excluded_log AS (
        INSERT INTO admin.elevation_fill_exclusions (run_id, observation_uuid, reason)
        SELECT '${RUN_ID}', e.observation_uuid, 'no_raster_value'
        FROM mark_excluded e
        ON CONFLICT (run_id, observation_uuid) DO NOTHING
        RETURNING observation_uuid
      )
      SELECT (SELECT count(*) FROM picked),
             (SELECT count(*) FROM updated),
             (SELECT count(*) FROM mark_excluded);
    " "elevation-fill:${RUN_ID}:w${worker_id}")"
    end_ms="$(date +%s%3N)"
    duration_ms=$((end_ms - start_ms))

    IFS='|' read -r claimed updated excluded <<<"${batch_result}"
    claimed="${claimed:-0}"
    updated="${updated:-0}"
    excluded="${excluded:-0}"

    if [[ "$claimed" == "0" ]]; then
      break
    fi

    batch_no=$((batch_no + 1))
    docker_psql "elevation-fill:${RUN_ID}:w${worker_id}" -c "
      UPDATE admin.elevation_fill_runs
      SET claimed_rows = claimed_rows + ${claimed},
          rows_updated = rows_updated + ${updated},
          rows_excluded = rows_excluded + ${excluded},
          batches_completed = batches_completed + 1,
          last_heartbeat = now(),
          updated_at = now()
      WHERE run_id = '${RUN_ID}';

      INSERT INTO admin.elevation_fill_batches (
        run_id, worker_id, batch_no, claimed_rows, updated_rows, excluded_rows,
        duration_ms, started_at, finished_at
      )
      VALUES (
        '${RUN_ID}', ${worker_id}, ${batch_no}, ${claimed}, ${updated}, ${excluded},
        ${duration_ms}, now() - make_interval(secs => (${duration_ms} / 1000.0)), now()
      );
    " >/dev/null

    if [[ "$updated" == "0" && "$excluded" == "0" ]]; then
      log "worker=${worker_id} claimed rows but recorded no progress; stopping worker defensively"
      break
    fi
  done

  log "worker=${worker_id} finished"
}

finalize_completed() {
  docker_psql "elevation-fill:${RUN_ID}:control" -c "
    UPDATE admin.elevation_fill_runs
    SET state = 'completed',
        finished_at = now(),
        last_heartbeat = now(),
        updated_at = now()
    WHERE run_id = '${RUN_ID}';
  " >/dev/null
  FINALIZED=1
}

cleanup_on_exit() {
  local exit_code="$?"
  if [[ "$STATUS_ONLY" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    return
  fi
  if [[ -z "${RUN_ID}" ]]; then
    return
  fi
  if [[ "$FINALIZED" -eq 1 ]]; then
    return
  fi
  if run_exists; then
    if [[ "$exit_code" -eq 0 ]]; then
      mark_run_state "stopped"
    else
      mark_run_state "failed"
    fi
  fi
}
trap cleanup_on_exit EXIT

log "Starting post-carryover elevation sequence on db=${DB_NAME} container=${DB_CONTAINER}"

if ! docker ps --format '{{.Names}}' | rg -qx "${DB_CONTAINER}"; then
  die "Container ${DB_CONTAINER} is not running"
fi

ensure_metadata_tables

if [[ "$STATUS_ONLY" -eq 1 ]]; then
  print_status "${RUN_ID}"
  exit 0
fi

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
    die "Carryover is still active (${active} backend) and --no-wait was set"
  fi
fi

if [[ "${WITH_STATS}" -eq 1 ]]; then
  print_full_stats "Pre-fill stats:"
fi

ensure_run_id

if [[ "${DRY_RUN}" -eq 1 ]]; then
  log "Dry-run mode enabled; printing status only."
  if run_exists; then
    print_status "${RUN_ID}"
  else
    print_status ""
  fi
  exit 0
fi

create_or_resume_run
print_status "${RUN_ID}"

log "Launching workers: workers=${WORKERS} batch_size=${BATCH_SIZE}"
pids=()
for ((w = 1; w <= WORKERS; w++)); do
  worker_loop "${w}" &
  pids+=("$!")
done

while true; do
  any_running=0
  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      any_running=1
      break
    fi
  done
  if [[ "${any_running}" -eq 0 ]]; then
    break
  fi
  sleep "${POLL_SECONDS}"
  print_status "${RUN_ID}"
done

worker_failed=0
for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
    worker_failed=1
  fi
done

if [[ "${worker_failed}" -ne 0 ]]; then
  die "One or more workers failed"
fi

if [[ "${RUN_VACUUM}" -eq 1 ]]; then
  log "Running VACUUM ANALYZE observations..."
  docker_psql "elevation-fill:${RUN_ID}:control" -c "VACUUM ANALYZE observations;"
else
  log "Skipping VACUUM ANALYZE (--skip-vacuum)."
fi

finalize_completed
print_status "${RUN_ID}"

if [[ "${WITH_STATS}" -eq 1 ]]; then
  print_full_stats "Post-fill stats:"
fi

log "Post-carryover elevation sequence complete."
