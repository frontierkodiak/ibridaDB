-- Rollback for Migration 002: annotation + annotation_geometry
-- POL-653 / Schema B
--
-- Drops annotation_geometry first (FK dependency), then annotation.
-- Does NOT drop annotation_set or annotation_subject (owned by POL-652).

BEGIN;

-- Drop annotation_geometry indexes explicitly for clarity
DROP INDEX IF EXISTS idx_geometry_mask_rle;
DROP INDEX IF EXISTS idx_geometry_polygon_vertices;
DROP INDEX IF EXISTS idx_geometry_sidecar;
DROP INDEX IF EXISTS idx_geometry_created_at;
DROP INDEX IF EXISTS idx_geometry_annotation_kind;
DROP INDEX IF EXISTS idx_geometry_kind;
DROP INDEX IF EXISTS idx_geometry_annotation;

DROP TABLE IF EXISTS annotation_geometry;

-- Drop annotation indexes
DROP INDEX IF EXISTS idx_annotation_sidecar;
DROP INDEX IF EXISTS idx_annotation_created_at;
DROP INDEX IF EXISTS idx_annotation_active;
DROP INDEX IF EXISTS idx_annotation_taxon;
DROP INDEX IF EXISTS idx_annotation_label;
DROP INDEX IF EXISTS idx_annotation_set_id;
DROP INDEX IF EXISTS idx_annotation_subject_set;

DROP TABLE IF EXISTS annotation;

COMMIT;
