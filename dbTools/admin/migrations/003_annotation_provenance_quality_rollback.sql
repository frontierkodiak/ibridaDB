-- Rollback for Migration 003 (POL-654)
-- Drops Schema C surfaces in dependency-safe order.

BEGIN;

DROP TRIGGER IF EXISTS trg_annotation_require_provenance ON annotation;
DROP FUNCTION IF EXISTS enforce_annotation_provenance_exists();

DROP VIEW IF EXISTS annotation_trusted_selection_v1;
DROP TABLE IF EXISTS annotation_quality;
DROP TABLE IF EXISTS annotation_provenance;

COMMIT;
