-- Verification script for Migration 005 (POL-1423)
--
-- Purpose:
--   Validate the write-gate hardening surfaces:
--     - annotation.updated_at and annotation_quality.updated_at exist and are
--       maintained by the touch_updated_at() BEFORE UPDATE triggers,
--     - annotation.source_annotation_key exists,
--     - duplicate (set_id, source_annotation_key) is rejected within a set,
--     - the same key in a different set is allowed,
--     - NULL source_annotation_key permits duplicates,
--     - the migration 004 supersession trigger no longer fails on a missing
--       updated_at column and still flips lifecycle_state.
--
-- Usage:
--   psql -U postgres -d <db_name> -f dbTools/admin/migrations/005_annotation_write_gate_hardening_verify.sql
--
-- Safety:
--   Runs in a transaction and ends with ROLLBACK.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Columns exist.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'annotation' AND column_name = 'updated_at'
    ) THEN
        RAISE EXCEPTION 'annotation.updated_at is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'annotation_quality' AND column_name = 'updated_at'
    ) THEN
        RAISE EXCEPTION 'annotation_quality.updated_at is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'annotation' AND column_name = 'source_annotation_key'
    ) THEN
        RAISE EXCEPTION 'annotation.source_annotation_key is missing';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Seed two sets and two subjects shared by the verification annotations.
-- ---------------------------------------------------------------------------
INSERT INTO annotation_set (set_id, dataset, release, source_kind, source_name, source_version, run_id)
VALUES
    ('aaaaaaaa-0005-4005-8005-000000000001', 'verify', 'r2', 'imported_dataset',
     'pol-1423-verify', 'v1', 'verify-run-005-a'),
    ('aaaaaaaa-0005-4005-8005-000000000002', 'verify', 'r2', 'imported_dataset',
     'pol-1423-verify', 'v1', 'verify-run-005-b');

INSERT INTO annotation_subject (subject_id, asset_uuid, asset_width_px, asset_height_px)
VALUES
    ('bbbbbbbb-0005-4005-8005-000000000001',
     'cccccccc-0005-4005-8005-000000000001', 1024, 768);

-- ---------------------------------------------------------------------------
-- 1. touch_updated_at fires on annotation UPDATE.
--    A BEFORE UPDATE trigger must overwrite a deliberately wrong updated_at.
-- ---------------------------------------------------------------------------
INSERT INTO annotation (annotation_id, subject_id, set_id, label, source_annotation_key)
VALUES ('dddddddd-0005-4005-8005-000000000001',
        'bbbbbbbb-0005-4005-8005-000000000001',
        'aaaaaaaa-0005-4005-8005-000000000001',
        'touch_probe', 'key-touch-1');

INSERT INTO annotation_provenance (annotation_id, source_kind, source_name, source_version)
VALUES ('dddddddd-0005-4005-8005-000000000001', 'imported_dataset',
        'pol-1423-verify', 'v1');

UPDATE annotation
   SET updated_at = TIMESTAMPTZ '2000-01-01 00:00:00+00'
 WHERE annotation_id = 'dddddddd-0005-4005-8005-000000000001';

DO $$
DECLARE
    touched TIMESTAMPTZ;
BEGIN
    SELECT updated_at INTO touched
    FROM annotation
    WHERE annotation_id = 'dddddddd-0005-4005-8005-000000000001';

    IF touched = TIMESTAMPTZ '2000-01-01 00:00:00+00' THEN
        RAISE EXCEPTION 'trg_annotation_touch_updated_at did not fire';
    END IF;
    RAISE NOTICE 'OK: annotation.updated_at maintained by touch trigger';
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. touch_updated_at fires on annotation_quality UPDATE.
-- ---------------------------------------------------------------------------
INSERT INTO annotation_quality (annotation_id, review_status)
VALUES ('dddddddd-0005-4005-8005-000000000001', 'unreviewed');

UPDATE annotation_quality
   SET updated_at = TIMESTAMPTZ '2000-01-01 00:00:00+00',
       review_status = 'needs_review'
 WHERE annotation_id = 'dddddddd-0005-4005-8005-000000000001';

DO $$
DECLARE
    touched TIMESTAMPTZ;
BEGIN
    SELECT updated_at INTO touched
    FROM annotation_quality
    WHERE annotation_id = 'dddddddd-0005-4005-8005-000000000001';

    IF touched = TIMESTAMPTZ '2000-01-01 00:00:00+00' THEN
        RAISE EXCEPTION 'trg_annotation_quality_touch_updated_at did not fire';
    END IF;
    RAISE NOTICE 'OK: annotation_quality.updated_at maintained by touch trigger';
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Duplicate (set_id, source_annotation_key) is rejected within a set.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        INSERT INTO annotation (subject_id, set_id, label, source_annotation_key)
        VALUES ('bbbbbbbb-0005-4005-8005-000000000001',
                'aaaaaaaa-0005-4005-8005-000000000001',
                'dup_probe', 'key-touch-1');
        RAISE EXCEPTION 'Expected duplicate source_annotation_key rejection did not occur';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'OK: duplicate source_annotation_key blocked within set';
    END;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. The same key in a different set is allowed.
-- ---------------------------------------------------------------------------
INSERT INTO annotation (annotation_id, subject_id, set_id, label, source_annotation_key)
VALUES ('dddddddd-0005-4005-8005-000000000002',
        'bbbbbbbb-0005-4005-8005-000000000001',
        'aaaaaaaa-0005-4005-8005-000000000002',
        'cross_set_probe', 'key-touch-1');

INSERT INTO annotation_provenance (annotation_id, source_kind, source_name, source_version)
VALUES ('dddddddd-0005-4005-8005-000000000002', 'imported_dataset',
        'pol-1423-verify', 'v1');

-- ---------------------------------------------------------------------------
-- 5. NULL source_annotation_key permits duplicates (partial-index exemption).
-- ---------------------------------------------------------------------------
INSERT INTO annotation (annotation_id, subject_id, set_id, label, source_annotation_key)
VALUES
    ('dddddddd-0005-4005-8005-000000000003',
     'bbbbbbbb-0005-4005-8005-000000000001',
     'aaaaaaaa-0005-4005-8005-000000000001', 'null_key_probe_a', NULL),
    ('dddddddd-0005-4005-8005-000000000004',
     'bbbbbbbb-0005-4005-8005-000000000001',
     'aaaaaaaa-0005-4005-8005-000000000001', 'null_key_probe_b', NULL);

INSERT INTO annotation_provenance (annotation_id, source_kind, source_name, source_version)
VALUES
    ('dddddddd-0005-4005-8005-000000000003', 'imported_dataset', 'pol-1423-verify', 'v1'),
    ('dddddddd-0005-4005-8005-000000000004', 'imported_dataset', 'pol-1423-verify', 'v1');

-- ---------------------------------------------------------------------------
-- 6. Supersession trigger (migration 004) no longer fails on updated_at and
--    still flips lifecycle_state to 'superseded'.
-- ---------------------------------------------------------------------------
INSERT INTO annotation_supersession (superseded_annotation_id, replacement_annotation_id, reason, created_by)
VALUES ('dddddddd-0005-4005-8005-000000000003',
        'dddddddd-0005-4005-8005-000000000004',
        'pol-1423 supersession verification', 'pol-1423-verify');

DO $$
DECLARE
    state TEXT;
BEGIN
    SELECT lifecycle_state INTO state
    FROM annotation
    WHERE annotation_id = 'dddddddd-0005-4005-8005-000000000003';

    IF state <> 'superseded' THEN
        RAISE EXCEPTION 'supersession did not flip lifecycle_state (got %)', state;
    END IF;
    RAISE NOTICE 'OK: supersession trigger runs and flips lifecycle_state';
END;
$$;

-- ---------------------------------------------------------------------------
-- Summary output.
-- ---------------------------------------------------------------------------
SELECT 'annotation rows' AS surface, COUNT(*) AS n FROM annotation
WHERE set_id IN ('aaaaaaaa-0005-4005-8005-000000000001',
                 'aaaaaaaa-0005-4005-8005-000000000002')
UNION ALL
SELECT 'rows with source_annotation_key', COUNT(*) FROM annotation
WHERE source_annotation_key IS NOT NULL
  AND set_id IN ('aaaaaaaa-0005-4005-8005-000000000001',
                 'aaaaaaaa-0005-4005-8005-000000000002');

ROLLBACK;
