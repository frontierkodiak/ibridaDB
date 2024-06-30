#!/bin/bash

# Define variables
DB_USER="postgres"
VERSION_VALUE="v0"
DB_NAME="ibrida-${VERSION_VALUE}"
REGION_TAG="NAfull"
MIN_OBS=50
MAX_RN=4000
PRIMARY_ONLY=true  # Set this to true to select only primary photos (position == 0)
EXPORT_SUBDIR="iNat-June2024/v0/primary_only"  # Subdirectory for CSV exports

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

# Export variables to be used by the child scripts
export DB_USER VERSION_VALUE DB_NAME REGION_TAG MIN_OBS MAX_RN PRIMARY_ONLY EXPORT_SUBDIR

# Execute the regional_base.sh script
execute_script "$REGIONAL_BASE_SCRIPT"

# If the first script succeeds, execute the cladistic.sh script
execute_script "$CLADISTIC_SCRIPT"

echo "All scripts executed successfully."
