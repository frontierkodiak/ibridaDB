---
name: "ibridadb-ingest-inat"
description: "Ingest a new iNat Open Data release into a clean ibrida-v0-rX database using the repo scripts. Use when pulling a fresh monthly dump and rebuilding a release base."
---

# ibridadb-ingest-inat

Use this skill when rebuilding a clean database for a new iNat Open Data release.

## Quick start
1) Identify latest iNat dump (monthly cadence on the 27th).
2) Download + extract to `/datasets/ibrida-data/intake/<MonYYYY>`.
3) Run the stream ingest script (or copy it for a new release).
4) Run expanded_taxa (taxa-only) and optional ColDP steps.

## Inputs
- iNat metadata tarball from `iNatOpenData:inaturalist-open-data/metadata/`.
- Target database name (e.g., `ibrida-v0-r2`).
- Metadata path (e.g., `/datasets/ibrida-data/intake/Dec2025`).

## Procedure
1) **Fetch latest metadata** (example)
   - `rclone lsf iNatOpenData:inaturalist-open-data/metadata/`
   - `rclone copy -P iNatOpenData:inaturalist-open-data/metadata/inaturalist-open-data-YYYYMM27.tar.gz /datasets/ibrida-data/intake/MonYYYY`
   - `tar -xzf ... --strip-components=1`

2) **Stream ingest into a clean DB**
   - Template script: `dbTools/admin/ingest_dec2025_r2_stream.sh`
   - For a new release, copy and update defaults (SOURCE, RELEASE, ORIGIN, METADATA_PATH, DB_NAME).
   - Run with a wrapper (agent-notify recommended for long jobs).

3) **expanded_taxa (taxa-only dependency)**
   - `DB_NAME=ibrida-v0-rX dbTools/taxa/expand/expand_taxa.sh`
   - `python3 scripts/add_immediate_ancestors.py --db ibrida-v0-rX`
   - Optional: `scripts/ingest_coldp/populate_common_names.py`

4) **Validate**
   - `SELECT COUNT(*) FROM observations` matches metadata counts.
   - `SELECT COUNT(*) FROM observations WHERE geom IS NOT NULL` == total.
   - Confirm GIN indexes on origin/version/release.

## Notes / gotchas
- The stream ingest adds `origin/version/release` via column defaults (fast). Do NOT run `vers_origin.sh` for large tables.
- `anomaly_score` is tracked in POL-360 for schema alignment; avoid expensive rewrites mid-ingest.
- Use `agent-notify` for any multi-hour step.
