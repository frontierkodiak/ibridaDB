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
# CLARIFY: We assume no sensitive env vars need filtering. If you store credentials,
#          you may want to exclude them from the final summary.
#
# ASSUMPTION: The user always sets WRAPPER_PATH="$0" in their wrapper, so we
#             can copy the original wrapper script here.

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

# If user wants to skip region creation, check if the table already exists
if [ "${SKIP_REGIONAL_BASE}" = "true" ]; then
    print_progress "SKIP_REGIONAL_BASE=true: Checking existing tables..."

    table_check=$(execute_sql "SELECT 1
      FROM pg_catalog.pg_tables
      WHERE schemaname = 'public'
        AND tablename = '${REGION_TAG}_min${MIN_OBS}_all_taxa_obs'
      LIMIT 1;")

    if [[ "$table_check" =~ "1" ]]; then
        print_progress "Table found, checking row count..."
        row_count=$(execute_sql "SELECT count(*) as cnt FROM \"${REGION_TAG}_min${MIN_OBS}_all_taxa_obs\";")
        numeric=$(echo "$row_count" | awk '/[0-9]/{print $1}' | head -1)

        if [[ -n "$numeric" && "$numeric" -gt 0 ]]; then
            print_progress "Table has $numeric rows; skipping creation of regional base."
            send_notification "Skipped creating regional base; table is non-empty."
        else
            print_progress "Table is empty; re-creating..."
            source "${BASE_DIR}/common/regional_base.sh"
            send_notification "${REGION_TAG} regional base tables created"
        fi
    else
        print_progress "Table not found; re-creating the regional base."
        source "${BASE_DIR}/common/regional_base.sh"
        send_notification "${REGION_TAG} regional base tables created"
    fi
else
    print_progress "Creating regional base tables"
    source "${BASE_DIR}/common/regional_base.sh"
    send_notification "${REGION_TAG} regional base tables created"
fi

# Run cladistic filtering
print_progress "Applying cladistic filters"
source "${BASE_DIR}/common/cladistic.sh"
send_notification "${EXPORT_GROUP} cladistic filtering complete"

# -------------------------------------------------------------------------
# Single unified export summary
# -------------------------------------------------------------------------
print_progress "Creating unified export summary"

# 1) Gather final table stats from <EXPORT_GROUP>_observations
#    If you want more complicated breakdowns, define them here or add queries.
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

# 2) Write summary file
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
  echo ""
  echo "Final Table Stats:"
  echo "${STATS}"
} > "${SUMMARY_FILE}"

# 3) Optionally copy the wrapper script for reproducibility
# If WRAPPER_PATH is not set, skip; if it is set but references something else, skip.
if [ -n "${WRAPPER_PATH}" ] && [ -f "${WRAPPER_PATH}" ]; then
    cp "${WRAPPER_PATH}" "${HOST_EXPORT_DIR}/"
fi

print_progress "Export process complete"
send_notification "Export for ${EXPORT_GROUP} is complete. Summary at ${SUMMARY_FILE}"