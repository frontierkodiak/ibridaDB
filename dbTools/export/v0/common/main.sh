#!/bin/bash

# Source common functions
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

# Create export directory structure
print_progress "Creating export directory structure"
EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
HOST_EXPORT_DIR="${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

# Create host directory with proper permissions
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

# CLARIFY: We assume the user won't skip if the table name is inconsistent with
# the desired region or MIN_OBS. We only do a basic check that the table exists
# and has rows.
# ASSUMPTION: The user is responsible for ensuring that the existing table
# matches the correct region and MIN_OBS setting if SKIP_REGIONAL_BASE=true.

if [ "${SKIP_REGIONAL_BASE}" = "true" ]; then
    print_progress "SKIP_REGIONAL_BASE=true: Checking existing tables..."

    # 1) Check if the table actually exists
    table_check=$(execute_sql "SELECT 1
      FROM pg_catalog.pg_tables
      WHERE schemaname = 'public'
        AND tablename = '${REGION_TAG}_min${MIN_OBS}_all_taxa_obs'
      LIMIT 1;")

    # Convert the output to something we can parse easily:
    # psql typically returns row headers, so we check if it contains "(1 row)" or "1"
    # For simplicity, we do a naive grep or check:
    if [[ "$table_check" =~ "1" ]]; then
        print_progress "Table ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs found, checking row count..."

        row_count=$(execute_sql "SELECT count(*) as cnt FROM \"${REGION_TAG}_min${MIN_OBS}_all_taxa_obs\";")

        # We'll parse the integer from row_count with a simple approach:
        # row_count might look like:
        #  cnt
        # ----
        #  452201
        # (1 row)
        # We can do a quick grep or awk:
        numeric=$(echo "$row_count" | awk '/[0-9]/{print $1}' | head -1)

        if [[ -n "$numeric" && "$numeric" -gt 0 ]]; then
            print_progress "Table has $numeric rows; skipping creation of regional base."
            send_notification "Skipped creating regional base; table is non-empty."
        else
            print_progress "Table is empty or row count could not be determined; re-creating..."
            source "${BASE_DIR}/common/regional_base.sh"
            send_notification "${REGION_TAG} regional base tables created"
        fi
    else
        print_progress "Table not found; re-creating the regional base."
        source "${BASE_DIR}/common/regional_base.sh"
        send_notification "${REGION_TAG} regional base tables created"
    fi
else
    # Run regional base creation (source functions first)
    print_progress "Creating regional base tables"
    source "${BASE_DIR}/common/regional_base.sh"
    send_notification "${REGION_TAG} regional base tables created"
fi

# Run cladistic filtering
print_progress "Applying cladistic filters"
source "${BASE_DIR}/common/cladistic.sh"
send_notification "${EXPORT_GROUP} cladistic filtering complete"

# Export summary
print_progress "Creating export summary"
# Changed from a fixed "export_summary.txt" to a unique name:
cat > "${HOST_EXPORT_DIR}/${EXPORT_GROUP}_export_summary.txt" << EOL
Export Summary
Version: ${VERSION_VALUE}
Release: ${RELEASE_VALUE}
Region: ${REGION_TAG}
Minimum Observations: ${MIN_OBS}
Maximum Random Number: ${MAX_RN}
Export Group: ${EXPORT_GROUP}
Date: $(date)
SKIP_REGIONAL_BASE: ${SKIP_REGIONAL_BASE}
EOL

print_progress "Export process complete"