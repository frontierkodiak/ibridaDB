#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
OLD_DB="${OLD_DB:-ibrida}"
NEW_DB="${NEW_DB:-ibrida-v0}"

if [[ "${OLD_DB}" == "${NEW_DB}" ]]; then
  echo "ERROR: OLD_DB and NEW_DB are identical (${OLD_DB}); nothing to rename." >&2
  exit 1
fi

echo "==> Terminating sessions on ${OLD_DB}"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -v ON_ERROR_STOP=1 -c \
  "SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE datname='${OLD_DB}' AND pid <> pg_backend_pid();"

echo "==> Renaming database ${OLD_DB} -> ${NEW_DB}"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -v ON_ERROR_STOP=1 -c \
  "ALTER DATABASE \"${OLD_DB}\" RENAME TO \"${NEW_DB}\";"

echo "==> Ensuring owner"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -v ON_ERROR_STOP=1 -d "${NEW_DB}" -c \
  "ALTER DATABASE \"${NEW_DB}\" OWNER TO ${DB_USER};"

echo "==> Verifying"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -At -c \
  "SELECT datname FROM pg_database WHERE datname IN ('${OLD_DB}','${NEW_DB}');"

echo "==> Done."
