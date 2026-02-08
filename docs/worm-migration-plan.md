# ibridaDB Blade -> Worm Migration Plan

Last updated: 2026-02-08 (UTC)

## Goal

Establish a concrete path to use `worm` for I/O-heavy ibridaDB build jobs (ingest/elevation), with optional continued serving from `blade`.

## Current snapshot (verified)

- Active DEM run (POL-335) is in-flight on `blade`; do not interrupt.
- Postgres DB catalog on `blade` currently includes:
  - `ibrida-v0`
  - `ibrida-v0-r2`
  - `ibrida-v0-old-backup`
  - `inaturalist-open-data`
- `ibrida-v0-r1` database name is **not** present. `ibrida-v0` rows show `version=v0, release=r1`.
- Source footprint on `blade`:
  - `/datasets/dem/merit`: ~67G
  - `/datasets/ibrida-data`: ~315G
  - PostgreSQL data dir (`/var/lib/postgresql/data` in container): ~2.1T on disk
- `worm` free space currently ~2.6T on root NVMe.

## Constraints and implications

- Copying raw PGDATA 1:1 is likely too tight on `worm` once all source datasets are present.
- `pg_database_size` totals are materially smaller than on-disk PGDATA footprint, so logical copy (dump/restore) is preferred over raw PGDATA rsync.
- Running large rsync from `stausee-pool` during the current DEM load can increase contention; throttle or defer hottest paths.

## Recommended target model (phase 1)

Use `worm` as **build host** for new releases (r3+ / heavy elevation work), keep `blade` as **serving host** for now.

- Build on `worm`: ingest, DEM load, heavy index builds, one-off transforms.
- Serve from `blade`: read-heavy exports/services until benchmark and ops confidence are complete.
- Replicate release artifacts/data products between hosts after build completion.

## Execution plan

## Phase 0: Keep current work safe

1. Let current DEM run finish on `blade`.
2. Do not run unthrottled bulk rsync against `/datasets/dem/merit` while this run is active.

## Phase 1: Worm prep (one-time)

1. Provision directories on `worm`:
   - `/datasets/ibrida-data`
   - `/datasets/dem`
   - `/database/ibridaDB`
   - `/peach/ibridaDB`
2. Install/start Docker and match base compose/runtime assumptions.
3. Add storage readiness checks on `worm` if any non-root mounts will be used (same class of guard as `stausee-ready` on blade).

## Phase 2: Data pre-seed (safe to start with throttling)

Start with lower-impact copies first (non-DEM, non-PGDATA), then DEM.

Example (from `blade`):

```bash
# Metadata/media/export tree pre-seed (throttled)
rsync -aHAX --numeric-ids --info=progress2 --bwlimit=80M \
  /datasets/ibrida-data/ worm:/datasets/ibrida-data/

# DEM pre-seed (schedule off-peak or after DEM ingest completes)
rsync -aHAX --numeric-ids --info=progress2 --bwlimit=80M \
  /datasets/dem/ worm:/datasets/dem/
```

Repeat incremental syncs with `--delete` only after confirming destination paths.

## Phase 3: Database copy strategy

Prefer logical copy over raw PGDATA rsync:

1. Create compressed custom-format dumps on blade per DB needed for migration.
2. Transfer dumps to worm.
3. Restore on worm into matching DB names.

Example:

```bash
# blade
mkdir -p /datasets/ibrida-data/backups/migration-202602
for db in ibrida-v0 ibrida-v0-r2 inaturalist-open-data; do
  docker exec ibridaDB pg_dump -U postgres -Fc "$db" \
    > "/datasets/ibrida-data/backups/migration-202602/${db}.dump"
done

# transfer
rsync -aHAX --info=progress2 \
  /datasets/ibrida-data/backups/migration-202602/ \
  worm:/datasets/ibrida-data/backups/migration-202602/

# worm restore (after container + empty DBs exist)
for db in ibrida-v0 ibrida-v0-r2 inaturalist-open-data; do
  docker exec -i ibridaDB pg_restore -U postgres -d "$db" \
    < "/datasets/ibrida-data/backups/migration-202602/${db}.dump"
done
```

Notes:
- For performance on rebuildable datasets, temporarily relaxing durability settings during restore can be considered, then reverted.
- Avoid copying transient `pg_wal`/bloat from blade by not rsyncing PGDATA.

## Phase 4: Validate worm as build host

Run verification on worm:

1. DB health: `docker exec ibridaDB psql -U postgres -Atc "select datname from pg_database"`
2. Table counts parity for key tables (`observations`, `taxa`, `expanded_taxa`, `elevation_raster`).
3. Re-run one representative heavy pipeline stage (e.g., DEM load subset for r3 scratch DB).
4. Capture wall-clock + CPU + iowait metrics.

## Phase 5: Decide steady-state topology

After worm validation, choose one:

1. Hybrid (recommended first): build on worm, serve from blade.
2. Full move: both build + serving on worm.

Decision criteria:
- Export latency and throughput
- Operational simplicity
- Backup/restore and reboot resilience
- Cross-host data movement overhead

## Quick answers to active questions

- Why typus test DSN failed on carbon:
  - The configured DSN referenced `ibrida-v0-r1`, which does not exist by that name.
  - Existing r1-equivalent data is in `ibrida-v0`.

## Immediate next actions (post current DEM run)

1. Pin canonical DB naming in test configs (`ibrida-v0` vs `ibrida-v0-r1`) to avoid repeated DSN confusion.
2. Start Phase 2 rsync pre-seed (throttled).
3. Generate per-DB dump set for worm import.
4. Run first worm-side restore + parity check.

