#!/bin/bash

## xMergeQuick_resume.sh
## This script resumes an interrupted xMergeQuick operation

# Define the source, origins, and exclude_before variables
SOURCE="May2024"
ORIGINS="iNat-May2024"
EXCLUDE_BEFORE="2023-06-01" 

# Define base directory for the scripts
BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/xMergeQuick"

# Define number of parallel processes
NUM_PROCESSES=16

# Export the variables so they are accessible to the docker exec commands
export SOURCE
export ORIGINS
export EXCLUDE_BEFORE
export NUM_PROCESSES

# Check if NUM_PROCESSES is valid
if [ -z "$NUM_PROCESSES" ] || [ "$NUM_PROCESSES" -eq 0 ]; then
  echo "NUM_PROCESSES is not set or zero, setting to default value of 16."
  NUM_PROCESSES=16
fi

# Create temporary SQL scripts with substituted variables
echo "Creating step1 SQL temp scripts..."
# Only create temporary scripts for steps that are being run
# sed "s/:source/$SOURCE/g; s/:origins/$ORIGINS/g; s/:exclude_before/$EXCLUDE_BEFORE/g" $BASE_DIR/step1_observations.sql > $BASE_DIR/step1_observations_tmp.sql
sed "s/:source/$SOURCE/g" $BASE_DIR/step1_pt1_photos.sql > $BASE_DIR/step1_pt1_photos_tmp.sql
sed "s/:origins/$ORIGINS/g" $BASE_DIR/step1_pt3_photos.sql > $BASE_DIR/step1_pt3_photos_tmp.sql
# sed "s/:source/$SOURCE/g; s/:origins/$ORIGINS/g" $BASE_DIR/step1_observers.sql > $BASE_DIR/step1_observers_tmp.sql

# Run the initial SQL scripts in parallel with variable substitution
echo "Running step1 photos (pt1) SQL script..."
# Skip other step1 scripts as they have already been run
docker exec ibrida psql -U postgres -f /tool/ingest/xMergeQuick/step1_pt1_photos_tmp.sql
echo "Completed step1_pt1_photos SQL script."

# Run the parallel deletion script for photos
echo "Running step1_pt2_photos deletion in parallel..."
$BASE_DIR/step1_pt2_photos.sh $NUM_PROCESSES
echo "Completed step1_pt2_photos deletion."

# Run the photos pt3 SQL script
echo "Running step1_pt3_photos SQL script..."
docker exec ibrida psql -U postgres -f /tool/ingest/xMergeQuick/step1_pt3_photos_tmp.sql
echo "Completed step1_pt3_photos SQL script."

# Check if the tables were created successfully
echo "Checking if tables were created successfully..."
docker exec ibrida psql -U postgres -c "\d int_observations_partial"
docker exec ibrida psql -U postgres -c "\d int_photos_partial"
docker exec ibrida psql -U postgres -c "\d int_observers_partial"

# Clean up temporary SQL scripts
# rm $BASE_DIR/step1_observations_tmp.sql
rm $BASE_DIR/step1_pt1_photos_tmp.sql
rm $BASE_DIR/step1_pt3_photos_tmp.sql
# rm $BASE_DIR/step1_observers_tmp.sql
echo "Tables created successfully, continuing with step 2..."

# Run the parallel update script
echo "Calculating geometry..."
$BASE_DIR/step2_observations.sh $NUM_PROCESSES
echo "Geometry calculation completed."

# Run the parallel insert scripts for step 3
echo "Running parallel insert scripts for step 3..."
$BASE_DIR/step3_observations.sh $NUM_PROCESSES
$BASE_DIR/step3_photos.sh $NUM_PROCESSES
echo "Parallel inserts for step 3 completed."

# Run the final SQL script for observers
echo "Running final SQL script for observers..."
docker exec ibrida psql -U postgres -f /tool/ingest/xMergeQuick/step3_observers_tmp.sql
rm $BASE_DIR/step3_observers_tmp.sql
echo "Final SQL script for observers completed."
echo "Cleaned up step 3 observers temporary SQL script."

# Reindex all tables
echo "Reindexing all tables..."
docker exec ibrida psql -U postgres -c "REINDEX TABLE observations;" &
docker exec ibrida psql -U postgres -c "REINDEX TABLE photos;" &
docker exec ibrida psql -U postgres -c "REINDEX TABLE observers;" &
wait
echo "Reindexing completed."

echo "All steps completed."
