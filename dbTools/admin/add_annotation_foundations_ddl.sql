-- Migration 001: annotation_subject + annotation_set foundations
-- POL-652 / Schema A — annotation lineage identity
-- Mirror note: keep this file byte-identical with its corresponding add/migration pair.
--
-- Purpose:
--   Define the foundational relational schema for annotation lineage:
--     annotation_subject  — stable target identity (what is being annotated)
--     annotation_set      — grouping of annotations produced together (one run/batch)
--
-- Prerequisites:
--   - pgcrypto extension (for gen_random_uuid)
--   - observations table (FK target for observation_uuid)
--
-- Safety:
--   - All CREATE statements are IF NOT EXISTS.
--   - No existing table is altered or dropped.
--   - Forward-compatible: later phases (POL-653 geometry, POL-654 provenance/quality)
--     will add tables that FK into these foundations.
--
-- Rollback: see 001_annotation_subject_set_rollback.sql

BEGIN;

-- Ensure pgcrypto is available for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- annotation_set
-- ============================================================================
-- Groups annotations produced together: one human labeling batch, one model
-- inference run, or one dataset import.  Rows are immutable once created;
-- new annotation work produces a new set.
--
-- Design notes (POL-524 §6 contract):
--   source_kind + source_name + run_id uniquely identify a production run.
--   prompt_hash/config_hash enable reproducibility verification.
--   dataset/release link back to the ibridaDB release context.

CREATE TABLE IF NOT EXISTS annotation_set (
    set_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255),                               -- human-readable label
    description     TEXT,
    dataset         VARCHAR(64)  NOT NULL DEFAULT 'ibrida',     -- dataset namespace
    release         VARCHAR(16),                                -- ibridaDB release (e.g. 'r2')
    source_kind     VARCHAR(32)  NOT NULL                       -- 'human', 'model', 'imported_dataset'
                    CHECK (source_kind IN ('human', 'model', 'imported_dataset')),
    source_name     VARCHAR(128) NOT NULL,                      -- e.g. 'sam3', 'gemini', 'expert-batch-2026'
    source_version  VARCHAR(64),                                -- model/tool version
    model_id        VARCHAR(128),                               -- full model identifier
    prompt_hash     VARCHAR(64),                                -- SHA-256 of prompt template (hex)
    config_hash     VARCHAR(64),                                -- SHA-256 of run config (hex)
    run_id          VARCHAR(128),                               -- external run/batch identifier
    created_by      VARCHAR(128),                               -- operator or agent identity
    sidecar         JSONB,                                      -- extensible metadata
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_annotation_set_prompt_hash_hex CHECK (
        prompt_hash IS NULL OR prompt_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT chk_annotation_set_config_hash_hex CHECK (
        config_hash IS NULL OR config_hash ~ '^[0-9a-f]{64}$'
    )
);

COMMENT ON TABLE  annotation_set IS 'Groups annotations produced together (POL-652).';
COMMENT ON COLUMN annotation_set.set_id       IS 'Stable UUID identity for the annotation set.';
COMMENT ON COLUMN annotation_set.source_kind  IS 'Producer type: human | model | imported_dataset.';
COMMENT ON COLUMN annotation_set.source_name  IS 'Producer name, e.g. sam3, gemini, expert-batch-2026.';
COMMENT ON COLUMN annotation_set.run_id       IS 'External run/batch id for deduplication and lineage.';
COMMENT ON COLUMN annotation_set.sidecar      IS 'Extensible JSON metadata (tools, params, notes).';

-- Prevent importing the same run twice
CREATE UNIQUE INDEX IF NOT EXISTS uq_annotation_set_run
    ON annotation_set (source_name, source_version, run_id)
    WHERE run_id IS NOT NULL;

-- Lookup by dataset + release
CREATE INDEX IF NOT EXISTS idx_annotation_set_dataset_release
    ON annotation_set (dataset, release);

-- Lookup by source
CREATE INDEX IF NOT EXISTS idx_annotation_set_source
    ON annotation_set (source_kind, source_name);

-- Temporal ordering
CREATE INDEX IF NOT EXISTS idx_annotation_set_created_at
    ON annotation_set (created_at);

-- ============================================================================
-- annotation_subject
-- ============================================================================
-- Stable identity for the target of annotation: "what is being annotated."
--
-- A subject always references an asset (image/video frame).  Optionally
-- links to an observation (when the asset comes from iNat/ibridaDB) and
-- a frame/time range (for video assets).
--
-- Design notes:
--   asset_uuid is intentionally NOT a FK to photos or media — it must
--   work for both iNat photo_uuids and non-iNat media items.  Downstream
--   consumers resolve asset_uuid through media catalog or photos table
--   as appropriate.
--
--   The uniqueness constraint ensures one subject row per distinct
--   asset + frame combination.

CREATE TABLE IF NOT EXISTS annotation_subject (
    subject_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_uuid      UUID         NOT NULL,                      -- photo_uuid or external media UUID
    observation_uuid UUID REFERENCES observations(observation_uuid) ON DELETE SET NULL,
    frame_index     INTEGER,                                    -- optional: video frame number
    time_start_ms   INTEGER,                                    -- optional: video segment start (ms)
    time_end_ms     INTEGER,                                    -- optional: video segment end (ms)
    asset_width_px  INTEGER,                                    -- original asset width (for coord normalization)
    asset_height_px INTEGER,                                    -- original asset height (for coord normalization)
    sidecar         JSONB,                                      -- extensible metadata
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- Time range sanity
    CONSTRAINT chk_time_range CHECK (
        time_end_ms IS NULL OR time_start_ms IS NULL OR time_end_ms >= time_start_ms
    ),
    -- Frame index non-negative
    CONSTRAINT chk_frame_index CHECK (frame_index IS NULL OR frame_index >= 0),
    -- Dimensions positive
    CONSTRAINT chk_dimensions CHECK (
        (asset_width_px IS NULL OR asset_width_px > 0) AND
        (asset_height_px IS NULL OR asset_height_px > 0)
    )
);

COMMENT ON TABLE  annotation_subject IS 'Stable annotation target identity (POL-652).';
COMMENT ON COLUMN annotation_subject.subject_id      IS 'Stable UUID for this annotation subject.';
COMMENT ON COLUMN annotation_subject.asset_uuid      IS 'Asset UUID — photo_uuid or external media UUID.';
COMMENT ON COLUMN annotation_subject.observation_uuid IS 'Optional link to ibridaDB observation.';
COMMENT ON COLUMN annotation_subject.frame_index     IS 'Video frame index (NULL for still images).';
COMMENT ON COLUMN annotation_subject.asset_width_px  IS 'Asset width in pixels (for coordinate normalization).';
COMMENT ON COLUMN annotation_subject.asset_height_px IS 'Asset height in pixels (for coordinate normalization).';

-- Uniqueness: one subject per asset + frame combination
-- Uses COALESCE to handle NULLs in the unique constraint
CREATE UNIQUE INDEX IF NOT EXISTS uq_annotation_subject_asset_frame
    ON annotation_subject (
        asset_uuid,
        COALESCE(frame_index, -1),
        COALESCE(time_start_ms, -1),
        COALESCE(time_end_ms, -1)
    );

-- Fast lookups
CREATE INDEX IF NOT EXISTS idx_annotation_subject_asset
    ON annotation_subject (asset_uuid);

CREATE INDEX IF NOT EXISTS idx_annotation_subject_observation
    ON annotation_subject (observation_uuid)
    WHERE observation_uuid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_annotation_subject_created_at
    ON annotation_subject (created_at);

-- GIN index on sidecar for metadata queries
CREATE INDEX IF NOT EXISTS idx_annotation_subject_sidecar
    ON annotation_subject USING GIN (sidecar)
    WHERE sidecar IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_annotation_set_sidecar
    ON annotation_set USING GIN (sidecar)
    WHERE sidecar IS NOT NULL;

COMMIT;
