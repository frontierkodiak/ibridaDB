#!/bin/bash
#
# update_elevation.sh
#
# Populates observations.elevation_meters from the elevation_raster table
# using ST_Value(raster, geometry). Runs in parallel for efficiency.
#
# Usage:
#   update_elevation.sh <DB_NAME> <DB_USER> <DB_CONTAINER> <NUM_PROCESSES>
#
# Environment Variables (expected):
#   - We rely on functions.sh for print_progress, execute_sql, etc.
#
# Notes:
#   - If ST_Value(...) is out of coverage (ocean or no-data area),
#     elevation_meters will remain NULL.
#   - We call VACUUM ANALYZE at the end to optimize performance.

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Parse arguments
# ------------------------------------------------------------------------------
if [ "$#" -lt 4 ]; then
  echo "Usage: $0 <DB_NAME> <DB_USER> <DB_CONTAINER> <NUM_PROCESSES>"
  exit 1
fi

DB_NAME="$1"
DB_USER="$2"
DB_CONTAINER="$3"
NUM_PROCESSES="$4"

# If BASE_DIR not set, default to current script's grandparent
BASE_DIR="${BASE_DIR:-"$(cd "$(dirname "$0")/../../.." && pwd)"}"

# ------------------------------------------------------------------------------
# 2. Source shared functions
# ------------------------------------------------------------------------------
source "${BASE_DIR}/common/functions.sh"

# ------------------------------------------------------------------------------
# 3. Ensure the column 'elevation_meters' exists on observations
# ------------------------------------------------------------------------------
print_progress "Ensuring observations.elevation_meters column exists"
execute_sql "ALTER TABLE observations ADD COLUMN IF NOT EXISTS elevation_meters numeric(10,2);" 

# ------------------------------------------------------------------------------
# 4. Determine row count, compute batch size
# ------------------------------------------------------------------------------
print_progress "Determining row count in observations"
TOTAL_ROWS=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM observations;" | tr -d ' ')
if [ -z "${TOTAL_ROWS}" ] || [ "${TOTAL_ROWS}" -eq 0 ]; then
  echo "No observations found. Skipping elevation update."
  exit 0
fi

BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES + 1))
send_notification "[INFO] Elevation update starting: ${TOTAL_ROWS} rows in total, batch size=${BATCH_SIZE}"

# ------------------------------------------------------------------------------
# 5. Parallel update function
# ------------------------------------------------------------------------------
update_chunk() {
  local offset="$1"
  local limit="$2"
  local chunk_id="$3"

  print_progress "Elevation update chunk #${chunk_id} (offset=${offset}, limit=${limit})"

  # Build an inline SQL
  local sql="
    UPDATE observations
    SET elevation_meters = ST_Value(er.rast, observations.geom)
    FROM elevation_raster er
    WHERE ST_Intersects(er.rast, observations.geom)
      AND observations.ctid IN (
        SELECT ctid FROM observations
        ORDER BY ctid
        OFFSET ${offset}
        LIMIT ${limit}
      );
  "

  # Run the update
  execute_sql "${sql}"

  print_progress "Chunk #${chunk_id} complete"
  send_notification "[OK] Elevation update chunk #${chunk_id} done"
}

# ------------------------------------------------------------------------------
# 6. Launch parallel updates
# ------------------------------------------------------------------------------
pids=()
for ((i=0; i<NUM_PROCESSES; i++)); do
  OFFSET=$((i * BATCH_SIZE))
  update_chunk "${OFFSET}" "${BATCH_SIZE}" "${i}" &
  pids+=($!)
done

for pid in "${pids[@]}"; do
  wait "$pid"
done

print_progress "All elevation updates completed for ${TOTAL_ROWS} rows."
send_notification "[OK] All elevation updates completed"

# ------------------------------------------------------------------------------
# 7. Final VACUUM ANALYZE
# ------------------------------------------------------------------------------
print_progress "Running VACUUM ANALYZE on observations..."
execute_sql "VACUUM ANALYZE observations;"
send_notification "[OK] VACUUM ANALYZE on observations complete"
