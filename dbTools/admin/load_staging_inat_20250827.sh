#!/usr/bin/env bash
set -euo pipefail

# Load iNat CSVs into staging schema
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-ibrida-v0}"
INTAKE_PATH="${INTAKE_PATH:-/datasets/ibrida-data/intake/Aug2025}"
CONTAINER_INTAKE_PATH="${CONTAINER_INTAKE_PATH:-/metadata/Aug2025}"
SCHEMA_NAME="${SCHEMA_NAME:-stg_inat_20250827}"

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
if docker exec "${DB_CONTAINER}" sh -c "test -f '${CONTAINER_INTAKE_PATH}/observations.csv'"; then
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.observations (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on, anomaly_score) FROM '${CONTAINER_INTAKE_PATH}/observations.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF
else
  HOST_OBS="${INTAKE_PATH}/observations.csv"
  if [[ ! -f "${HOST_OBS}" ]]; then
    echo "ERROR: observations.csv not found at ${HOST_OBS} and container path missing"
    exit 1
  fi
  cat "${HOST_OBS}" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy ${SCHEMA_NAME}.observations (observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on, anomaly_score) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"
fi

echo "==> Loading photos.csv" 
if docker exec "${DB_CONTAINER}" sh -c "test -f '${CONTAINER_INTAKE_PATH}/photos.csv'"; then
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.photos (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position) FROM '${CONTAINER_INTAKE_PATH}/photos.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF
else
  HOST_PHOTOS="${INTAKE_PATH}/photos.csv"
  if [[ ! -f "${HOST_PHOTOS}" ]]; then
    echo "ERROR: photos.csv not found at ${HOST_PHOTOS} and container path missing"
    exit 1
  fi
  cat "${HOST_PHOTOS}" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy ${SCHEMA_NAME}.photos (photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"
fi

echo "==> Loading observers.csv"
if docker exec "${DB_CONTAINER}" sh -c "test -f '${CONTAINER_INTAKE_PATH}/observers.csv'"; then
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.observers (observer_id, login, name) FROM '${CONTAINER_INTAKE_PATH}/observers.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF
else
  HOST_OBSERVERS="${INTAKE_PATH}/observers.csv"
  if [[ ! -f "${HOST_OBSERVERS}" ]]; then
    echo "ERROR: observers.csv not found at ${HOST_OBSERVERS} and container path missing"
    exit 1
  fi
  cat "${HOST_OBSERVERS}" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy ${SCHEMA_NAME}.observers (observer_id, login, name) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"
fi

echo "==> Loading taxa.csv"
if docker exec "${DB_CONTAINER}" sh -c "test -f '${CONTAINER_INTAKE_PATH}/taxa.csv'"; then
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" <<EOF
\\copy ${SCHEMA_NAME}.taxa (taxon_id, ancestry, rank_level, rank, name, active) FROM '${CONTAINER_INTAKE_PATH}/taxa.csv' DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;
EOF
else
  HOST_TAXA="${INTAKE_PATH}/taxa.csv"
  if [[ ! -f "${HOST_TAXA}" ]]; then
    echo "ERROR: taxa.csv not found at ${HOST_TAXA} and container path missing"
    exit 1
  fi
  cat "${HOST_TAXA}" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 -c "\\copy ${SCHEMA_NAME}.taxa (taxon_id, ancestry, rank_level, rank, name, active) FROM STDIN DELIMITER E'\\t' QUOTE E'\\b' CSV HEADER;"
fi

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
