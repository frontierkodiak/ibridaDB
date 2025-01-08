#!/bin/bash

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

log_message "Initializing export process with configuration:"

# Database config
export DB_USER="postgres"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r1"
export ORIGIN_VALUE="iNat-Dec2024"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"
log_message "Database: ${DB_NAME}"
log_message "Version: ${VERSION_VALUE}"
log_message "Release: ${RELEASE_VALUE}"

# Export parameters
export REGION_TAG="NAfull"
export MIN_OBS=50
export MAX_RN=4000
export PRIMARY_ONLY=true
export METACLADE="primary_terrestrial_arthropoda"
export EXPORT_GROUP="${METACLADE}"
export PROCESS_OTHER=false
export SKIP_REGIONAL_BASE=true # Note: adjust as needed, typically used for successive cladistic exports (from same regional base)

log_message "Region: ${REGION_TAG}"
log_message "Min Observations: ${MIN_OBS}"
log_message "Max Random Number: ${MAX_RN}"
log_message "Export Group: ${EXPORT_GROUP}"
log_message "Skip Regional Base Creation: ${SKIP_REGIONAL_BASE}"

# Paths
export DB_CONTAINER="ibridaDB"
export HOST_EXPORT_BASE_PATH="/datasets/ibrida-data/exports"
export CONTAINER_EXPORT_BASE_PATH="/exports"
export EXPORT_SUBDIR="${VERSION_VALUE}/${RELEASE_VALUE}/primary_only_${MIN_OBS}min_${MAX_RN}max"
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/export/v0"
log_message "Export Directory: ${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

# Source common functions
source "${BASE_DIR}/common/functions.sh"

# Execute main script
send_notification "Starting ${EXPORT_GROUP} export"
log_message "Executing main script at $(date)"
"${BASE_DIR}/common/main.sh"

log_message "Process completed at $(date)"
send_notification "${EXPORT_GROUP} export completed!"