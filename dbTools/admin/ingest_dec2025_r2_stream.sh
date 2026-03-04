#!/usr/bin/env bash
set -euo pipefail

# Stream Dec2025 iNat CSVs into a clean ibrida-v0-r2 database.
# Uses STDIN \copy to avoid container bind-mount requirements.

DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
DB_TEMPLATE="${DB_TEMPLATE:-template_postgis}"
NUM_PROCESSES="${NUM_PROCESSES:-16}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-$(cd "${SCRIPT_DIR}/../ingest/v0" && pwd)}"
STRUCTURE_SQL="${STRUCTURE_SQL:-${BASE_DIR}/r1/structure.sql}"
METADATA_PATH="${METADATA_PATH:-/datasets/ibrida-data/intake/Dec2025}"
SOURCE="${SOURCE:-Dec2025}"
VERSION_VALUE="${VERSION_VALUE:-v0}"
RELEASE_VALUE="${RELEASE_VALUE:-r2}"
ORIGIN_VALUE="${ORIGIN_VALUE:-iNat-${SOURCE}}"
DB_NAME="${DB_NAME:-ibrida-${VERSION_VALUE}-${RELEASE_VALUE}}"
DROP_EXISTING="${DROP_EXISTING:-false}"

print_progress() {
  echo "======================================"
  echo "$1"
  echo "======================================"
}

execute_sql_postgres() {
  local sql="$1"
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -c "$sql"
}

execute_sql() {
  local sql="$1"
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "$sql"
}

print_progress "Starting Dec2025 stream ingest into ${DB_NAME}"
print_progress "Source: ${SOURCE}  Origin: ${ORIGIN_VALUE}  Version: ${VERSION_VALUE}  Release: ${RELEASE_VALUE}"
print_progress "Metadata path: ${METADATA_PATH}"

if [[ ! -f "${STRUCTURE_SQL}" ]]; then
  echo "ERROR: STRUCTURE_SQL not found: ${STRUCTURE_SQL}"
  exit 1
fi

for f in observations.csv photos.csv taxa.csv observers.csv; do
  if [[ ! -f "${METADATA_PATH}/${f}" ]]; then
    echo "ERROR: Missing ${METADATA_PATH}/${f}"
    exit 1
  fi
done

print_progress "Creating database ${DB_NAME} from ${DB_TEMPLATE}"
if [[ "${DROP_EXISTING}" == "true" ]]; then
  execute_sql_postgres "DROP DATABASE IF EXISTS \"${DB_NAME}\";"
fi
execute_sql_postgres "CREATE DATABASE \"${DB_NAME}\" WITH TEMPLATE ${DB_TEMPLATE} OWNER ${DB_USER};"

print_progress "Creating tables from ${STRUCTURE_SQL}"
cat "${STRUCTURE_SQL}" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

print_progress "Widening anomaly_score for r2 ingest"
execute_sql "
DO \$\$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'observations'
        AND column_name = 'anomaly_score'
    ) THEN
        ALTER TABLE observations ALTER COLUMN anomaly_score TYPE numeric(20,6);
    END IF;
END \$\$;"

print_progress "Streaming observations.csv"
cat "${METADATA_PATH}/observations.csv" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy observations (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on, anomaly_score) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"

print_progress "Streaming photos.csv"
cat "${METADATA_PATH}/photos.csv" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy photos (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"

print_progress "Streaming taxa.csv"
cat "${METADATA_PATH}/taxa.csv" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy taxa (taxon_id, ancestry, rank_level, rank, name, active) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"

print_progress "Streaming observers.csv"
cat "${METADATA_PATH}/observers.csv" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy observers (observer_id, login, name) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"

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

print_progress "Adding geom column + computing geometry"
execute_sql "ALTER TABLE observations ADD COLUMN geom public.geometry;"
"${BASE_DIR}/common/geom.sh" "${DB_NAME}" "observations" "${NUM_PROCESSES}" "${BASE_DIR}"

print_progress "Creating GIST index on geom"
execute_sql "CREATE INDEX observations_geom ON observations USING GIST (geom);"

print_progress "Vacuum/Analyze"
execute_sql "VACUUM ANALYZE;"

print_progress "Adding origin/version/release columns (fast defaults)"
execute_sql "
BEGIN;
ALTER TABLE taxa         ADD COLUMN origin   VARCHAR(255) DEFAULT '${ORIGIN_VALUE}';
ALTER TABLE observers    ADD COLUMN origin   VARCHAR(255) DEFAULT '${ORIGIN_VALUE}';
ALTER TABLE observations ADD COLUMN origin   VARCHAR(255) DEFAULT '${ORIGIN_VALUE}';
ALTER TABLE photos       ADD COLUMN origin   VARCHAR(255) DEFAULT '${ORIGIN_VALUE}';

ALTER TABLE photos       ADD COLUMN version  VARCHAR(255) DEFAULT '${VERSION_VALUE}';
ALTER TABLE observations ADD COLUMN version  VARCHAR(255) DEFAULT '${VERSION_VALUE}';
ALTER TABLE observers    ADD COLUMN version  VARCHAR(255) DEFAULT '${VERSION_VALUE}';
ALTER TABLE taxa         ADD COLUMN version  VARCHAR(255) DEFAULT '${VERSION_VALUE}';

ALTER TABLE photos       ADD COLUMN release  VARCHAR(255) DEFAULT '${RELEASE_VALUE}';
ALTER TABLE observations ADD COLUMN release  VARCHAR(255) DEFAULT '${RELEASE_VALUE}';
ALTER TABLE observers    ADD COLUMN release  VARCHAR(255) DEFAULT '${RELEASE_VALUE}';
ALTER TABLE taxa         ADD COLUMN release  VARCHAR(255) DEFAULT '${RELEASE_VALUE}';
COMMIT;
"

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

print_progress "Dec2025 r2 ingest complete for ${DB_NAME}"
