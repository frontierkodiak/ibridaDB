# Annotation Lineage Migration Notes (POL-652 / POL-653 / POL-654 / POL-655)

This note explains how existing assumptions map onto the initial annotation-lineage layers:

- `annotation_set`
- `annotation_subject`
- `annotation`
- `annotation_geometry`
- `annotation_provenance`
- `annotation_quality`
- `annotation_supersession`
- `annotation_export_policy`

`POL-652` delivers identity scaffolding; `POL-653` adds representational geometry; `POL-654` adds provenance and quality policy surfaces; `POL-655` finalizes insert-only versioning and deterministic export-selection semantics.

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

## 5. Geometry representation (added in POL-653)

`POL-653` adds two surfaces:

- `annotation`: one row per annotation instance (label, score, lifecycle).
- `annotation_geometry`: one row per geometry payload with discriminator `bbox|polygon|mask|point`.

Core guarantees from Schema B:

- Geometry is non-lossy across bbox/polygon/mask/point.
- Coordinate assumptions are explicit: normalized `[0,1]` with top-left origin.
- Geometry-kind-specific completeness checks are enforced in DB constraints.

## 6. Provenance + quality policy (added in POL-654)

`POL-654` adds two policy surfaces:

- `annotation_provenance`: source-kind-specific completeness checks (`human`, `model`, `imported_dataset`).
- `annotation_quality`: review lifecycle, conflict metadata, adjudication identity/timestamps.

Core guarantees from Schema C:

- Model-generated annotations require provenance completeness (`model_id`, `config_hash`, `run_id`).
- Human annotations require operator identity.
- Adjudicated states (`accepted`, `rejected`, `conflict`) require adjudicator identity and timestamp.
- Trusted-selection semantics are explicit via `annotation_trusted_selection_v1`.

## 7. Versioning + export selection invariants (added in POL-655)

`POL-655` adds two final control surfaces:

- `annotation_supersession`: insert-only replacement edges so updates do not require destructive overwrite.
- `annotation_export_policy`: versioned policy matrix (`human_first`, `model_first`, `hybrid`) for deterministic selection.

Core guarantees from Schema D:

- Active selectors exclude superseded rows via `annotation_active_selection_v1`.
- Export selection is deterministic and policy-driven via `annotation_export_select_v1(policy_name, policy_version)`.
- Delete operations are guarded on annotation-lineage tables to reinforce non-destructive history preservation.

## What is intentionally deferred

No remaining annotation-lineage schema rules are deferred after `POL-655`; downstream work should consume these invariants rather than re-derive policy ad hoc.

## Validation checklist for downstream lanes

Before building on this foundation:

1. Confirm inserts into `annotation_set` and `annotation_subject` succeed for representative human/model/import examples.
2. Confirm duplicate `(source_name, source_version, run_id)` rows are blocked when `run_id` is populated.
3. Confirm duplicate subject identity for the same asset/frame slot is blocked.
4. Confirm nullable video fields work for still-image assets.
5. Confirm representative bbox/polygon/mask inserts pass on Schema B (`002_annotation_geometry_verify.sql`).
6. Confirm source-kind completeness + adjudication constraints pass on Schema C (`003_annotation_provenance_quality_verify.sql`).
7. Confirm supersession + policy-driven selection invariants pass on Schema D (`004_annotation_versioning_policy_verify.sql`).

## File references

- DDL (Schema A): `dbTools/admin/add_annotation_foundations_ddl.sql`
- DDL (Schema B): `dbTools/admin/add_annotation_geometry_ddl.sql`
- Migration: `dbTools/admin/migrations/001_annotation_subject_set.sql`
- Rollback: `dbTools/admin/migrations/001_annotation_subject_set_rollback.sql`
- Migration: `dbTools/admin/migrations/002_annotation_geometry.sql`
- Rollback: `dbTools/admin/migrations/002_annotation_geometry_rollback.sql`
- Verification inserts: `dbTools/admin/migrations/002_annotation_geometry_verify.sql`
- DDL (Schema C): `dbTools/admin/add_annotation_provenance_quality_ddl.sql`
- Migration: `dbTools/admin/migrations/003_annotation_provenance_quality.sql`
- Rollback: `dbTools/admin/migrations/003_annotation_provenance_quality_rollback.sql`
- Verification inserts: `dbTools/admin/migrations/003_annotation_provenance_quality_verify.sql`
- DDL (Schema D): `dbTools/admin/add_annotation_versioning_policy_ddl.sql`
- Migration: `dbTools/admin/migrations/004_annotation_versioning_policy.sql`
- Rollback: `dbTools/admin/migrations/004_annotation_versioning_policy_rollback.sql`
- Verification inserts: `dbTools/admin/migrations/004_annotation_versioning_policy_verify.sql`
- ORM: `models/annotation_models.py` (Schema A + Schema B + Schema C + Schema D)
