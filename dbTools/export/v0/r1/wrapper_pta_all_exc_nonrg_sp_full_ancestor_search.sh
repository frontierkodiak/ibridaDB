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
export MIN_OBS=50
export MAX_RN=3000
export PRIMARY_ONLY=true

export METACLADE="pta" # primary_terrestrial_arthropoda
export EXPORT_GROUP="pta_all_exc_nonrg_sp_full_ancestor_search"

# Additional flags
export PROCESS_OTHER=false
export SKIP_REGIONAL_BASE=false  # typically used for successive cladistic exports

# ---[ NEW ENV VARS ]---
# Whether to include out-of-region observations in the final dataset
export INCLUDE_OUT_OF_REGION_OBS=true

# Whether to keep research-grade only, non-research, etc.
# For now, we default to ALL; future steps will integrate it
export RG_FILTER_MODE="ALL_EXCLUDE_SPECIES_NON_RESEARCH"

export MIN_OCCURRENCES_PER_RANK=50
export INCLUDE_MINOR_RANKS_IN_ANCESTORS=true

log_message "Region: ${REGION_TAG}"
log_message "Min Observations: ${MIN_OBS}"
log_message "Max Random Number: ${MAX_RN}"
log_message "Export Group: ${EXPORT_GROUP}"
log_message "Skip Regional Base Creation: ${SKIP_REGIONAL_BASE}"
log_message "Include Out-of-Region Obs: ${INCLUDE_OUT_OF_REGION_OBS}"
log_message "RG Filter Mode: ${RG_FILTER_MODE}"
log_message "Min Occurrences per Rank: ${MIN_OCCURRENCES_PER_RANK}"
log_message "Include Minor Ranks in Ancestors: ${INCLUDE_MINOR_RANKS_IN_ANCESTORS}"
# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
export DB_CONTAINER="ibridaDB"
export HOST_EXPORT_BASE_PATH="/datasets/ibrida-data/exports"
export CONTAINER_EXPORT_BASE_PATH="/exports"
export EXPORT_SUBDIR="${VERSION_VALUE}/${RELEASE_VALUE}/primary_only_${MIN_OBS}min_${MAX_RN}max"
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/export/v0"

log_message "Export Directory: ${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

# ---------------------------------------------------------------------------
# Source common functions
# ---------------------------------------------------------------------------
source "${BASE_DIR}/common/functions.sh"

# ---------------------------------------------------------------------------
# Execute main script
# ---------------------------------------------------------------------------
send_notification "Starting ${EXPORT_GROUP} export"
log_message "Executing main script at $(date)"
"${BASE_DIR}/common/main.sh"

log_message "Process completed at $(date)"
send_notification "${EXPORT_GROUP} export completed!"
