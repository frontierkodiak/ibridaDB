#!/bin/bash
#
# main.sh
#
# High-level orchestration for setting up elevation data:
#   1) create_elevation_table.sh
#   2) load_dem.sh
#   3) update_elevation.sh
#
# Usage:
#   main.sh <DB_NAME> <DB_USER> <DB_CONTAINER> <DEM_DIR> <NUM_PROCESSES> [EPSG=4326] [TILE_SIZE=100x100]
#
# Example:
#   main.sh ibrida-v0-r1 postgres ibridaDB /datasets/dem/merit 16 4326 100x100
#
# Notes:
#   - Called by wrapper.sh typically, but can be run standalone.
#   - We rely on the geometry column (observations.geom) to already exist!

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Parse arguments
# ------------------------------------------------------------------------------
if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <DB_NAME> <DB_USER> <DB_CONTAINER> <DEM_DIR> <NUM_PROCESSES> [EPSG] [TILE_SIZE]"
  exit 1
fi

DB_NAME="$1"
DB_USER="$2"
DB_CONTAINER="$3"
DEM_DIR="$4"
NUM_PROCESSES="$5"
EPSG="${6:-4326}"
TILE_SIZE="${7:-100x100}"

# If BASE_DIR not set, default to current script's grandparent
BASE_DIR="${BASE_DIR:-"$(cd "$(dirname "$0")/../../.." && pwd)"}"

# ------------------------------------------------------------------------------
# 2. Source shared functions
# ------------------------------------------------------------------------------
source "${BASE_DIR}/common/functions.sh"

print_progress "=== Elevation: main.sh start ==="
send_notification "[INFO] Starting elevation main flow for DB=${DB_NAME}"

# ------------------------------------------------------------------------------
# 3. Step 1: Create elevation_raster table
# ------------------------------------------------------------------------------
"${BASE_DIR}/utils/elevation/create_elevation_table.sh" \
  "${DB_NAME}" \
  "${DB_USER}" \
  "${DB_CONTAINER}"

# ------------------------------------------------------------------------------
# 4. Step 2: Load DEM data
# ------------------------------------------------------------------------------
"${BASE_DIR}/utils/elevation/load_dem.sh" \
  "${DEM_DIR}" \
  "${DB_NAME}" \
  "${DB_USER}" \
  "${DB_CONTAINER}" \
  "${EPSG}" \
  "${TILE_SIZE}"

# ------------------------------------------------------------------------------
# 5. Step 3: Update observations with elevation
# ------------------------------------------------------------------------------
"${BASE_DIR}/utils/elevation/update_elevation.sh" \
  "${DB_NAME}" \
  "${DB_USER}" \
  "${DB_CONTAINER}" \
  "${NUM_PROCESSES}"

print_progress "=== Elevation: main.sh complete ==="
send_notification "[OK] Elevation pipeline complete for DB=${DB_NAME}"
