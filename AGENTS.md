# AGENTS.md (ibridaDB)

This file is the quickstart + living memory for agents working in this repo.
Keep it updated as we learn new constraints or workflows.

## Purpose
ibridaDB ingests iNaturalist open data (and other datasets) into PostgreSQL/PostGIS,
then exports curated training datasets consumed downstream by ibrida.generator.

## Non-negotiables
- Preserve `ibrida-v0-r1` for reproducibility. No destructive changes to r1.
- Each release (r2, r3, ...) gets its own database (clean rebuild is preferred).
- Use `origin` to distinguish iNat vs non-iNat data.
- For long-running jobs, use `agent-notify` so completion/failure is broadcast.

## Canonical workflow
- Track work in Linear (POL-335 for r2/anthophila; POL-360 for anomaly_score schema).
- Prefer repo scripts; avoid ad-hoc SQL unless documented.
- Keep notes in Linear and/or `dev/logs/*` when you run long jobs.

## Docs ownership (repo-local)
- Treat repo-local docs as living memory; update them when you discover new truths.
- Keep docs organized; refactor/restructure if needed to make workflows clear.
- Maintain the local repo report copy at `docs/org-kb/repos/reports/`.
- Do **not** propagate changes to the polli monorepo copy until the new docstore CLI lands
  (watch agent-mail; related issues POL-381 and POL-417).

## Infrastructure (blade)
- DB container: `ibridaDB` (see `docker/stausee/docker-compose.yml`).
- PGDATA lives on `/mango/database/ibridaDB/pgdata` (symlink `/database/ibridaDB`).
- Temp tablespace: `/peach/ibridaDB/pgtemp` (fast NVMe).
- Data paths:
  - iNat metadata: `/datasets/ibrida-data/intake/<MonYYYY>`
  - Exports: `/datasets/ibrida-data/exports`
  - DEM: `/datasets/dem`
- Anthophila media: `/datasets/ibrida-data/media/anthophila/r2/flat`

## Backups
- Local r1 dump: `/mango/datasets/ibrida-data/backups/ibrida-v0-r1_20250829_003104/ibrida-v0-r1.dump`
- B2 `backups-0` exists (personal); no documented ibridaDB paths yet.

## iNat release cadence
- iNat open-data dumps are published monthly on the 27th.

## r2 base ingest (Dec2025)
- Script: `dbTools/admin/ingest_dec2025_r2_stream.sh`
- Streams TSV via STDIN (no container mount required).
- Adds `geom` and builds GIST index.
- Sets `origin/version/release` via column defaults (fast) rather than a full update.
- Creates GIN indexes on origin/version/release.
- **Do not** run `vers_origin.sh` for r2.

## expanded_taxa (taxa-only)
- `expanded_taxa` depends only on `taxa` (not observations, not anthophila).
- Run as soon as taxa is loaded:
  - `dbTools/taxa/expand/expand_taxa.sh` (DB_NAME=ibrida-v0-r2)
  - `scripts/add_immediate_ancestors.py --db ibrida-v0-r2`
- Optional: `scripts/ingest_coldp/populate_common_names.py` after expanded_taxa.

## Anthophila ingest (non-iNat)
- Use `media` + `observation_media` tables (apply `dbTools/admin/add_media_catalog_ddl.sql`).
- Deterministic IDs:
  - `asset_uuid` and `flat_name` are sha256-based.
  - `observation_key = name:<scientific_name_norm>|id:<id_core>` when id_core exists; else asset_uuid.
  - Hard-fail if any observation_key maps to >1 scientific_name_norm.
- Local paths:
  - Flat media: `/datasets/ibrida-data/media/anthophila/r2/flat`
  - Manifests: `/datasets/ibrida-data/media/anthophila/r2/manifests`
- Remote paths (B2 via rclone remote `ibrida:ibrida-1`):
  - `datasets/v0/r2/media/anthophila/flat/` and `.../manifests/`
- In DB:
  - `media.uri` = local `file://...` path
  - `media.sidecar` stores remote object key/URI
  - All anthophila inserts **must set explicit origin/version/release** (avoid iNat defaults).

## Elevation strategy
- r1 already has `observations.elevation_meters` computed.
- Preferred r2 approach:
  - Carry over `elevation_meters` from r1 by joining on observation_uuid.
  - Compute only missing rows (new observations) afterward.
- Avoid full-table elevation recompute unless absolutely required.

## Notifications
- Use `agent-notify` for any multi-hour job:
  - `cd /home/caleb/repo/polli && ~/.agents/run/agent-notify run --issue POL-335 -- <command>`
- This posts completion/failure to agent-mail.

## Known gotchas
- `observations.observation_uuid` is not indexed by default. Plan join/update strategies accordingly.
- `anomaly_score` type differs from upstream; alignment is tracked in POL-360.

## Local skill drafts
Draft skills are under `skills/` (local only, for now):
- `skills/ibridadb-ingest-inat`
- `skills/ibridadb-ingest-noninat`
- `skills/ibridadb-export`
