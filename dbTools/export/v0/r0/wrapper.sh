#!/bin/bash

# Database config
export DB_USER="postgres"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r0"
export ORIGIN_VALUE="iNat-June2024"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"
export DB_CONTAINER="ibridaDB"

# Base paths
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/export/v0"
export HOST_EXPORT_BASE_PATH="/datasets/ibrida-data/exports"
export CONTAINER_EXPORT_BASE_PATH="/exports"

### Primary Terrestrial Arthropoda Export Parameters
export REGION_TAG="NAfull"
export MIN_OBS=50
export MAX_RN=3000
export PRIMARY_ONLY=true
export EXPORT_GROUP="primary_terrestrial_arthropoda"
export PROCESS_OTHER=false
export EXPORT_SUBDIR="${VERSION_VALUE}/${RELEASE_VALUE}/primary_only_${MIN_OBS}min_${MAX_RN}max"

### Amphibia Export Parameters (commented out)
# export REGION_TAG="NAfull"
# export MIN_OBS=400
# export MAX_RN=1000
# export PRIMARY_ONLY=true
# export EXPORT_GROUP="amphibia"
# export PROCESS_OTHER=false
# export EXPORT_SUBDIR="${VERSION_VALUE}/${RELEASE_VALUE}/primary_only_${MIN_OBS}min_${MAX_RN}max"

# Execute main script
"${BASE_DIR}/common/main.sh"