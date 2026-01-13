#!/usr/bin/env bash
set -euo pipefail

# Orchestration script for anthophila ingest pipeline
# Runs the complete workflow from manifest building to database insertion
#
# Usage: ./scripts/orchestrate_anthophila_ingest.sh [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
ANTHOPHILA_DIR="${ANTHOPHILA_DIR:-/datasets/dataZoo/anthophila}"
FLAT_DIR="${FLAT_DIR:-/datasets/ibrida-data/anthophila_flat}"
MANIFEST_CSV="${MANIFEST_CSV:-${REPO_ROOT}/anthophila_manifest.csv}"
DEDUP_CSV="${DEDUP_CSV:-${REPO_ROOT}/anthophila_duplicates.csv}"
DB_CONNECTION="${DB_CONNECTION:-postgresql://postgres:ooglyboogly69@localhost/ibrida-v0}"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "==> DRY RUN MODE: Commands will be printed but not executed"
fi

# Function to run command or print in dry-run mode
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        echo "==> $*"
        "$@"
    fi
}

echo "==> Starting Anthophila Ingest Orchestration"
echo "    Anthophila dir: $ANTHOPHILA_DIR"
echo "    Flat dir: $FLAT_DIR" 
echo "    Manifest CSV: $MANIFEST_CSV"
echo "    Dedup CSV: $DEDUP_CSV"
echo "    DB connection: $DB_CONNECTION"
echo

# Step 1: Build manifest
echo "==> Step 1: Building anthophila manifest"
if [[ ! -f "$MANIFEST_CSV" ]] || [[ "$MANIFEST_CSV" -ot "$ANTHOPHILA_DIR" ]]; then
    run_cmd uv run python3 "${SCRIPT_DIR}/build_anthophila_manifest.py" \
        --anthophila-dir "$ANTHOPHILA_DIR" \
        --output "$MANIFEST_CSV"
else
    echo "    Manifest already exists and is up to date: $MANIFEST_CSV"
fi

# Step 2: Apply media catalog DDL (if not already applied)
echo "==> Step 2: Ensuring media catalog tables exist"
run_cmd "${REPO_ROOT}/dbTools/admin/apply_media_catalog_ddl.sh"

# Step 3: Run deduplication
echo "==> Step 3: Running two-pass deduplication"
if [[ ! -f "$DEDUP_CSV" ]] || [[ "$DEDUP_CSV" -ot "$MANIFEST_CSV" ]]; then
    run_cmd uv run python3 "${SCRIPT_DIR}/deduplicate_anthophila.py" \
        --manifest "$MANIFEST_CSV" \
        --output "$DEDUP_CSV" \
        --db-connection "$DB_CONNECTION"
else
    echo "    Deduplication results already exist and are up to date: $DEDUP_CSV"
fi

# Step 4: Materialize flat directory and insert into media table
echo "==> Step 4: Materializing anthophila_flat/ and inserting media records"
run_cmd uv run python3 "${SCRIPT_DIR}/materialize_anthophila_flat.py" \
    --manifest "$DEDUP_CSV" \
    --flat-dir "$FLAT_DIR" \
    --db-connection "$DB_CONNECTION"

# Step 5: Summary and verification
echo "==> Step 5: Final verification and summary"
if [[ "$DRY_RUN" == "false" ]]; then
    echo "Checking results..."
    
    # Count files in flat directory
    FLAT_COUNT=$(find "$FLAT_DIR" -name "*.jpg" -type f | wc -l)
    echo "Files in anthophila_flat/: $FLAT_COUNT"
    
    # Count media records
    MEDIA_COUNT=$(docker exec ibridaDB psql -U postgres -d ibrida-v0 -t -c \
        "SELECT COUNT(*) FROM media WHERE dataset = 'anthophila' AND release = 'r2';" | tr -d ' ')
    echo "Media table records (anthophila r2): $MEDIA_COUNT"
    
    # Count kept vs total from dedup CSV
    if [[ -f "$DEDUP_CSV" ]]; then
        TOTAL_COUNT=$(tail -n +2 "$DEDUP_CSV" | wc -l)
        KEPT_COUNT=$(tail -n +2 "$DEDUP_CSV" | awk -F',' '$NF == "True"' | wc -l)
        DUPLICATE_COUNT=$((TOTAL_COUNT - KEPT_COUNT))
        
        echo "Total anthophila files processed: $TOTAL_COUNT"
        echo "Duplicates removed: $DUPLICATE_COUNT ($(echo "scale=1; $DUPLICATE_COUNT * 100 / $TOTAL_COUNT" | bc)%)"
        echo "Files kept: $KEPT_COUNT"
    fi
    
    echo
    if [[ "$FLAT_COUNT" == "$MEDIA_COUNT" ]] && [[ "$MEDIA_COUNT" == "$KEPT_COUNT" ]]; then
        echo "✅ SUCCESS: All counts match, anthophila ingest completed successfully"
    else
        echo "❌ WARNING: Count mismatch detected, manual investigation required"
        echo "   Flat files: $FLAT_COUNT, Media records: $MEDIA_COUNT, Expected (kept): $KEPT_COUNT"
    fi
fi

echo "==> Anthophila ingest orchestration complete"

# Save the configuration used for this run
if [[ "$DRY_RUN" == "false" ]]; then
    cat > "${REPO_ROOT}/anthophila_ingest_config.txt" << EOF
# Anthophila Ingest Configuration - $(date)
ANTHOPHILA_DIR=$ANTHOPHILA_DIR
FLAT_DIR=$FLAT_DIR
MANIFEST_CSV=$MANIFEST_CSV
DEDUP_CSV=$DEDUP_CSV
DB_CONNECTION=$DB_CONNECTION
EOF
    echo "Configuration saved to: ${REPO_ROOT}/anthophila_ingest_config.txt"
fi