#!/bin/bash

## step1_pt2_photos.sh
## This script deletes photos that are not in the post-date-filter observations table

# Accept NUM_PROCESSES from the command line
NUM_PROCESSES=$1

# Define base directory for the scripts
BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/xMergeQuick"

# Function to run the delete operation in parallel
run_delete() {
  local OFFSET=$1
  local LIMIT=$2
  docker exec ibrida psql -U postgres -c "
  DELETE FROM int_photos_partial
  WHERE observation_uuid NOT IN (
    SELECT observation_uuid FROM int_observations_partial
  ) AND ctid IN (
    SELECT ctid FROM int_photos_partial
    ORDER BY ctid
    OFFSET ${OFFSET}
    LIMIT ${LIMIT}
  );"
}

# Calculate total rows and batch size
TOTAL_ROWS=$(docker exec ibrida psql -U postgres -t -c "SELECT COUNT(*) FROM int_photos_partial WHERE observation_uuid NOT IN (SELECT observation_uuid FROM int_observations_partial);")
BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES + 1))

# Run deletes in parallel
for ((i=0; i<NUM_PROCESSES; i++)); do
  OFFSET=$((i * BATCH_SIZE))
  run_delete ${OFFSET} ${BATCH_SIZE} &
done

# Wait for all processes to finish
wait
echo "Parallel delete operations completed."
