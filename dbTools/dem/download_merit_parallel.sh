#!/bin/bash
#
# download_merit_parallel.sh
#
# Downloads MERIT DEM files in parallel with controlled concurrency. 
# Retains retry logic for robustness.

# --- Configuration ---

# Credentials
USERNAME="hydrography"
PASSWORD="rivernetwork"

# Base URL for the dataset
BASE_URL="http://hydro.iis.u-tokyo.ac.jp/~yamadai/MERIT_Hydro/distribute/v1.0"

# Destination directory for downloaded files
DEST_DIR="/datasets/dem/merit"

# Main log file
LOG_FILE="${DEST_DIR}/download.log"

# Default number of parallel processes (override by passing an argument)
NUM_PARALLEL=4
if [ -n "$1" ]; then
  NUM_PARALLEL="$1"
fi

# Maximum number of retry attempts for each file
MAX_ATTEMPTS=3

# Seconds to wait between retries
RETRY_WAIT=180

# Seconds to wait between spawn of parallel tasks (to avoid hammering the server)
# You can set this to 0 if you prefer no delay at all.
SPAWN_DELAY=45


# --- Setup ---

# Create destination directory
mkdir -p "${DEST_DIR}"

# Initialize log file
echo "Starting MERIT DEM download at $(date)" > "${LOG_FILE}"
echo "Using concurrency level: ${NUM_PARALLEL}" | tee -a "${LOG_FILE}"

# Temporary file to track failures across parallel processes
FAIL_FILE=$(mktemp)
touch "$FAIL_FILE"


# --- Helper Functions ---

# Thread-safe logging function for general messages.
# In extreme concurrency, lines may still interleave. For robust locking,
# consider using 'flock'. We keep it simple here.
log_message() {
  local msg="$1"
  echo "$msg" | tee -a "$LOG_FILE"
}

# Download a single file with retry logic
# Usage: download_file "filename.tar"
download_file() {
    local filename="$1"
    local attempt

    for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
        log_message "Downloading ${filename} (attempt ${attempt}/${MAX_ATTEMPTS})..."
        
        if wget --quiet --user="${USERNAME}" \
                --password="${PASSWORD}" \
                --no-check-certificate \
                -P "${DEST_DIR}" \
                "${BASE_URL}/${filename}"; then
            log_message "Successfully downloaded ${filename}"
            return 0
        else
            log_message "Failed to download ${filename} on attempt ${attempt}"
            if [ $attempt -lt $MAX_ATTEMPTS ]; then
                log_message "Waiting ${RETRY_WAIT} seconds before retry..."
                sleep "${RETRY_WAIT}"
            fi
        fi
    done
    
    # If we reached here, all attempts failed
    echo "${filename}" >> "${FAIL_FILE}"
    log_message "Failed to download ${filename} after ${MAX_ATTEMPTS} attempts"
    return 1
}


# --- File List ---

# List of all valid files to download (excluding "no data" regions)
files=(
    # # N60-N90
    # "elv_n60w180.tar" "elv_n60w150.tar" "elv_n60w120.tar" "elv_n60w090.tar" "elv_n60w060.tar" "elv_n60w030.tar"
    # "elv_n60e000.tar" "elv_n60e030.tar" "elv_n60e060.tar" "elv_n60e090.tar" "elv_n60e120.tar" "elv_n60e150.tar"
    # # N30-N60
    # "elv_n30w180.tar" "elv_n30w150.tar" "elv_n30w120.tar" "elv_n30w090.tar" "elv_n30w060.tar" "elv_n30w030.tar"
    # "elv_n30e000.tar" "elv_n30e030.tar" "elv_n30e060.tar"
    "elv_n30e090.tar" "elv_n30e120.tar" "elv_n30e150.tar"
    # N00-N30
    "elv_n00w180.tar" "elv_n00w120.tar" "elv_n00w090.tar" "elv_n00w060.tar" "elv_n00w030.tar"
    "elv_n00e000.tar" "elv_n00e030.tar" "elv_n00e060.tar" "elv_n00e090.tar" "elv_n00e120.tar" "elv_n00e150.tar"
    # S30-N00
    "elv_s30w180.tar" "elv_s30w150.tar" "elv_s30w120.tar" "elv_s30w090.tar" "elv_s30w060.tar" "elv_s30w030.tar"
    "elv_s30e000.tar" "elv_s30e030.tar" "elv_s30e060.tar" "elv_s30e090.tar" "elv_s30e120.tar" "elv_s30e150.tar"
    # S60-S30
    "elv_s60w180.tar" "elv_s60w090.tar" "elv_s60w060.tar" "elv_s60w030.tar"
    "elv_s60e000.tar" "elv_s60e030.tar" "elv_s60e060.tar" "elv_s60e090.tar" "elv_s60e120.tar" "elv_s60e150.tar"
)

total_files=${#files[@]}
log_message "Total files to download: ${total_files}"

# --- Parallel Download Loop ---

pids=()
count=0

for file in "${files[@]}"; do
    # Start the download in a background subshell
    (
      download_file "${file}"
    ) &
    pids+=($!)
    
    # Throttle concurrency
    ((count++))
    if [ "$((count % NUM_PARALLEL))" -eq 0 ]; then
        # Wait for at least one job to finish before spawning new ones
        wait -n
    fi

    # Optional small delay to prevent saturating the remote server
    sleep "${SPAWN_DELAY}"
done

# Wait for all remaining jobs to finish
wait

# --- Summarize ---

# Gather any failed files from the temp failure file
mapfile -t failed_files < "$FAIL_FILE"
rm -f "$FAIL_FILE"

num_failed=${#failed_files[@]}
log_message ""
log_message "Download Summary:"
log_message "Total files attempted: ${total_files}"
log_message "Failed downloads: ${num_failed}"

if [ ${num_failed} -gt 0 ]; then
    log_message "Failed files:"
    for f in "${failed_files[@]}"; do
        log_message "  - $f"
    done
    log_message "Check the log file for more details: ${LOG_FILE}"
    exit 1
fi

log_message "All downloads completed successfully at $(date)"
exit 0
