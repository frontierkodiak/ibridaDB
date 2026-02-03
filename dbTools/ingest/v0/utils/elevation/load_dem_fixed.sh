#!/bin/bash
#
# load_dem_fixed.sh
#
# FIXED VERSION: Creates index only ONCE (optionally after full load), not per file
# Loads MERIT DEM tiles from .tar archives into the elevation_raster table via raster2pgsql.
# Supports parallelization by tar file (PARALLEL_TARS env).
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
CONTAINER_TEMP_BASE="/dem/merit/temp"

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

PARALLEL_TARS="${PARALLEL_TARS:-4}"
CREATE_INDEX_AFTER_LOAD="${CREATE_INDEX_AFTER_LOAD:-true}"

mapfile -t TAR_FILES < <(ls "${HOST_DEM_DIR}"/*.tar 2>/dev/null || true)

if [ "${#TAR_FILES[@]}" -eq 0 ]; then
  print_progress "No TIF files found, creating empty elevation_raster table..."
  execute_sql "$(cat ${BASE_DIR}/utils/elevation/create_elevation_table.sql)"
  exit 0
fi

PSQL_ENV=( -e PGOPTIONS="-c synchronous_commit=off" )

seed_tar="${TAR_FILES[0]}"
seed_name="$(basename "${seed_tar}" .tar)"
seed_temp_dir="${TEMP_DIR}/${seed_name}"
seed_container_dir="${CONTAINER_TEMP_BASE}/${seed_name}"

# Prepare seed temp dir
rm -rf "${seed_temp_dir}" || true
ensure_directory "${seed_temp_dir}"

print_progress "Extracting ${seed_tar} (seed tar)..."
tar -xf "${seed_tar}" -C "${seed_temp_dir}"

mapfile -t seed_tifs < <(find "${seed_temp_dir}" -type f -name '*.tif' | sort)
if [ "${#seed_tifs[@]}" -eq 0 ]; then
  echo "Warning: No .tif found in ${seed_tar}; skipping seed tar."
else
  seed_tif="${seed_tifs[0]}"
  seed_container_tif="${seed_container_dir}/$(basename "$(dirname "${seed_tif}")")/$(basename "${seed_tif}")"
  print_progress "Creating elevation_raster table with seed tif ${seed_tif}"
  # Create table (no index). We'll add index after full load.
  docker exec "${DB_CONTAINER}" raster2pgsql -C -s "${EPSG}" -t "${TILE_SIZE}" "${seed_container_tif}" elevation_raster \
    | docker exec -i "${PSQL_ENV[@]}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"
  # Drop max extent constraint so subsequent tiles outside the first tile bounds can append.
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" \
    -c "ALTER TABLE elevation_raster DROP CONSTRAINT IF EXISTS enforce_max_extent_rast;"

  # Append remaining tifs from seed tar (skip seed tif to avoid duplication)
  for tiffile in "${seed_tifs[@]}"; do
    if [ "${tiffile}" = "${seed_tif}" ]; then
      continue
    fi
    print_progress "Loading ${tiffile} into PostGIS (EPSG=${EPSG}, tile=${TILE_SIZE})"
    container_tif="${seed_container_dir}/$(basename "$(dirname "${tiffile}")")/$(basename "${tiffile}")"
    docker exec "${DB_CONTAINER}" raster2pgsql -a -s "${EPSG}" -t "${TILE_SIZE}" "${container_tif}" elevation_raster \
      | docker exec -i "${PSQL_ENV[@]}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"
  done
fi

# Cleanup seed temp dir
rm -rf "${seed_temp_dir}" || true

process_tar() {
  local tarfile="$1"
  local tarname="$(basename "${tarfile}" .tar)"
  local host_dir="${TEMP_DIR}/${tarname}"
  local container_dir="${CONTAINER_TEMP_BASE}/${tarname}"

  rm -rf "${host_dir}" || true
  ensure_directory "${host_dir}"

  print_progress "Extracting ${tarfile}..."
  tar -xf "${tarfile}" -C "${host_dir}"

  mapfile -t found_tifs < <(find "${host_dir}" -type f -name '*.tif' | sort)
  if [ "${#found_tifs[@]}" -eq 0 ]; then
    echo "Warning: No .tif found in ${tarfile}; skipping."
    rm -rf "${host_dir}" || true
    return
  fi

  for tiffile in "${found_tifs[@]}"; do
    print_progress "Loading ${tiffile} into PostGIS (EPSG=${EPSG}, tile=${TILE_SIZE})"
    container_tif="${container_dir}/$(basename "$(dirname "${tiffile}")")/$(basename "${tiffile}")"
    docker exec "${DB_CONTAINER}" raster2pgsql -a -s "${EPSG}" -t "${TILE_SIZE}" "${container_tif}" elevation_raster \
      | docker exec -i "${PSQL_ENV[@]}" "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}"
  done

  rm -rf "${host_dir}" || true
}

export -f process_tar print_progress ensure_directory

# Process remaining tar files in parallel
for tarfile in "${TAR_FILES[@]:1}"; do
  process_tar "${tarfile}" &
  while [ "$(jobs -rp | wc -l)" -ge "${PARALLEL_TARS}" ]; do
    wait -n
  done
done

wait

if [ "${CREATE_INDEX_AFTER_LOAD}" = "true" ]; then
  print_progress "Creating GIST index on elevation_raster"
  execute_sql "CREATE INDEX IF NOT EXISTS elevation_raster_st_convexhull_idx ON elevation_raster USING gist (ST_ConvexHull(rast));"
fi

# ------------------------------------------------------------------------------
# 5. If we never found any files, create the table manually
# ------------------------------------------------------------------------------
print_progress "DEM loading complete."
send_notification "[OK] Completed loading DEM data into ${DB_NAME}"
