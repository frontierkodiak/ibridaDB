#!/bin/bash
#
# wrapper.sh
#
# A typical user-facing script that sets environment variables and then calls main.sh.
# We define WRAPPER_PATH="$0" so that main.sh can copy this file for reproducibility.

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

# Provide path to wrapper for reproducibility
export WRAPPER_PATH="$0"

# ---------------------------------------------------------------------------
# Database config
# ---------------------------------------------------------------------------
export DB_USER="postgres"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r1"
export ORIGIN_VALUE="iNat-Dec2024"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"

log_message "Database: ${DB_NAME}"
log_message "Version: ${VERSION_VALUE}"
log_message "Release: ${RELEASE_VALUE}"

# ---------------------------------------------------------------------------
# Export parameters
# ---------------------------------------------------------------------------
export REGION_TAG="NAfull"
export MIN_OBS=100
export MAX_RN=200
export PRIMARY_ONLY=true

# We could set CLADE or METACLADE here; let's pick something as an example:
export CLADE="amphibia"
export EXPORT_GROUP="${CLADE}"

# Additional flags
export PROCESS_OTHER=false
export SKIP_REGIONAL_BASE=false

# NEW ENV VARS
export INCLUDE_OUT_OF_REGION_OBS=true
export RG_FILTER_MODE="ALL"

log_message "Region: ${REGION_TAG}"
log_message "Min Observations: ${MIN_OBS}"
log_message "Max Random Number: ${MAX_RN}"
log_message "Export Group: ${EXPORT_GROUP}"
log_message "Skip Regional Base Creation: ${SKIP_REGIONAL_BASE}"
log_message "Include Out-of-Region Obs: ${INCLUDE_OUT_OF_REGION_OBS}"
log_message "RG Filter Mode: ${RG_FILTER_MODE}"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
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