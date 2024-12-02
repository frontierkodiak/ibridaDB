#!/bin/bash

# Database and user variables
export DB_USER="postgres"
export DB_TEMPLATE="template_postgis"
export NUM_PROCESSES=16
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/v0"

# Source variable
export SOURCE="Dec2024"
export METADATA_PATH="/metadata/${SOURCE}"

# Version and origin values
export ORIGIN_VALUE="iNat-${SOURCE}"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r1"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"
export DB_CONTAINER="ibridaDB"
export STRUCTURE_SQL="${BASE_DIR}/r1/structure.sql"

# Execute main script
"${BASE_DIR}/common/main.sh"