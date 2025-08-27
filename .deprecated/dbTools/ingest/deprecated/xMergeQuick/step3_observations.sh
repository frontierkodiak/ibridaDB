#!/bin/bash

# step3_observations.sh
# This script inserts the observations table in parallel

NUM_PROCESSES=$1
BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/xMergeQuick"

run_insert_observations() {
  local OFFSET=$1
  local LIMIT=$2
  docker exec ibrida psql -U postgres -c "
  INSERT INTO observations
  SELECT observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on, origin, geom
  FROM int_observations_partial
  ORDER BY observation_uuid
  OFFSET ${OFFSET}
  LIMIT ${LIMIT}
  ON CONFLICT (observation_uuid) DO NOTHING;"
}

TOTAL_ROWS=$(docker exec ibrida psql -U postgres -t -c "SELECT COUNT(*) FROM int_observations_partial;")
BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES + 1))

for ((i=0; i<NUM_PROCESSES; i++)); do
  OFFSET=$((i * BATCH_SIZE))
  run_insert_observations ${OFFSET} ${BATCH_SIZE} &
done

wait
echo "Parallel observation insert operations completed."
