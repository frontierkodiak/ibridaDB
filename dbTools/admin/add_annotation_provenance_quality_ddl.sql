-- Migration 003: annotation_provenance + annotation_quality
-- POL-654 / Schema C — provenance completeness and quality/adjudication policy
--
-- Purpose:
--   Add first-class provenance + quality tables for annotation rows so
--   machine/human/imported annotations can coexist with deterministic
--   trust-selection behavior.
--
-- Prerequisites:
--   - Migration 001 (annotation_set, annotation_subject)
--   - Migration 002 (annotation, annotation_geometry)
--
-- Safety:
--   - Non-destructive (CREATE IF NOT EXISTS + view create/replace)
--   - No ALTER/DROP on existing schema A/B tables
--
-- Rollback:
--   See 003_annotation_provenance_quality_rollback.sql

BEGIN;

-- ============================================================================
-- annotation_provenance
-- ============================================================================
-- One provenance row per annotation. This captures source identity and the
-- minimum required metadata per source kind.
--
-- Source-kind requirements:
--   human:
--     - operator_identity required
--   model:
--     - model_id, config_hash, run_id required
--   imported_dataset:
--     - source_version required

CREATE TABLE IF NOT EXISTS annotation_provenance (
    provenance_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    annotation_id      UUID         NOT NULL REFERENCES annotation(annotation_id),

    source_kind        VARCHAR(32)  NOT NULL
                       CHECK (source_kind IN ('human', 'model', 'imported_dataset')),
    source_name        VARCHAR(128) NOT NULL,
    source_version     VARCHAR(64),

    model_id           VARCHAR(128),
    prompt_hash        VARCHAR(64),
    config_hash        VARCHAR(64),
    run_id             VARCHAR(128),

    operator_identity  VARCHAR(128),
    recorded_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    sidecar            JSONB,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_annotation_provenance_annotation UNIQUE (annotation_id),

    CONSTRAINT chk_provenance_prompt_hash_hex CHECK (
        prompt_hash IS NULL OR prompt_hash ~ '^[0-9a-f]{64}$'
    ),

    CONSTRAINT chk_provenance_config_hash_hex CHECK (
        config_hash IS NULL OR config_hash ~ '^[0-9a-f]{64}$'
    ),

    CONSTRAINT chk_provenance_required_by_kind CHECK (
        (source_kind = 'human' AND operator_identity IS NOT NULL)
        OR (source_kind = 'model' AND model_id IS NOT NULL AND config_hash IS NOT NULL AND run_id IS NOT NULL)
        OR (source_kind = 'imported_dataset' AND source_version IS NOT NULL)
    )
);

COMMENT ON TABLE  annotation_provenance IS 'Per-annotation provenance metadata with source-kind-specific completeness checks (POL-654).';
COMMENT ON COLUMN annotation_provenance.annotation_id     IS 'FK -> annotation.annotation_id; exactly one provenance row per annotation.';
COMMENT ON COLUMN annotation_provenance.source_kind       IS 'Source category: human | model | imported_dataset.';
COMMENT ON COLUMN annotation_provenance.source_name       IS 'Producer identifier (sam3, md3, inat2017-import, etc).';
COMMENT ON COLUMN annotation_provenance.model_id          IS 'Model identity for source_kind=model.';
COMMENT ON COLUMN annotation_provenance.prompt_hash       IS 'Deterministic prompt hash (hex SHA-256) when prompts are used.';
COMMENT ON COLUMN annotation_provenance.config_hash       IS 'Deterministic config hash (hex SHA-256). Required for source_kind=model.';
COMMENT ON COLUMN annotation_provenance.run_id            IS 'External run/build identity for replay and lineage joins.';
COMMENT ON COLUMN annotation_provenance.operator_identity IS 'Human operator identity (required for source_kind=human).';

CREATE INDEX IF NOT EXISTS idx_provenance_source
    ON annotation_provenance (source_kind, source_name, source_version);

CREATE INDEX IF NOT EXISTS idx_provenance_model
    ON annotation_provenance (model_id)
    WHERE model_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_provenance_run_id
    ON annotation_provenance (run_id)
    WHERE run_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_provenance_recorded_at
    ON annotation_provenance (recorded_at);

CREATE INDEX IF NOT EXISTS idx_provenance_sidecar
    ON annotation_provenance USING GIN (sidecar)
    WHERE sidecar IS NOT NULL;


-- ============================================================================
-- annotation_quality
-- ============================================================================
-- One quality/adjudication row per annotation.  This captures review status,
-- confidence, conflict metadata, and adjudication identity/timestamps.

CREATE TABLE IF NOT EXISTS annotation_quality (
    quality_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    annotation_id      UUID         NOT NULL REFERENCES annotation(annotation_id),

    review_status      VARCHAR(32)  NOT NULL DEFAULT 'unreviewed'
                       CHECK (review_status IN ('unreviewed', 'needs_review', 'accepted', 'rejected', 'conflict')),

    confidence_score   DOUBLE PRECISION,
    conflict_flag      BOOLEAN      NOT NULL DEFAULT FALSE,
    conflict_reason    TEXT,

    adjudicated_by     VARCHAR(128),
    adjudicated_at     TIMESTAMPTZ,
    review_notes       TEXT,

    sidecar            JSONB,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_annotation_quality_annotation UNIQUE (annotation_id),

    CONSTRAINT chk_quality_confidence_range CHECK (
        confidence_score IS NULL OR (confidence_score >= 0.0 AND confidence_score <= 1.0)
    ),

    CONSTRAINT chk_quality_adjudication_required CHECK (
        (
            review_status IN ('accepted', 'rejected', 'conflict')
            AND adjudicated_by IS NOT NULL
            AND adjudicated_at IS NOT NULL
        )
        OR (
            review_status IN ('unreviewed', 'needs_review')
        )
    ),

    CONSTRAINT chk_quality_conflict_consistency CHECK (
        (review_status = 'conflict' AND conflict_flag = TRUE)
        OR (review_status <> 'conflict' AND conflict_flag = FALSE)
    ),

    CONSTRAINT chk_quality_conflict_reason CHECK (
        conflict_flag = FALSE OR conflict_reason IS NOT NULL
    )
);

COMMENT ON TABLE  annotation_quality IS 'Per-annotation quality/review/adjudication metadata (POL-654).';
COMMENT ON COLUMN annotation_quality.review_status    IS 'Review lifecycle: unreviewed | needs_review | accepted | rejected | conflict.';
COMMENT ON COLUMN annotation_quality.confidence_score IS 'Optional quality confidence in [0,1].';
COMMENT ON COLUMN annotation_quality.conflict_flag    IS 'True when annotation has unresolved disagreement.';
COMMENT ON COLUMN annotation_quality.adjudicated_by   IS 'Operator identity required for accepted/rejected/conflict states.';
COMMENT ON COLUMN annotation_quality.adjudicated_at   IS 'Timestamp required for accepted/rejected/conflict states.';

CREATE INDEX IF NOT EXISTS idx_quality_status
    ON annotation_quality (review_status);

CREATE INDEX IF NOT EXISTS idx_quality_status_conflict
    ON annotation_quality (review_status, conflict_flag);

CREATE INDEX IF NOT EXISTS idx_quality_confidence
    ON annotation_quality (confidence_score)
    WHERE confidence_score IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_quality_adjudicated_at
    ON annotation_quality (adjudicated_at)
    WHERE adjudicated_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_quality_sidecar
    ON annotation_quality USING GIN (sidecar)
    WHERE sidecar IS NOT NULL;


-- ============================================================================
-- Trusted-selection query surface
-- ============================================================================
-- Query semantics for selecting trusted annotations across source kinds.
-- This view keeps selection policy explicit and auditable.

CREATE OR REPLACE VIEW annotation_trusted_selection_v1 AS
SELECT
    a.annotation_id,
    a.subject_id,
    a.set_id,
    a.label,
    a.score,
    a.lifecycle_state,
    p.source_kind,
    p.source_name,
    p.source_version,
    p.model_id,
    p.run_id,
    COALESCE(q.review_status, 'unreviewed') AS review_status,
    COALESCE(q.conflict_flag, FALSE) AS conflict_flag,
    q.confidence_score,
    CASE
        WHEN COALESCE(q.review_status, 'unreviewed') = 'rejected' THEN 0
        WHEN COALESCE(q.conflict_flag, FALSE) = TRUE THEN 0
        WHEN p.source_kind = 'human'
             AND COALESCE(q.review_status, 'unreviewed') IN ('accepted', 'unreviewed') THEN 3
        WHEN p.source_kind = 'model'
             AND COALESCE(q.review_status, 'unreviewed') = 'accepted'
             AND COALESCE(q.confidence_score, 0.0) >= 0.50 THEN 2
        WHEN p.source_kind = 'imported_dataset'
             AND COALESCE(q.review_status, 'unreviewed') IN ('accepted', 'unreviewed') THEN 2
        ELSE 1
    END AS trust_rank
FROM annotation a
JOIN annotation_provenance p
  ON p.annotation_id = a.annotation_id
LEFT JOIN annotation_quality q
  ON q.annotation_id = a.annotation_id
WHERE a.lifecycle_state = 'active';

COMMENT ON VIEW annotation_trusted_selection_v1 IS 'Policy view for trusted annotation selection across source kinds (POL-654).';

COMMIT;
