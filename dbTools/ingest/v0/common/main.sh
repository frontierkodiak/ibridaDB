#!/bin/bash
#
# main.sh
#
# Core ingestion logic for a given database release. Creates the database,
# imports CSV data, configures geometry, version columns, etc. Now also
# optionally calls the elevation pipeline if ENABLE_ELEVATION=true.
#
# This script expects the following variables to be set by the wrapper:
#   - DB_USER
#   - DB_TEMPLATE
#   - NUM_PROCESSES
#   - BASE_DIR
#   - SOURCE
#   - ORIGIN_VALUE
#   - VERSION_VALUE
#   - RELEASE_VALUE
#   - DB_NAME
#   - DB_CONTAINER
#   - METADATA_PATH
#   - STRUCTURE_SQL
#   - ENABLE_ELEVATION (new; optional, defaults to "false" if not set)
#
# Example usage:
#   ENABLE_ELEVATION=true /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh
#

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Validate required variables
# ------------------------------------------------------------------------------
required_vars=(
    "DB_USER" "DB_TEMPLATE" "NUM_PROCESSES" "BASE_DIR"
    "SOURCE" "ORIGIN_VALUE" "VERSION_VALUE" "DB_NAME"
    "DB_CONTAINER" "METADATA_PATH" "STRUCTURE_SQL"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "Error: Required variable $var is not set"
        exit 1
    fi
done

# Default ENABLE_ELEVATION to "false" if not defined
ENABLE_ELEVATION="${ENABLE_ELEVATION:-false}"

# ------------------------------------------------------------------------------
# 2. Source shared functions
# ------------------------------------------------------------------------------
source "${BASE_DIR}/common/functions.sh"

print_progress "Starting core ingestion for ${DB_NAME}"
send_notification "[INFO] Starting ingestion for ${DB_NAME}"

# ------------------------------------------------------------------------------
# 3. Create Database
# ------------------------------------------------------------------------------
print_progress "Creating database ${DB_NAME} from template ${DB_TEMPLATE}"
execute_sql_postgres() {
    local sql="$1"
    docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -c "$sql"
}

execute_sql_postgres "DROP DATABASE IF EXISTS \"${DB_NAME}\";"
execute_sql_postgres "CREATE DATABASE \"${DB_NAME}\" WITH TEMPLATE ${DB_TEMPLATE} OWNER ${DB_USER};"

# ------------------------------------------------------------------------------
# 4. Create tables from structure SQL
# ------------------------------------------------------------------------------
print_progress "Creating tables from ${STRUCTURE_SQL}"
if [ ! -f "${STRUCTURE_SQL}" ]; then
  echo "Error: STRUCTURE_SQL file not found: ${STRUCTURE_SQL}"
  exit 1
fi

cat "${STRUCTURE_SQL}" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

# ------------------------------------------------------------------------------
# 5. Import data
# ------------------------------------------------------------------------------
print_progress "Importing CSV data from ${METADATA_PATH}"
execute_sql "
BEGIN;

COPY observations
FROM '${METADATA_PATH}/observations.csv'
DELIMITER E'\t'
QUOTE E'\b'
CSV HEADER;

COPY photos
FROM '${METADATA_PATH}/photos.csv'
DELIMITER E'\t'
QUOTE E'\b'
CSV HEADER;

COPY taxa
FROM '${METADATA_PATH}/taxa.csv'
DELIMITER E'\t'
QUOTE E'\b'
CSV HEADER;

COPY observers
FROM '${METADATA_PATH}/observers.csv'
DELIMITER E'\t'
QUOTE E'\b'
CSV HEADER;

COMMIT;
"

# ------------------------------------------------------------------------------
# 6. Create indexes
# ------------------------------------------------------------------------------
print_progress "Creating base indexes"
execute_sql "
BEGIN;

CREATE INDEX index_photos_photo_uuid         ON photos USING btree (photo_uuid);
CREATE INDEX index_photos_observation_uuid   ON photos USING btree (observation_uuid);
CREATE INDEX index_photos_position           ON photos USING btree (position);
CREATE INDEX index_photos_photo_id           ON photos USING btree (photo_id);
CREATE INDEX index_taxa_taxon_id             ON taxa   USING btree (taxon_id);
CREATE INDEX index_observers_observers_id    ON observers USING btree (observer_id);
CREATE INDEX index_observations_observer_id  ON observations USING btree (observer_id);
CREATE INDEX index_observations_quality      ON observations USING btree (quality_grade);
CREATE INDEX index_observations_taxon_id     ON observations USING btree (taxon_id);
CREATE INDEX index_taxa_active               ON taxa USING btree (active);

COMMIT;
"

# Conditional index for anomaly_score
execute_sql "
DO \$\$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'observations'
        AND column_name = 'anomaly_score'
    ) THEN
        CREATE INDEX idx_observations_anomaly ON observations (anomaly_score);
    END IF;
END \$\$;"

# ------------------------------------------------------------------------------
# 7. Add geom column & compute geometry in parallel
# ------------------------------------------------------------------------------
print_progress "Adding geom column to observations"
execute_sql "ALTER TABLE observations ADD COLUMN geom public.geometry;"

print_progress "Populating geom column in parallel"
"${BASE_DIR}/common/geom.sh" "${DB_NAME}" "observations" "${NUM_PROCESSES}" "${BASE_DIR}"

# Create geom index
print_progress "Creating GIST index on geom"
execute_sql "CREATE INDEX observations_geom ON observations USING GIST (geom);"

# ------------------------------------------------------------------------------
# 8. Vacuum
# ------------------------------------------------------------------------------
print_progress "Vacuum/Analyze after geometry load"
execute_sql "VACUUM ANALYZE;"

# ------------------------------------------------------------------------------
# 9. Add origin, version, and release columns
# ------------------------------------------------------------------------------
print_progress "Adding origin/version/release columns in parallel"
execute_sql "
BEGIN;

ALTER TABLE taxa         ADD COLUMN origin   VARCHAR(255);
ALTER TABLE observers    ADD COLUMN origin   VARCHAR(255);
ALTER TABLE observations ADD COLUMN origin   VARCHAR(255);
ALTER TABLE photos       ADD COLUMN origin   VARCHAR(255);

ALTER TABLE photos       ADD COLUMN version  VARCHAR(255);
ALTER TABLE observations ADD COLUMN version  VARCHAR(255);
ALTER TABLE observers    ADD COLUMN version  VARCHAR(255);
ALTER TABLE taxa         ADD COLUMN version  VARCHAR(255);

ALTER TABLE photos       ADD COLUMN release  VARCHAR(255);
ALTER TABLE observations ADD COLUMN release  VARCHAR(255);
ALTER TABLE observers    ADD COLUMN release  VARCHAR(255);
ALTER TABLE taxa         ADD COLUMN release  VARCHAR(255);

COMMIT;
"

print_progress "Populating origin/version/release columns"
"${BASE_DIR}/common/vers_origin.sh" "${DB_NAME}" "${NUM_PROCESSES}" "${ORIGIN_VALUE}" "${VERSION_VALUE}" "${RELEASE_VALUE}"

# ------------------------------------------------------------------------------
# 10. Create GIN indexes for origin/version/release
# ------------------------------------------------------------------------------
print_progress "Creating GIN indexes for origin/version/release"
execute_sql "
BEGIN;

CREATE INDEX index_taxa_origins        ON taxa        USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_taxa_name           ON taxa        USING GIN (to_tsvector('simple', name));
CREATE INDEX index_observers_origins   ON observers   USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_observations_origins ON observations USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_origins      ON photos      USING GIN (to_tsvector('simple', origin));

CREATE INDEX index_photos_version      ON photos      USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observations_version ON observations USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observers_version   ON observers   USING GIN (to_tsvector('simple', version));
CREATE INDEX index_taxa_version        ON taxa        USING GIN (to_tsvector('simple', version));

CREATE INDEX index_photos_release      ON photos      USING GIN (to_tsvector('simple', release));
CREATE INDEX index_observations_release ON observations USING GIN (to_tsvector('simple', release));
CREATE INDEX index_observers_release   ON observers   USING GIN (to_tsvector('simple', release));
CREATE INDEX index_taxa_release        ON taxa        USING GIN (to_tsvector('simple', release));

COMMIT;
"

# ------------------------------------------------------------------------------
# 11. Optional Elevation Flow
# ------------------------------------------------------------------------------
if [ "${ENABLE_ELEVATION}" == "true" ]; then
  print_progress "ENABLE_ELEVATION=true, proceeding with elevation pipeline"
  send_notification "[INFO] Elevation pipeline triggered for ${DB_NAME}"

  # Either call the 'wrapper.sh' or call 'main.sh' directly.
  # We'll illustrate direct call to main.sh here: (note; makes sense to direct call here, wrapper is for standalone use)
  ELEVATION_SCRIPT="${BASE_DIR}/utils/elevation/main.sh"

  # Example: pass your dem directory, concurrency, etc. 
  # If your release wrapper already sets DEM_DIR, EPSG, etc. environment variables, you can do:
  DEM_DIR="${DEM_DIR:-"/datasets/dem/merit"}"
  EPSG="${EPSG:-"4326"}"
  TILE_SIZE="${TILE_SIZE:-"100x100"}"

  if [ -x "${ELEVATION_SCRIPT}" ]; then
    "${ELEVATION_SCRIPT}" \
      "${DB_NAME}" \
      "${DB_USER}" \
      "${DB_CONTAINER}" \
      "${DEM_DIR}" \
      "${NUM_PROCESSES}" \
      "${EPSG}" \
      "${TILE_SIZE}"
  else
    echo "Warning: Elevation script not found or not executable at ${ELEVATION_SCRIPT}"
  fi

  print_progress "Elevation pipeline complete for ${DB_NAME}"
else
  print_progress "ENABLE_ELEVATION=false, skipping elevation pipeline"
  send_notification "[INFO] Skipping elevation pipeline for ${DB_NAME}"
fi

# ------------------------------------------------------------------------------
# 12. Final notice
# ------------------------------------------------------------------------------
print_progress "Database setup complete for ${DB_NAME}"
send_notification "[OK] Ingestion (and optional elevation) complete for ${DB_NAME}"
