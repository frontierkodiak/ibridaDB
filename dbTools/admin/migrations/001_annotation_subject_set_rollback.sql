-- Rollback for migration 001: annotation_subject + annotation_set foundations
-- POL-652 / Schema A
--
-- Drops all objects created by 001_annotation_subject_set.sql.
-- Safe to run if objects do not exist (IF EXISTS on all statements).
--
-- WARNING: This will destroy all annotation_subject and annotation_set data.
-- Only use on dev/isolated databases.

BEGIN;

-- Drop indexes first (they are dropped with the tables, but explicit for clarity)
DROP INDEX IF EXISTS idx_annotation_set_sidecar;
DROP INDEX IF EXISTS idx_annotation_subject_sidecar;
DROP INDEX IF EXISTS idx_annotation_subject_created_at;
DROP INDEX IF EXISTS idx_annotation_subject_observation;
DROP INDEX IF EXISTS idx_annotation_subject_asset;
DROP INDEX IF EXISTS uq_annotation_subject_asset_frame;
DROP INDEX IF EXISTS idx_annotation_set_created_at;
DROP INDEX IF EXISTS idx_annotation_set_source;
DROP INDEX IF EXISTS idx_annotation_set_dataset_release;
DROP INDEX IF EXISTS uq_annotation_set_run;

-- Drop tables
DROP TABLE IF EXISTS annotation_subject;
DROP TABLE IF EXISTS annotation_set;

-- Note: We do NOT drop pgcrypto — it may be used by other tables.

COMMIT;
