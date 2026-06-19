-- Verification script for Migration 006 (POL-1784)
--
-- Purpose:
--   Validate the set-scoped selector fix:
--     - the new three-argument signature is installed,
--     - in_set_ids = NULL reproduces global two-argument selection,
--     - two overlapping sets sharing one (subject_id, label) each select their
--       own annotation when scoped by set_ids,
--     - the existing two-argument call remains backward-compatible.
--
-- Usage:
--   psql -U postgres -d <db_name> -f dbTools/admin/migrations/006_annotation_set_scoped_selector_verify.sql
--
-- Safety:
--   Runs in a transaction and ends with ROLLBACK.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Function signature exists and the old two-arg overload is absent.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regprocedure('annotation_export_select_v1(character varying, integer, uuid[])') IS NULL THEN
        RAISE EXCEPTION 'annotation_export_select_v1(varchar, integer, uuid[]) is missing';
    END IF;

    IF to_regprocedure('annotation_export_select_v1(character varying, integer)') IS NOT NULL THEN
        RAISE EXCEPTION 'old two-argument annotation_export_select_v1 overload still exists';
    END IF;

    RAISE NOTICE 'OK: selector signature is the canonical three-argument form';
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. NULL set_ids is equivalent to the backward-compatible two-arg call.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    delta_count INTEGER;
BEGIN
    WITH two_arg AS (
        SELECT * FROM annotation_export_select_v1('human_first', 1)
    ),
    null_scoped AS (
        SELECT * FROM annotation_export_select_v1('human_first', 1, NULL::UUID[])
    ),
    deltas AS (
        (SELECT * FROM two_arg EXCEPT SELECT * FROM null_scoped)
        UNION ALL
        (SELECT * FROM null_scoped EXCEPT SELECT * FROM two_arg)
    )
    SELECT COUNT(*) INTO delta_count FROM deltas;

    IF delta_count <> 0 THEN
        RAISE EXCEPTION 'NULL set_ids changed global selection (% row deltas)', delta_count;
    END IF;

    RAISE NOTICE 'OK: NULL set_ids reproduces global two-arg selection';
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Seed two annotation sets sharing the same subject_id + label.
--    The second row wins globally by higher confidence, but each set-scoped
--    call must return that set's own annotation.
-- ---------------------------------------------------------------------------
INSERT INTO annotation_set (set_id, dataset, release, source_kind, source_name, source_version, run_id)
VALUES
    ('aaaaaaaa-0006-4006-8006-000000000001', 'verify', 'r2', 'human',
     'pol-1784-verify', 'v1', 'verify-run-006-a'),
    ('aaaaaaaa-0006-4006-8006-000000000002', 'verify', 'r2', 'human',
     'pol-1784-verify', 'v1', 'verify-run-006-b');

INSERT INTO annotation_subject (subject_id, asset_uuid, asset_width_px, asset_height_px)
VALUES
    ('bbbbbbbb-0006-4006-8006-000000000001',
     'cccccccc-0006-4006-8006-000000000001', 1024, 768);

INSERT INTO annotation (annotation_id, subject_id, set_id, label, score, source_annotation_key)
VALUES
    ('dddddddd-0006-4006-8006-000000000001',
     'bbbbbbbb-0006-4006-8006-000000000001',
     'aaaaaaaa-0006-4006-8006-000000000001',
     'pol_1784_overlap_probe', 0.61, 'set-a-overlap-probe'),
    ('dddddddd-0006-4006-8006-000000000002',
     'bbbbbbbb-0006-4006-8006-000000000001',
     'aaaaaaaa-0006-4006-8006-000000000002',
     'pol_1784_overlap_probe', 0.99, 'set-b-overlap-probe');

INSERT INTO annotation_provenance (
    annotation_id,
    source_kind,
    source_name,
    source_version,
    operator_identity
)
VALUES
    ('dddddddd-0006-4006-8006-000000000001', 'human', 'pol-1784-verify', 'v1',
     'verify.operator@example.org'),
    ('dddddddd-0006-4006-8006-000000000002', 'human', 'pol-1784-verify', 'v1',
     'verify.operator@example.org');

INSERT INTO annotation_quality (
    annotation_id,
    review_status,
    confidence_score,
    conflict_flag,
    adjudicated_by,
    adjudicated_at
)
VALUES
    ('dddddddd-0006-4006-8006-000000000001', 'accepted', 0.61, FALSE,
     'verify.lead@example.org', NOW()),
    ('dddddddd-0006-4006-8006-000000000002', 'accepted', 0.99, FALSE,
     'verify.lead@example.org', NOW());

DO $$
DECLARE
    global_winner UUID;
    set_a_winner UUID;
    set_b_winner UUID;
BEGIN
    SELECT annotation_id INTO global_winner
    FROM annotation_export_select_v1('human_first', 1)
    WHERE subject_id = 'bbbbbbbb-0006-4006-8006-000000000001'
      AND label = 'pol_1784_overlap_probe';

    SELECT annotation_id INTO set_a_winner
    FROM annotation_export_select_v1(
        'human_first',
        1,
        ARRAY['aaaaaaaa-0006-4006-8006-000000000001']::UUID[]
    )
    WHERE subject_id = 'bbbbbbbb-0006-4006-8006-000000000001'
      AND label = 'pol_1784_overlap_probe';

    SELECT annotation_id INTO set_b_winner
    FROM annotation_export_select_v1(
        'human_first',
        1,
        ARRAY['aaaaaaaa-0006-4006-8006-000000000002']::UUID[]
    )
    WHERE subject_id = 'bbbbbbbb-0006-4006-8006-000000000001'
      AND label = 'pol_1784_overlap_probe';

    IF global_winner <> 'dddddddd-0006-4006-8006-000000000002' THEN
        RAISE EXCEPTION 'global selector winner mismatch: %', global_winner;
    END IF;

    IF set_a_winner <> 'dddddddd-0006-4006-8006-000000000001' THEN
        RAISE EXCEPTION 'set A selector winner mismatch: %', set_a_winner;
    END IF;

    IF set_b_winner <> 'dddddddd-0006-4006-8006-000000000002' THEN
        RAISE EXCEPTION 'set B selector winner mismatch: %', set_b_winner;
    END IF;

    RAISE NOTICE 'OK: global winner is set B, while set A and set B scoped calls return their own annotations';
END;
$$;

-- ---------------------------------------------------------------------------
-- Summary output for PR receipts.
-- ---------------------------------------------------------------------------
SELECT
    'two_arg_global' AS probe,
    annotation_id::text,
    confidence_score
FROM annotation_export_select_v1('human_first', 1)
WHERE subject_id = 'bbbbbbbb-0006-4006-8006-000000000001'
  AND label = 'pol_1784_overlap_probe'
UNION ALL
SELECT
    'null_scoped_global' AS probe,
    annotation_id::text,
    confidence_score
FROM annotation_export_select_v1('human_first', 1, NULL::UUID[])
WHERE subject_id = 'bbbbbbbb-0006-4006-8006-000000000001'
  AND label = 'pol_1784_overlap_probe'
UNION ALL
SELECT
    'set_a_scoped' AS probe,
    annotation_id::text,
    confidence_score
FROM annotation_export_select_v1(
    'human_first',
    1,
    ARRAY['aaaaaaaa-0006-4006-8006-000000000001']::UUID[]
)
WHERE subject_id = 'bbbbbbbb-0006-4006-8006-000000000001'
  AND label = 'pol_1784_overlap_probe'
UNION ALL
SELECT
    'set_b_scoped' AS probe,
    annotation_id::text,
    confidence_score
FROM annotation_export_select_v1(
    'human_first',
    1,
    ARRAY['aaaaaaaa-0006-4006-8006-000000000002']::UUID[]
)
WHERE subject_id = 'bbbbbbbb-0006-4006-8006-000000000001'
  AND label = 'pol_1784_overlap_probe'
ORDER BY probe;

ROLLBACK;
