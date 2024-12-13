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

# Run regional base creation (source functions first)
print_progress "Creating regional base tables"
source "${BASE_DIR}/common/regional_base.sh"

# Run cladistic filtering
print_progress "Applying cladistic filters"
source "${BASE_DIR}/common/cladistic.sh"

# Export summary
print_progress "Creating export summary"
cat > "${HOST_EXPORT_DIR}/export_summary.txt" << EOL
Export Summary
Version: ${VERSION_VALUE}
Release: ${RELEASE_VALUE}
Region: ${REGION_TAG}
Minimum Observations: ${MIN_OBS}
Maximum Random Number: ${MAX_RN}
Export Group: ${EXPORT_GROUP}
Date: $(date)
EOL

print_progress "Export process complete"