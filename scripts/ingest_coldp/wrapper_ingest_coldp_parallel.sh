#!/bin/bash

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default settings
ENABLE_FUZZY_MATCH=${ENABLE_FUZZY_MATCH:-true}
FUZZY_THRESHOLD=${FUZZY_THRESHOLD:-90}
NUM_PROCESSES=${NUM_PROCESSES:-12}  # Use 12 processes by default
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="${SCRIPT_DIR}/wrapper_ingest_coldp_parallel_${TIMESTAMP}.log"
PYTHON_EXECUTABLE=${PYTHON_EXECUTABLE:-"${SCRIPT_DIR}/../../.venv/bin/python"}
COLDP_DIR=${COLDP_DIR:-"/datasets/taxa/catalogue_of_life/2024/ColDP"}

# Database config
DB_USER=${DB_USER:-"postgres"}
DB_PASSWORD=${DB_PASSWORD:-"ooglyboogly69"}
DB_HOST=${DB_HOST:-"localhost"}
DB_PORT=${DB_PORT:-"5432"}
DB_NAME=${DB_NAME:-"ibrida-v0-r1"}

# Step flags
DO_LOAD_TABLES=${DO_LOAD_TABLES:-true}
DO_MAP_TAXA=${DO_MAP_TAXA:-true}
DO_POPULATE_COMMON_NAMES=${DO_POPULATE_COMMON_NAMES:-true}

# Create a function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Start the log file
echo "Starting ColDP Ingestion Parallel Wrapper at $(date)" | tee "$LOG_FILE"
echo "--------------------------------------------------" | tee -a "$LOG_FILE"
echo "Configuration:" | tee -a "$LOG_FILE"
echo "  DB User: $DB_USER" | tee -a "$LOG_FILE"
echo "  DB Host: $DB_HOST" | tee -a "$LOG_FILE"
echo "  DB Port: $DB_PORT" | tee -a "$LOG_FILE"
echo "  DB Name: $DB_NAME" | tee -a "$LOG_FILE"
echo "  ColDP Data Dir: $COLDP_DIR" | tee -a "$LOG_FILE"
echo "  Python Executable: $PYTHON_EXECUTABLE" | tee -a "$LOG_FILE"
echo "  Enable Fuzzy Match: $ENABLE_FUZZY_MATCH" | tee -a "$LOG_FILE"
echo "  Fuzzy Threshold: $FUZZY_THRESHOLD" | tee -a "$LOG_FILE"
echo "  Number of Processes: $NUM_PROCESSES" | tee -a "$LOG_FILE"
echo "  Log File: $LOG_FILE" | tee -a "$LOG_FILE"
echo "--------------------------------------------------" | tee -a "$LOG_FILE"
echo "Steps Configuration:" | tee -a "$LOG_FILE"
echo "  Load Tables: $DO_LOAD_TABLES" | tee -a "$LOG_FILE"
echo "  Map Taxa: $DO_MAP_TAXA" | tee -a "$LOG_FILE"
echo "  Populate Common Names: $DO_POPULATE_COMMON_NAMES" | tee -a "$LOG_FILE"
echo "--------------------------------------------------" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Clean up the ColDP tables before loading (but NOT expanded_taxa)
if [[ "$DO_LOAD_TABLES" == "true" ]]; then
    log "Dropping ColDP tables to ensure correct schema..."
    
    # Use Docker to run psql commands since we're running the database in a container
    docker exec ibridaDB psql -U "$DB_USER" -d "$DB_NAME" -c "
    -- Drop all ColDP tables (but NOT expanded_taxa) so they can be recreated with the correct schema
    DROP TABLE IF EXISTS coldp_vernacular_name, coldp_distribution, coldp_media, 
                          coldp_reference, coldp_type_material, coldp_name_usage_staging CASCADE;
    " 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log "Failed to drop ColDP tables"
        exit 1
    else
        log "Successfully dropped ColDP tables - they will be recreated with the correct schema"
    fi
fi

# Step 1: Load ColDP tables
if [[ "$DO_LOAD_TABLES" == "true" ]]; then
    log ">>> Running load_tables.py..."
    
    # Run the loading script
    "$PYTHON_EXECUTABLE" "${SCRIPT_DIR}/load_tables.py" \
        --coldp-dir="$COLDP_DIR" \
        --db-user="$DB_USER" \
        --db-password="$DB_PASSWORD" \
        --db-host="$DB_HOST" \
        --db-port="$DB_PORT" \
        --db-name="$DB_NAME" \
        2>&1 | tee -a "$LOG_FILE"
    
    SCRIPT_EXIT_CODE=${PIPESTATUS[0]}
    if [ $SCRIPT_EXIT_CODE -eq 0 ]; then
        log ">>> Finished load_tables.py successfully."
    else
        log ">>> load_tables.py failed with exit code $SCRIPT_EXIT_CODE."
        exit 1
    fi
fi

# Step 2: Map taxa (with parallelization)
if [[ "$DO_MAP_TAXA" == "true" ]]; then
    log ">>> Running map_taxa_parallel.py..."
    
    FUZZY_ARGS=""
    if [[ "$ENABLE_FUZZY_MATCH" == "true" ]]; then
        FUZZY_ARGS="--fuzzy-match --fuzzy-threshold=$FUZZY_THRESHOLD"
    fi
    
    # Run the parallel mapping script
    "$PYTHON_EXECUTABLE" "${SCRIPT_DIR}/map_taxa_parallel.py" \
        --db-user="$DB_USER" \
        --db-password="$DB_PASSWORD" \
        --db-host="$DB_HOST" \
        --db-port="$DB_PORT" \
        --db-name="$DB_NAME" \
        --processes="$NUM_PROCESSES" \
        $FUZZY_ARGS \
        2>&1 | tee -a "$LOG_FILE"
    
    SCRIPT_EXIT_CODE=${PIPESTATUS[0]}
    if [ $SCRIPT_EXIT_CODE -eq 0 ]; then
        log ">>> Finished map_taxa_parallel.py successfully."
    else
        log ">>> map_taxa_parallel.py failed with exit code $SCRIPT_EXIT_CODE."
        exit 1
    fi
fi

# Step 3: Populate common names
if [[ "$DO_POPULATE_COMMON_NAMES" == "true" ]]; then
    log ">>> Running populate_common_names.py..."
    
    # Run the common names population script
    "$PYTHON_EXECUTABLE" "${SCRIPT_DIR}/populate_common_names.py" \
        --db-user="$DB_USER" \
        --db-password="$DB_PASSWORD" \
        --db-host="$DB_HOST" \
        --db-port="$DB_PORT" \
        --db-name="$DB_NAME" \
        --clear-first \
        2>&1 | tee -a "$LOG_FILE"
    
    SCRIPT_EXIT_CODE=${PIPESTATUS[0]}
    if [ $SCRIPT_EXIT_CODE -eq 0 ]; then
        log ">>> Finished populate_common_names.py successfully."
    else
        log ">>> populate_common_names.py failed with exit code $SCRIPT_EXIT_CODE."
        exit 1
    fi
fi

log "All steps completed successfully!"
echo "=========================================================================================" | tee -a "$LOG_FILE"
log "ColDP integration process completed. Log file: $LOG_FILE"