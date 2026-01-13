-- IBRIDA-008: Fast Taxonomy Preflight Check for r2
-- Focus on detecting BREAKING changes efficiently

\timing on
\echo '=== TAXONOMY PREFLIGHT CHECK (r2) ==='
\echo ''

-- Step 1: Quick stats on r2 staging data
\echo 'Step 1: R2 staging data statistics'
SELECT 
    'observations' as table_name,
    COUNT(*) as total_rows,
    COUNT(DISTINCT taxon_id) as unique_taxa,
    MIN(observed_on) as min_date,
    MAX(observed_on) as max_date
FROM stg_inat_20250827.observations
WHERE taxon_id IS NOT NULL;

-- Step 2: Check for NEW taxa in r2 (not in r1)
\echo ''
\echo 'Step 2: Checking for NEW taxa in r2...'
WITH new_taxa AS (
    SELECT s.taxon_id, s.name, s.rank
    FROM stg_inat_20250827.taxa s
    LEFT JOIN taxa r ON s.taxon_id = r.taxon_id
    WHERE r.taxon_id IS NULL
    LIMIT 100
)
SELECT COUNT(*) as new_taxa_count FROM new_taxa;

-- Step 3: Check for REMOVED taxa (in r1 but not r2)
\echo ''
\echo 'Step 3: Checking for REMOVED taxa from r1...'
WITH removed_taxa AS (
    SELECT r.taxon_id, r.name, r.rank
    FROM taxa r
    LEFT JOIN stg_inat_20250827.taxa s ON r.taxon_id = s.taxon_id
    WHERE s.taxon_id IS NULL
    AND r.taxon_id IN (
        SELECT DISTINCT taxon_id 
        FROM stg_inat_20250827.observations 
        WHERE taxon_id IS NOT NULL
        LIMIT 10000
    )
)
SELECT COUNT(*) as removed_taxa_count FROM removed_taxa;

-- Step 4: Sample check for BREAKING changes in existing taxa
\echo ''
\echo 'Step 4: Sampling for BREAKING changes in existing taxa...'
WITH sample_taxa AS (
    -- Get a sample of taxa that exist in both r1 and r2
    SELECT taxon_id 
    FROM taxa 
    WHERE taxon_id IN (
        SELECT taxon_id FROM stg_inat_20250827.taxa
    )
    LIMIT 10000
),
breaking_changes AS (
    SELECT 
        r1.taxon_id,
        r1.name as r1_name,
        r2.name as r2_name,
        r1.rank as r1_rank,
        r2.rank as r2_rank,
        r1.rank_level as r1_rank_level,
        r2.rank_level as r2_rank_level,
        r1.active as r1_active,
        r2.active as r2_active,
        CASE
            WHEN r1.rank != r2.rank THEN 'RANK_CHANGE'
            WHEN r1.rank_level != r2.rank_level THEN 'RANK_LEVEL_CHANGE'
            WHEN r1.active = true AND r2.active = false THEN 'DEACTIVATED'
            WHEN r1.ancestry != r2.ancestry THEN 'ANCESTRY_CHANGE'
            ELSE 'OTHER'
        END as change_type
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.taxon_id IN (SELECT taxon_id FROM sample_taxa)
    AND (
        r1.rank != r2.rank OR
        r1.rank_level != r2.rank_level OR
        (r1.active = true AND r2.active = false) OR
        r1.ancestry != r2.ancestry
    )
)
SELECT 
    change_type,
    COUNT(*) as count,
    ARRAY_AGG(DISTINCT r1_name ORDER BY r1_name LIMIT 3) as example_taxa
FROM breaking_changes
GROUP BY change_type
ORDER BY count DESC;

-- Step 5: Name changes (non-breaking)
\echo ''
\echo 'Step 5: Checking for name changes (non-breaking)...'
WITH name_changes AS (
    SELECT COUNT(*) as count
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.name != r2.name
    AND r1.rank = r2.rank
    AND r1.rank_level = r2.rank_level
    AND r1.active = r2.active
    LIMIT 1000
)
SELECT * FROM name_changes;

-- Final summary
\echo ''
\echo '=== PREFLIGHT DECISION ==='
DO $$
DECLARE
    breaking_count INTEGER;
BEGIN
    -- Quick check for any obvious breaking changes
    SELECT COUNT(*) INTO breaking_count
    FROM (
        SELECT 1
        FROM taxa r1
        JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
        WHERE r1.rank != r2.rank 
           OR r1.rank_level != r2.rank_level
           OR (r1.active = true AND r2.active = false)
        LIMIT 1
    ) x;
    
    IF breaking_count > 0 THEN
        RAISE WARNING 'POTENTIAL BREAKING CHANGES DETECTED - Review results above';
    ELSE
        RAISE NOTICE 'NO OBVIOUS BREAKING CHANGES DETECTED - Safe to proceed';
    END IF;
END $$;

\echo ''
\echo 'Preflight check complete. Review results above for any concerns.'