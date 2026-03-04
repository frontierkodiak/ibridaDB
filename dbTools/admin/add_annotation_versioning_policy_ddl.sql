-- Migration 004: annotation versioning invariants + export-selection semantics
-- POL-655 / Schema D
-- Mirror note: keep this file byte-identical with its corresponding add/migration pair.
--
-- Purpose:
--   Finalize non-destructive lifecycle behavior and deterministic export policy
--   selection semantics across human/model/imported annotation sources.
--
-- Prerequisites:
--   - Migration 001 (annotation_set, annotation_subject)
--   - Migration 002 (annotation, annotation_geometry)
--   - Migration 003 (annotation_provenance, annotation_quality)
--
-- Safety:
--   - Non-destructive migration
--   - Insert-only supersession lineage (no overwrite required)
--   - Deterministic policy-driven export selector
--
-- Rollback:
--   See 004_annotation_versioning_policy_rollback.sql

BEGIN;

-- ============================================================================
-- annotation_supersession
-- ============================================================================
-- Explicitly records that one annotation supersedes another.
-- Old rows remain preserved; active selectors exclude superseded rows.

CREATE TABLE IF NOT EXISTS annotation_supersession (
    supersession_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    superseded_annotation_id   UUID NOT NULL REFERENCES annotation(annotation_id),
    replacement_annotation_id  UUID NOT NULL REFERENCES annotation(annotation_id),
    reason                     TEXT,
    created_by                 VARCHAR(128),
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_superseded_annotation UNIQUE (superseded_annotation_id),
    CONSTRAINT chk_supersession_distinct_ids CHECK (
        superseded_annotation_id <> replacement_annotation_id
    )
);

COMMENT ON TABLE annotation_supersession IS 'Insert-only supersession edges for annotation lineage updates (POL-655).';
COMMENT ON COLUMN annotation_supersession.superseded_annotation_id IS 'Annotation row retired from active selection (row still preserved).';
COMMENT ON COLUMN annotation_supersession.replacement_annotation_id IS 'New annotation row that supersedes the retired row.';

CREATE INDEX IF NOT EXISTS idx_supersession_replacement
    ON annotation_supersession (replacement_annotation_id);

CREATE INDEX IF NOT EXISTS idx_supersession_created_at
    ON annotation_supersession (created_at);


-- Keep lifecycle state and supersession lineage synchronized.
CREATE OR REPLACE FUNCTION sync_annotation_lifecycle_on_supersession()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE annotation
       SET lifecycle_state = 'superseded',
           updated_at = NOW()
     WHERE annotation_id = NEW.superseded_annotation_id
       AND lifecycle_state <> 'superseded';
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_lifecycle_on_supersession ON annotation_supersession;
CREATE TRIGGER trg_sync_lifecycle_on_supersession
AFTER INSERT ON annotation_supersession
FOR EACH ROW
EXECUTE FUNCTION sync_annotation_lifecycle_on_supersession();


-- ============================================================================
-- annotation_export_policy
-- ============================================================================
-- Versioned export policy registry for deterministic source-selection behavior.

CREATE TABLE IF NOT EXISTS annotation_export_policy (
    policy_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_name            VARCHAR(64) NOT NULL,
    policy_version         INTEGER     NOT NULL,
    strategy               VARCHAR(32) NOT NULL
                          CHECK (strategy IN ('human_first', 'model_first', 'hybrid')),
    min_trust_rank         INTEGER     NOT NULL DEFAULT 1
                          CHECK (min_trust_rank >= 0 AND min_trust_rank <= 3),
    allowed_source_kinds   TEXT[]      NOT NULL,
    include_conflict       BOOLEAN     NOT NULL DEFAULT FALSE,
    notes                  JSONB,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_export_policy_name_version UNIQUE (policy_name, policy_version),
    CONSTRAINT chk_export_policy_sources_nonempty CHECK (
        cardinality(allowed_source_kinds) > 0
    )
);

COMMENT ON TABLE annotation_export_policy IS 'Versioned policy matrix for deterministic annotation export selection (POL-655).';
COMMENT ON COLUMN annotation_export_policy.strategy IS 'Source ordering strategy: human_first | model_first | hybrid.';

CREATE INDEX IF NOT EXISTS idx_export_policy_lookup
    ON annotation_export_policy (policy_name, policy_version);

-- Seed baseline policy set (idempotent).
INSERT INTO annotation_export_policy (
    policy_name,
    policy_version,
    strategy,
    min_trust_rank,
    allowed_source_kinds,
    include_conflict,
    notes
)
VALUES
    (
        'human_first',
        1,
        'human_first',
        1,
        ARRAY['human', 'model', 'imported_dataset'],
        FALSE,
        '{"description":"Prefer human annotations, then imported_dataset, then model."}'::jsonb
    ),
    (
        'model_first',
        1,
        'model_first',
        2,
        ARRAY['model', 'human', 'imported_dataset'],
        FALSE,
        '{"description":"Prefer model annotations with stricter trust gate."}'::jsonb
    ),
    (
        'hybrid',
        1,
        'hybrid',
        1,
        ARRAY['human', 'model', 'imported_dataset'],
        FALSE,
        '{"description":"Blend human/model by trust rank with deterministic tie-breaks."}'::jsonb
    )
ON CONFLICT (policy_name, policy_version) DO NOTHING;


-- ============================================================================
-- Active/non-destructive selection surfaces
-- ============================================================================

CREATE OR REPLACE VIEW annotation_active_selection_v1 AS
SELECT
    a.annotation_id,
    a.subject_id,
    a.set_id,
    a.label,
    a.score,
    a.lifecycle_state,
    a.created_at
FROM annotation a
LEFT JOIN annotation_supersession s
  ON s.superseded_annotation_id = a.annotation_id
WHERE a.lifecycle_state = 'active'
  AND s.supersession_id IS NULL;

COMMENT ON VIEW annotation_active_selection_v1 IS 'Active annotation rows excluding superseded lineage edges (POL-655).';


-- ============================================================================
-- Deterministic export selector
-- ============================================================================
-- Returns one selected annotation per (subject_id, label) for a given policy.

CREATE OR REPLACE FUNCTION annotation_export_select_v1(
    in_policy_name VARCHAR DEFAULT 'human_first',
    in_policy_version INTEGER DEFAULT 1
)
RETURNS TABLE (
    policy_name VARCHAR,
    policy_version INTEGER,
    strategy VARCHAR,
    subject_id UUID,
    label VARCHAR,
    annotation_id UUID,
    source_kind VARCHAR,
    trust_rank INTEGER,
    confidence_score DOUBLE PRECISION,
    review_status VARCHAR,
    conflict_flag BOOLEAN,
    source_priority INTEGER
)
LANGUAGE sql
STABLE
AS $$
WITH selected_policy AS (
    SELECT
        p.policy_name,
        p.policy_version,
        p.strategy,
        p.min_trust_rank,
        p.allowed_source_kinds,
        p.include_conflict
    FROM annotation_export_policy p
    WHERE p.policy_name = in_policy_name
      AND p.policy_version = in_policy_version
),
candidates AS (
    SELECT
        policy.policy_name,
        policy.policy_version,
        policy.strategy,
        a.subject_id,
        a.label,
        a.annotation_id,
        prov.source_kind,
        COALESCE(ts.trust_rank, 0) AS trust_rank,
        q.confidence_score,
        COALESCE(q.review_status, 'unreviewed') AS review_status,
        COALESCE(q.conflict_flag, FALSE) AS conflict_flag,
        CASE
            WHEN policy.strategy = 'human_first' THEN
                CASE prov.source_kind
                    WHEN 'human' THEN 0
                    WHEN 'imported_dataset' THEN 1
                    WHEN 'model' THEN 2
                    ELSE 9
                END
            WHEN policy.strategy = 'model_first' THEN
                CASE prov.source_kind
                    WHEN 'model' THEN 0
                    WHEN 'human' THEN 1
                    WHEN 'imported_dataset' THEN 2
                    ELSE 9
                END
            ELSE
                CASE prov.source_kind
                    WHEN 'human' THEN 0
                    WHEN 'model' THEN 1
                    WHEN 'imported_dataset' THEN 2
                    ELSE 9
                END
        END AS source_priority
    FROM annotation_active_selection_v1 a
    JOIN annotation_provenance prov
      ON prov.annotation_id = a.annotation_id
    LEFT JOIN annotation_quality q
      ON q.annotation_id = a.annotation_id
    LEFT JOIN annotation_trusted_selection_v1 ts
      ON ts.annotation_id = a.annotation_id
    CROSS JOIN selected_policy policy
    WHERE prov.source_kind = ANY(policy.allowed_source_kinds)
      AND COALESCE(ts.trust_rank, 0) >= policy.min_trust_rank
      AND (policy.include_conflict OR COALESCE(q.conflict_flag, FALSE) = FALSE)
      AND COALESCE(q.review_status, 'unreviewed') <> 'rejected'
),
ranked AS (
    SELECT
        c.*,
        row_number() OVER (
            PARTITION BY c.subject_id, c.label
            ORDER BY
                c.source_priority ASC,
                c.trust_rank DESC,
                c.confidence_score DESC NULLS LAST,
                c.annotation_id ASC
        ) AS rn
    FROM candidates c
)
SELECT
    policy_name,
    policy_version,
    strategy,
    subject_id,
    label,
    annotation_id,
    source_kind,
    trust_rank,
    confidence_score,
    review_status,
    conflict_flag,
    source_priority
FROM ranked
WHERE rn = 1
ORDER BY subject_id, label, annotation_id;
$$;

COMMENT ON FUNCTION annotation_export_select_v1(VARCHAR, INTEGER) IS 'Deterministic policy-driven export selector for annotation rows (POL-655).';

CREATE OR REPLACE VIEW annotation_export_default_human_first_v1 AS
SELECT *
FROM annotation_export_select_v1('human_first', 1);

COMMENT ON VIEW annotation_export_default_human_first_v1 IS 'Default export selector projection using policy human_first/v1.';


-- ============================================================================
-- Non-destructive guardrail: forbid deletes on lineage tables
-- ============================================================================

CREATE OR REPLACE FUNCTION forbid_annotation_lineage_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Deletes are forbidden on % for non-destructive annotation lineage invariants',
        TG_TABLE_NAME;
END;
$$;

DROP TRIGGER IF EXISTS trg_no_delete_annotation ON annotation;
CREATE TRIGGER trg_no_delete_annotation
BEFORE DELETE ON annotation
FOR EACH ROW EXECUTE FUNCTION forbid_annotation_lineage_delete();

DROP TRIGGER IF EXISTS trg_no_delete_annotation_geometry ON annotation_geometry;
CREATE TRIGGER trg_no_delete_annotation_geometry
BEFORE DELETE ON annotation_geometry
FOR EACH ROW EXECUTE FUNCTION forbid_annotation_lineage_delete();

DROP TRIGGER IF EXISTS trg_no_delete_annotation_provenance ON annotation_provenance;
CREATE TRIGGER trg_no_delete_annotation_provenance
BEFORE DELETE ON annotation_provenance
FOR EACH ROW EXECUTE FUNCTION forbid_annotation_lineage_delete();

DROP TRIGGER IF EXISTS trg_no_delete_annotation_quality ON annotation_quality;
CREATE TRIGGER trg_no_delete_annotation_quality
BEFORE DELETE ON annotation_quality
FOR EACH ROW EXECUTE FUNCTION forbid_annotation_lineage_delete();

DROP TRIGGER IF EXISTS trg_no_delete_annotation_supersession ON annotation_supersession;
CREATE TRIGGER trg_no_delete_annotation_supersession
BEFORE DELETE ON annotation_supersession
FOR EACH ROW EXECUTE FUNCTION forbid_annotation_lineage_delete();

COMMIT;
