#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 /path/to/ibrida-v0.dump [RESTORE_DB_NAME]"
  exit 1
fi

DUMP_FILE="$1"
TARGET_DB="${2:-}"  # If provided, restore into this pre-created DB

DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
TEMPLATE_DB="${TEMPLATE_DB:-template_postgis}"

if [ ! -f "${DUMP_FILE}" ]; then
  echo "ERROR: dump file not found: ${DUMP_FILE}"
  exit 1
fi

if [ -f "${DUMP_FILE}.sha256" ]; then
  echo "==> Verifying checksum"
  sha256sum -c "${DUMP_FILE}.sha256"
fi

if [ -n "${TARGET_DB}" ]; then
  echo "==> Creating fresh DB '${TARGET_DB}' from ${TEMPLATE_DB}"
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -c \
    "DROP DATABASE IF EXISTS \"${TARGET_DB}\";"
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -c \
    "CREATE DATABASE \"${TARGET_DB}\" TEMPLATE ${TEMPLATE_DB} OWNER ${DB_USER};"

  echo "==> Restoring into '${TARGET_DB}'"
  # --clean drops objects if they exist; --no-owner avoids owner differences
  cat "${DUMP_FILE}" | docker exec -i "${DB_CONTAINER}" pg_restore \
    -U "${DB_USER}" -d "${TARGET_DB}" --clean --no-owner -j 4
else
  echo "==> Restoring with --create (DB name from archive)"
  cat "${DUMP_FILE}" | docker exec -i "${DB_CONTAINER}" pg_restore \
    -U "${DB_USER}" -d postgres -C --no-owner -j 4
fi

echo "==> Restore complete."