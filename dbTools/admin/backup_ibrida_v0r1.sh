#!/usr/bin/env bash
set -euo pipefail

# Defaults (override via env if needed)
DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-ibrida-v0}"

# Backups live under /datasets/ibrida-data/backups
BACKUP_ROOT="${BACKUP_ROOT:-/datasets/ibrida-data/backups}"
TS="$(date +%Y%m%d_%H%M%S)"
TARGET_DIR="${BACKUP_ROOT}/${DB_NAME}_${TS}"

mkdir -p "${TARGET_DIR}"

echo "==> Checking free space and DB size..."
df -h /datasets/ibrida-data | sed -n '1,2p' || true
DB_SIZE=$(docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -At -c \
  "SELECT pg_size_pretty(pg_database_size('${DB_NAME}'));")
echo "==> ${DB_NAME} size: ${DB_SIZE}"

echo "==> Dumping database (custom format) to ${TARGET_DIR}/${DB_NAME}.dump"
# Custom format (-Fc) is recommended for pg_restore flexibility
docker exec "${DB_CONTAINER}" pg_dump -U "${DB_USER}" -d "${DB_NAME}" -Fc > \
  "${TARGET_DIR}/${DB_NAME}.dump"

echo "==> Dumping cluster globals (roles, etc.) to ${TARGET_DIR}/globals.sql"
docker exec "${DB_CONTAINER}" pg_dumpall -U "${DB_USER}" --globals-only > \
  "${TARGET_DIR}/globals.sql" || true

echo "==> Creating checksum"
sha256sum "${TARGET_DIR}/${DB_NAME}.dump" > "${TARGET_DIR}/${DB_NAME}.dump.sha256"

echo "==> Writing manifest"
cat > "${TARGET_DIR}/MANIFEST.txt" <<EOF
DATE=$(date -Is)
DB_CONTAINER=${DB_CONTAINER}
DB_USER=${DB_USER}
DB_NAME=${DB_NAME}
DB_SIZE=${DB_SIZE}
DUMP_FILE=${TARGET_DIR}/${DB_NAME}.dump
GLOBALS_FILE=${TARGET_DIR}/globals.sql
EOF

echo "==> Backup complete."
echo "Backup directory: ${TARGET_DIR}"