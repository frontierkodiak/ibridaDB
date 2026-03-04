#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-ibrida-v0}"  # Still using old name until IBRIDA-017 completes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

psql_exec() {
  docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" "$@"
}

echo "==> Applying media catalog DDL to ${DB_NAME}"

echo "==> Preflight: validating observations(observation_uuid) uniqueness prerequisites"
HAS_UNIQUE_OBS_UUID="$(psql_exec -Atqc "
SELECT CASE WHEN EXISTS (
  SELECT 1
  FROM pg_index i
  JOIN pg_class t ON t.oid = i.indrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(i.indkey)
  WHERE n.nspname = 'public'
    AND t.relname = 'observations'
    AND i.indisunique
    AND i.indisvalid
    AND i.indpred IS NULL
    AND i.indnatts = 1
    AND a.attname = 'observation_uuid'
) THEN 1 ELSE 0 END;
")"

if [[ "${HAS_UNIQUE_OBS_UUID}" != "1" ]]; then
  echo "==> No usable unique index/constraint found on observations(observation_uuid)."
  echo "==> Creating unique index for FK target: uq_observations_observation_uuid"
  if ! psql_exec -c "CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_observations_observation_uuid ON observations(observation_uuid);"; then
    echo "ERROR: failed to create unique index on observations(observation_uuid)." >&2
    echo "Likely cause: duplicate observation_uuid values in observations." >&2
    echo "Inspect duplicates, resolve, then rerun apply_media_catalog_ddl.sh." >&2
    exit 1
  fi
fi

# Apply the DDL
psql_exec -v ON_ERROR_STOP=1 < "${SCRIPT_DIR}/add_media_catalog_ddl.sql"

echo "==> DDL applied successfully"

echo "==> Verifying tables exist"
psql_exec -c "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('media', 'observation_media')
ORDER BY table_name;
"

echo "==> Checking public_media view"
psql_exec -c "
SELECT COUNT(*) as media_count FROM public_media;
"

echo "==> Testing basic insert/select"
psql_exec -c "
INSERT INTO media (dataset, release, uri, sha256_hex)
VALUES ('test', 'r0', 'file:///tmp/test.jpg', 'abc123def456')
ON CONFLICT (uri) DO NOTHING;

SELECT media_id, dataset, release, uri FROM media WHERE dataset = 'test';

DELETE FROM media WHERE dataset = 'test';
"

echo "==> Media catalog setup complete"
