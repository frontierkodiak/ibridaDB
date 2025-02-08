#!/bin/bash
#
# create_elevation_table.sh
#
# Creates or ensures the elevation_raster table exists in the target database,
# using create_elevation_table.sql. Index is also ensured via IF NOT EXISTS.
#
# Usage:
#   create_elevation_table.sh <DB_NAME> <DB_USER> <DB_CONTAINER>
#
# Environment Variables:
#   - BASE_DIR (optional if create_elevation_table.sql is elsewhere)
# 
# This script relies on helper functions from functions.sh for consistency.

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Parse arguments
# ------------------------------------------------------------------------------
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <DB_NAME> <DB_USER> <DB_CONTAINER>"
  exit 1
fi

DB_NAME="$1"
DB_USER="$2"
DB_CONTAINER="$3"

# If BASE_DIR not set, default to current script's grandparent
BASE_DIR="${BASE_DIR:-"$(cd "$(dirname "$0")/../../.." && pwd)"}"

# ------------------------------------------------------------------------------
# 2. Source shared functions
# ------------------------------------------------------------------------------
# We assume common/functions.sh is up two levels from 'elevation' subdir
source "${BASE_DIR}/common/functions.sh"

# ------------------------------------------------------------------------------
# 3. Run
# ------------------------------------------------------------------------------
print_progress "Creating elevation_raster table in database '${DB_NAME}'"

SQL_FILE="${BASE_DIR}/utils/elevation/create_elevation_table.sql"
if [ ! -f "${SQL_FILE}" ]; then
  echo "Error: Missing SQL file at ${SQL_FILE}"
  exit 1
fi

# We do not have a dedicated 'execute_sql_file' helper, so we cat + pipe:
cat "${SQL_FILE}" | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"

print_progress "elevation_raster table is created or already exists."
send_notification "[OK] Created/verified elevation_raster table in ${DB_NAME}"
