-- Verification script for Migration 003 (POL-654)
--
-- Purpose:
--   Validate provenance/quality completeness constraints and trusted-selection
--   query semantics with representative human/model/imported rows.
--
-- Usage:
--   psql -U postgres -d <db_name> -f dbTools/admin/migrations/003_annotation_provenance_quality_verify.sql
--
-- Safety:
--   Runs in a transaction and ends with ROLLBACK.

BEGIN;

-- Seed set + subject used by all verification annotations.
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
        'pol-654-verify',
        'v1',
        'verify-run-003'
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
        '33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
        20,
        2000,
        2200,
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
    is_primary,
    lifecycle_state
)
SELECT
    seeded_subject.subject_id,
    seeded_set.set_id,
    'human_verified',
    NULL,
    TRUE,
    'active'
FROM seeded_set, seeded_subject;

WITH s AS (
    SELECT annotation_id
    FROM annotation
    WHERE label = 'human_verified'
    ORDER BY created_at DESC
    LIMIT 1
)
INSERT INTO annotation_provenance (
    annotation_id,
    source_kind,
    source_name,
    source_version,
    operator_identity
)
SELECT
    s.annotation_id,
    'human',
    'manual-review',
    'v1',
    'qa.operator@example.org'
FROM s;

WITH s AS (
    SELECT annotation_id
    FROM annotation
    WHERE label = 'human_verified'
    ORDER BY created_at DESC
    LIMIT 1
)
INSERT INTO annotation_quality (
    annotation_id,
    review_status,
    confidence_score,
    conflict_flag,
    adjudicated_by,
    adjudicated_at,
    review_notes
)
SELECT
    s.annotation_id,
    'accepted',
    0.98,
    FALSE,
    'qa.lead@example.org',
    NOW(),
    'Accepted after manual verification.'
FROM s;

-- Valid model example.
WITH seeded_set AS (
    SELECT set_id
    FROM annotation_set
    WHERE run_id = 'verify-run-003'
    ORDER BY created_at DESC
    LIMIT 1
),
seeded_subject AS (
    SELECT subject_id
    FROM annotation_subject
    WHERE asset_uuid = '33333333-3333-4333-8333-333333333333'
    ORDER BY created_at DESC
    LIMIT 1
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
        'model_verified',
        0.83,
        FALSE,
        'active'
    FROM seeded_set, seeded_subject
    RETURNING annotation_id
)
INSERT INTO annotation_provenance (
    annotation_id,
    source_kind,
    source_name,
    source_version,
    model_id,
    prompt_hash,
    config_hash,
    run_id
)
SELECT
    seeded_annotation.annotation_id,
    'model',
    'md3',
    'preview-2026-03',
    'moondream3-preview',
    repeat('a', 64),
    repeat('b', 64),
    'run-model-003'
FROM seeded_annotation;

WITH s AS (
    SELECT annotation_id
    FROM annotation
    WHERE label = 'model_verified'
    ORDER BY created_at DESC
    LIMIT 1
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
    s.annotation_id,
    'accepted',
    0.91,
    FALSE,
    'qa.lead@example.org',
    NOW()
FROM s;

-- Invalid model provenance should fail (missing config_hash).
WITH seeded_set AS (
    SELECT set_id
    FROM annotation_set
    WHERE run_id = 'verify-run-003'
    ORDER BY created_at DESC
    LIMIT 1
),
seeded_subject AS (
    SELECT subject_id
    FROM annotation_subject
    WHERE asset_uuid = '33333333-3333-4333-8333-333333333333'
    ORDER BY created_at DESC
    LIMIT 1
)
INSERT INTO annotation (
    subject_id,
    set_id,
    label,
    score,
    lifecycle_state
)
SELECT
    seeded_subject.subject_id,
    seeded_set.set_id,
    'invalid_model_missing_config',
    0.51,
    'active'
FROM seeded_set, seeded_subject;

DO $$
DECLARE
    target_annotation UUID;
BEGIN
    SELECT annotation_id INTO target_annotation
    FROM annotation
    WHERE label = 'invalid_model_missing_config'
    ORDER BY created_at DESC
    LIMIT 1;

    BEGIN
        INSERT INTO annotation_provenance (
            annotation_id,
            source_kind,
            source_name,
            source_version,
            model_id,
            run_id
        )
        VALUES (
            target_annotation,
            'model',
            'md3',
            'preview-2026-03',
            'moondream3-preview',
            'run-model-invalid-003'
        );

        RAISE EXCEPTION 'Expected provenance completeness failure did not occur';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;
END;
$$;

-- Invalid quality adjudication should fail (accepted without adjudicator).
WITH seeded_set AS (
    SELECT set_id
    FROM annotation_set
    WHERE run_id = 'verify-run-003'
    ORDER BY created_at DESC
    LIMIT 1
),
seeded_subject AS (
    SELECT subject_id
    FROM annotation_subject
    WHERE asset_uuid = '33333333-3333-4333-8333-333333333333'
    ORDER BY created_at DESC
    LIMIT 1
),
seeded_annotation AS (
    INSERT INTO annotation (
        subject_id,
        set_id,
        label,
        score,
        lifecycle_state
    )
    SELECT
        seeded_subject.subject_id,
        seeded_set.set_id,
        'invalid_quality_missing_adjudicator',
        0.64,
        'active'
    FROM seeded_set, seeded_subject
    RETURNING annotation_id
)
INSERT INTO annotation_provenance (
    annotation_id,
    source_kind,
    source_name,
    source_version,
    operator_identity
)
SELECT
    seeded_annotation.annotation_id,
    'human',
    'manual-review',
    'v1',
    'qa.operator@example.org'
FROM seeded_annotation;

DO $$
DECLARE
    target_annotation UUID;
BEGIN
    SELECT annotation_id INTO target_annotation
    FROM annotation
    WHERE label = 'invalid_quality_missing_adjudicator'
    ORDER BY created_at DESC
    LIMIT 1;

    BEGIN
        INSERT INTO annotation_quality (
            annotation_id,
            review_status,
            confidence_score,
            conflict_flag
        )
        VALUES (
            target_annotation,
            'accepted',
            0.88,
            FALSE
        );

        RAISE EXCEPTION 'Expected quality adjudication failure did not occur';
    EXCEPTION
        WHEN check_violation THEN
            NULL;
    END;
END;
$$;

-- Trusted-selection sanity output.
SELECT source_kind, review_status, trust_rank, COUNT(*) AS n
FROM annotation_trusted_selection_v1
GROUP BY source_kind, review_status, trust_rank
ORDER BY source_kind, review_status, trust_rank;

SELECT COUNT(*) AS provenance_rows FROM annotation_provenance;
SELECT COUNT(*) AS quality_rows FROM annotation_quality;

ROLLBACK;
