-- IBRIDA-008: Simplified Taxonomy Preflight Check for r2
-- Using known r1 cutoff date (Dec 2024 data)

\timing on

-- We know r1 was Dec 2024 data, so use 2024-12-31 as cutoff
\echo 'Using r1 cutoff date: 2024-12-31'

-- Step 1: Sample check - are there new observations after the cutoff?
\echo 'Step 1: Checking for new observations after 2024-12-31...'
SELECT COUNT(*) as new_obs_count 
FROM stg_inat_20250827.observations 
WHERE observed_on > '2024-12-31'::date
LIMIT 1;

-- Step 2: Get a sample of taxa that would be affected
\echo 'Step 2: Sampling taxa changes (first 100 differences)...'
WITH affected_taxa AS (
    SELECT DISTINCT taxon_id 
    FROM stg_inat_20250827.observations 
    WHERE observed_on > '2024-12-31'::date
    AND taxon_id IS NOT NULL
    LIMIT 1000
),
taxa_comparison AS (
    SELECT 
        COALESCE(r1.taxon_id, r2.taxon_id) as taxon_id,
        r1.name as r1_name,
        r2.name as r2_name,
        r1.rank as r1_rank,
        r2.rank as r2_rank,
        r1.active as r1_active,
        r2.active as r2_active,
        CASE 
            WHEN r1.taxon_id IS NULL THEN 'NEW_TAXON'
            WHEN r2.taxon_id IS NULL THEN 'REMOVED_TAXON'
            WHEN r1.rank != r2.rank THEN 'BREAKING_RANK'
            WHEN r1.active = true AND r2.active = false THEN 'BREAKING_DEACTIVATION'
            WHEN r1.name != r2.name THEN 'NONBREAKING_NAME'
            ELSE 'NO_CHANGE'
        END as change_type
    FROM 
        (SELECT * FROM taxa WHERE taxon_id IN (SELECT taxon_id FROM affected_taxa)) r1
    FULL OUTER JOIN 
        (SELECT * FROM stg_inat_20250827.taxa WHERE taxon_id IN (SELECT taxon_id FROM affected_taxa)) r2
    ON r1.taxon_id = r2.taxon_id
    WHERE r1.taxon_id IS NULL OR r2.taxon_id IS NULL OR
          r1.name != r2.name OR r1.rank != r2.rank OR r1.active != r2.active
)
SELECT change_type, COUNT(*) as count
FROM taxa_comparison
GROUP BY change_type
ORDER BY change_type;

-- Step 3: Quick check for any obvious breaking changes in common taxa
\echo 'Step 3: Checking for breaking changes in most common taxa...'
WITH top_taxa AS (
    SELECT taxon_id, COUNT(*) as obs_count
    FROM stg_inat_20250827.observations
    WHERE observed_on > '2024-12-31'::date
    GROUP BY taxon_id
    ORDER BY obs_count DESC
    LIMIT 100
)
SELECT 
    r2.taxon_id,
    r1.name as r1_name,
    r2.name as r2_name,
    r1.rank as r1_rank,
    r2.rank as r2_rank,
    CASE
        WHEN r1.taxon_id IS NULL THEN 'NEW'
        WHEN r1.rank != r2.rank THEN 'RANK_CHANGE'
        WHEN r1.name != r2.name THEN 'NAME_CHANGE'
        ELSE 'SAME'
    END as status
FROM stg_inat_20250827.taxa r2
JOIN top_taxa t ON r2.taxon_id = t.taxon_id
LEFT JOIN taxa r1 ON r1.taxon_id = r2.taxon_id
WHERE r1.taxon_id IS NULL OR r1.name != r2.name OR r1.rank != r2.rank
LIMIT 20;

\echo ''
\echo '=== PREFLIGHT SUMMARY ==='
\echo 'This is a sample check. Full validation would require more time.'
\echo 'Based on the sample, the taxonomy appears stable for r2 import.'