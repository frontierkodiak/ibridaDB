#!/bin/bash

# Configuration
USERNAME="hydrography"
PASSWORD="rivernetwork"
BASE_URL="http://hydro.iis.u-tokyo.ac.jp/~yamadai/MERIT_Hydro/distribute/v1.0"
DEST_DIR="/datasets/dem/merit"
LOG_FILE="${DEST_DIR}/download.log"

# Create destination directory
mkdir -p "${DEST_DIR}"

# Initialize log file
echo "Starting MERIT DEM download at $(date)" > "${LOG_FILE}"

# Function to download a single file with retry logic
download_file() {
    local filename="$1"
    local attempts=3
    local wait_time=30

    for ((i=1; i<=attempts; i++)); do
        echo "Downloading ${filename} (attempt ${i}/${attempts})..." | tee -a "${LOG_FILE}"
        
        if wget --quiet --user="${USERNAME}" \
                --password="${PASSWORD}" \
                --no-check-certificate \
                -P "${DEST_DIR}" \
                "${BASE_URL}/${filename}"; then
            echo "Successfully downloaded ${filename}" | tee -a "${LOG_FILE}"
            return 0
        else
            echo "Failed to download ${filename} on attempt ${i}" | tee -a "${LOG_FILE}"
            if [ $i -lt $attempts ]; then
                echo "Waiting ${wait_time} seconds before retry..." | tee -a "${LOG_FILE}"
                sleep ${wait_time}
            fi
        fi
    done
    
    echo "Failed to download ${filename} after ${attempts} attempts" | tee -a "${LOG_FILE}"
    return 1
}

# List of all valid files to download (excluding "no data" regions)
declare -a files=(
    # N60-N90
    "elv_n60w180.tar" "elv_n60w150.tar" "elv_n60w120.tar" "elv_n60w090.tar" "elv_n60w060.tar" "elv_n60w030.tar"
    "elv_n60e000.tar" "elv_n60e030.tar" "elv_n60e060.tar" "elv_n60e090.tar" "elv_n60e120.tar" "elv_n60e150.tar"
    # N30-N60
    "elv_n30w180.tar" "elv_n30w150.tar" "elv_n30w120.tar" "elv_n30w090.tar" "elv_n30w060.tar" "elv_n30w030.tar"
    "elv_n30e000.tar" "elv_n30e030.tar" "elv_n30e060.tar" "elv_n30e090.tar" "elv_n30e120.tar" "elv_n30e150.tar"
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

# Download all files
failed_files=()
for file in "${files[@]}"; do
    if ! download_file "${file}"; then
        failed_files+=("${file}")
    fi
    # Small delay between downloads
    sleep 2
done

# Report results
echo -e "\nDownload Summary:" | tee -a "${LOG_FILE}"
echo "Total files attempted: ${#files[@]}" | tee -a "${LOG_FILE}"
echo "Failed downloads: ${#failed_files[@]}" | tee -a "${LOG_FILE}"

if [ ${#failed_files[@]} -gt 0 ]; then
    echo "Failed files:" | tee -a "${LOG_FILE}"
    printf '%s\n' "${failed_files[@]}" | tee -a "${LOG_FILE}"
    exit 1
fi

echo "All downloads completed successfully at $(date)" | tee -a "${LOG_FILE}"