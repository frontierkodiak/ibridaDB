Awesome—below are ready‑to‑run admin utilities and SQL you can drop into the repo to 1) back up ibrida-v0, 2) (optionally) test a restore, 3) rename the database to ibrida-v0, and 4) safely update in‑repo references (excluding the archival wrappers). I’ve also included pure SQL you can run for the taxa checks you mentioned (bee genera and rare species).

The execute_sql() wrapper used below matches the pattern already present in your export scripts (see dbTools/export/v0/common/functions.sh).  ￼

⸻

0) Where to put these

mkdir -p /home/caleb/repo/ibridaDB/dbTools/admin

Save each script in that folder, chmod +x them, and run as shown.

⸻

1) Preflight / backup (LOCAL, custom-format dump)

dbTools/admin/backup_ibrida_v0r1.sh

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

Run it:

bash /home/caleb/repo/ibridaDB/dbTools/admin/backup_ibrida_v0r1.sh

This creates /datasets/ibrida-data/backups/<db>_<timestamp>/ with:
	•	ibrida-v0.dump (custom format)
	•	globals.sql (cluster globals; best-effort)
	•	MANIFEST.txt, checksum

⸻

2) (Optional) Quick test restore to a scratch DB

dbTools/admin/restore_from_backup.sh

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

Example (scratch DB):

bash /home/caleb/repo/ibridaDB/dbTools/admin/restore_from_backup.sh \
  /datasets/ibrida-data/backups/ibrida-v0_YYYYMMDD_HHMMSS/ibrida-v0.dump \
  ibrida-v0_scratch


⸻

3) Rename the database after backup

dbTools/admin/rename_db_to_v0.sh

#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
OLD_DB="${OLD_DB:-ibrida-v0}"
NEW_DB="${NEW_DB:-ibrida-v0}"

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

Run it:

bash /home/caleb/repo/ibridaDB/dbTools/admin/rename_db_to_v0.sh


⸻

4) Update repo references (excluding archival wrappers)

Per your note: do not touch dbTools/<ingest|export>/v0/<r0|r1> wrappers; but do update places like dbTools/taxa/expand/expand_taxa.sh and docs.

dbTools/admin/update_repo_refs_after_rename.sh

#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/home/caleb/repo/ibridaDB}"
OLD="ibrida-v0"
NEW="ibrida-v0"
BRANCH="${BRANCH:-chore/rename-db-to-v0}"

cd "${REPO_ROOT}"
git rev-parse --is-inside-work-tree >/dev/null

echo "==> Creating branch ${BRANCH}"
git checkout -b "${BRANCH}"

# 1) Explicitly update the taxa expander default:
if [ -f "dbTools/taxa/expand/expand_taxa.sh" ]; then
  sed -i 's/DB_NAME="${DB_NAME:-ibrida-v0}"/DB_NAME="${DB_NAME:-ibrida-v0}"/' \
    dbTools/taxa/expand/expand_taxa.sh || true
fi

# 2) Bulk replace all other references EXCEPT archival wrappers
#    (and of course exclude .git)
echo "==> Replacing '${OLD}' -> '${NEW}' (excluding archival wrappers)"
grep -rl --exclude-dir=.git \
         --exclude-dir=dbTools/ingest/v0/r0 \
         --exclude-dir=dbTools/ingest/v0/r1 \
         --exclude-dir=dbTools/export/v0/r0 \
         --exclude-dir=dbTools/export/v0/r1 \
         -e "${OLD}" . \
| xargs sed -i "s/${OLD}/${NEW}/g"

# 3) Commit
git add -A
git commit -m "chore: rename DB references ${OLD} -> ${NEW} (exclude v0 r0/r1 wrappers for archival)"
echo "==> Committed. Review diff, then push when ready:"
echo "   git push --set-upstream origin ${BRANCH}"

Run it:

bash /home/caleb/repo/ibridaDB/dbTools/admin/update_repo_refs_after_rename.sh


⸻

5) Pure SQL for the taxa analysis steps (ready to paste/run)

These are safe to run as ad‑hoc psql -c or via your agent (admin). They use only taxa and observations and make no schema changes.

5.1 Count observations for selected bee genera (Osmia, Megachile, Agapostemon) by species

WITH target_genera AS (
  SELECT taxon_id, name
  FROM taxa
  WHERE rank = 'genus' AND active = TRUE
    AND name IN ('Osmia','Megachile','Agapostemon')
),
desc_species AS (
  SELECT t.taxon_id, t.name, t.rank
  FROM taxa t
  JOIN target_genera g
    ON t.rank = 'species'
   AND t.active = TRUE
   AND (t.ancestry LIKE ('%' || E'\\' || g.taxon_id::text || E'\\' || '%'))
)
SELECT ds.name AS species_name,
       COUNT(*) AS obs_count
FROM observations o
JOIN desc_species ds ON ds.taxon_id = o.taxon_id
GROUP BY ds.name
ORDER BY obs_count DESC
LIMIT 100;

5.2 “Rare” species (< 100 observations) within those genera

WITH target_genera AS (
  SELECT taxon_id, name
  FROM taxa
  WHERE rank = 'genus' AND active = TRUE
    AND name IN ('Osmia','Megachile','Agapostemon')
),
desc_species AS (
  SELECT t.taxon_id, t.name
  FROM taxa t
  JOIN target_genera g
    ON t.rank = 'species'
   AND t.active = TRUE
   AND (t.ancestry LIKE ('%' || E'\\' || g.taxon_id::text || E'\\' || '%'))
)
SELECT t.name AS species_name,
       COUNT(*) AS obs_count
FROM observations o
JOIN desc_species t ON t.taxon_id = o.taxon_id
GROUP BY t.name
HAVING COUNT(*) < 100
ORDER BY obs_count ASC, species_name
LIMIT 200;

5.3 Quick check for specific taxa (as used in your notes)

SELECT t.name, COUNT(*) AS obs_count
FROM observations o
JOIN taxa t ON t.taxon_id = o.taxon_id
WHERE t.rank = 'species'
  AND t.name IN ('Megachile addenda', 'Megachile canescens')
GROUP BY t.name
ORDER BY t.name;

5.4 Hymenoptera coverage snapshot (species count and observations)

WITH root AS (
  SELECT taxon_id
  FROM taxa
  WHERE name='Hymenoptera' AND rank='order' AND active=TRUE
  LIMIT 1
),
desc_species AS (
  SELECT t.taxon_id
  FROM taxa t, root r
  WHERE t.rank='species' AND t.active=TRUE
    AND (t.ancestry LIKE ('%' || E'\\' || r.taxon_id::text || E'\\' || '%')
         OR t.taxon_id = r.taxon_id)
)
SELECT COUNT(DISTINCT o.taxon_id) AS species_present,
       COUNT(*)                    AS total_observations
FROM observations o
JOIN desc_species s ON s.taxon_id = o.taxon_id;

If you prefer a single .sql file, drop all four blocks into dbTools/taxa/bee_taxa_analysis.sql and run:

docker exec ibridaDB psql -U postgres -d ibrida-v0 -f /metadata/sql/bee_taxa_analysis.sql

(adjust DB name as needed after the rename)

⸻

6) Minimal “wrappered SQL” style helper (optional)

If you want to keep a shell wrapper that mirrors your pattern:

dbTools/admin/sql_runner.sh

#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-ibridaDB}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-ibrida-v0}"

execute_sql() {
  local sql="$1"
  docker exec "${DB_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "$sql"
}

# Example usage:
# execute_sql "SELECT COUNT(*) FROM observations;"
# execute_sql "$(cat /path/to/your_query.sql)"


⸻

7) Preflight checklist (for the AI assigned to ibridaDB)
	1.	Confirm container + DB exist
	•	docker ps | grep ibridaDB
	•	docker exec ibridaDB psql -U postgres -At -c "SELECT datname FROM pg_database;" | grep ibrida-v0
	2.	Create backup root
	•	mkdir -p /datasets/ibrida-data/backups && chmod -R 775 /datasets/ibrida-data/backups
	3.	Run the backup script (Section 1) and record the resulting path.
	4.	(Optional) Test restore into ibrida-v0_scratch (Section 2).
	5.	Rename the working database to ibrida-v0 (Section 3).
	6.	Update repo references (Section 4). This:
	•	Leaves dbTools/<ingest|export>/v0/<r0|r1> wrappers untouched (archival).
	•	Updates dbTools/taxa/expand/expand_taxa.sh default (DB_NAME="${DB_NAME:-ibrida-v0}").
	•	Updates CLAUDE.md examples and any other non‑archival references.
	7.	Sanity checks after rename
	•	docker exec ibridaDB psql -U postgres -At -c "SELECT current_database();" -d ibrida-v0
	•	docker exec ibridaDB psql -U postgres -d ibrida-v0 -c "SELECT COUNT(*) FROM observations;"
	8.	Record the backup manifest path + git branch from the rename refactor.

⸻

Notes / gotchas
	•	PostGIS: The dump includes CREATE EXTENSION postgis metadata; the container image must have PostGIS installed so a restore succeeds.
	•	Connections during rename: The rename script terminates active connections to avoid lock conflicts.
	•	Parallel restore: We set -j 4 in the restore script; feel free to increase on beefy hardware.
	•	Wrapper parity: The execute_sql above matches your existing pattern (export functions.sh).  ￼

⸻

If you want, I can also package these into a small Makefile target (e.g., make backup, make rename_db, make update_refs) reusing the same scripts.