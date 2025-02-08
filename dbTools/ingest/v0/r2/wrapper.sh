#!/bin/bash

### REVIEW: Previous run didn't populate version/origin columns. We applied a fix to vers_origin.sh (argument mismatch) but watch logs carefully next run.

# Setup logging
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/$(basename "$0" .sh)_$(date +%Y%m%d_%H%M%S).log"
echo "Starting new run at $(date)" > "${LOG_FILE}"

# Function to log messages to both console and file
log_message() {
    echo "$1" | tee -a "${LOG_FILE}"
}

# Redirect all stdout and stderr to both console and log file
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}")

log_message "Initializing ingest process with configuration:"

# Database and user variables
export DB_USER="postgres"
export DB_TEMPLATE="template_postgis"
export NUM_PROCESSES=16
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/v0"
log_message "Database User: ${DB_USER}"
log_message "Template DB: ${DB_TEMPLATE}"
log_message "Parallel Processes: ${NUM_PROCESSES}"

# Source variable
export SOURCE="Feb2025"
export METADATA_PATH="/metadata/${SOURCE}"
log_message "Source: ${SOURCE}"
log_message "Metadata Path: ${METADATA_PATH}"

# Process elevation?
export ENABLE_ELEVATION=true
export DEM_DIR="/datasets/dem/merit"
export EPSG="4326"
export TILE_SIZE="100x100"

# Version and origin values
export ORIGIN_VALUE="iNat-${SOURCE}"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r2"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"
export DB_CONTAINER="ibridaDB"
export STRUCTURE_SQL="${BASE_DIR}/r2/structure.sql"
log_message "Database: ${DB_NAME}"
log_message "Version: ${VERSION_VALUE}"
log_message "Release: ${RELEASE_VALUE}"
log_message "Origin: ${ORIGIN_VALUE}"
log_message "Structure SQL: ${STRUCTURE_SQL}"

# Execute main script
log_message "Executing main script at $(date)"
"${BASE_DIR}/common/main.sh"

log_message "Process completed at $(date)"