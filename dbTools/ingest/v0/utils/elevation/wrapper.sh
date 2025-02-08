#!/bin/bash
#
# wrapper.sh
#
# A wrapper that sets environment variables / parameters and calls the
# elevation main.sh. This is useful for a one-off scenario on an existing DB,
# or for hooking into your ingestion flow after geometry is set.
#
# Usage:
#   wrapper.sh
#   (no arguments; you can edit the variables in-script)
#
# Example:
#   chmod +x wrapper.sh
#   ./wrapper.sh
#
# Required Tools:
#   - Docker
#   - raster2pgsql
#

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Configuration
# ------------------------------------------------------------------------------
export DB_NAME="ibrida-v0-r1"
export DB_USER="postgres"
export DB_CONTAINER="ibridaDB"
export DEM_DIR="/datasets/dem/merit"
export NUM_PROCESSES="16"
export EPSG="4326"
export TILE_SIZE="100x100"
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/v0"

# ------------------------------------------------------------------------------
# 2. Logging / Sourcing
# ------------------------------------------------------------------------------
LOG_FILE="$(dirname "$(readlink -f "$0")")/wrapper_$(date +%Y%m%d_%H%M%S).log"
echo "Starting elevation wrapper at $(date)" | tee -a "${LOG_FILE}"

source "${BASE_DIR}/common/functions.sh"

print_progress "Invoking elevation main script" | tee -a "${LOG_FILE}"
send_notification "[INFO] Elevation wrapper invoked"

# ------------------------------------------------------------------------------
# 3. Call main.sh
# ------------------------------------------------------------------------------
"${BASE_DIR}/utils/elevation/main.sh" \
  "${DB_NAME}" \
  "${DB_USER}" \
  "${DB_CONTAINER}" \
  "${DEM_DIR}" \
  "${NUM_PROCESSES}" \
  "${EPSG}" \
  "${TILE_SIZE}" \
  2>&1 | tee -a "${LOG_FILE}"

print_progress "Elevation wrapper complete" | tee -a "${LOG_FILE}"
send_notification "[OK] Elevation wrapper flow finished successfully"
