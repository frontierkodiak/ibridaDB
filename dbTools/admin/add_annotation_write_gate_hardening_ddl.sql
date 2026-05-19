-- Migration 005: annotation write-gate hardening
-- POL-1423 / Schema E — updated_at lifecycle columns + typed idempotency key
-- Mirror note: keep this file byte-identical with its corresponding add/migration pair.
--
-- Purpose:
--   Close the typed annotation write/readback gate by adding the lifecycle
--   and idempotency surfaces the live typed writer depends on:
--     - annotation.updated_at            — lifecycle audit timestamp
--     - annotation_quality.updated_at    — mutable review-surface audit timestamp
--     - annotation.source_annotation_key — deterministic per-set idempotency key
--   It installs a generic touch_updated_at() trigger so writers do not have to
--   remember to maintain updated_at, and a per-set partial unique index so
--   duplicate source annotation keys are rejected deterministically.
--
-- Context:
--   Migration 004 already installs sync_annotation_lifecycle_on_supersession(),
--   which sets annotation.updated_at, but the updated_at column was never
--   created.  Any supersession insert therefore fails against a missing
--   column.  This migration adds the column so the supersession trigger stops
--   referencing a non-existent column while preserving its retraction/
--   supersession semantics unchanged.
--
-- Prerequisites:
--   - Migration 001 (annotation_set, annotation_subject)
--   - Migration 002 (annotation, annotation_geometry)
--   - Migration 003 (annotation_provenance, annotation_quality)
--   - Migration 004 (annotation_supersession, annotation_export_policy)
--
-- Safety:
--   - Idempotent: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
--     DROP TRIGGER IF EXISTS + CREATE TRIGGER, CREATE [UNIQUE] INDEX IF NOT EXISTS.
--   - Non-destructive: no column, table, or row is dropped.
--   - The annotation-lineage tables are empty on the target DB; backfilling
--     updated_at with NOW() for any pre-existing rows is acceptable.
--
-- Rollback: see 005_annotation_write_gate_hardening_rollback.sql
-- Verification: see 005_annotation_write_gate_hardening_verify.sql

BEGIN;

-- ============================================================================
-- annotation.updated_at — lifecycle audit timestamp
-- ============================================================================
-- created_at records when a candidate annotation was born; updated_at records
-- when its active/superseded/retracted lifecycle state last changed.  This is
-- also the column the migration 004 supersession trigger already expects.

ALTER TABLE annotation
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

COMMENT ON COLUMN annotation.updated_at IS
    'Lifecycle audit timestamp; maintained by trg_annotation_touch_updated_at and by the supersession trigger (POL-1423).';

-- ============================================================================
-- annotation_quality.updated_at — mutable review-surface audit timestamp
-- ============================================================================
-- annotation_quality is intentionally mutable (review status, notes,
-- confidence, conflict state, adjudication).  updated_at records when the
-- review surface last changed.  annotation_provenance stays immutable and is
-- deliberately not given an updated_at column.

ALTER TABLE annotation_quality
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

COMMENT ON COLUMN annotation_quality.updated_at IS
    'Review-surface audit timestamp; maintained by trg_annotation_quality_touch_updated_at (POL-1423).';

-- ============================================================================
-- annotation.source_annotation_key — typed per-set idempotency key
-- ============================================================================
-- Deterministic key identifying an annotation within its set for typed
-- idempotency and duplicate-import detection.  For imported_dataset rows this
-- is the upstream record identity (e.g. COCO annotation id plus split); for
-- model rows it is a deterministic candidate hash over asset uuid, prompt/
-- config fingerprint, normalized geometry, and label.  NULL is permitted for
-- sets that do not carry a stable upstream key.

ALTER TABLE annotation
    ADD COLUMN IF NOT EXISTS source_annotation_key VARCHAR(255);

COMMENT ON COLUMN annotation.source_annotation_key IS
    'Deterministic upstream/candidate key for typed idempotency and duplicate-import detection; unique within set_id (POL-1423).';

-- Duplicate source annotation keys are rejected within a set.  The index is
-- scoped to (set_id, source_annotation_key) so unrelated annotation sets are
-- never blocked, and NULL keys are exempt via the partial predicate.
CREATE UNIQUE INDEX IF NOT EXISTS uq_annotation_source_key
    ON annotation (set_id, source_annotation_key)
    WHERE source_annotation_key IS NOT NULL;

-- Lookup by key alone (cross-set provenance tracing / duplicate diagnosis).
CREATE INDEX IF NOT EXISTS idx_annotation_source_key
    ON annotation (source_annotation_key)
    WHERE source_annotation_key IS NOT NULL;

-- ============================================================================
-- touch_updated_at() — generic updated_at maintenance trigger
-- ============================================================================
-- A single BEFORE UPDATE trigger function shared by every table that carries
-- an updated_at column.  Writers never have to set updated_at by hand.

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION touch_updated_at() IS
    'BEFORE UPDATE trigger function: refresh updated_at on every row update (POL-1423).';

DROP TRIGGER IF EXISTS trg_annotation_touch_updated_at ON annotation;
CREATE TRIGGER trg_annotation_touch_updated_at
BEFORE UPDATE ON annotation
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS trg_annotation_quality_touch_updated_at ON annotation_quality;
CREATE TRIGGER trg_annotation_quality_touch_updated_at
BEFORE UPDATE ON annotation_quality
FOR EACH ROW
EXECUTE FUNCTION touch_updated_at();

COMMIT;
