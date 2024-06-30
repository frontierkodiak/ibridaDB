#!/bin/bash

# Define variables
DB_USER="postgres"
DB_NAME="ibrida-${VERSION_VALUE}"
REGION_TAG="NAfull"
MIN_OBS=50

# Function to set region-specific coordinates
set_region_coordinates() {
  case "$REGION_TAG" in
    "NAfull")
      XMIN=-169.453125
      YMIN=12.211180
      XMAX=-23.554688
      YMAX=84.897147
      ;;
    *)
      echo "Unknown REGION_TAG: $REGION_TAG"
      exit 1
      ;;
  esac
}

# Set region coordinates
set_region_coordinates

# Function to execute SQL commands
execute_sql() {
  local sql="$1"
  docker exec ibrida psql -U "$DB_USER" -d "$DB_NAME" -c "$sql"
}

# Function to print progress
print_progress() {
  local message="$1"
  echo "======================================"
  echo "$message"
  echo "======================================"
}

# Create table <REGION_TAG>_min<MIN_OBS>_all_taxa
print_progress "Creating table ${REGION_TAG}_min${MIN_OBS}_all_taxa"
execute_sql "
BEGIN;

CREATE TABLE ${REGION_TAG}_min${MIN_OBS}_all_taxa AS
SELECT  
    DISTINCT observations.taxon_id  
FROM  
    observations 
WHERE 
    observations.observation_uuid = ANY (
        SELECT observations.observation_uuid
        FROM observations
        JOIN taxa ON observations.taxon_id = taxa.taxon_id
        WHERE 
            NOT (taxa.rank_level = 10 AND observations.quality_grade != 'research')
            AND observations.latitude BETWEEN ${YMIN} AND ${YMAX}
            AND observations.longitude BETWEEN ${XMIN} AND ${XMAX}
    )
    AND observations.taxon_id IN (
        SELECT observations.taxon_id
        FROM observations
        GROUP BY observations.taxon_id
        HAVING COUNT(observation_uuid) >= ${MIN_OBS}
    );

COMMIT;
"

# Create table <REGION_TAG>_min<MIN_OBS>_all_taxa_obs
print_progress "Creating table ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs"
execute_sql "
BEGIN;

CREATE TABLE ${REGION_TAG}_min${MIN_OBS}_all_taxa_obs AS
SELECT  
    observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade,  
    observed_on, origin, version
FROM
    observations
WHERE
    taxon_id IN (
        SELECT taxon_id
        FROM ${REGION_TAG}_min${MIN_OBS}_all_taxa
    );

COMMIT;
"

print_progress "Regional base tables created"
