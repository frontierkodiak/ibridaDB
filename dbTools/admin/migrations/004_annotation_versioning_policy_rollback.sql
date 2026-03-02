-- Rollback for Migration 004 (POL-655)

BEGIN;

DROP TRIGGER IF EXISTS trg_no_delete_annotation_supersession ON annotation_supersession;
DROP TRIGGER IF EXISTS trg_no_delete_annotation_quality ON annotation_quality;
DROP TRIGGER IF EXISTS trg_no_delete_annotation_provenance ON annotation_provenance;
DROP TRIGGER IF EXISTS trg_no_delete_annotation_geometry ON annotation_geometry;
DROP TRIGGER IF EXISTS trg_no_delete_annotation ON annotation;

DROP FUNCTION IF EXISTS forbid_annotation_lineage_delete();

DROP VIEW IF EXISTS annotation_export_default_human_first_v1;
DROP FUNCTION IF EXISTS annotation_export_select_v1(VARCHAR, INTEGER);
DROP VIEW IF EXISTS annotation_active_selection_v1;

DROP TABLE IF EXISTS annotation_export_policy;
DROP TABLE IF EXISTS annotation_supersession;

COMMIT;
