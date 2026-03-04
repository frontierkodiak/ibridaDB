-- Fast Taxonomy Impact Analysis for r2 Breaking Changes
-- Focused on getting key metrics quickly

\timing on
\echo '=== FAST TAXONOMY IMPACT ANALYSIS ==='
\echo ''

-- First, let's get a sample to understand the scale
\echo 'Quick sample of deactivated taxa (first 100):'
SELECT 
    r1.taxon_id,
    r1.name,
    r1.rank,
    r2.active as r2_active
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
WHERE r1.active = true AND r2.active = false
LIMIT 100;

\echo ''
\echo 'Sample of rank changes (first 20):'
SELECT 
    r1.taxon_id,
    r1.name,
    r1.rank as r1_rank,
    r2.rank as r2_rank
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
WHERE r1.rank != r2.rank
LIMIT 20;

-- Check if we have any observations for a sample of deactivated taxa
\echo ''
\echo 'Checking observation counts for sample of deactivated taxa:'
WITH sample_deactivated AS (
    SELECT r1.taxon_id, r1.name, r1.rank
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.active = true AND r2.active = false
    LIMIT 10
)
SELECT 
    sd.taxon_id,
    sd.name,
    sd.rank,
    (SELECT COUNT(*) FROM observations o WHERE o.taxon_id = sd.taxon_id LIMIT 1) as obs_count
FROM sample_deactivated sd
ORDER BY obs_count DESC;

-- Get aggregate statistics without joining large tables
\echo ''
\echo 'Breaking change statistics by rank:'
WITH breaking_taxa AS (
    SELECT 
        r1.taxon_id,
        r1.rank,
        CASE 
            WHEN r1.active = true AND r2.active = false THEN 'DEACTIVATED'
            WHEN r1.rank != r2.rank THEN 'RANK_CHANGED'
            ELSE 'OTHER'
        END as change_type
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE (r1.active = true AND r2.active = false) OR r1.rank != r2.rank
)
SELECT 
    rank,
    change_type,
    COUNT(*) as taxa_count
FROM breaking_taxa
GROUP BY rank, change_type
ORDER BY taxa_count DESC
LIMIT 20;

\echo ''
\echo '=== END FAST ANALYSIS ===