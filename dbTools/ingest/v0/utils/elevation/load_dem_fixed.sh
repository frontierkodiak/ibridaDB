#!/bin/bash
#
# load_dem_fixed.sh
#
# FIXED VERSION: Creates index only ONCE, not for every TIF file
# Loads MERIT DEM tiles from .tar archives into the elevation_raster table via raster2pgsql.
#
# Usage:
#   load_dem_fixed.sh <DEM_DIR> <DB_NAME> <DB_USER> <DB_CONTAINER> <EPSG> <TILE_SIZE>
#
# Example:
#   load_dem_fixed.sh /datasets/dem/merit ibrida-v0 postgres ibridaDB 4326 100x100
#
# Changes from original:
#   - Only creates GIST index once at the end, not per file
#   - Much faster ingestion (hours instead of weeks)

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Parse arguments
# ------------------------------------------------------------------------------
if [ "$#" -lt 6 ]; then
  echo "Usage: $0 <DEM_DIR> <DB_NAME> <DB_USER> <DB_CONTAINER> <EPSG> <TILE_SIZE>"
  exit 1
fi

# Host-side paths
HOST_DEM_DIR="$1"
DB_NAME="$2"
DB_USER="$3"
DB_CONTAINER="$4"
EPSG="$5"
TILE_SIZE="$6"

# Container-side paths (translate from host paths)
CONTAINER_DEM_DIR="/dem/merit"  # /datasets/dem/merit -> /dem/merit
CONTAINER_TEMP_DIR="/dem/merit/temp"

# If BASE_DIR not set, default to current script's grandparent
BASE_DIR="${BASE_DIR:-"$(cd "$(dirname "$0")/../../.." && pwd)"}"

# ------------------------------------------------------------------------------
# 2. Source shared functions
# ------------------------------------------------------------------------------
source "${BASE_DIR}/common/functions.sh"

# ------------------------------------------------------------------------------
# 3. Prepare temporary directory (use host path for mkdir)
# ------------------------------------------------------------------------------
TEMP_DIR="${HOST_DEM_DIR}/temp"
ensure_directory "${TEMP_DIR}"

print_progress "Loading DEM data from ${HOST_DEM_DIR} into ${DB_NAME}"

# ------------------------------------------------------------------------------
# 4. Loop over .tar files, extract, load via raster2pgsql
# ------------------------------------------------------------------------------
FIRST_FILE=true

for tarfile in "${HOST_DEM_DIR}"/*.tar; do
  if [ ! -f "${tarfile}" ]; then
    # If no .tar files exist, skip
    continue
  fi

  # Extract (using host paths)
  print_progress "Extracting ${tarfile}..."
  tar -xf "${tarfile}" -C "${TEMP_DIR}"

  # Find any .tif file(s) (using host paths)
  found_tifs=($(find "${TEMP_DIR}" -type f -name '*.tif'))
  if [ "${#found_tifs[@]}" -eq 0 ]; then
    echo "Warning: No .tif found in ${tarfile}; skipping."
    rm -rf "${TEMP_DIR:?}"/*
    continue
  fi

  # Load each TIF
  for tiffile in "${found_tifs[@]}"; do
    print_progress "Loading ${tiffile} into PostGIS (EPSG=${EPSG}, tile=${TILE_SIZE})"
    
    # Convert host path to container path for the TIF file
    CONTAINER_TIFFILE="${CONTAINER_TEMP_DIR}/$(basename "$(dirname "${tiffile}")")/$(basename "${tiffile}")"
    
    # FIXED: Only use -I flag on the very first file to create the index once
    if [ "${FIRST_FILE}" = true ]; then
      print_progress "Creating table and index with first file..."
      # Use -C to create table and -I to create index (only once!)
      docker exec "${DB_CONTAINER}" raster2pgsql -C -s "${EPSG}" -t "${TILE_SIZE}" -I "${CONTAINER_TIFFILE}" elevation_raster \
        | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"
      FIRST_FILE=false
    else
      # For all subsequent files, use -a (append) WITHOUT -I flag
      docker exec "${DB_CONTAINER}" raster2pgsql -a -s "${EPSG}" -t "${TILE_SIZE}" "${CONTAINER_TIFFILE}" elevation_raster \
        | docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"
    fi

    send_notification "[OK] Loaded DEM tile: $(basename "${tiffile}") into ${DB_NAME}"
  done

  # Cleanup extracted files (using host path)
  rm -rf "${TEMP_DIR:?}"/*
done

# ------------------------------------------------------------------------------
# 5. If we never found any files, create the table manually
# ------------------------------------------------------------------------------
if [ "${FIRST_FILE}" = true ]; then
  print_progress "No TIF files found, creating empty elevation_raster table..."
  execute_sql "$(cat ${BASE_DIR}/utils/elevation/create_elevation_table.sql)"
fi

print_progress "DEM loading complete."
send_notification "[OK] Completed loading DEM data into ${DB_NAME}"