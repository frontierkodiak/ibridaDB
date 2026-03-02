-- Rollback for Migration 003 (POL-654)
-- Drops Schema C surfaces in dependency-safe order.

BEGIN;

DROP VIEW IF EXISTS annotation_trusted_selection_v1;
DROP TABLE IF EXISTS annotation_quality;
DROP TABLE IF EXISTS annotation_provenance;

COMMIT;
