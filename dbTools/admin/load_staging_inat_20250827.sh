#!/usr/bin/env bash
set -euo pipefail

# Load Aug-2025 iNat CSVs into staging schema
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-ibrida-v0}"  # Still using old name until IBRIDA-017 completes
INTAKE_PATH="${INTAKE_PATH:-/datasets/ibrida-data/intake/Aug2025}"
SCHEMA_NAME="stg_inat_20250827"

execute_sql() {
  local sql="$1"
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "$sql"
}

echo "==> Creating staging schema ${SCHEMA_NAME}"
execute_sql "CREATE SCHEMA IF NOT EXISTS ${SCHEMA_NAME};"

echo "==> Creating staging tables with LIKE structure"

# Create tables with same structure as main tables
execute_sql "
CREATE TABLE IF NOT EXISTS ${SCHEMA_NAME}.observations (LIKE public.observations INCLUDING ALL);
CREATE TABLE IF NOT EXISTS ${SCHEMA_NAME}.photos (LIKE public.photos INCLUDING ALL);  
CREATE TABLE IF NOT EXISTS ${SCHEMA_NAME}.observers (LIKE public.observers INCLUDING ALL);
CREATE TABLE IF NOT EXISTS ${SCHEMA_NAME}.taxa (LIKE public.taxa INCLUDING ALL);
"

echo "==> Loading observations.csv"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.observations (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on, anomaly_score) FROM '/metadata/Aug2025/observations.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF

echo "==> Loading photos.csv" 
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.photos (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position) FROM '/metadata/Aug2025/photos.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF

echo "==> Loading observers.csv"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.observers (observer_id, login, name) FROM '/metadata/Aug2025/observers.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF

echo "==> Loading taxa.csv"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.taxa (taxon_id, ancestry, rank_level, rank, name, active) FROM '/metadata/Aug2025/taxa.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF

echo "==> Running ANALYZE on all staging tables"
execute_sql "
ANALYZE ${SCHEMA_NAME}.observations;
ANALYZE ${SCHEMA_NAME}.photos;
ANALYZE ${SCHEMA_NAME}.observers;
ANALYZE ${SCHEMA_NAME}.taxa;
"

echo "==> Checking row counts"
execute_sql "
SELECT 
  'observations' as table_name, COUNT(*) as row_count FROM ${SCHEMA_NAME}.observations
UNION ALL
SELECT 
  'photos' as table_name, COUNT(*) as row_count FROM ${SCHEMA_NAME}.photos  
UNION ALL
SELECT 
  'observers' as table_name, COUNT(*) as row_count FROM ${SCHEMA_NAME}.observers
UNION ALL
SELECT 
  'taxa' as table_name, COUNT(*) as row_count FROM ${SCHEMA_NAME}.taxa;
"

echo "==> Staging load complete for ${SCHEMA_NAME}"