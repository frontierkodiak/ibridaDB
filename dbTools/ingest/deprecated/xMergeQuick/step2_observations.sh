#!/bin/bash

# step2_observations.sh
# This script updates the observations table with the geom column

# Accept NUM_PROCESSES from the command line
NUM_PROCESSES=$1

# Define base directory for the scripts
BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/xMerge"

# Function to run the update in parallel
run_update() {
  local OFFSET=$1
  local LIMIT=$2
  docker exec ibrida psql -U postgres -c "
  UPDATE int_observations_partial
  SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::public.geometry
  WHERE observation_uuid IN (
    SELECT observation_uuid
    FROM int_observations_partial
    ORDER BY observation_uuid
    OFFSET ${OFFSET}
    LIMIT ${LIMIT}
  );"
}

# Calculate total rows and batch size
TOTAL_ROWS=$(docker exec ibrida psql -U postgres -t -c "SELECT COUNT(*) FROM int_observations_partial;")
BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES))

# Run updates in parallel
for ((i=0; i<NUM_PROCESSES; i++)); do
  OFFSET=$((i * BATCH_SIZE))
  run_update ${OFFSET} ${BATCH_SIZE} &
done

# Wait for all processes to finish
wait
echo "All updates completed."
