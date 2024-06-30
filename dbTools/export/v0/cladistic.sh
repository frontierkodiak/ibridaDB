#!/bin/bash

# Define variables
DB_USER="postgres"
DB_NAME="ibrida-${VERSION_VALUE}"
REGION_TAG="NAfull"
MIN_OBS=50
MAX_RN=4000
PRIMARY_ONLY=true  # Set this to true to select only primary photos (position == 0)
EXPORT_SUBDIR="iNat-June2024"  # Subdirectory for CSV exports

# Clades and their respective ancestry filters
declare -A CLADES
CLADES=( 
    ["arthropoda"]="48460/1/47120/%"
    ["aves"]="48460/1/2/355675/3/%"
    ["reptilia"]="48460/1/2/355675/26036/%"
    ["mammalia"]="48460/1/2/355675/40151%"
    ["amphibia"]="48460/1/2/355675/20978%"
    ["angiospermae"]="48460/47126/211194/47125/%"
)

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

# Function to process a clade
process_clade() {
  local clade=$1
  local ancestry_filter=${CLADES[$clade]}
  local table_name="${REGION_TAG}_${clade}_min${MIN_OBS}all_cap${MAX_RN}"
  local photos_table_name="${table_name}_photos"
  local export_path="/exports/${EXPORT_SUBDIR}/${photos_table_name}.csv"

  if [ -z "$ancestry_filter" ]; then
    echo "Unknown clade: $clade"
    exit 1
  fi

  # Drop existing tables
  execute_sql "DROP TABLE IF EXISTS ${table_name};"
  execute_sql "DROP TABLE IF EXISTS ${photos_table_name};"

  # Create table for the clade
  print_progress "Creating table ${table_name}"
  execute_sql "
  CREATE TABLE ${table_name} AS (
      SELECT  
          observation_uuid, 
          observer_id, 
          latitude, 
          longitude, 
          positional_accuracy, 
          taxon_id, 
          quality_grade,  
          observed_on,
          origin,
          ROW_NUMBER() OVER (
              PARTITION BY taxon_id 
              ORDER BY RANDOM()
          ) as rn
      FROM
          ${REGION_TAG}_min${MIN_OBS}all_taxa_obs
      WHERE
          taxon_id IN (
              SELECT taxon_id
              FROM taxa
              WHERE ancestry LIKE '${ancestry_filter}'
          )
          AND taxon_id IN (
              SELECT taxon_id
              FROM ${REGION_TAG}_min${MIN_OBS}all_taxa_obs
              GROUP BY taxon_id
              HAVING COUNT(*) >= ${MIN_OBS}
          )
  );
  DELETE FROM ${table_name} WHERE rn > ${MAX_RN};
  "

  # Create photos table for the clade
  print_progress "Creating table ${photos_table_name}"
  local photos_where_clause=""
  if [ "$PRIMARY_ONLY" = true ]; then
    photos_where_clause="AND t2.position = 0"
  fi
  execute_sql "
  CREATE TABLE ${photos_table_name} AS
  SELECT  
      t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
      t1.observed_on, t1.origin, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
  FROM
      ${table_name} t1
      JOIN photos t2
      ON t1.observation_uuid = t2.observation_uuid
  WHERE 1=1 ${photos_where_clause};
  ALTER TABLE ${photos_table_name} ADD COLUMN ancestry varchar(255);  
  ALTER TABLE ${photos_table_name} ADD COLUMN rank_level double precision;  
  ALTER TABLE ${photos_table_name} ADD COLUMN rank varchar(255);  
  ALTER TABLE ${photos_table_name} ADD COLUMN name varchar(255);  
  UPDATE ${photos_table_name} t1  
  SET ancestry = t2.ancestry  
  FROM taxa t2  
  WHERE t1.taxon_id = t2.taxon_id;  
  UPDATE ${photos_table_name} t1  
  SET rank_level = t2.rank_level  
  FROM taxa t2  
  WHERE t1.taxon_id = t2.taxon_id;  
  UPDATE ${photos_table_name} t1  
  SET rank = t2.rank  
  FROM taxa t2  
  WHERE t1.taxon_id = t2.taxon_id;  
  UPDATE ${photos_table_name} t1  
  SET name = t2.name  
  FROM taxa t2  
  WHERE t1.taxon_id = t2.taxon_id;
  VACUUM ANALYZE ${photos_table_name};
  "

  # Create export directory if it doesn't exist
  if [ ! -d "/exports/${EXPORT_SUBDIR}" ]; then
    mkdir -p "/exports/${EXPORT_SUBDIR}"
  fi

  # Export photos table to CSV
  print_progress "Exporting table ${photos_table_name} to CSV"
  docker exec ibrida psql -U "$DB_USER" -d "$DB_NAME" -c "\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, origin, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM ${photos_table_name}) TO '${export_path}' DELIMITER ',' CSV HEADER;"
}

# Process each clade
for clade in "${!CLADES[@]}"; do
  process_clade "$clade"
done

print_progress "All clades processed and exported"
