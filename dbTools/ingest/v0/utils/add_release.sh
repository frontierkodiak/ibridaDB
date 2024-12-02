#!/bin/bash

# Database variables
DB_USER="postgres"
DB_NAME="ibrida-v0"  # The existing database name
DB_CONTAINER="ibridaDB"
RELEASE_VALUE="r0"

# Function to execute SQL commands
execute_sql() {
    local sql="$1"
    docker exec ${DB_CONTAINER} psql -U ${DB_USER} -d "${DB_NAME}" -c "$sql"
}

# Function to print progress
print_progress() {
    echo "======================================"
    echo "$1"
    echo "======================================"
}

# Add release column to all tables
print_progress "Adding release column to tables"
execute_sql "
BEGIN;
ALTER TABLE taxa ADD COLUMN release VARCHAR(255);
ALTER TABLE observers ADD COLUMN release VARCHAR(255);
ALTER TABLE observations ADD COLUMN release VARCHAR(255);
ALTER TABLE photos ADD COLUMN release VARCHAR(255);
COMMIT;
"

# Set release values
print_progress "Setting release values"
execute_sql "
BEGIN;
UPDATE taxa SET release = '${RELEASE_VALUE}';
UPDATE observers SET release = '${RELEASE_VALUE}';
UPDATE observations SET release = '${RELEASE_VALUE}';
UPDATE photos SET release = '${RELEASE_VALUE}';
COMMIT;
"

# Create indexes for release column
print_progress "Creating indexes for release column"
execute_sql "
BEGIN;
CREATE INDEX index_taxa_release ON taxa USING GIN (to_tsvector('simple', release));
CREATE INDEX index_observers_release ON observers USING GIN (to_tsvector('simple', release));
CREATE INDEX index_observations_release ON observations USING GIN (to_tsvector('simple', release));
CREATE INDEX index_photos_release ON photos USING GIN (to_tsvector('simple', release));
COMMIT;
"

print_progress "Release column added and populated successfully"