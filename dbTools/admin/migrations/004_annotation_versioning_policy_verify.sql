-- Verification script for Migration 004 (POL-655)
--
-- Purpose:
--   Validate insert-only supersession invariants and deterministic export policy
--   selector behavior (human_first/model_first/hybrid).
--
-- Usage:
--   psql -U postgres -d <db_name> -f dbTools/admin/migrations/004_annotation_versioning_policy_verify.sql
--
-- Safety:
--   Runs in a transaction and ends with ROLLBACK.

BEGIN;

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
        'pol-655-verify',
        'v1',
        'verify-run-004'
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
        '55555555-5555-4555-8555-555555555555',
        '66666666-6666-4666-8666-666666666666',
        30,
        3000,
        3200,
        1920,
        1080
    )
    RETURNING subject_id
)
INSERT INTO annotation (
    subject_id,
    set_id,
    label,
    score,
    lifecycle_state
)
SELECT seeded_subject.subject_id, seeded_set.set_id, 'apis_mellifera', NULL, 'active'
FROM seeded_set, seeded_subject;

WITH seeded_set AS (
    SELECT set_id FROM annotation_set WHERE run_id = 'verify-run-004' ORDER BY created_at DESC LIMIT 1
),
seeded_subject AS (
    SELECT subject_id FROM annotation_subject WHERE asset_uuid = '55555555-5555-4555-8555-555555555555' ORDER BY created_at DESC LIMIT 1
)
INSERT INTO annotation (subject_id, set_id, label, score, lifecycle_state)
SELECT seeded_subject.subject_id, seeded_set.set_id, 'apis_mellifera', 0.83, 'active'
FROM seeded_set, seeded_subject;

WITH seeded_set AS (
    SELECT set_id FROM annotation_set WHERE run_id = 'verify-run-004' ORDER BY created_at DESC LIMIT 1
),
seeded_subject AS (
    SELECT subject_id FROM annotation_subject WHERE asset_uuid = '55555555-5555-4555-8555-555555555555' ORDER BY created_at DESC LIMIT 1
)
INSERT INTO annotation (subject_id, set_id, label, score, lifecycle_state)
SELECT seeded_subject.subject_id, seeded_set.set_id, 'apis_mellifera', 0.97, 'active'
FROM seeded_set, seeded_subject;

WITH seeded_set AS (
    SELECT set_id FROM annotation_set WHERE run_id = 'verify-run-004' ORDER BY created_at DESC LIMIT 1
),
seeded_subject AS (
    SELECT subject_id FROM annotation_subject WHERE asset_uuid = '55555555-5555-4555-8555-555555555555' ORDER BY created_at DESC LIMIT 1
)
INSERT INTO annotation (subject_id, set_id, label, score, lifecycle_state)
SELECT seeded_subject.subject_id, seeded_set.set_id, 'apis_mellifera', 0.88, 'active'
FROM seeded_set, seeded_subject;

-- Assign stable provenance identities by created_at order.
WITH ordered AS (
    SELECT annotation_id, row_number() OVER (ORDER BY created_at ASC) AS rn
    FROM annotation
    WHERE label = 'apis_mellifera'
)
INSERT INTO annotation_provenance (
    annotation_id,
    source_kind,
    source_name,
    source_version,
    operator_identity,
    model_id,
    prompt_hash,
    config_hash,
    run_id
)
SELECT
    ordered.annotation_id,
    CASE ordered.rn
        WHEN 1 THEN 'human'
        WHEN 2 THEN 'model'
        WHEN 3 THEN 'model'
        ELSE 'imported_dataset'
    END,
    CASE ordered.rn
        WHEN 1 THEN 'manual-review'
        WHEN 2 THEN 'md3'
        WHEN 3 THEN 'md3'
        ELSE 'inat2017-import'
    END,
    CASE ordered.rn
        WHEN 4 THEN 'v2017'
        ELSE 'v1'
    END,
    CASE ordered.rn
        WHEN 1 THEN 'qa.operator@example.org'
        ELSE NULL
    END,
    CASE ordered.rn
        WHEN 2 THEN 'moondream3-preview'
        WHEN 3 THEN 'moondream3-preview'
        ELSE NULL
    END,
    CASE ordered.rn
        WHEN 2 THEN repeat('a', 64)
        WHEN 3 THEN repeat('c', 64)
        ELSE NULL
    END,
    CASE ordered.rn
        WHEN 2 THEN repeat('b', 64)
        WHEN 3 THEN repeat('d', 64)
        ELSE NULL
    END,
    CASE ordered.rn
        WHEN 2 THEN 'run-model-004-a'
        WHEN 3 THEN 'run-model-004-b'
        ELSE NULL
    END
FROM ordered;

WITH ordered AS (
    SELECT annotation_id, row_number() OVER (ORDER BY created_at ASC) AS rn
    FROM annotation
    WHERE label = 'apis_mellifera'
)
INSERT INTO annotation_quality (
    annotation_id,
    review_status,
    confidence_score,
    conflict_flag,
    adjudicated_by,
    adjudicated_at
)
SELECT
    ordered.annotation_id,
    'accepted',
    CASE ordered.rn
        WHEN 1 THEN 0.95
        WHEN 2 THEN 0.83
        WHEN 3 THEN 0.97
        ELSE 0.88
    END,
    FALSE,
    'qa.lead@example.org',
    NOW()
FROM ordered;

-- Supersede model annotation #2 by model annotation #3.
WITH ordered AS (
    SELECT annotation_id, row_number() OVER (ORDER BY created_at ASC) AS rn
    FROM annotation
    WHERE label = 'apis_mellifera'
)
INSERT INTO annotation_supersession (
    superseded_annotation_id,
    replacement_annotation_id,
    reason,
    created_by
)
SELECT
    old.annotation_id,
    new.annotation_id,
    'higher-confidence model rerun',
    'verify-script'
FROM ordered old
JOIN ordered new ON old.rn = 2 AND new.rn = 3;

-- Validate active selector excludes superseded row.
SELECT COUNT(*) AS active_rows
FROM annotation_active_selection_v1
WHERE label = 'apis_mellifera';

-- Deterministic policy outputs.
SELECT policy_name, strategy, source_kind, trust_rank, confidence_score
FROM annotation_export_select_v1('human_first', 1);

SELECT policy_name, strategy, source_kind, trust_rank, confidence_score
FROM annotation_export_select_v1('model_first', 1);

SELECT policy_name, strategy, source_kind, trust_rank, confidence_score
FROM annotation_export_select_v1('hybrid', 1);

-- Delete guardrail should fire.
DO $$
BEGIN
    BEGIN
        DELETE FROM annotation_supersession
        WHERE reason = 'higher-confidence model rerun';

        RAISE EXCEPTION 'Expected delete guardrail did not fire';
    EXCEPTION
        WHEN raise_exception THEN
            IF SQLERRM NOT LIKE 'Deletes are forbidden on%' THEN
                RAISE;
            END IF;
    END;
END;
$$;

ROLLBACK;
