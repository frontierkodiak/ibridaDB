-- Migration 002: annotation + annotation_geometry
-- POL-653 / Schema B — annotation core rows and geometry representation
--
-- Purpose:
--   Define canonical annotation rows with label/score/lifecycle, and
--   a discriminated geometry table supporting bbox, polygon, mask, and
--   point representations without lossy coercion.
--
-- Prerequisites:
--   - Migration 001 (annotation_set, annotation_subject) applied.
--   - pgcrypto extension available.
--
-- Coordinate contract:
--   Canonical coordinates are normalized [0, 1] × [0, 1] relative to the
--   asset dimensions stored in annotation_subject (asset_width_px, asset_height_px).
--   Origin is top-left; x increases rightward, y increases downward.
--   Pixel-space bbox columns are optional denormalized convenience fields.
--
-- Safety:
--   - All CREATE statements use IF NOT EXISTS.
--   - No existing table is altered or dropped.
--   - Forward-compatible: POL-654 (provenance/quality) and POL-655 (export)
--     will add tables that FK into these.
--
-- Rollback: see 002_annotation_geometry_rollback.sql

BEGIN;

-- ============================================================================
-- annotation
-- ============================================================================
-- Core annotation row: one row per localization instance (detection, label,
-- or human annotation).  Links a subject (what) to a set (who/when/how)
-- with label, confidence, and lifecycle metadata.
--
-- Design notes:
--   - label is a free-text class name; label_id provides optional numeric
--     mapping to a vocabulary.
--   - taxon_id links to ibridaDB taxonomy when the label maps to a taxon.
--   - lifecycle_state enables soft versioning: 'active' annotations are
--     current; 'superseded' marks replaced annotations; 'retracted' marks
--     withdrawn annotations.  Hard deletes are discouraged.
--   - is_primary flags the preferred annotation when multiple exist for
--     the same subject.

CREATE TABLE IF NOT EXISTS annotation (
    annotation_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id      UUID         NOT NULL REFERENCES annotation_subject(subject_id),
    set_id          UUID         NOT NULL REFERENCES annotation_set(set_id),

    -- Label / classification
    label           VARCHAR(255) NOT NULL,                      -- class label
    label_id        INTEGER,                                    -- optional numeric label mapping
    taxon_id        INTEGER,                                    -- optional: ibridaDB taxon link

    -- Confidence
    score           DOUBLE PRECISION,                           -- model confidence [0, 1]

    -- Lifecycle
    is_primary      BOOLEAN      NOT NULL DEFAULT FALSE,
    lifecycle_state VARCHAR(32)  NOT NULL DEFAULT 'active'
                    CHECK (lifecycle_state IN ('active', 'superseded', 'retracted')),

    sidecar         JSONB,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- Score must be in [0, 1] when present
    CONSTRAINT chk_annotation_score CHECK (
        score IS NULL OR (score >= 0.0 AND score <= 1.0)
    )
);

COMMENT ON TABLE  annotation IS 'Core annotation row — one per localization/label instance (POL-653).';
COMMENT ON COLUMN annotation.annotation_id   IS 'Stable UUID identity for this annotation.';
COMMENT ON COLUMN annotation.subject_id      IS 'FK → annotation_subject: what is being annotated.';
COMMENT ON COLUMN annotation.set_id          IS 'FK → annotation_set: which production run/batch.';
COMMENT ON COLUMN annotation.label           IS 'Human-readable class label (e.g. pollinator, Apis mellifera).';
COMMENT ON COLUMN annotation.label_id        IS 'Optional numeric label ID for vocabulary mapping.';
COMMENT ON COLUMN annotation.taxon_id        IS 'Optional link to ibridaDB expanded_taxa.taxonID.';
COMMENT ON COLUMN annotation.score           IS 'Model confidence in [0, 1]; NULL for human annotations.';
COMMENT ON COLUMN annotation.is_primary      IS 'TRUE if this is the preferred annotation for this subject.';
COMMENT ON COLUMN annotation.lifecycle_state IS 'Annotation lifecycle: active | superseded | retracted.';
COMMENT ON COLUMN annotation.sidecar         IS 'Extensible JSON metadata (tool params, review notes).';

-- Composite: all annotations for a subject within a set
CREATE INDEX IF NOT EXISTS idx_annotation_subject_set
    ON annotation (subject_id, set_id);

-- All annotations in a set
CREATE INDEX IF NOT EXISTS idx_annotation_set_id
    ON annotation (set_id);

-- Filter by label
CREATE INDEX IF NOT EXISTS idx_annotation_label
    ON annotation (label);

-- Taxonomy join (partial — only when taxon_id is populated)
CREATE INDEX IF NOT EXISTS idx_annotation_taxon
    ON annotation (taxon_id)
    WHERE taxon_id IS NOT NULL;

-- Active annotations only (most common query pattern)
CREATE INDEX IF NOT EXISTS idx_annotation_active
    ON annotation (subject_id)
    WHERE lifecycle_state = 'active';

-- Temporal ordering
CREATE INDEX IF NOT EXISTS idx_annotation_created_at
    ON annotation (created_at);

-- GIN index on sidecar for metadata queries
CREATE INDEX IF NOT EXISTS idx_annotation_sidecar
    ON annotation USING GIN (sidecar)
    WHERE sidecar IS NOT NULL;


-- ============================================================================
-- annotation_geometry
-- ============================================================================
-- Discriminated geometry table: each row stores one spatial representation
-- for an annotation.  The geometry_kind column selects which column group
-- is populated.  An annotation may have multiple geometries (e.g. a bbox
-- AND a segmentation mask for the same detection).
--
-- Coordinate contract:
--   All spatial values use normalized coordinates [0, 1] relative to
--   annotation_subject.asset_width_px / asset_height_px.
--   Origin = top-left; x = rightward; y = downward.
--
--   Optional pixel-space bbox columns (bbox_*_px) are denormalized
--   convenience fields computed as: pixel = normalized × asset_dimension.
--
-- Geometry kinds:
--   bbox    — axis-aligned bounding box (x_min, y_min, x_max, y_max)
--   polygon — ordered vertex ring as JSONB array [[x, y], ...]
--   mask    — binary segmentation mask via RLE or external URI
--   point   — single keypoint (x, y)

CREATE TABLE IF NOT EXISTS annotation_geometry (
    geometry_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    annotation_id   UUID         NOT NULL REFERENCES annotation(annotation_id),

    -- Discriminator
    geometry_kind   VARCHAR(16)  NOT NULL
                    CHECK (geometry_kind IN ('bbox', 'polygon', 'mask', 'point')),

    -- ---- Bounding box (normalized [0, 1]) ----
    -- Populated for geometry_kind = 'bbox'.
    -- Also populated as the enclosing bbox for polygon/mask geometries.
    bbox_x_min      DOUBLE PRECISION,
    bbox_y_min      DOUBLE PRECISION,
    bbox_x_max      DOUBLE PRECISION,
    bbox_y_max      DOUBLE PRECISION,

    -- ---- Pixel-space bounding box (denormalized convenience) ----
    bbox_x_min_px   INTEGER,
    bbox_y_min_px   INTEGER,
    bbox_x_max_px   INTEGER,
    bbox_y_max_px   INTEGER,

    -- ---- Polygon ----
    -- Ordered vertex ring: [[x1, y1], [x2, y2], ...] in normalized coords.
    -- First and last vertex need not be identical (implicit close).
    -- Populated for geometry_kind = 'polygon'.
    polygon_vertices JSONB,

    -- ---- Mask ----
    -- Binary segmentation mask.  Exactly one of mask_rle or mask_uri must
    -- be populated when geometry_kind = 'mask'.
    -- mask_rle: COCO-style RLE object {"counts": [...], "size": [h, w]}
    -- mask_uri: external URI (e.g. s3://bucket/masks/abc.png)
    mask_rle        JSONB,
    mask_uri        TEXT,
    mask_format     VARCHAR(32),                                -- 'coco_rle', 'png_uri', 'b64_png'

    -- ---- Point ----
    -- Single keypoint in normalized coords.
    -- Populated for geometry_kind = 'point'.
    point_x         DOUBLE PRECISION,
    point_y         DOUBLE PRECISION,

    sidecar         JSONB,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- ---- Validation constraints ----

    -- Bbox ordering: min < max (when all four bbox columns are present)
    CONSTRAINT chk_bbox_ordering CHECK (
        bbox_x_min IS NULL OR bbox_x_max IS NULL
        OR (bbox_x_min < bbox_x_max AND bbox_y_min < bbox_y_max)
    ),

    -- Normalized bbox bounds: [0, 1] (when present)
    CONSTRAINT chk_bbox_normalized CHECK (
        bbox_x_min IS NULL OR (
            bbox_x_min >= 0.0 AND bbox_x_min <= 1.0
            AND bbox_y_min >= 0.0 AND bbox_y_min <= 1.0
            AND bbox_x_max >= 0.0 AND bbox_x_max <= 1.0
            AND bbox_y_max >= 0.0 AND bbox_y_max <= 1.0
        )
    ),

    -- Pixel bbox non-negative (when present)
    CONSTRAINT chk_bbox_px_nonneg CHECK (
        bbox_x_min_px IS NULL OR (
            bbox_x_min_px >= 0 AND bbox_y_min_px >= 0
            AND bbox_x_max_px >= 0 AND bbox_y_max_px >= 0
        )
    ),

    -- Point normalized bounds: [0, 1] (when present)
    CONSTRAINT chk_point_normalized CHECK (
        point_x IS NULL OR (
            point_x >= 0.0 AND point_x <= 1.0
            AND point_y >= 0.0 AND point_y <= 1.0
        )
    ),

    -- Mask: at least one of rle or uri when kind is mask
    CONSTRAINT chk_mask_payload CHECK (
        geometry_kind != 'mask'
        OR mask_rle IS NOT NULL
        OR mask_uri IS NOT NULL
    ),

    -- Bbox: all four bbox columns populated when kind is bbox
    CONSTRAINT chk_bbox_complete CHECK (
        geometry_kind != 'bbox'
        OR (bbox_x_min IS NOT NULL AND bbox_y_min IS NOT NULL
            AND bbox_x_max IS NOT NULL AND bbox_y_max IS NOT NULL)
    ),

    -- Point: both coordinates populated when kind is point
    CONSTRAINT chk_point_complete CHECK (
        geometry_kind != 'point'
        OR (point_x IS NOT NULL AND point_y IS NOT NULL)
    ),

    -- Polygon: vertices populated when kind is polygon
    CONSTRAINT chk_polygon_complete CHECK (
        geometry_kind != 'polygon'
        OR polygon_vertices IS NOT NULL
    )
);

COMMENT ON TABLE  annotation_geometry IS 'Discriminated geometry for annotations — bbox/polygon/mask/point (POL-653).';
COMMENT ON COLUMN annotation_geometry.geometry_id      IS 'Stable UUID for this geometry row.';
COMMENT ON COLUMN annotation_geometry.annotation_id    IS 'FK → annotation: which annotation this geometry belongs to.';
COMMENT ON COLUMN annotation_geometry.geometry_kind    IS 'Geometry type: bbox | polygon | mask | point.';
COMMENT ON COLUMN annotation_geometry.bbox_x_min       IS 'Normalized [0,1] bounding box left edge.';
COMMENT ON COLUMN annotation_geometry.bbox_y_min       IS 'Normalized [0,1] bounding box top edge.';
COMMENT ON COLUMN annotation_geometry.bbox_x_max       IS 'Normalized [0,1] bounding box right edge.';
COMMENT ON COLUMN annotation_geometry.bbox_y_max       IS 'Normalized [0,1] bounding box bottom edge.';
COMMENT ON COLUMN annotation_geometry.bbox_x_min_px    IS 'Pixel-space bbox left (denormalized convenience).';
COMMENT ON COLUMN annotation_geometry.polygon_vertices IS 'JSONB vertex ring: [[x1,y1], [x2,y2], ...] in normalized coords.';
COMMENT ON COLUMN annotation_geometry.mask_rle         IS 'COCO-style RLE: {"counts": [...], "size": [h, w]}.';
COMMENT ON COLUMN annotation_geometry.mask_uri         IS 'External mask URI (e.g. s3://bucket/masks/abc.png).';
COMMENT ON COLUMN annotation_geometry.mask_format      IS 'Mask encoding format: coco_rle | png_uri | b64_png.';
COMMENT ON COLUMN annotation_geometry.point_x          IS 'Normalized [0,1] keypoint x coordinate.';
COMMENT ON COLUMN annotation_geometry.point_y          IS 'Normalized [0,1] keypoint y coordinate.';

-- All geometries for an annotation
CREATE INDEX IF NOT EXISTS idx_geometry_annotation
    ON annotation_geometry (annotation_id);

-- Filter by geometry kind
CREATE INDEX IF NOT EXISTS idx_geometry_kind
    ON annotation_geometry (geometry_kind);

-- Composite: annotation + kind (common query: "get all bboxes for annotation X")
CREATE INDEX IF NOT EXISTS idx_geometry_annotation_kind
    ON annotation_geometry (annotation_id, geometry_kind);

-- Temporal ordering
CREATE INDEX IF NOT EXISTS idx_geometry_created_at
    ON annotation_geometry (created_at);

-- GIN index on sidecar
CREATE INDEX IF NOT EXISTS idx_geometry_sidecar
    ON annotation_geometry USING GIN (sidecar)
    WHERE sidecar IS NOT NULL;

-- GIN index on polygon_vertices for containment queries
CREATE INDEX IF NOT EXISTS idx_geometry_polygon_vertices
    ON annotation_geometry USING GIN (polygon_vertices)
    WHERE polygon_vertices IS NOT NULL;

-- GIN index on mask_rle for metadata queries
CREATE INDEX IF NOT EXISTS idx_geometry_mask_rle
    ON annotation_geometry USING GIN (mask_rle)
    WHERE mask_rle IS NOT NULL;

COMMIT;
