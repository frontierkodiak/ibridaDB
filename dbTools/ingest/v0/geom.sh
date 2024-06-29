#!/bin/bash

# Function to run the update in parallel
run_update() {
  local OFFSET=$1
  local LIMIT=$2
  local DB_NAME=$3
  local TABLE_NAME=$4

  docker exec ibrida psql -U postgres -d "${DB_NAME}" -c "
  UPDATE ${TABLE_NAME}
  SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::public.geometry
  WHERE observation_uuid IN (
    SELECT observation_uuid
    FROM ${TABLE_NAME}
    ORDER BY observation_uuid
    OFFSET ${OFFSET}
    LIMIT ${LIMIT}
  );"
}

# Check if correct number of arguments are provided
if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <database_name> <table_name> <num_workers> <base_dir>"
  exit 1
fi

# Define arguments
DB_NAME=$1
TABLE_NAME=$2
NUM_PROCESSES=$3
BASE_DIR=$4

# Calculate total rows and batch size
TOTAL_ROWS=$(docker exec ibrida psql -U postgres -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ${TABLE_NAME};")
BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES))

# Run updates in parallel
for ((i=0; i<NUM_PROCESSES; i++)); do
  OFFSET=$((i * BATCH_SIZE))
  run_update ${OFFSET} ${BATCH_SIZE} ${DB_NAME} ${TABLE_NAME} &
done

# Wait for all processes to finish
wait
echo "All updates completed."
