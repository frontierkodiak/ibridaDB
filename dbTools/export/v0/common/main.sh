#!/bin/bash
#
# main.sh
#
# Orchestrates the export pipeline by:
#   1) Validating environment variables
#   2) Always calling regional_base.sh (which handles creating/reusing
#      the region/clade-specific ancestor tables as needed).
#   3) Calling cladistic.sh to produce the final <EXPORT_GROUP>_observations table
#   4) Writing a unified export summary (environment variables + final stats)
#   5) Optionally copying the wrapper script for reproducibility
#
# NOTE:
#  - We no longer do skip/existence checks here. Instead, regional_base.sh
#    performs partial skip logic for its tables (_all_sp, _all_sp_and_ancestors_*, etc.).
#  - We have removed references to ANCESTOR_ROOT_RANKLEVEL, since our new multi-root
#    approach does not require it.
#
# This script expects the following environment variables to be set by the wrapper:
#   DB_USER           -> PostgreSQL user (e.g. "postgres")
#   VERSION_VALUE     -> Database version identifier (e.g. "v0")
#   RELEASE_VALUE     -> Release identifier (e.g. "r1")
#   ORIGIN_VALUE      -> (Optional) For logging context
#   DB_NAME           -> Name of the database (e.g. "ibrida-v0-r1")
#   REGION_TAG        -> Region bounding box key (e.g. "NAfull")
#   MIN_OBS           -> Minimum observations required for a species to be included
#   MAX_RN            -> Max random number of research-grade rows per species in final CSV
#   DB_CONTAINER      -> Docker container name for exec (e.g. "ibridaDB")
#   HOST_EXPORT_BASE_PATH -> Host system directory for exports
#   CONTAINER_EXPORT_BASE_PATH -> Container path that maps to HOST_EXPORT_BASE_PATH
#   EXPORT_SUBDIR     -> Subdirectory for the export (e.g. "v0/r1/primary_only_50min_4000max")
#   EXPORT_GROUP      -> Name of the final group (used in final table naming)
#
# Additionally, you may define:
#   WRAPPER_PATH      -> Path to the wrapper script for reproducibility (copied into the output dir if present).
#   INCLUDE_OUT_OF_REGION_OBS -> Whether to keep out-of-region observations for a region-based species.
#   RG_FILTER_MODE    -> One of: ONLY_RESEARCH, ALL, ALL_EXCLUDE_SPECIES_NON_RESEARCH, etc.
#   PRIMARY_ONLY      -> If true, only the primary (position=0) photo is included.
#   SKIP_REGIONAL_BASE-> If true, we skip regeneration of base tables if they exist.
#   INCLUDE_ELEVATION_EXPORT -> If "true", we include the 'elevation_meters' column (provided the DB has it, e.g. not "r0").
#
# All these environment variables are typically set in the release-specific wrapper (e.g. r1/wrapper_amphibia_all_exc_nonrg_sp.sh).
#

set -e

# ------------------------------------------------------------------------------
# 0) Source common functions
# ------------------------------------------------------------------------------
# We'll assume the caller sets BASE_DIR to the root of export/v0
# so that we can find common/functions.sh easily.
source "${BASE_DIR}/common/functions.sh"

# ------------------------------------------------------------------------------
# 1) Validate Required Environment Variables
# ------------------------------------------------------------------------------
required_vars=(
    "DB_USER" "VERSION_VALUE" "RELEASE_VALUE" "ORIGIN_VALUE"
    "DB_NAME" "REGION_TAG" "MIN_OBS" "MAX_RN"
    "DB_CONTAINER" "HOST_EXPORT_BASE_PATH" "CONTAINER_EXPORT_BASE_PATH"
    "EXPORT_SUBDIR" "EXPORT_GROUP"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "Error: Required variable $var is not set"
        exit 1
    fi
done

# Some environment variables are optional but relevant:
# - SKIP_REGIONAL_BASE, INCLUDE_OUT_OF_REGION_OBS, RG_FILTER_MODE, MIN_OCCURRENCES_PER_RANK,
#   INCLUDE_MINOR_RANKS_IN_ANCESTORS, PRIMARY_ONLY, etc.
# We'll let them default if not set.

# ------------------------------------------------------------------------------
# 2) Create Export Directory Structure
# ------------------------------------------------------------------------------
print_progress "Creating export directory structure"
EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
HOST_EXPORT_DIR="${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
ensure_directory "${HOST_EXPORT_DIR}"

# ------------------------------------------------------------------------------
# 3) Create PostgreSQL Extension & Role if needed (once per container, safe to run again)
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
# Optional Logging for Elevation Setting
# ------------------------------------------------------------------------------
if [ "${INCLUDE_ELEVATION_EXPORT:-true}" = "true" ]; then
    print_progress "INCLUDE_ELEVATION_EXPORT=true => Elevation data (elevation_meters) will be included if present"
else
    print_progress "INCLUDE_ELEVATION_EXPORT=false => Elevation data will NOT be included"
fi

# ------------------------------------------------------------------------------
# Timing: We'll measure how long each major phase takes
# ------------------------------------------------------------------------------
overall_start=$(date +%s)

# ------------------------------------------------------------------------------
# 4) Always Invoke regional_base.sh
# ------------------------------------------------------------------------------
# The script 'regional_base.sh' is responsible for building or reusing
# region/clade-specific base tables. If SKIP_REGIONAL_BASE=true and the table
# exists, it is reused. Otherwise, it is created fresh.
regional_start=$(date +%s)
print_progress "Invoking ancestor-aware regional_base.sh"
source "${BASE_DIR}/common/regional_base.sh"
print_progress "regional_base.sh completed"
regional_end=$(date +%s)
regional_secs=$(( regional_end - regional_start ))

# ------------------------------------------------------------------------------
# 5) Apply Cladistic Filtering => Produces <EXPORT_GROUP>_observations
# ------------------------------------------------------------------------------
cladistic_start=$(date +%s)
print_progress "Applying cladistic filters via cladistic.sh"
source "${BASE_DIR}/common/cladistic.sh"
print_progress "Cladistic filtering complete"
cladistic_end=$(date +%s)
cladistic_secs=$(( cladistic_end - cladistic_start ))

# ------------------------------------------------------------------------------
# 6) Single Unified Export Summary
# ------------------------------------------------------------------------------
# We'll store environment variables, row counts, timing, etc. in a single file.
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
  echo "Origin: ${ORIGIN_VALUE}"
  echo "Region: ${REGION_TAG}"
  echo "Minimum Observations (species): ${MIN_OBS}"
  echo "Maximum Random Number (MAX_RN): ${MAX_RN}"
  echo "Export Group: ${EXPORT_GROUP}"
  echo "Date: $(date)"
  echo "SKIP_REGIONAL_BASE: ${SKIP_REGIONAL_BASE}"
  echo "INCLUDE_OUT_OF_REGION_OBS: ${INCLUDE_OUT_OF_REGION_OBS}"
  echo "INCLUDE_MINOR_RANKS_IN_ANCESTORS: ${INCLUDE_MINOR_RANKS_IN_ANCESTORS}"
  echo "RG_FILTER_MODE: ${RG_FILTER_MODE}"
  echo "MIN_OCCURRENCES_PER_RANK: ${MIN_OCCURRENCES_PER_RANK}"
  echo "INCLUDE_ELEVATION_EXPORT: ${INCLUDE_ELEVATION_EXPORT}"
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
# 7) Optionally Copy the Wrapper Script for Reproducibility
# ------------------------------------------------------------------------------
if [ -n "${WRAPPER_PATH:-}" ] && [ -f "${WRAPPER_PATH}" ]; then
    cp "${WRAPPER_PATH}" "${HOST_EXPORT_DIR}/"
fi

# ------------------------------------------------------------------------------
# 8) Wrap Up
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
