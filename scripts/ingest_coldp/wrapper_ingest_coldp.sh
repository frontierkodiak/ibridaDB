#!/bin/bash
# ibridaDB/scripts/ingest_coldp/wrapper_ingest_coldp.sh

# This wrapper orchestrates the ingestion of Catalogue of Life Data Package (ColDP)
# data into the ibridaDB. It loads raw ColDP tables, maps iNaturalist taxon IDs
# to ColDP taxon IDs, and then populates common name fields in the expanded_taxa table.

set -euo pipefail # Exit on error, undefined variable, or pipe failure

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/wrapper_ingest_coldp_$(date +%Y%m%d_%H%M%S).log"

# --- Configuration ---
# These can be overridden by environment variables if needed
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-password}" # Be cautious with passwords in scripts; use env vars or secrets manager in prod
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-ibrida-v0-r1}" # Target ibridaDB database

COLDP_DATA_DIR="${COLDP_DATA_DIR:-/datasets/taxa/catalogue_of_life/2024/ColDP}" # Path to unzipped ColDP files

PYTHON_EXE="${PYTHON_EXE:-python3}" # Path to python executable if not in PATH or using venv
## NOTE: Use venv interpreter at /home/caleb/repo/ibridaDB/.venv/bin/python

# Enable/disable fuzzy matching (default: enabled)
ENABLE_FUZZY_MATCH="${ENABLE_FUZZY_MATCH:-true}"
FUZZY_THRESHOLD="${FUZZY_THRESHOLD:-90}" # Match threshold (0-100)

# Enable/disable steps (for debugging or incremental runs)
RUN_LOAD_TABLES="${RUN_LOAD_TABLES:-true}"
RUN_MAP_TAXA="${RUN_MAP_TAXA:-true}"
RUN_POPULATE_COMMON_NAMES="${RUN_POPULATE_COMMON_NAMES:-true}"

# --- Logging ---
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "Starting ColDP Ingestion Wrapper at $(date)"
echo "--------------------------------------------------"
echo "Configuration:"
echo "  DB User: ${DB_USER}"
echo "  DB Host: ${DB_HOST}"
echo "  DB Port: ${DB_PORT}"
echo "  DB Name: ${DB_NAME}"
echo "  ColDP Data Dir: ${COLDP_DATA_DIR}"
echo "  Python Executable: ${PYTHON_EXE}"
echo "  Enable Fuzzy Match: ${ENABLE_FUZZY_MATCH}"
echo "  Fuzzy Threshold: ${FUZZY_THRESHOLD}"
echo "  Log File: ${LOG_FILE}"
echo "--------------------------------------------------"
echo "Steps Configuration:"
echo "  Load Tables: ${RUN_LOAD_TABLES}"
echo "  Map Taxa: ${RUN_MAP_TAXA}"
echo "  Populate Common Names: ${RUN_POPULATE_COMMON_NAMES}"
echo "--------------------------------------------------"

# --- Helper function to run Python scripts ---
run_python_script() {
    local script_name="$1"
    shift  # Remove first argument (script_name) so $@ contains only the remaining args
    local script_path="${SCRIPT_DIR}/${script_name}.py"
    
    echo ""
    echo ">>> Running ${script_name}.py..."
    if [ ! -f "${script_path}" ]; then
        echo "ERROR: Python script not found: ${script_path}"
        exit 1
    fi

    # Pass database connection details as arguments
    "${PYTHON_EXE}" "${script_path}" \
        --db-user "${DB_USER}" \
        --db-password "${DB_PASSWORD}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT}" \
        --db-name "${DB_NAME}" \
        "$@" # Pass through any additional arguments for the specific script
    
    if [ $? -ne 0 ]; then
        echo "ERROR: ${script_name}.py failed. Check logs above."
        exit 1
    fi
    echo ">>> Finished ${script_name}.py successfully."
}

# --- Main Orchestration ---

# Step 1: Load raw ColDP tables
# The load_tables.py script handles table creation and data loading from TSVs.
if [ "${RUN_LOAD_TABLES}" = "true" ]; then
    run_python_script "load_tables" --coldp-dir "${COLDP_DATA_DIR}"
else
    echo "Skipping load_tables.py (RUN_LOAD_TABLES=${RUN_LOAD_TABLES})"
fi

# Step 2: Map iNaturalist taxon IDs to ColDP taxon IDs
# This creates and populates the 'inat_to_coldp_taxon_map' table.
if [ "${RUN_MAP_TAXA}" = "true" ]; then
    # Build the arguments list based on whether fuzzy matching is enabled
    MAP_TAXA_ARGS=()
    if [ "${ENABLE_FUZZY_MATCH}" = "true" ]; then
        MAP_TAXA_ARGS+=("--fuzzy-match" "--fuzzy-threshold" "${FUZZY_THRESHOLD}")
    fi
    
    run_python_script "map_taxa" "${MAP_TAXA_ARGS[@]}"
else
    echo "Skipping map_taxa.py (RUN_MAP_TAXA=${RUN_MAP_TAXA})"
fi

# Step 3: Populate common names in the expanded_taxa table
# This uses the mapping table and vernacular names to update expanded_taxa.
if [ "${RUN_POPULATE_COMMON_NAMES}" = "true" ]; then
    run_python_script "populate_common_names" --clear-first
else
    echo "Skipping populate_common_names.py (RUN_POPULATE_COMMON_NAMES=${RUN_POPULATE_COMMON_NAMES})"
fi

echo "--------------------------------------------------"
echo "ColDP Ingestion Wrapper finished successfully at $(date)."
echo "--------------------------------------------------"

exit 0