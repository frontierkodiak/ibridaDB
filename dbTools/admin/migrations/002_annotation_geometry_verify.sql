-- Verification script for Migration 002 (POL-653)
--
-- Purpose:
--   Exercise representative inserts for bbox/polygon/mask geometry kinds and
--   confirm core constraints accept valid payloads.
--
-- Usage:
--   psql -U postgres -d <db_name> -f dbTools/admin/migrations/002_annotation_geometry_verify.sql
--
-- Safety:
--   Runs in a transaction and ends with ROLLBACK (no persistent rows).

BEGIN;

-- Seed one annotation_set + annotation_subject for verification rows.
WITH seeded_set AS (
    INSERT INTO annotation_set (
        dataset,
        release,
        source_kind,
        source_name,
        source_version,
        run_id
    )
    VALUES (
        'verify',
        'r2',
        'model',
        'pol-653-verify',
        'v1',
        'verify-run-002'
    )
    RETURNING set_id
),
seeded_subject AS (
    INSERT INTO annotation_subject (
        asset_uuid,
        observation_uuid,
        frame_index,
        time_start_ms,
        time_end_ms,
        asset_width_px,
        asset_height_px
    )
    VALUES (
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
        10,
        1000,
        1200,
        1920,
        1080
    )
    RETURNING subject_id
),
seeded_annotation AS (
    INSERT INTO annotation (
        subject_id,
        set_id,
        label,
        score,
        is_primary,
        lifecycle_state
    )
    SELECT
        seeded_subject.subject_id,
        seeded_set.set_id,
        'apis_mellifera',
        0.91,
        TRUE,
        'active'
    FROM seeded_set, seeded_subject
    RETURNING annotation_id
)
-- bbox geometry
INSERT INTO annotation_geometry (
    annotation_id,
    geometry_kind,
    bbox_x_min,
    bbox_y_min,
    bbox_x_max,
    bbox_y_max,
    bbox_x_min_px,
    bbox_y_min_px,
    bbox_x_max_px,
    bbox_y_max_px
)
SELECT
    annotation_id,
    'bbox',
    0.10,
    0.20,
    0.40,
    0.55,
    192,
    216,
    768,
    594
FROM seeded_annotation;

WITH seeded_annotation AS (
    SELECT annotation_id
    FROM annotation
    ORDER BY created_at DESC
    LIMIT 1
)
-- polygon geometry
INSERT INTO annotation_geometry (
    annotation_id,
    geometry_kind,
    polygon_vertices,
    bbox_x_min,
    bbox_y_min,
    bbox_x_max,
    bbox_y_max
)
SELECT
    annotation_id,
    'polygon',
    '[ [0.15, 0.22], [0.33, 0.21], [0.36, 0.48], [0.18, 0.50] ]'::jsonb,
    0.15,
    0.21,
    0.36,
    0.50
FROM seeded_annotation;

WITH seeded_annotation AS (
    SELECT annotation_id
    FROM annotation
    ORDER BY created_at DESC
    LIMIT 1
)
-- mask geometry (RLE-backed)
INSERT INTO annotation_geometry (
    annotation_id,
    geometry_kind,
    mask_rle,
    mask_format,
    bbox_x_min,
    bbox_y_min,
    bbox_x_max,
    bbox_y_max
)
SELECT
    annotation_id,
    'mask',
    '{"counts":"eJz....","size":[1080,1920]}'::jsonb,
    'coco_rle',
    0.12,
    0.18,
    0.41,
    0.57
FROM seeded_annotation;

-- Quick sanity summaries.
SELECT geometry_kind, COUNT(*) AS n
FROM annotation_geometry
GROUP BY geometry_kind
ORDER BY geometry_kind;

SELECT COUNT(*) AS annotation_rows
FROM annotation;

-- Non-destructive verification.
ROLLBACK;
