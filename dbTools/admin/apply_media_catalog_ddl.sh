#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-ibrida-v0}"  # Still using old name until IBRIDA-017 completes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Applying media catalog DDL to ${DB_NAME}"

# Apply the DDL
docker exec -i "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 \
  < "${SCRIPT_DIR}/add_media_catalog_ddl.sql"

echo "==> DDL applied successfully"

echo "==> Verifying tables exist"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "
\\dt+ media
\\dt+ observation_media  
"

echo "==> Checking public_media view"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "
SELECT COUNT(*) as media_count FROM public_media;
"

echo "==> Testing basic insert/select"
docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "
INSERT INTO media (dataset, release, uri, sha256_hex) 
VALUES ('test', 'r0', 'file:///tmp/test.jpg', 'abc123def456') 
ON CONFLICT (uri) DO NOTHING;

SELECT media_id, dataset, release, uri FROM media WHERE dataset = 'test';

DELETE FROM media WHERE dataset = 'test';
"

echo "==> Media catalog setup complete"