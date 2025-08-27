#!/bin/bash

# step3_photos.sh
# This script inserts the photos table in parallel

NUM_PROCESSES=$1
BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/xMergeQuick"

run_insert_photos() {
  local OFFSET=$1
  local LIMIT=$2
  docker exec ibrida psql -U postgres -c "
  INSERT INTO photos
  SELECT photo_uuid, photo_id, observation_uuid, observer_id, extension, license, width, height, position, origin
  FROM int_photos_partial
  ORDER BY photo_uuid, photo_id, position, observation_uuid
  OFFSET ${OFFSET}
  LIMIT ${LIMIT}
  ON CONFLICT (photo_uuid, photo_id, position, observation_uuid) DO NOTHING;"
}

TOTAL_ROWS=$(docker exec ibrida psql -U postgres -t -c "SELECT COUNT(*) FROM int_photos_partial;")
BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES + 1))

for ((i=0; i<NUM_PROCESSES; i++)); do
  OFFSET=$((i * BATCH_SIZE))
  run_insert_photos ${OFFSET} ${BATCH_SIZE} &
done

wait
echo "Parallel photo insert operations completed."
