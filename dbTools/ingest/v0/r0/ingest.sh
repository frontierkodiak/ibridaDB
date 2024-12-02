#!/bin/bash
### DEV: DEPRECATED, REMOVE ONCE WRAPPER/MAIN IS TESTED/VERIFIED
### DEV: Reference for functionality to port to new modularized system

# Database and user variables
DB_USER="postgres"
DB_TEMPLATE="template_postgis"
NUM_PROCESSES=16
BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/v0"

# Source variable
SOURCE="June2024"

# Construct origin value based on source
ORIGIN_VALUE="iNat-${SOURCE}"

# Version variable
VERSION_VALUE="v0"

# Construct database name
DB_NAME="ibrida-${VERSION_VALUE}"

# Function to execute SQL commands
execute_sql() {
  local sql="$1"
  docker exec ibrida psql -U "$DB_USER" -d "$DB_NAME" -c "$sql"
}

# Function to print progress
print_progress() {
  local message="$1"
  echo "======================================"
  echo "$message"
  echo "======================================"
}

# Create database, drop if exists
print_progress "Creating database"
docker exec ibrida psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
docker exec ibrida psql -U "$DB_USER" -c "CREATE DATABASE \"$DB_NAME\" WITH TEMPLATE $DB_TEMPLATE OWNER $DB_USER;"

# Connect to the database and create tables
print_progress "Creating tables"
execute_sql "
BEGIN;

CREATE TABLE observations (
    observation_uuid uuid NOT NULL,
    observer_id integer,
    latitude numeric(15,10),
    longitude numeric(15,10),
    positional_accuracy integer,
    taxon_id integer,
    quality_grade character varying(255),
    observed_on date
);

CREATE TABLE photos (
    photo_uuid uuid NOT NULL,
    photo_id integer NOT NULL,
    observation_uuid uuid NOT NULL,
    observer_id integer,
    extension character varying(5),
    license character varying(255),
    width smallint,
    height smallint,
    position smallint
);

CREATE TABLE taxa (
    taxon_id integer NOT NULL,
    ancestry character varying(255),
    rank_level double precision,
    rank character varying(255),
    name character varying(255),
    active boolean
);

CREATE TABLE observers (
    observer_id integer NOT NULL,
    login character varying(255),
    name character varying(255)
);

COMMIT;
"

# Import data
print_progress "Importing data"
execute_sql "
BEGIN;

COPY observations FROM '/metadata/${SOURCE}/observations.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY photos FROM '/metadata/${SOURCE}/photos.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY taxa FROM '/metadata/${SOURCE}/taxa.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY observers FROM '/metadata/${SOURCE}/observers.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;

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
CREATE INDEX index_observations_taxon_id ON observations USING btree (taxon_id);

COMMIT;
"

# Add geom column (parallelized calculation using geom.sh)
print_progress "Adding geom column"
execute_sql "ALTER TABLE observations ADD COLUMN geom public.geometry;"

# Run parallel geom calculations
print_progress "Running parallel geom calculations"
"${BASE_DIR}/geom.sh" "$DB_NAME" "observations" "$NUM_PROCESSES" "$BASE_DIR"

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
print_progress "Adding origin and version columns"
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

COMMIT;
"

# Run parallel updates for origin and version columns
print_progress "Running parallel updates for origin and version columns"
"${BASE_DIR}/vers_origin.sh" "$DB_NAME" "$NUM_PROCESSES" "$ORIGIN_VALUE" "$VERSION_VALUE"

# Create indexes for origin and version columns
print_progress "Creating indexes for origin and version columns"
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

COMMIT;
"

print_progress "Database setup complete"
