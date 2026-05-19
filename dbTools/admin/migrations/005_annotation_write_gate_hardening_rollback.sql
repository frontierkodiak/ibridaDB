-- Rollback for Migration 005 (POL-1423)
-- Drops the Schema E write-gate hardening surfaces in dependency-safe order.
--
-- WARNING: dropping annotation.updated_at returns the database to the known
-- pre-005 state in which the migration 004 supersession trigger references a
-- missing column.  Only run this rollback if migration 004 is also rolled
-- back or the supersession trigger is otherwise disabled.

BEGIN;

DROP TRIGGER IF EXISTS trg_annotation_quality_touch_updated_at ON annotation_quality;
DROP TRIGGER IF EXISTS trg_annotation_touch_updated_at ON annotation;
DROP FUNCTION IF EXISTS touch_updated_at();

DROP INDEX IF EXISTS idx_annotation_source_key;
DROP INDEX IF EXISTS uq_annotation_source_key;

ALTER TABLE annotation DROP COLUMN IF EXISTS source_annotation_key;
ALTER TABLE annotation_quality DROP COLUMN IF EXISTS updated_at;
ALTER TABLE annotation DROP COLUMN IF EXISTS updated_at;

COMMIT;
