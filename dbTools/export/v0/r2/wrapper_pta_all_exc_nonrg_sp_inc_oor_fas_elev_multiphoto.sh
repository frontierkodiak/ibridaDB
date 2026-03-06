#!/bin/bash
set -euo pipefail

# Setup logging
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/$(basename "$0" .sh)_$(date +%Y%m%d_%H%M%S).log"
echo "Starting new run at $(date)" > "${LOG_FILE}"

# Redirect all stdout and stderr to both console and log file.
# After this, plain echo/printf go to both console and log — no need for tee in helpers.
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}")

echo "Initializing export process with configuration:"

# ---------------------------------------------------------------------------
# Database config
# ---------------------------------------------------------------------------
export DB_USER="postgres"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r2"
export ORIGIN_VALUE="iNat-Dec2024"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"

echo "Database: ${DB_NAME}"
echo "Version: ${VERSION_VALUE}"
echo "Release: ${RELEASE_VALUE}"

# ---------------------------------------------------------------------------
# Export parameters
# ---------------------------------------------------------------------------
export REGION_TAG="NAfull"
export MIN_OBS=50
export MAX_RN=2750
export PRIMARY_ONLY=false

export METACLADE="pta" # primary_terrestrial_arthropoda
export EXPORT_GROUP="pta_all_exc_nonrg_sp_inc_oor_fas_elev_multiphoto"

# Additional flags
export PROCESS_OTHER=false
export SKIP_REGIONAL_BASE=false
export INCLUDE_OUT_OF_REGION_OBS=true
export INCLUDE_ELEVATION_EXPORT=true
export RG_FILTER_MODE="ALL_EXCLUDE_SPECIES_NON_RESEARCH"

export MIN_OCCURRENCES_PER_RANK=50
export INCLUDE_MINOR_RANKS_IN_ANCESTORS=true

echo "Region: ${REGION_TAG}"
echo "Min Observations: ${MIN_OBS}"
echo "Max Observation Cap (MAX_RN): ${MAX_RN}"
echo "Primary Only: ${PRIMARY_ONLY}"
echo "Export Group: ${EXPORT_GROUP}"
echo "Skip Regional Base Creation: ${SKIP_REGIONAL_BASE}"
echo "Include Out-of-Region Obs: ${INCLUDE_OUT_OF_REGION_OBS}"
echo "RG Filter Mode: ${RG_FILTER_MODE}"
echo "Min Occurrences per Rank: ${MIN_OCCURRENCES_PER_RANK}"
echo "Include Minor Ranks in Ancestors: ${INCLUDE_MINOR_RANKS_IN_ANCESTORS}"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
export DB_CONTAINER="ibridaDB"
export HOST_EXPORT_BASE_PATH="/datasets/ibrida-data/exports"
export CONTAINER_EXPORT_BASE_PATH="/exports"
export EXPORT_SUBDIR="${VERSION_VALUE}/${RELEASE_VALUE}/multi_photo_${MIN_OBS}min_${MAX_RN}max"
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/export/v0"
export WRAPPER_PATH="$0"

echo "Export Directory: ${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

# ---------------------------------------------------------------------------
# Source common functions
# ---------------------------------------------------------------------------
source "${BASE_DIR}/common/functions.sh"

# ---------------------------------------------------------------------------
# Execute main script
# ---------------------------------------------------------------------------
send_notification "Starting ${EXPORT_GROUP} export"
echo "Executing main script at $(date)"
if "${BASE_DIR}/common/main.sh"; then
  echo "Process completed at $(date)"
  send_notification "${EXPORT_GROUP} export completed!"
else
  rc=$?
  echo "ERROR: main.sh exited with code ${rc} at $(date)"
  send_notification "FAILED: ${EXPORT_GROUP} export (exit ${rc})"
  exit "${rc}"
fi
