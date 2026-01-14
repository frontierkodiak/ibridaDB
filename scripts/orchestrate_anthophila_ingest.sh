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
FLAT_DIR="${FLAT_DIR:-/datasets/ibrida-data/media/anthophila/r2/flat}"
MANIFEST_DIR="${MANIFEST_DIR:-/datasets/ibrida-data/media/anthophila/r2/manifests}"
MANIFEST_CSV="${MANIFEST_CSV:-${MANIFEST_DIR}/anthophila_manifest.csv}"
DEDUP_CSV="${DEDUP_CSV:-${MANIFEST_DIR}/anthophila_duplicates.csv}"
RESOLVED_CSV="${RESOLVED_CSV:-${MANIFEST_DIR}/anthophila_duplicates_resolved.csv}"
DB_CONNECTION="${DB_CONNECTION:-postgresql://postgres:ooglyboogly69@localhost/ibrida-v0}"
DATASET="${DATASET:-anthophila}"
ORIGIN="${ORIGIN:-anthophila}"
VERSION="${VERSION:-v0}"
RELEASE="${RELEASE:-r2}"
REMOTE_KEY_PREFIX="${REMOTE_KEY_PREFIX:-datasets/v0/r2/media/anthophila/flat}"
REMOTE_URI_PREFIX="${REMOTE_URI_PREFIX:-b2://ibrida-1}"
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"

if [[ -n "${DB_CONNECTION:-}" ]]; then
    read -r DB_NAME_FROM_CONN DB_USER_FROM_CONN < <(python3 - <<'PY'
import os
import urllib.parse

conn = os.environ.get("DB_CONNECTION", "")
db = ""
user = ""
if conn:
    try:
        parsed = urllib.parse.urlparse(conn)
        if parsed.path:
            db = parsed.path.lstrip("/").split("/")[0]
        user = parsed.username or ""
    except Exception:
        pass
print(db, user)
PY
    )
    if [[ -z "${DB_NAME}" && -n "${DB_NAME_FROM_CONN}" ]]; then
        DB_NAME="${DB_NAME_FROM_CONN}"
    fi
    if [[ -z "${DB_USER}" && -n "${DB_USER_FROM_CONN}" ]]; then
        DB_USER="${DB_USER_FROM_CONN}"
    fi
fi

DB_NAME="${DB_NAME:-ibrida-v0}"
DB_USER="${DB_USER:-postgres}"

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
echo "    Manifest dir: $MANIFEST_DIR"
echo "    Manifest CSV: $MANIFEST_CSV"
echo "    Dedup CSV: $DEDUP_CSV"
echo "    Resolved CSV: $RESOLVED_CSV"
echo "    DB connection: $DB_CONNECTION"
echo "    Dataset: $DATASET  Origin: $ORIGIN  Version: $VERSION  Release: $RELEASE"
echo "    Remote key prefix: $REMOTE_KEY_PREFIX"
echo "    Remote URI prefix: $REMOTE_URI_PREFIX"
echo

if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p "$MANIFEST_DIR"
    mkdir -p "$FLAT_DIR"
fi

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

# Step 3.5: Resolve taxa
echo "==> Step 3.5: Resolving scientific names to taxon_id"
if [[ ! -f "$RESOLVED_CSV" ]] || [[ "$RESOLVED_CSV" -ot "$DEDUP_CSV" ]]; then
    run_cmd uv run python3 "${SCRIPT_DIR}/resolve_anthophila_taxa.py" \
        --manifest "$DEDUP_CSV" \
        --output "$RESOLVED_CSV" \
        --db-connection "$DB_CONNECTION"
else
    echo "    Resolved manifest already exists and is up to date: $RESOLVED_CSV"
fi

# Step 4: Materialize flat directory and insert into media/observations tables
echo "==> Step 4: Materializing anthophila_flat/ and inserting records"
run_cmd uv run python3 "${SCRIPT_DIR}/materialize_anthophila_flat.py" \
    --manifest "$RESOLVED_CSV" \
    --flat-dir "$FLAT_DIR" \
    --db-connection "$DB_CONNECTION" \
    --dataset "$DATASET" \
    --origin "$ORIGIN" \
    --version "$VERSION" \
    --release "$RELEASE" \
    --remote-key-prefix "$REMOTE_KEY_PREFIX" \
    --remote-uri-prefix "$REMOTE_URI_PREFIX"

# Step 5: Summary and verification
echo "==> Step 5: Final verification and summary"
if [[ "$DRY_RUN" == "false" ]]; then
    echo "Checking results..."
    
    # Count files in flat directory
    FLAT_COUNT=$(find "$FLAT_DIR" -name "*.jpg" -type f | wc -l)
    echo "Files in anthophila_flat/: $FLAT_COUNT"
    
    # Count media records
    MEDIA_COUNT=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -t -c \
        "SELECT COUNT(*) FROM media WHERE dataset = '${DATASET}' AND release = '${RELEASE}';" | tr -d ' ')
    echo "Media table records (${DATASET} ${RELEASE}): $MEDIA_COUNT"
    
    # Count kept vs total from dedup CSV
    if [[ -f "$RESOLVED_CSV" ]]; then
        TOTAL_COUNT=$(tail -n +2 "$RESOLVED_CSV" | wc -l)
        KEPT_COUNT=$(awk -F',' '
          NR==1 {for (i=1;i<=NF;i++) if ($i=="keep_flag") k=i}
          NR>1 && k>0 && $k=="True" {c++}
          END {print c+0}
        ' "$RESOLVED_CSV")
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
MANIFEST_DIR=$MANIFEST_DIR
MANIFEST_CSV=$MANIFEST_CSV
DEDUP_CSV=$DEDUP_CSV
RESOLVED_CSV=$RESOLVED_CSV
DB_CONNECTION=$DB_CONNECTION
DATASET=$DATASET
ORIGIN=$ORIGIN
VERSION=$VERSION
RELEASE=$RELEASE
REMOTE_KEY_PREFIX=$REMOTE_KEY_PREFIX
REMOTE_URI_PREFIX=$REMOTE_URI_PREFIX
EOF
    echo "Configuration saved to: ${REPO_ROOT}/anthophila_ingest_config.txt"
fi
