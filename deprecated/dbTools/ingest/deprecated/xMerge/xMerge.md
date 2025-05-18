Sure, here's a concise documentation for the operation and arguments of the `xMerge` process:

### xMerge Documentation

#### Overview
The `xMerge` process is designed to efficiently merge new datasets into the master database by parallelizing the execution of SQL scripts. The process is divided into three main steps: initial setup, parallel geometry calculation, and final merge. Each step involves specific SQL scripts and a Bash script for handling parallel tasks.

#### Directory Structure
```
.
├── ingest
│   ├── init.md
│   ├── merge.md
│   ├── merge.sql
│   ├── xMerge
│   │   ├── step1_observations.sql
│   │   ├── step1_observers.sql
│   │   ├── step1_photos.sql
│   │   ├── step2_observations.sh
│   │   ├── step3_observations.sql
│   │   ├── step3_observers.sql
│   │   ├── step3_photos.sql
│   │   └── xMerge.sh
```

#### Steps and Scripts

**Step 1: Initial Setup**
- **`step1_observations.sql`**: Sets up the `int_observations` table and copies data from the specified source. Updates the `origin` column with the provided value.
- **`step1_photos.sql`**: Sets up the `int_photos` table and copies data from the specified source. Updates the `origin` column with the provided value.
- **`step1_observers.sql`**: Sets up the `int_observers` table and copies data from the specified source. Updates the `origin` column with the provided value.

**Step 2: Parallel Geometry Calculation**
- **`step2_observations.sh`**: Calculates the `geom` column for the `int_observations` table in parallel by splitting the task into multiple processes.

**Step 3: Final Merge**
- **`step3_observations.sql`**: Merges the `int_observations` table into the `observations` table.
- **`step3_photos.sql`**: Merges the `int_photos` table into the `photos` table.
- **`step3_observers.sql`**: Merges the `int_observers` table into the `observers` table.

**Wrapper Script**
- **`xMerge.sh`**: Coordinates the execution of the above scripts, ensuring each step is performed in the correct order and parallelized where appropriate.

#### Arguments
The main arguments required for the `xMerge` process are:
- **`SOURCE`**: The folder in the `metadata` directory that contains the `observations.csv`, `photos.csv`, and `observers.csv` files.
- **`ORIGINS`**: A value to be set in the `origin` column of the intermediate tables, indicating the source dataset.

#### Usage

1. **Set the Arguments**: Define the `SOURCE` and `ORIGINS` variables in the `xMerge.sh` script.
2. **Execute the Wrapper Script**: Run the `xMerge.sh` script from the host to start the merge process.

Example:
```bash
#!/bin/bash

# Define the source and origins variables
SOURCE="May2024"
ORIGINS="iNat-May2024"

# Export the variables so they are accessible to the docker exec commands
export SOURCE
export ORIGINS

# Run the initial SQL scripts in parallel with variable substitution
docker exec -e SOURCE="$SOURCE" -e ORIGINS="$ORIGINS" -ti ibrida psql -U postgres -v source="'$SOURCE'" -v origins="'$ORIGINS'" -f /tool/ingest/xMerge/step1_observations.sql &
docker exec -e SOURCE="$SOURCE" -e ORIGINS="$ORIGINS" -ti ibrida psql -U postgres -v source="'$SOURCE'" -v origins="'$ORIGINS'" -f /tool/ingest/xMerge/step1_photos.sql &
docker exec -e SOURCE="$SOURCE" -e ORIGINS="$ORIGINS" -ti ibrida psql -U postgres -v source="'$SOURCE'" -v origins="'$ORIGINS'" -f /tool/ingest/xMerge/step1_observers.sql &
wait

# Run the parallel update script
./tool/ingest/xMerge/step2_observations.sh

# Run the final SQL scripts in parallel with variable substitution
docker exec -e SOURCE="$SOURCE" -e ORIGINS="$ORIGINS" -ti ibrida psql -U postgres -v origins="'$ORIGINS'" -f /tool/ingest/xMerge/step3_observations.sql &
docker exec -e SOURCE="$SOURCE" -e ORIGINS="$ORIGINS" -ti ibrida psql -U postgres -v origins="'$ORIGINS'" -f /tool/ingest/xMerge/step3_photos.sql &
docker exec -e SOURCE="$SOURCE" -e ORIGINS="$ORIGINS" -ti ibrida psql -U postgres -v origins="'$ORIGINS'" -f /tool/ingest/xMerge/step3_observers.sql &
wait

echo "All steps completed."
```

This documentation should help you and others understand and execute the `xMerge` process efficiently.