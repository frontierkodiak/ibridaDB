#!/bin/bash

# Define number of parallel processes
NUM_PROCESSES=4

# Function to run the update in parallel
run_update() {
  local OFFSET=$1
  local LIMIT=$2
  docker exec -ti ibrida psql -U postgres -c "
  UPDATE temp_observations
  SET origin = 'iNat-May2024',
      geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
  WHERE observation_uuid IN (
    SELECT observation_uuid
    FROM temp_observations
    ORDER BY observation_uuid
    OFFSET ${OFFSET}
    LIMIT ${LIMIT}
  );"
}

# Calculate total rows and batch size
TOTAL_ROWS=$(docker exec -ti ibrida psql -U postgres -t -c "SELECT COUNT(*) FROM temp_observations;")
BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES))

# Run updates in parallel
for ((i=0; i<NUM_PROCESSES; i++)); do
  OFFSET=$((i * BATCH_SIZE))
  run_update ${OFFSET} ${BATCH_SIZE} &
done

# Wait for all processes to finish
wait
echo "All updates completed."
