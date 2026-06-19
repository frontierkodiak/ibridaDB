-- Migration 006: annotation set-scoped export selector
-- POL-1784 — optional set filter before deterministic selector ranking
-- Mirror note: keep this file byte-identical with its corresponding add/migration pair.
--
-- Purpose:
--   Fix annotation readback for explicit annotation sets that overlap on the
--   same (subject_id, label).  The previous selector ranked candidates across
--   all active annotation sets, then callers filtered by set_id after joining
--   to the selected row.  If another set won the global rank, the losing set
--   produced zero readback rows.
--
--   This migration keeps annotation_export_select_v1 as the single canonical
--   selector and adds an optional set scope:
--
--     annotation_export_select_v1(policy, version, set_ids uuid[] DEFAULT NULL)
--
--   NULL set_ids preserves global selection semantics for existing two-arg
--   callers.  Non-NULL set_ids filters candidates before row_number() ranking.
--
-- Context:
--   annotation_active_selection_v1 already exposes set_id, so the set filter
--   can be applied inside the candidates CTE before deterministic ranking.
--   Because PostgreSQL treats defaulted-argument overloads as ambiguous, the
--   old two-argument function is dropped before the new three-argument
--   function is created.  The default human-first view is the only expected DB
--   dependency on the old function; it is recreated after the signature swap.
--
-- Prerequisites:
--   - Migration 001 (annotation_set, annotation_subject)
--   - Migration 002 (annotation, annotation_geometry)
--   - Migration 003 (annotation_provenance, annotation_quality)
--   - Migration 004 (annotation_supersession, annotation_export_policy)
--   - Migration 005 (annotation write-gate hardening)
--
-- Safety:
--   - Idempotent: dependency guard, DROP VIEW IF EXISTS, DROP FUNCTION IF EXISTS,
--     CREATE OR REPLACE FUNCTION, CREATE OR REPLACE VIEW.
--   - Non-destructive: no table, column, or row is dropped.
--   - Dependency-safe: raises if any object other than
--     annotation_export_default_human_first_v1 depends on the old two-arg
--     function before it is dropped.
--
-- Rollback: see 006_annotation_set_scoped_selector_rollback.sql
-- Verification: see 006_annotation_set_scoped_selector_verify.sql

BEGIN;

-- ============================================================================
-- Dependency guard for the old two-argument selector
-- ============================================================================
-- The default human-first view is recreated below.  Any other database object
-- depending on the old signature should be reviewed explicitly before applying
-- this migration.

DO $$
DECLARE
    old_selector OID := to_regprocedure('annotation_export_select_v1(character varying, integer)');
    unexpected_dependencies TEXT;
BEGIN
    IF old_selector IS NULL THEN
        RETURN;
    END IF;

    SELECT string_agg(
               COALESCE(
                   view_ns.nspname || '.' || view_rel.relname,
                   proc_ns.nspname || '.' || proc_rel.proname || '(' ||
                       pg_get_function_identity_arguments(proc_rel.oid) || ')',
                   dep.classid::regclass::text || ':' || dep.objid::text
               ),
               ', '
               ORDER BY 1
           )
      INTO unexpected_dependencies
      FROM pg_depend dep
      LEFT JOIN pg_rewrite rw
        ON rw.oid = dep.objid
      LEFT JOIN pg_class view_rel
        ON view_rel.oid = rw.ev_class
      LEFT JOIN pg_namespace view_ns
        ON view_ns.oid = view_rel.relnamespace
      LEFT JOIN pg_proc proc_rel
        ON proc_rel.oid = dep.objid
      LEFT JOIN pg_namespace proc_ns
        ON proc_ns.oid = proc_rel.pronamespace
     WHERE dep.refobjid = old_selector
       AND dep.deptype = 'n'
       AND COALESCE(view_rel.relname, '') <> 'annotation_export_default_human_first_v1';

    IF unexpected_dependencies IS NOT NULL THEN
        RAISE EXCEPTION
            'annotation_export_select_v1(varchar, int) has unexpected dependents: %',
            unexpected_dependencies;
    END IF;
END;
$$;

DROP VIEW IF EXISTS annotation_export_default_human_first_v1;
DROP FUNCTION IF EXISTS annotation_export_select_v1(VARCHAR, INTEGER);


-- ============================================================================
-- Deterministic export selector with optional set scope
-- ============================================================================
-- Returns one selected annotation per (subject_id, label) for a given policy.
-- When in_set_ids is NULL, selection remains global and preserves the original
-- two-argument behavior.  When in_set_ids is non-NULL, candidate rows are
-- restricted before row_number() ranking so each requested set can select its
-- own best annotation for overlapping subjects/labels.

CREATE OR REPLACE FUNCTION annotation_export_select_v1(
    in_policy_name VARCHAR DEFAULT 'human_first',
    in_policy_version INTEGER DEFAULT 1,
    in_set_ids UUID[] DEFAULT NULL
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
      AND (in_set_ids IS NULL OR a.set_id = ANY(in_set_ids))
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

COMMENT ON FUNCTION annotation_export_select_v1(VARCHAR, INTEGER, UUID[]) IS
    'Deterministic policy-driven export selector; optional set_ids scope filters candidates before ranking (POL-1784).';

CREATE OR REPLACE VIEW annotation_export_default_human_first_v1 AS
SELECT *
FROM annotation_export_select_v1('human_first', 1);

COMMENT ON VIEW annotation_export_default_human_first_v1 IS 'Default export selector projection using policy human_first/v1.';

COMMIT;
