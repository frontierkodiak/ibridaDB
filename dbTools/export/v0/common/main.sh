#!/bin/bash

# This script expects the following variables from wrapper:
# - DB_USER
# - VERSION_VALUE
# - RELEASE_VALUE
# - ORIGIN_VALUE
# - DB_NAME
# - REGION_TAG
# - MIN_OBS
# - MAX_RN
# - DB_CONTAINER
# - HOST_EXPORT_BASE_PATH
# - CONTAINER_EXPORT_BASE_PATH
# - EXPORT_GROUP
# - PROCESS_OTHER

# Validate required variables
required_vars=(
    "DB_USER" "VERSION_VALUE" "RELEASE_VALUE" "ORIGIN_VALUE" 
    "DB_NAME" "REGION_TAG" "MIN_OBS" "MAX_RN" 
    "DB_CONTAINER" "HOST_EXPORT_BASE_PATH" "CONTAINER_EXPORT_BASE_PATH"
    "EXPORT_GROUP"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set"
        exit 1
    fi
done

# Create export directory structure
print_progress "Creating export directory structure"
EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
HOST_EXPORT_DIR="${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

# Create directories on host
mkdir -p "${HOST_EXPORT_DIR}"
chmod -R 777 "${HOST_EXPORT_DIR}"

# Ensure container can access export directory
docker exec ${DB_CONTAINER} mkdir -p "${EXPORT_DIR}"
docker exec ${DB_CONTAINER} chown postgres:postgres "${EXPORT_DIR}"
docker exec ${DB_CONTAINER} chmod 777 "${EXPORT_DIR}"

print_progress "Export directories created and permissions set"

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

# Build dynamic column list for observations
get_obs_columns() {
    # Start with standard columns
    local cols="observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on"
    
    # Add version tracking columns
    cols="${cols}, origin, version, release"
    
    # Check if anomaly_score exists and add it
    if [[ "${RELEASE_VALUE}" == "r1" ]]; then
        cols="${cols}, anomaly_score"
    fi
    
    echo "$cols"
}

# Create export base directory
EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
execute_sql "
DO \$\$
BEGIN
    CREATE EXTENSION IF NOT EXISTS dblink;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exportuser') THEN
        CREATE ROLE exportuser;
    END IF;
END \$\$;
"

# Run regional base creation
print_progress "Creating regional base tables"
"${BASE_DIR}/common/regional_base.sh"

# Run cladistic filtering
print_progress "Applying cladistic filters"
"${BASE_DIR}/common/cladistic.sh"

# Export summary
print_progress "Creating export summary"
SUMMARY_FILE="${EXPORT_DIR}/export_summary.txt"
echo "Export Summary" > "$SUMMARY_FILE"
echo "Version: ${VERSION_VALUE}" >> "$SUMMARY_FILE"
echo "Release: ${RELEASE_VALUE}" >> "$SUMMARY_FILE"
echo "Region: ${REGION_TAG}" >> "$SUMMARY_FILE"
echo "Minimum Observations: ${MIN_OBS}" >> "$SUMMARY_FILE"
echo "Maximum Random Number: ${MAX_RN}" >> "$SUMMARY_FILE"
echo "Export Group: ${EXPORT_GROUP}" >> "$SUMMARY_FILE"
echo "Date: $(date)" >> "$SUMMARY_FILE"

print_progress "Export process complete"