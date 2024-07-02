#!/bin/bash

# Define variables
DB_USER="postgres"
VERSION_VALUE="v0"
ORIGIN_VALUE="iNat-June2024"
DB_NAME="ibrida-${VERSION_VALUE}"
REGION_TAG="NAfull"
MIN_OBS=50
MAX_RN=4000
PRIMARY_ONLY=true  # Set this to true to select only primary photos (position == 0)
EXPORT_SUBDIR="${ORIGIN_VALUE}/${VERSION_VALUE}/primary_only"  # Subdirectory for CSV exports
DB_CONTAINER="fast-ibrida-1"  # Update this to your container name
HOST_EXPORT_BASE_PATH="/pond/Polli/ibridaExports"
CONTAINER_EXPORT_BASE_PATH="/exports"

# Paths to the scripts
REGIONAL_BASE_SCRIPT="/home/caleb/repo/ibridaDB/dbTools/export/v0/regional_base.sh"
CLADISTIC_SCRIPT="/home/caleb/repo/ibridaDB/dbTools/export/v0/cladistic.sh"

# Function to execute a script and check its success
execute_script() {
  local script="$1"
  if ! bash "$script"; then
    echo "Error: Script $script failed."
    exit 1
  fi
}

# Set permissions before running scripts
docker exec "$DB_CONTAINER" bash -c "chmod -R 777 $CONTAINER_EXPORT_BASE_PATH && chown -R postgres:postgres $CONTAINER_EXPORT_BASE_PATH"
echo "Permissions set for $CONTAINER_EXPORT_BASE_PATH"

# Export variables to be used by the child scripts
export DB_USER VERSION_VALUE ORIGIN_VALUE DB_NAME REGION_TAG MIN_OBS MAX_RN PRIMARY_ONLY EXPORT_SUBDIR DB_CONTAINER HOST_EXPORT_BASE_PATH CONTAINER_EXPORT_BASE_PATH

# # Execute the regional_base.sh script
execute_script "$REGIONAL_BASE_SCRIPT"

# If the first script succeeds, execute the cladistic.sh script
execute_script "$CLADISTIC_SCRIPT"

echo "All scripts executed successfully."

# NOTE: Version and origin temporarily removed from export tables.
# NOTE: Version still used for export path.
