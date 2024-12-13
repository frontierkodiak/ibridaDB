#!/bin/bash

# Setup logging
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/vers_origin_$(date +%Y%m%d_%H%M%S).log"
echo "Starting version/origin/release updates at $(date)" > "${LOG_FILE}"

# Function to log messages to both console and file
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Function for error logging and exit
error_exit() {
    log_message "ERROR: $1"
    exit 1
}

# Function to run the update in parallel
run_update() {
    local TABLE_NAME=$1
    local COLUMN_NAME=$2
    local VALUE=$3
    local OFFSET=$4
    local LIMIT=$5
    local DB_NAME=$6
    local DB_CONTAINER=$7
    local PROCESS_NUM=$8

    log_message "Process $PROCESS_NUM: Updating $TABLE_NAME.$COLUMN_NAME (offset: $OFFSET, limit: $LIMIT)"
    
    UPDATE_RESULT=$(docker exec ${DB_CONTAINER} psql -U postgres -d "${DB_NAME}" -t -c "
    UPDATE ${TABLE_NAME}
    SET ${COLUMN_NAME} = '${VALUE}'
    WHERE ctid IN (
        SELECT ctid
        FROM ${TABLE_NAME}
        ORDER BY ctid
        OFFSET ${OFFSET}
        LIMIT ${LIMIT}
    );")
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to update ${TABLE_NAME}.${COLUMN_NAME} in process $PROCESS_NUM"
    fi
    
    log_message "Process $PROCESS_NUM: Completed update of $TABLE_NAME.$COLUMN_NAME"
}

# Validate arguments
if [ "$#" -ne 5 ]; then
    error_exit "Usage: $0 <database_name> <num_workers> <origin_value> <version_value> <release_value>"
fi

# Define arguments
DB_NAME=$1
NUM_PROCESSES=$2
ORIGIN_VALUE=$3
VERSION_VALUE=$4
RELEASE_VALUE=$5

# Validate NUM_PROCESSES is a positive integer
if ! [[ "$NUM_PROCESSES" =~ ^[1-9][0-9]*$ ]]; then
    error_exit "Number of workers must be a positive integer"
fi

# Use container name from environment or default
DB_CONTAINER=${DB_CONTAINER:-"ibridaDB"}

# Verify database exists
if ! docker exec ${DB_CONTAINER} psql -U postgres -lqt | cut -d \| -f 1 | grep -qw "${DB_NAME}"; then
    error_exit "Database ${DB_NAME} does not exist"
fi

# Tables and their columns to update
declare -A TABLES_COLUMNS
TABLES_COLUMNS=(
    ["taxa"]="origin,version,release"
    ["observers"]="origin,version,release"
    ["observations"]="origin,version,release"
    ["photos"]="origin,version,release"
)

# Function to update columns in parallel
update_columns_in_parallel() {
    local TABLE_NAME=$1
    local COLUMN_NAME=$2
    local VALUE=$3
    local TOTAL_ROWS

    # Verify table exists
    if ! docker exec ${DB_CONTAINER} psql -U postgres -d "${DB_NAME}" -c "\d ${TABLE_NAME}" &>/dev/null; then
        error_exit "Table ${TABLE_NAME} does not exist in database ${DB_NAME}"
    }

    # Get total rows with error handling
    TOTAL_ROWS=$(docker exec ${DB_CONTAINER} psql -U postgres -d "${DB_NAME}" -t -c "SELECT COUNT(*) FROM ${TABLE_NAME};" | tr -d ' ')
    if [ $? -ne 0 ] || ! [[ "$TOTAL_ROWS" =~ ^[0-9]+$ ]]; then
        error_exit "Failed to get row count for ${TABLE_NAME}"
    }

    log_message "Starting parallel update of ${TABLE_NAME}.${COLUMN_NAME} (${TOTAL_ROWS} total rows)"
    
    local BATCH_SIZE=$((TOTAL_ROWS / NUM_PROCESSES + 1))
    local PIDS=()

    for ((i=0; i<NUM_PROCESSES; i++)); do
        local OFFSET=$((i * BATCH_SIZE))
        run_update ${TABLE_NAME} ${COLUMN_NAME} ${VALUE} ${OFFSET} ${BATCH_SIZE} ${DB_NAME} ${DB_CONTAINER} $i &
        PIDS+=($!)
    done

    # Wait for all processes and check their exit status
    for pid in "${PIDS[@]}"; do
        if ! wait $pid; then
            error_exit "One of the parallel update processes failed"
        fi
    done
    
    log_message "Completed update of ${TABLE_NAME}.${COLUMN_NAME}"
}

# Main update process
log_message "Starting updates with parameters:"
log_message "Database: ${DB_NAME}"
log_message "Number of processes: ${NUM_PROCESSES}"
log_message "Origin value: ${ORIGIN_VALUE}"
log_message "Version value: ${VERSION_VALUE}"
log_message "Release value: ${RELEASE_VALUE}"

for TABLE_NAME in "${!TABLES_COLUMNS[@]}"; do
    log_message "Processing table: ${TABLE_NAME}"
    IFS=',' read -ra COLUMNS <<< "${TABLES_COLUMNS[$TABLE_NAME]}"
    for COLUMN in "${COLUMNS[@]}"; do
        case "$COLUMN" in
            "origin")
                update_columns_in_parallel "$TABLE_NAME" "$COLUMN" "$ORIGIN_VALUE"
                ;;
            "version")
                update_columns_in_parallel "$TABLE_NAME" "$COLUMN" "$VERSION_VALUE"
                ;;
            "release")
                update_columns_in_parallel "$TABLE_NAME" "$COLUMN" "$RELEASE_VALUE"
                ;;
        esac
    done
done

log_message "All updates completed successfully"