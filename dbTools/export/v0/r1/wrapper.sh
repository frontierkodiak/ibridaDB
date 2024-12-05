#!/bin/bash

# Database config
export DB_USER="postgres"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r1"
export ORIGIN_VALUE="iNat-Dec2024"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"

# Export parameters
export REGION_TAG="NAfull"
export MIN_OBS=50
export MAX_RN=4000
export PRIMARY_ONLY=true
export EXPORT_GROUP="primary_terrestrial_arthropoda"
export PROCESS_OTHER=false

# Paths
export DB_CONTAINER="ibridaDB"
export HOST_EXPORT_BASE_PATH="/datasets/ibrida-data/exports"
export CONTAINER_EXPORT_BASE_PATH="/exports"
export EXPORT_SUBDIR="${VERSION_VALUE}/${RELEASE_VALUE}/primary_only_${MIN_OBS}min_${MAX_RN}max"
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/export/v0"

# Execute main script
"${BASE_DIR}/common/main.sh"