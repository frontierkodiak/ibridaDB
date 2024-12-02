#!/bin/bash

# This script expects the following variables to be set by the wrapper:
# - DB_USER
# - DB_TEMPLATE
# - NUM_PROCESSES
# - BASE_DIR
# - SOURCE
# - ORIGIN_VALUE
# - VERSION_VALUE
# - RELEASE_VALUE
# - DB_NAME
# - DB_CONTAINER
# - METADATA_PATH
# - STRUCTURE_SQL

# Validate required variables
required_vars=(
    "DB_USER" "DB_TEMPLATE" "NUM_PROCESSES" "BASE_DIR" 
    "SOURCE" "ORIGIN_VALUE" "VERSION_VALUE" "DB_NAME" 
    "DB_CONTAINER" "METADATA_PATH" "STRUCTURE_SQL"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set"
        exit 1
    fi
done

# Function to execute SQL commands
execute_sql() {
    local sql="$1"
    docker exec ${DB_CONTAINER} psql -U ${DB_USER} -d "${DB_NAME}" -c "$sql"
}

# Function to execute SQL commands on default postgres database
execute_sql_postgres() {
    local sql="$1"
    docker exec ${DB_CONTAINER} psql -U ${DB_USER} -c "$sql"
}

# Function to print progress
print_progress() {
    echo "======================================"
    echo "$1"
    echo "======================================"
}

# Create database
print_progress "Creating database"
execute_sql_postgres "DROP DATABASE IF EXISTS \"$DB_NAME\";"
execute_sql_postgres "CREATE DATABASE \"$DB_NAME\" WITH TEMPLATE $DB_TEMPLATE OWNER $DB_USER;"

# Create tables from structure file
print_progress "Creating tables"
cat "${STRUCTURE_SQL}" | docker exec -i ${DB_CONTAINER} psql -U ${DB_USER} -d "${DB_NAME}"

# Import data
print_progress "Importing data"
execute_sql "
BEGIN;

COPY observations FROM '${METADATA_PATH}/observations.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY photos FROM '${METADATA_PATH}/photos.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY taxa FROM '${METADATA_PATH}/taxa.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY observers FROM '${METADATA_PATH}/observers.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

COMMIT;
"

# Create indexes
print_progress "Creating indexes"
execute_sql "
BEGIN;

CREATE INDEX index_photos_photo_uuid ON photos USING btree (photo_uuid);
CREATE INDEX index_photos_observation_uuid ON photos USING btree (observation_uuid);
CREATE INDEX index_photos_position ON photos USING btree (position);
CREATE INDEX index_photos_photo_id ON photos USING btree (photo_id);
CREATE INDEX index_taxa_taxon_id ON taxa USING btree (taxon_id);
CREATE INDEX index_observers_observers_id ON observers USING btree (observer_id);
CREATE INDEX index_observations_observer_id ON observations USING btree (observer_id);
CREATE INDEX index_observations_quality ON observations USING btree (quality_grade);
CREATE INDEX index_observations_taxon_id ON observations USING btree (taxon_id);
CREATE INDEX index_taxa_active ON taxa USING btree (active);

COMMIT;
"

# Create conditional index for anomaly_score if it exists
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

# Add geom column
print_progress "Adding geom column"
execute_sql "ALTER TABLE observations ADD COLUMN geom public.geometry;"

# Run parallel geom calculations
print_progress "Running parallel geom calculations"
"${BASE_DIR}/common/geom.sh" "$DB_NAME" "observations" "$NUM_PROCESSES" "$BASE_DIR"

# Create geom index
print_progress "Creating geom index"
execute_sql "
BEGIN;
CREATE INDEX observations_geom ON observations USING GIST (geom);
COMMIT;
"

# Vacuum analyze
print_progress "Vacuum analyze"
execute_sql "VACUUM ANALYZE;"

# Add origin and version columns in parallel
print_progress "Adding origin, version, and release columns"
execute_sql "
BEGIN;

ALTER TABLE taxa ADD COLUMN origin VARCHAR(255);
ALTER TABLE observers ADD COLUMN origin VARCHAR(255);
ALTER TABLE observations ADD COLUMN origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN version VARCHAR(255);
ALTER TABLE observations ADD COLUMN version VARCHAR(255);
ALTER TABLE observers ADD COLUMN version VARCHAR(255);
ALTER TABLE taxa ADD COLUMN version VARCHAR(255);
ALTER TABLE photos ADD COLUMN release VARCHAR(255);
ALTER TABLE observations ADD COLUMN release VARCHAR(255);
ALTER TABLE observers ADD COLUMN release VARCHAR(255);
ALTER TABLE taxa ADD COLUMN release VARCHAR(255);

COMMIT;
"

# Run parallel updates for origin and version columns
print_progress "Running parallel updates for origin and version columns"
"${BASE_DIR}/common/vers_origin.sh" "$DB_NAME" "$NUM_PROCESSES" "$ORIGIN_VALUE" "$VERSION_VALUE" "$RELEASE_VALUE"

# Create indexes for origin and version columns
print_progress "Creating indexes for origin, version, and release columns"
execute_sql "
BEGIN;

CREATE INDEX index_taxa_origins ON taxa USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_taxa_name ON taxa USING GIN (to_tsvector('simple', name));
CREATE INDEX index_observers_origins ON observers USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_observations_origins ON observations USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_origins ON photos USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_version ON photos USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observations_version ON observations USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observers_version ON observers USING GIN (to_tsvector('simple', version));
CREATE INDEX index_taxa_version ON taxa USING GIN (to_tsvector('simple', version));
CREATE INDEX index_photos_release ON photos USING GIN (to_tsvector('simple', release));
CREATE INDEX index_observations_release ON observations USING GIN (to_tsvector('simple', release));
CREATE INDEX index_observers_release ON observers USING GIN (to_tsvector('simple', release));
CREATE INDEX index_taxa_release ON taxa USING GIN (to_tsvector('simple', release));

COMMIT;
"

print_progress "Database setup complete"