#!/bin/bash

# Exit on any error
set -e

# Database configuration
DB_USER="postgres"
DB_TEMPLATE="template_postgis"
DB_CONTAINER="ibrida"

# Version and origin configuration
SOURCE="Dec2024"
VERSION_VALUE="v0r1"
ORIGIN_VALUE="iNat-${SOURCE}"
DB_NAME="ibrida-${VERSION_VALUE}"

# Input/Output paths
METADATA_PATH="/metadata/${SOURCE}"

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
print_progress "Creating database ${DB_NAME}"
execute_sql_postgres "DROP DATABASE IF EXISTS \"${DB_NAME}\";"
execute_sql_postgres "CREATE DATABASE \"${DB_NAME}\" WITH TEMPLATE ${DB_TEMPLATE} OWNER ${DB_USER};"

# Create tables
print_progress "Creating tables"
execute_sql "
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
);"

# Import data
print_progress "Importing data from ${METADATA_PATH}"
execute_sql "
COPY observations FROM '${METADATA_PATH}/observations.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY photos FROM '${METADATA_PATH}/photos.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY taxa FROM '${METADATA_PATH}/taxa.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;
COPY observers FROM '${METADATA_PATH}/observers.csv' DELIMITER E'\t' QUOTE E'\b' CSV HEADER;"

# Create indexes
print_progress "Creating indexes"
execute_sql "
CREATE INDEX index_photos_photo_uuid ON photos USING btree (photo_uuid);
CREATE INDEX index_photos_observation_uuid ON photos USING btree (observation_uuid);
CREATE INDEX index_photos_position ON photos USING btree (position);
CREATE INDEX index_photos_photo_id ON photos USING btree (photo_id);
CREATE INDEX index_taxa_taxon_id ON taxa USING btree (taxon_id);
CREATE INDEX index_observers_observers_id ON observers USING btree (observer_id);
CREATE INDEX index_observations_observer_id ON observations USING btree (observer_id);
CREATE INDEX index_observations_quality ON observations USING btree (quality_grade);
CREATE INDEX index_observations_taxon_id ON observations USING btree (taxon_id);
CREATE INDEX index_taxa_active ON taxa USING btree (active);"

# Add geometry column
print_progress "Adding geometry column"
execute_sql "
ALTER TABLE observations ADD COLUMN geom public.geometry;
UPDATE observations SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326);
CREATE INDEX observations_geom ON observations USING GIST (geom);
VACUUM ANALYZE;"

# Add origin and version columns
print_progress "Adding origin and version columns"
execute_sql "
ALTER TABLE taxa ADD COLUMN origin VARCHAR(255);
ALTER TABLE observers ADD COLUMN origin VARCHAR(255);
ALTER TABLE observations ADD COLUMN origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN origin VARCHAR(255);
ALTER TABLE photos ADD COLUMN version VARCHAR(255);
ALTER TABLE observations ADD COLUMN version VARCHAR(255);
ALTER TABLE observers ADD COLUMN version VARCHAR(255);
ALTER TABLE taxa ADD COLUMN version VARCHAR(255);"

# Set origin and version values
print_progress "Setting origin and version values"
execute_sql "
UPDATE taxa SET origin = '${ORIGIN_VALUE}', version = '${VERSION_VALUE}';
UPDATE observers SET origin = '${ORIGIN_VALUE}', version = '${VERSION_VALUE}';
UPDATE observations SET origin = '${ORIGIN_VALUE}', version = '${VERSION_VALUE}';
UPDATE photos SET origin = '${ORIGIN_VALUE}', version = '${VERSION_VALUE}';"

# Create indexes for origin and version
print_progress "Creating indexes for origin and version"
execute_sql "
CREATE INDEX index_taxa_origins ON taxa USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_taxa_name ON taxa USING GIN (to_tsvector('simple', name));
CREATE INDEX index_observers_origins ON observers USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_observations_origins ON observations USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_origins ON photos USING GIN (to_tsvector('simple', origin));
CREATE INDEX index_photos_version ON photos USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observations_version ON observations USING GIN (to_tsvector('simple', version));
CREATE INDEX index_observers_version ON observers USING GIN (to_tsvector('simple', version));
CREATE INDEX index_taxa_version ON taxa USING GIN (to_tsvector('simple', version));"

# Set primary keys
print_progress "Setting primary keys"
execute_sql "
ALTER TABLE observations ADD CONSTRAINT observations_pkey PRIMARY KEY (observation_uuid);
ALTER TABLE photos ADD CONSTRAINT photos_pkey PRIMARY KEY (photo_uuid, photo_id, position, observation_uuid);
ALTER TABLE observers ADD CONSTRAINT observers_pkey PRIMARY KEY (observer_id);
ALTER TABLE taxa ADD CONSTRAINT taxa_pkey PRIMARY KEY (taxon_id);"

print_progress "Database initialization complete"