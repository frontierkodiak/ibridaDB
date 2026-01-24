---
name: "ibridadb-ingest-noninat"
description: "Ingest a non-iNat dataset (e.g., anthophila) into ibridaDB: build manifest, dedup, flatten media, upload to B2, and insert observations/media with explicit origin/version/release."
---

# ibridadb-ingest-noninat

Use this skill for any non-iNat dataset. Anthophila is the reference workflow.

## Preconditions
- `media` + `observation_media` tables exist (`dbTools/admin/add_media_catalog_ddl.sql`).
- Target DB is a clean release base (e.g., `ibrida-v0-r2`).
- Local + remote storage paths are agreed.

## Canonical paths (anthophila r2)
- Local flat media: `/datasets/ibrida-data/media/anthophila/r2/flat/`
- Local manifests: `/datasets/ibrida-data/media/anthophila/r2/manifests/`
- Remote (rclone `ibrida:ibrida-1`): `datasets/v0/r2/media/anthophila/flat/` and `.../manifests/`

## Deterministic identity (must-haves)
- `asset_uuid` and `flat_name` derive from sha256 (stable across reruns).
- `observation_key = name:<scientific_name_norm>|id:<id_core>` when id_core exists; else asset_uuid.
- Hard-fail if any observation_key maps to >1 scientific_name_norm.

## Procedure (anthophila)
1) **Build manifest**
   - `python3 scripts/build_anthophila_manifest.py ...`
   - Manifests are canonical artifacts; store in `/manifests`.

2) **Deduplicate**
   - `python3 scripts/deduplicate_anthophila.py ...`

3) **Materialize flat media + metadata**
   - `python3 scripts/materialize_anthophila_flat.py ...`
   - Capture image metadata (dims) during flatten.
   - Ensure `media.uri` uses local `file://...` and `media.sidecar` records remote key/URI.

4) **Upload to B2**
   - `rclone copy` to `ibrida:ibrida-1/datasets/v0/r2/media/anthophila/flat/`
   - Upload manifests alongside images.
   - Run `rclone check` for integrity.

5) **Insert into DB**
   - Insert observations, media, observation_media.
   - **Always set origin/version/release explicitly** to avoid iNat defaults.

## Validation
- Observation key uniqueness check passes.
- `media` + `observation_media` counts match manifest.
- Sample rows show correct origin/version/release.
