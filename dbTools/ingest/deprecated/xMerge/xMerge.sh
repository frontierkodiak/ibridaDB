#!/bin/bash

# Define the source and origins variables
SOURCE="May2024"
ORIGINS="iNat-May2024"

# Define base directory for the scripts
BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/xMerge"

# Export the variables so they are accessible to the docker exec commands
export SOURCE
export ORIGINS

# Create temporary SQL scripts with substituted variables
echo "Creating step1 SQL temp scripts..."
sed "s/:source/$SOURCE/g; s/:origins/$ORIGINS/g" $BASE_DIR/step1_observations.sql > $BASE_DIR/step1_observations_tmp.sql
sed "s/:source/$SOURCE/g; s/:origins/$ORIGINS/g" $BASE_DIR/step1_photos.sql > $BASE_DIR/step1_photos_tmp.sql
sed "s/:source/$SOURCE/g; s/:origins/$ORIGINS/g" $BASE_DIR/step1_observers.sql > $BASE_DIR/step1_observers_tmp.sql

# Run the initial SQL scripts in parallel with variable substitution
echo "Running step1 SQL scripts..."
docker exec ibrida psql -U postgres -f /tool/ingest/xMerge/step1_observations_tmp.sql &
docker exec ibrida psql -U postgres -f /tool/ingest/xMerge/step1_photos_tmp.sql &
docker exec ibrida psql -U postgres -f /tool/ingest/xMerge/step1_observers_tmp.sql &
wait
echo "Completed all step1 SQL scripts."

# Check if the tables were created successfully
docker exec ibrida psql -U postgres -c "\d int_observations"
docker exec ibrida psql -U postgres -c "\d int_photos"
docker exec ibrida psql -U postgres -c "\d int_observers"

# Clean up temporary SQL scripts
rm $BASE_DIR/step1_observations_tmp.sql
rm $BASE_DIR/step1_photos_tmp.sql
rm $BASE_DIR/step1_observers_tmp.sql

# Run the parallel update script
echo "Calculating geometry..."
$BASE_DIR/step2_observations.sh
echo "Geometry calculation completed."

# Create temporary SQL scripts with substituted variables for step 3
sed "s/:origins/$ORIGINS/g" $BASE_DIR/step3_observations.sql > $BASE_DIR/step3_observations_tmp.sql
sed "s/:origins/$ORIGINS/g" $BASE_DIR/step3_photos.sql > $BASE_DIR/step3_photos_tmp.sql
sed "s/:origins/$ORIGINS/g" $BASE_DIR/step3_observers.sql > $BASE_DIR/step3_observers_tmp.sql
echo "Created step3 SQL temp scripts..."

# Run the final SQL scripts in parallel with variable substitution
echo "Running final SQL scripts..."
docker exec ibrida psql -U postgres -f /tool/ingest/xMerge/step3_observations_tmp.sql &
docker exec ibrida psql -U postgres -f /tool/ingest/xMerge/step3_photos_tmp.sql &
docker exec ibrida psql -U postgres -f /tool/ingest/xMerge/step3_observers_tmp.sql &
wait
echo "Final SQL scripts completed."

# Clean up temporary SQL scripts
rm $BASE_DIR/step3_observations_tmp.sql
rm $BASE_DIR/step3_photos_tmp.sql
rm $BASE_DIR/step3_observers_tmp.sql
echo "Cleaned up temporary SQL scripts."

echo "All steps completed."
