#!/bin/bash
#
# main.sh
#
# Orchestrates the export pipeline by:
#  1) Validating environment variables
#  2) Always calling regional_base.sh (which handles creating/reusing
#     the region/clade-specific ancestor tables as needed).
#  3) Calling cladistic.sh to produce the final <EXPORT_GROUP>_observations table
#  4) Writing a unified export summary (environment variables + final stats)
#  5) Optionally copying the wrapper script for reproducibility
#
# NOTE:
#  - We no longer do skip/existence checks here. Instead, regional_base.sh
#    performs partial skip logic for its tables (_all_sp, _all_sp_and_ancestors_*, etc.).
#  - We have removed references to ANCESTOR_ROOT_RANKLEVEL, since our new multi-root
#    approach does not require it.

source "${BASE_DIR}/common/functions.sh"

# ------------------------------------------------------------------------------
# 0) Validate Required Environment Variables
# ------------------------------------------------------------------------------
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

# Some environment variables are optional but relevant, so let's note them.
# e.g. SKIP_REGIONAL_BASE, INCLUDE_OUT_OF_REGION_OBS, RG_FILTER_MODE, MIN_OCCURRENCES_PER_RANK,
# INCLUDE_MINOR_RANKS_IN_ANCESTORS, etc.
# We'll just rely on them if set, or let them default in the scripts.

# ------------------------------------------------------------------------------
# 1) Create Export Directory Structure
# ------------------------------------------------------------------------------
print_progress "Creating export directory structure"
EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
HOST_EXPORT_DIR="${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
ensure_directory "${HOST_EXPORT_DIR}"

# ------------------------------------------------------------------------------
# 2) Create PostgreSQL Extension & Role if needed (once per container, but safe to run again)
# ------------------------------------------------------------------------------
execute_sql "
DO \$\$
BEGIN
    CREATE EXTENSION IF NOT EXISTS dblink;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exportuser') THEN
        CREATE ROLE exportuser;
    END IF;
END \$\$;"

# ------------------------------------------------------------------------------
# Timing: We'll measure how long each major phase takes
# ------------------------------------------------------------------------------
overall_start=$(date +%s)
regional_start=$(date +%s)

# ------------------------------------------------------------------------------
# 3) Always Invoke regional_base.sh (which handles partial skip logic)
# ------------------------------------------------------------------------------
print_progress "Invoking ancestor-aware regional_base.sh"
source "${BASE_DIR}/common/regional_base.sh"
print_progress "regional_base.sh completed"
regional_end=$(date +%s)
regional_secs=$(( regional_end - regional_start ))

# ------------------------------------------------------------------------------
# 4) Apply Cladistic Filtering
# ------------------------------------------------------------------------------
cladistic_start=$(date +%s)
print_progress "Applying cladistic filters via cladistic.sh"
source "${BASE_DIR}/common/cladistic.sh"
print_progress "Cladistic filtering complete"
cladistic_end=$(date +%s)
cladistic_secs=$(( cladistic_end - cladistic_start ))

# ------------------------------------------------------------------------------
# 5) Single Unified Export Summary
# ------------------------------------------------------------------------------
stats_start=$(date +%s)
print_progress "Creating unified export summary"

STATS=$(execute_sql "
WITH export_stats AS (
    SELECT 
        COUNT(DISTINCT observation_uuid) AS num_observations,
        COUNT(DISTINCT taxon_id) AS num_taxa,
        COUNT(DISTINCT observer_id) AS num_observers
    FROM \"${EXPORT_GROUP}_observations\"
)
SELECT format(
    'Observations: %s\nUnique Taxa: %s\nUnique Observers: %s',
    num_observations, num_taxa, num_observers
)
FROM export_stats;")

SUMMARY_FILE="${HOST_EXPORT_DIR}/${EXPORT_GROUP}_export_summary.txt"
{
  echo "Export Summary"
  echo "Version: ${VERSION_VALUE}"
  echo "Release: ${RELEASE_VALUE}"
  echo "Region: ${REGION_TAG}"
  echo "Minimum Observations (species): ${MIN_OBS}"
  echo "Maximum Random Number (MAX_RN): ${MAX_RN}"
  echo "Export Group: ${EXPORT_GROUP}"
  echo "Date: $(date)"
  echo "SKIP_REGIONAL_BASE: ${SKIP_REGIONAL_BASE}"
  echo "INCLUDE_OUT_OF_REGION_OBS: ${INCLUDE_OUT_OF_REGION_OBS}"
  echo "INCLUDE_MINOR_RANKS_IN_ANCESTORS: ${INCLUDE_MINOR_RANKS_IN_ANCESTORS}"
  echo "RG_FILTER_MODE: ${RG_FILTER_MODE}"
  echo "MIN_OCCURRENCES_PER_RANK (L20, L30, L40): ${MIN_OCCURRENCES_PER_RANK}"
  echo ""
  echo "Final Table Stats:"
  echo "${STATS}"
  echo ""
  echo "Timing:"
  echo " - Regional Base: ${regional_secs} seconds"
} > "${SUMMARY_FILE}"

stats_end=$(date +%s)
stats_secs=$(( stats_end - stats_start ))
print_progress "Stats/summary step took ${stats_secs} seconds"

# ------------------------------------------------------------------------------
# 6) Optionally Copy the Wrapper Script for Reproducibility
# ------------------------------------------------------------------------------
if [ -n "${WRAPPER_PATH}" ] && [ -f "${WRAPPER_PATH}" ]; then
    cp "${WRAPPER_PATH}" "${HOST_EXPORT_DIR}/"
fi

# ------------------------------------------------------------------------------
# 7) Wrap Up
# ------------------------------------------------------------------------------
overall_end=$(date +%s)
overall_secs=$(( overall_end - overall_start ))
print_progress "Export process complete (total time: ${overall_secs} seconds)"

{
  echo " - Cladistic: ${cladistic_secs} seconds"
  echo " - Summary/Stats Step: ${stats_secs} seconds"
  echo " - Overall: ${overall_secs} seconds"
} >> "${SUMMARY_FILE}"

send_notification "Export for ${EXPORT_GROUP} complete. Summary at ${SUMMARY_FILE}"
