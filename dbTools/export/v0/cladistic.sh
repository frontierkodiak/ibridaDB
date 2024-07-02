#!/bin/bash
## dbTools/export/v0/cladistic.sh

# Use the variables passed from the wrapper script
DB_USER="${DB_USER}"
DB_NAME="${DB_NAME}"
REGION_TAG="${REGION_TAG}"
MIN_OBS="${MIN_OBS}"
MAX_RN="${MAX_RN}"
PRIMARY_ONLY="${PRIMARY_ONLY}"
EXPORT_SUBDIR="${EXPORT_SUBDIR}"
DB_CONTAINER="${DB_CONTAINER}"
HOST_EXPORT_BASE_PATH="${HOST_EXPORT_BASE_PATH}"
CONTAINER_EXPORT_BASE_PATH="${CONTAINER_EXPORT_BASE_PATH}"
ORIGIN_VALUE="${ORIGIN_VALUE}"
VERSION_VALUE="${VERSION_VALUE}"

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
  docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$sql"
}

# Function to print progress
print_progress() {
  local message="$1"
  echo "======================================"
  echo "$message"
  echo "======================================"
}

# Ensure export directory exists and is writable
HOST_EXPORT_DIR="${HOST_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"
CONTAINER_EXPORT_DIR="${CONTAINER_EXPORT_BASE_PATH}/${EXPORT_SUBDIR}"

if [ ! -d "$HOST_EXPORT_DIR" ]; then
  mkdir -p "$HOST_EXPORT_DIR"
fi

if [ ! -w "$HOST_EXPORT_DIR" ]; then
  echo "Error: Directory $HOST_EXPORT_DIR is not writable."
  exit 1
fi

# Function to process a clade
process_clade() {
  local clade=$1
  local ancestry_filter=${CLADES[$clade]}
  local table_name="${REGION_TAG}_${clade}_min${MIN_OBS}all_cap${MAX_RN}"
  local photos_table_name="${table_name}_photos"
  local export_path="${CONTAINER_EXPORT_DIR}/${photos_table_name}.csv"

  if [ -z "$ancestry_filter" ]; then
    echo "Unknown clade: $clade"
    exit 1
  fi

  # Drop existing tables
  execute_sql "DROP TABLE IF EXISTS ${table_name};"
  execute_sql "DROP TABLE IF EXISTS ${photos_table_name};"

  # Create table for the clade
  ## NOTE: Origin temporarily removed from export tables.
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
  ## NOTE: Origin temporarily removed from export tables.
  print_progress "Creating table ${photos_table_name}"
  local photos_where_clause=""
  if [ "$PRIMARY_ONLY" = true ]; then
    photos_where_clause="AND t2.position = 0"
  fi
  execute_sql "
  CREATE TABLE ${photos_table_name} AS
  SELECT  
      t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
      t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
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

  # Export photos table to CSV
  ## NOTE: Origin temporarily removed from export tables.
  print_progress "Exporting table ${photos_table_name} to CSV"
  docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM ${photos_table_name}) TO '${export_path}' DELIMITER ',' CSV HEADER;"
}

# Function to process the "other" clade
process_other_clade() {
  local clade="other"
  local table_name="${REGION_TAG}_${clade}_min${MIN_OBS}all_cap${MAX_RN}"
  local photos_table_name="${table_name}_photos"
  local export_path="${CONTAINER_EXPORT_DIR}/${photos_table_name}.csv"

  # Construct the exclusion filter for predefined clades
  local exclusion_filters=""
  for ancestry_filter in "${CLADES[@]}"; do
    exclusion_filters+="AND ancestry NOT LIKE '${ancestry_filter}' "
  done

  # Drop existing tables
  execute_sql "DROP TABLE IF EXISTS ${table_name};"
  execute_sql "DROP TABLE IF EXISTS ${photos_table_name};"

  # Create table for the "other" clade
  ## NOTE: Origin temporarily removed from export tables.
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
              WHERE 1=1 ${exclusion_filters}
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

  # Create photos table for the "other" clade
  ## NOTE: Origin temporarily removed from export tables.
  print_progress "Creating table ${photos_table_name}"
  local photos_where_clause=""
  if [ "$PRIMARY_ONLY" = true ]; then
    photos_where_clause="AND t2.position = 0"
  fi
  execute_sql "
  CREATE TABLE ${photos_table_name} AS
  SELECT  
      t1.observation_uuid, t1.latitude, t1.longitude, t1.positional_accuracy, t1.taxon_id,  
      t1.observed_on, t2.photo_uuid, t2.photo_id, t2.extension, t2.width, t2.height, t2.position
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

  # Export photos table to CSV
  ## NOTE: Origin temporarily removed from export tables.
  print_progress "Exporting table ${photos_table_name} to CSV"
  docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "\copy (SELECT observation_uuid, latitude, longitude, positional_accuracy, taxon_id, observed_on, photo_uuid, photo_id, extension, width, height, position, ancestry, rank_level, rank, name FROM ${photos_table_name}) TO '${export_path}' DELIMITER ',' CSV HEADER;"
}

# Process each clade
for clade in "${!CLADES[@]}"; do
  process_clade "$clade"
done

# Process the "other" clade
process_other_clade

# Create the export summary file
summary_file="${HOST_EXPORT_DIR}/export_summary.txt"

{
  echo "Export Summary"
  echo "=============="
  echo "DB_USER: ${DB_USER}"
  echo "DB_NAME: ${DB_NAME}"
  echo "REGION_TAG: ${REGION_TAG}"
  echo "MIN_OBS: ${MIN_OBS}"
  echo "MAX_RN: ${MAX_RN}"
  echo "PRIMARY_ONLY: ${PRIMARY_ONLY}"
  echo "EXPORT_SUBDIR: ${EXPORT_SUBDIR}"
  echo "DB_CONTAINER: ${DB_CONTAINER}"
  echo "HOST_EXPORT_BASE_PATH: ${HOST_EXPORT_BASE_PATH}"
  echo "CONTAINER_EXPORT_BASE_PATH: ${CONTAINER_EXPORT_BASE_PATH}"
  echo "ORIGIN_VALUE: ${ORIGIN_VALUE}"
  echo "VERSION_VALUE: ${VERSION_VALUE}"
  echo ""
  echo "Table Row Counts:"
  for clade in "${!CLADES[@]}"; do
    table_name="${REGION_TAG}_${clade}_min${MIN_OBS}all_cap${MAX_RN}"
    row_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM ${table_name};" | tr -d '[:space:]')
    echo "${table_name}: ${row_count} rows"
  done
  table_name="${REGION_TAG}_other_min${MIN_OBS}all_cap${MAX_RN}"
  row_count=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM ${table_name};" | tr -d '[:space:]')
  echo "${table_name}: ${row_count} rows"
  echo ""
  echo "Column Names:"
  for clade in "${!CLADES[@]}"; do
    table_name="${REGION_TAG}_${clade}_min${MIN_OBS}all_cap${MAX_RN}_photos"
    columns=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = '${table_name}';" | tr -d '[:space:]' | paste -sd, -)
    echo "${table_name}: ${columns}"
  done
  table_name="${REGION_TAG}_other_min${MIN_OBS}all_cap${MAX_RN}_photos"
  columns=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = '${table_name}';" | tr -d '[:space:]' | paste -sd, -)
  echo "${table_name}: ${columns}"
} > "$summary_file"

print_progress "Export summary written to ${summary_file}"

print_progress "All clades processed and exported"
