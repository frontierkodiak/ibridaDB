#!bin/bash

## dbTools/ingest/v0/common/functions.sh

# Common functions used across ingest scripts (mostly mirrored from export functions.sh)

# Function to execute SQL commands
execute_sql() {
    local sql="$1"
    docker exec ${DB_CONTAINER} psql -U ${DB_USER} -d "${DB_NAME}" -c "$sql"
}

# Function to print progress
print_progress() {
    echo "======================================"
    echo "$1"
    echo "======================================"
}

# Function to ensure directory exists with proper permissions
ensure_directory() {
    local dir="$1"
    mkdir -p "${dir}"
    chmod -R 777 "${dir}"
}

# Function to send ntfy notification
send_notification() {
    local message="$1"
    # Attempt curl with:
    # - max time of 5 seconds (-m 5)
    # - silent mode (-s)
    # - show errors but don't include in output (-S)
    # Redirect stderr to /dev/null to suppress error messages
    curl -m 5 -sS -d "$message" polliserve:8089/ibridaDB 2>/dev/null || true
}

# Export the functions
export -f execute_sql
export -f print_progress
export -f ensure_directory
export -f send_notification