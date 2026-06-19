-- Rollback for Migration 006 (POL-1784)
-- Restores the pre-006 global-only two-argument annotation export selector.
--
-- WARNING: after this rollback, callers that pass the third set_ids argument
-- to annotation_export_select_v1 will fail until migration 006 is reapplied.

BEGIN;

DROP VIEW IF EXISTS annotation_export_default_human_first_v1;
DROP FUNCTION IF EXISTS annotation_export_select_v1(VARCHAR, INTEGER, UUID[]);

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

COMMENT ON FUNCTION annotation_export_select_v1(VARCHAR, INTEGER) IS
    'Deterministic policy-driven export selector for annotation rows (POL-655).';

CREATE OR REPLACE VIEW annotation_export_default_human_first_v1 AS
SELECT *
FROM annotation_export_select_v1('human_first', 1);

COMMENT ON VIEW annotation_export_default_human_first_v1 IS 'Default export selector projection using policy human_first/v1.';

COMMIT;
