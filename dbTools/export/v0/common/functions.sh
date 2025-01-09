#!/bin/bash

# Common functions used across export scripts

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

get_obs_columns() {
    # Start with standard columns
    local cols="observation_uuid, observer_id, latitude, longitude, positional_accuracy, taxon_id, quality_grade, observed_on"
    
    # TEMPORARY HOTFIX: Commenting out version tracking columns until bulk update is complete
    # Add version tracking columns
    # cols="${cols}, origin, version, release"
    
    # Check if anomaly_score exists in this release
    if [[ "${RELEASE_VALUE}" == "r1" ]]; then
        cols="${cols}, anomaly_score"
    fi
    
    echo "$cols"
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
export -f get_obs_columns
export -f ensure_directory
export -f send_notification