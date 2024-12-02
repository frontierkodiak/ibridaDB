#!/bin/bash

# Function to run the update in parallel
run_update() {
  local TABLE_NAME=$1
  local COLUMN_NAME=$2
  local VALUE=$3
  local OFFSET=$4
  local LIMIT=$5
  local DB_NAME=$6
  local DB_CONTAINER=$7

  docker exec ${DB_CONTAINER} psql -U postgres -d "${DB_NAME}" -c "
  UPDATE ${TABLE_NAME}
  SET ${COLUMN_NAME} = '${VALUE}'
  WHERE ctid IN (
    SELECT ctid
    FROM ${TABLE_NAME}
    ORDER BY ctid
    OFFSET ${OFFSET}
    LIMIT ${LIMIT}
  );"
}

# Check if correct number of arguments are provided
if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <database_name> <num_workers> <origin_value> <version_value>"
  exit 1
fi

# Define arguments
DB_NAME=$1
NUM_PROCESSES=$2
ORIGIN_VALUE=$3
VERSION_VALUE=$4

# Use container name from environment or default
DB_CONTAINER=${DB_CONTAINER:-"ibridaDB"}

# Tables and their columns to update
declare -A TABLES_COLUMNS
TABLES_COLUMNS=(
  ["taxa"]="origin,version"
  ["observers"]="origin,version"
  ["observations"]="origin,version"
  ["photos"]="origin,version"
)

# Function to update columns in parallel
update_columns_in_parallel() {
  local TABLE_NAME=$1
  local COLUMN_NAME=$2
  local VALUE=$3
  local TOTAL_ROWS
  TOTAL_ROWS=$(docker exec ${DB_CONTAINER} psql -U postgres -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ${TABLE_NAME};")
  local BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES))

  for ((i=0; i<NUM_PROCESSES; i++)); do
    local OFFSET=$((i * BATCH_SIZE))
    run_update ${TABLE_NAME} ${COLUMN_NAME} ${VALUE} ${OFFSET} ${BATCH_SIZE} ${DB_NAME} ${DB_CONTAINER} &
  done
}

# Update columns in parallel
for TABLE_NAME in "${!TABLES_COLUMNS[@]}"; do
  IFS=',' read -ra COLUMNS <<< "${TABLES_COLUMNS[$TABLE_NAME]}"
  for COLUMN in "${COLUMNS[@]}"; do
    if [ "$COLUMN" == "origin" ]; then
      update_columns_in_parallel "$TABLE_NAME" "$COLUMN" "$ORIGIN_VALUE"
    elif [ "$COLUMN" == "version" ]; then
      update_columns_in_parallel "$TABLE_NAME" "$COLUMN" "$VERSION_VALUE"
    fi
  done
done

# Wait for all processes to finish
wait
echo "All updates completed."