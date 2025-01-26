#!/bin/bash
#
# main.sh
#
# Orchestrates the export pipeline by:
#  1) Validating environment variables
#  2) Optionally creating the regional base tables (unless SKIP_REGIONAL_BASE=true)
#  3) Calling cladistic.sh to produce <EXPORT_GROUP>_observations
#  4) Writing a unified export summary (environment variables + final stats)
#  5) Optionally copying the wrapper script for reproducibility
#
# NOTE: Now references new naming logic for ancestor-aware approach.

source "${BASE_DIR}/common/functions.sh"

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

# We also note optional env vars:
# ANCESTOR_ROOT_RANKLEVEL, MIN_OCCURRENCES_PER_RANK
# They can be empty or set. We'll handle them in cladistic/regional_base.

print_progress "Creating export directory structure"
EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
HOST_EXPORT_DIR="${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

ensure_directory "${HOST_EXPORT_DIR}"

# Create PostgreSQL extension and role if needed
execute_sql "
DO \$\$
BEGIN
    CREATE EXTENSION IF NOT EXISTS dblink;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exportuser') THEN
        CREATE ROLE exportuser;
    END IF;
END \$\$;"

overall_start=$(date +%s)
regional_start=$(date +%s)

# We'll check for presence of the final table we plan to produce
# if user sets SKIP_REGIONAL_BASE=true
# New naming might be: ${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors_obs
# or some variant. # CLARIFY: We assume user wants to skip only if that table is found.

BASE_TABLE_NAME="${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors_obs"
# CLARIFY: If we incorporate INCLUDE_OUT_OF_REGION_OBS in the name, do so:
# if [ "${INCLUDE_OUT_OF_REGION_OBS}" = "true" ]; then
#   BASE_TABLE_NAME="${REGION_TAG}_min${MIN_OBS}_all_sp_and_ancestors_obs_ioorTrue"
# fi

if [ "${SKIP_REGIONAL_BASE}" = "true" ]; then
    print_progress "SKIP_REGIONAL_BASE=true: Checking existing tables..."

    table_check=$(execute_sql "SELECT 1
      FROM pg_catalog.pg_tables
      WHERE schemaname = 'public'
        AND tablename = '${BASE_TABLE_NAME}'
      LIMIT 1;")

    if [[ "$table_check" =~ "1" ]]; then
        print_progress "Table ${BASE_TABLE_NAME} found, checking row count..."
        row_count=$(execute_sql "SELECT count(*) as cnt FROM \"${BASE_TABLE_NAME}\";")
        numeric=$(echo "$row_count" | awk '/[0-9]/{print $1}' | head -1)

        if [[ -n "$numeric" && "$numeric" -gt 0 ]]; then
            print_progress "Table has $numeric rows; skipping creation of regional base."
            send_notification "Skipped creating regional base; table is non-empty."
        else
            print_progress "Table is empty; re-creating..."
            source "${BASE_DIR}/common/regional_base.sh"
            send_notification "${REGION_TAG} ancestor-aware base tables created"
        fi
    else
        print_progress "Table not found; re-creating the regional base."
        source "${BASE_DIR}/common/regional_base.sh"
        send_notification "${REGION_TAG} ancestor-aware base tables created"
    fi
else
    print_progress "Creating ancestor-aware regional base tables"
    source "${BASE_DIR}/common/regional_base.sh"
    send_notification "${REGION_TAG} ancestor-aware base tables created"
fi

regional_end=$(date +%s)
regional_secs=$(( regional_end - regional_start ))
print_progress "Regional base step took ${regional_secs} seconds"

# Now run cladistic
cladistic_start=$(date +%s)
print_progress "Applying cladistic filters"
source "${BASE_DIR}/common/cladistic.sh"
send_notification "${EXPORT_GROUP} cladistic filtering complete"

cladistic_end=$(date +%s)
cladistic_secs=$(( cladistic_end - cladistic_start ))
print_progress "Cladistic filtering step took ${cladistic_secs} seconds"

# Single unified export summary
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
  echo "RG_FILTER_MODE: ${RG_FILTER_MODE}"
  echo "ANCESTOR_ROOT_RANKLEVEL: ${ANCESTOR_ROOT_RANKLEVEL}"
  echo "MIN_OCCURRENCES_PER_RANK: ${MIN_OCCURRENCES_PER_RANK}"
  echo ""
  echo "Final Table Stats:"
  echo "${STATS}"
  echo ""
  echo "Timing:"
  echo " - Regional Base: ${regional_secs} seconds"
  echo " - Cladistic: ${cladistic_secs} seconds"
} > "${SUMMARY_FILE}"

stats_end=$(date +%s)
stats_secs=$(( stats_end - stats_start ))
print_progress "Stats/summary step took ${stats_secs} seconds"

# Optionally copy the wrapper
if [ -n "${WRAPPER_PATH}" ] && [ -f "${WRAPPER_PATH}" ]; then
    cp "${WRAPPER_PATH}" "${HOST_EXPORT_DIR}/"
fi

overall_end=$(date +%s)
overall_secs=$(( overall_end - overall_start ))
print_progress "Export process complete (total time: ${overall_secs} seconds)"

{
  echo " - Summary/Stats Step: ${stats_secs} seconds"
  echo " - Overall: ${overall_secs} seconds"
} >> "${SUMMARY_FILE}"

send_notification "Export for ${EXPORT_GROUP} complete. Summary at ${SUMMARY_FILE}"