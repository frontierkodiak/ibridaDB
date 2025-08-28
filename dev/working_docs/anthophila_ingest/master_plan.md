---
issue_id: "PLAN-ANTH-R2"
title: "Master Plan: Anthophila + iNat r2 Integration (ibridaDB + Generator)"
status: "open"
priority: "high"
plan: "anthophila_r2_integration"
phase: "Overview"
created: "2025-08-28T00:00:00Z"
updated: "2025-08-28T00:00:00Z"
tags: ["plan", "anthophila", "r2", "media", "generator", "taxonomy", "ingest", "export"]
blocked_by: []
blocks: ["IBRIDA-008","IBRIDA-017","IBRIDA-006","IBRIDA-007","IBRIDA-009","IBRIDA-011","IBRIDA-012","IBRIDA-013","IBRIDA-010","IBRIDA-015","IBRIDA-016","IBRIDA-020","IBRIDA-021","IBRIDA-022","IBRIDA-023","IBRIDA-024","IBRIDA-025"]
notes: "Single source of truth for Phase R2: add Aug-2025 iNat delta + ingest anthophila media, then enable generator to consume local/B2 URIs."
---

# Master Plan (Anthophila + r2)

## Goals
- **Aug-2025 iNat delta (r2)**: incrementally extend v0 dataset (r1’r2) without losing r1 history.
- **Anthophila ingest**: add expert-labeled bee imagery as first-class media with provenance & dedup.
- **Generator enablement**: support local/B2/HTTP URIs alongside iNat photos for dataset builds.

## Milestones (dependency-ordered)

**M0. Safety & Naming**
- P0: Backup `ibrida-v0-r1`; test restore; rename DB to `ibrida-v0`; update in-repo references (excl. archival wrappers). ’ _IBRIDA-017_

**M1. Staging & Preflight**
- P1: Load Aug-2025 iNat CSVs to staging `stg_inat_20250827`. ’ _IBRIDA-007_
- P0: **Taxonomy preflight** (r1 vs r2) over only the *new* obs' taxon_ids; block on breaking changes. ’ _IBRIDA-008_

**M2. r2 Delta Import**
- P1: Idempotent upserts for observations/photos/observers + new taxa; record release row. ’ _IBRIDA-009_
- P2: Elevation for **r2 delta only** via a work-queue view + optional geohash cache. ’ _IBRIDA-010_
- P2: Public views that exclude unknown/restricted licenses. ’ _IBRIDA-015_
- P2: Create `releases` row for r2. ’ _IBRIDA-016_

**M3. Anthophila Normalization & Ingest**
- P1: Build `anthophila_manifest.csv` with width/height, sha256, pHash, ID-type guess. ’ _IBRIDA-011_
- P1: Two-pass dedup (ID vs DB + hash vs DB). ’ _IBRIDA-012_
- P1: Materialize `anthophila_flat/` (copy/hardlink kept samples) and insert rows to **media** (generic table with `uri` & `sidecar`). ’ _IBRIDA-013_
- P2: Verify counts/FKs, orphan scan, license sentinels, origin/version/release tags. ’ _IBRIDA-014_

**M4. Generator Compatibility & Quality**
- P1: **Generator LocalFileProvider** + tests, reading `media.uri` (file://, b2://, s3://, https://). ’ _IBRIDA-022_
- P2: Example configs + docs and a Postgres view feeding `image_path` + labels. ’ _IBRIDA-021_, _IBRIDA-023_
- P2: Leakage-guard optional hook (sha256 grouping across iNat photos & media). ’ _IBRIDA-020_, _IBRIDA-024_

**M5. Docs & Release**
- P3: Release notes & tracker updates; finalize r2 narrative. ’ _IBRIDA-019_

## Design anchors (internal references)
- Issue tracker & prior investigation issues are in `dev/issues/` (completed IBRIDA-001..005).  
- Working drafts for the anthophila plan sit under `dev/working_docs/anthophila_ingest/`.  
- Export repo configuration & traversal context for v0’r2 are captured in export dumps.

## Acceptance for "r2 ready"
- Taxonomy preflight reports **no breaking** diffs for taxa referenced by r2 delta.
- Observations/photos/observers imported for r2; elevation filled for r2 subset.
- `media` contains anthophila **kept** items; duplicates removed/flagged.
- Generator builds a hybrid dataset from anthophila rows (images + labels.h5) with LocalFileProvider.
- ISSUE_TRACKER reflects current open/closed sets; all P0/P1 issues in progress or done.