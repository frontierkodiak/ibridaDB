#!/bin/bash

# Define variables
DB_USER="postgres"
VERSION_VALUE="v0"
ORIGIN_VALUE="iNat-June2024"
DB_NAME="ibrida-${VERSION_VALUE}"
REGION_TAG="NAfull"
MIN_OBS=50
MAX_RN=3000
PRIMARY_ONLY=true  # Set this to true to select only primary photos (position == 0)
EXPORT_GROUP="primary_terrestrial_arthropoda"  # Metaclade to export
PROCESS_OTHER=false  # Set to true if you want to process the 'other' group
EXPORT_SUBDIR="${ORIGIN_VALUE}/${VERSION_VALUE}/primary_only_${MIN_OBS}min_${MAX_RN}max"  # Subdirectory for CSV exports
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
export DB_USER VERSION_VALUE ORIGIN_VALUE DB_NAME REGION_TAG MIN_OBS MAX_RN PRIMARY_ONLY EXPORT_SUBDIR DB_CONTAINER HOST_EXPORT_BASE_PATH CONTAINER_EXPORT_BASE_PATH EXPORT_GROUP PROCESS_OTHER

# Execute the regional_base.sh script
# NOTE: Commented as we already ran this successfully.
# execute_script "$REGIONAL_BASE_SCRIPT"

# Execute the cladistic.sh script
execute_script "$CLADISTIC_SCRIPT"

echo "All scripts executed successfully."

# NOTE: Version and origin temporarily removed from export tables.
# NOTE: Version still used for export path.

# Display summary information
echo "Export Summary:"
echo "---------------"
echo "Database: $DB_NAME"
echo "Export Group: $EXPORT_GROUP"
echo "Region: $REGION_TAG"
echo "Minimum Observations: $MIN_OBS"
echo "Maximum Random Number: $MAX_RN"
echo "Primary Photos Only: $PRIMARY_ONLY"
echo "Process 'Other' Group: $PROCESS_OTHER"
echo "Export Directory: ${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

# Check if export was successful
if [ -f "${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}/${EXPORT_GROUP}_photos.csv" ]; then
    echo "Export successful. CSV file created: ${EXPORT_GROUP}_photos.csv"
else
    echo "Warning: CSV file not found. Export may have failed."
fi

echo "For detailed export information, please check the export_summary.txt file in the export directory."