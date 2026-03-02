# Annotation Foundations Migration Notes (POL-652)

This note explains how existing assumptions map onto the new Schema A foundations:

- `annotation_set`
- `annotation_subject`

These tables are identity scaffolding only. Geometry/provenance/quality policy arrives in `POL-653`/`POL-654`/`POL-655`.

## Why this split exists

Current export and ingest surfaces encode annotation intent implicitly inside run artifacts, script names, and ad hoc metadata. That pattern does not support durable lineage, multi-source coexistence, or stable joins across reruns.

`POL-652` introduces explicit relational identities without forcing immediate migration of all annotation payload logic.

## Mapping from current assumptions

### 1. "One run = one annotation production"

- **Old pattern:** Batch/run identity is inferred from file paths or script wrappers.
- **New pattern:** Create one `annotation_set` row per run/import/human batch.

Recommended fields:

- `source_kind`: `human` | `model` | `imported_dataset`
- `source_name`: tool or process name (for example `sam3`, `gemini`, `inat2017-import`)
- `source_version`: model/tool version
- `run_id`: external run key when available
- `prompt_hash` / `config_hash`: deterministic hashes for replayability

### 2. "Asset identity is implicit in photo/media tables"

- **Old pattern:** Consumers join directly to `photos` or `media` and carry their own frame semantics.
- **New pattern:** Represent each annotatable target as an `annotation_subject`.

Recommended fields:

- `asset_uuid`: stable target identity (photo UUID or external media UUID)
- `observation_uuid`: optional linkage for observation-level queries
- `frame_index`, `time_start_ms`, `time_end_ms`: optional for video/segment targeting

### 3. "Duplicates are handled ad hoc"

- **Old pattern:** Duplicate run imports can slip in unless scripts guard manually.
- **New pattern:** `annotation_set` partial unique index on `(source_name, source_version, run_id)` where `run_id` is present.

### 4. "Subject identity can be rewritten"

- **Old pattern:** Different jobs may construct the same asset/frame identity inconsistently.
- **New pattern:** `annotation_subject` unique identity index on `(asset_uuid, frame_index?, time_start_ms?, time_end_ms?)` via `COALESCE` strategy.

## What is intentionally deferred

The following are explicitly out of scope for `POL-652` and should not be backfilled into this migration:

- Geometry payload tables (bbox/polygon/mask storage)
- Provenance graph details beyond set-level source metadata
- Quality scoring policy and adjudication contracts
- Export selection/version matrix rules

These are covered by `POL-653`, `POL-654`, and `POL-655`.

## Validation checklist for downstream lanes

Before building on this foundation:

1. Confirm inserts into `annotation_set` and `annotation_subject` succeed for representative human/model/import examples.
2. Confirm duplicate `(source_name, source_version, run_id)` rows are blocked when `run_id` is populated.
3. Confirm duplicate subject identity for the same asset/frame slot is blocked.
4. Confirm nullable video fields work for still-image assets.

## File references

- DDL: `dbTools/admin/add_annotation_foundations_ddl.sql`
- Migration: `dbTools/admin/migrations/001_annotation_subject_set.sql`
- Rollback: `dbTools/admin/migrations/001_annotation_subject_set_rollback.sql`
- ORM: `models/annotation_models.py`
