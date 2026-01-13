-- IBRIDA-008: Impact Analysis of Taxonomy Breaking Changes on Existing Observations
-- Determine how many existing r1 observations are affected by breaking changes

\timing on
\echo '=== TAXONOMY BREAKING CHANGES IMPACT ANALYSIS ==='
\echo ''

-- Step 1: Analyze deactivated taxa impact on existing observations
\echo 'Step 1: Impact of DEACTIVATED taxa on existing r1 observations'
\echo '---------------------------------------------------------------'

WITH deactivated_taxa AS (
    SELECT r1.taxon_id, r1.name, r1.rank, r1.rank_level
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.active = true AND r2.active = false
),
deactivated_impact AS (
    SELECT 
        dt.taxon_id,
        dt.name,
        dt.rank,
        dt.rank_level,
        COUNT(DISTINCT o.observation_uuid) as affected_obs_count,
        COUNT(DISTINCT CASE WHEN o.quality_grade = 'research' THEN o.observation_uuid END) as affected_rg_obs_count
    FROM deactivated_taxa dt
    LEFT JOIN observations o ON o.taxon_id = dt.taxon_id
    GROUP BY dt.taxon_id, dt.name, dt.rank, dt.rank_level
)
SELECT 
    rank,
    COUNT(*) as taxa_count,
    SUM(affected_obs_count) as total_affected_obs,
    SUM(affected_rg_obs_count) as total_affected_rg_obs,
    ROUND(AVG(affected_obs_count), 2) as avg_obs_per_taxon
FROM deactivated_impact
GROUP BY rank
ORDER BY SUM(affected_obs_count) DESC;

\echo ''
\echo 'Top 10 deactivated taxa by observation count:'
WITH deactivated_taxa AS (
    SELECT r1.taxon_id, r1.name, r1.rank
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.active = true AND r2.active = false
)
SELECT 
    dt.taxon_id,
    dt.name,
    dt.rank,
    COUNT(DISTINCT o.observation_uuid) as obs_count
FROM deactivated_taxa dt
LEFT JOIN observations o ON o.taxon_id = dt.taxon_id
GROUP BY dt.taxon_id, dt.name, dt.rank
ORDER BY obs_count DESC
LIMIT 10;

-- Step 2: Analyze rank changes impact
\echo ''
\echo 'Step 2: Impact of RANK CHANGES on existing r1 observations'
\echo '------------------------------------------------------------'

WITH rank_changed_taxa AS (
    SELECT 
        r1.taxon_id, 
        r1.name,
        r1.rank as old_rank,
        r2.rank as new_rank
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.rank != r2.rank
),
rank_change_impact AS (
    SELECT 
        rct.taxon_id,
        rct.name,
        rct.old_rank,
        rct.new_rank,
        COUNT(DISTINCT o.observation_uuid) as affected_obs_count,
        COUNT(DISTINCT CASE WHEN o.quality_grade = 'research' THEN o.observation_uuid END) as affected_rg_obs_count
    FROM rank_changed_taxa rct
    LEFT JOIN observations o ON o.taxon_id = rct.taxon_id
    GROUP BY rct.taxon_id, rct.name, rct.old_rank, rct.new_rank
)
SELECT 
    old_rank || ' -> ' || new_rank as rank_change,
    COUNT(*) as taxa_count,
    SUM(affected_obs_count) as total_affected_obs,
    SUM(affected_rg_obs_count) as total_affected_rg_obs
FROM rank_change_impact
GROUP BY old_rank, new_rank
ORDER BY SUM(affected_obs_count) DESC
LIMIT 15;

\echo ''
\echo 'Top 10 rank-changed taxa by observation count:'
WITH rank_changed_taxa AS (
    SELECT 
        r1.taxon_id, 
        r1.name,
        r1.rank as old_rank,
        r2.rank as new_rank
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.rank != r2.rank
)
SELECT 
    rct.taxon_id,
    rct.name,
    rct.old_rank || ' -> ' || rct.new_rank as rank_change,
    COUNT(DISTINCT o.observation_uuid) as obs_count
FROM rank_changed_taxa rct
LEFT JOIN observations o ON o.taxon_id = rct.taxon_id
GROUP BY rct.taxon_id, rct.name, rct.old_rank, rct.new_rank
ORDER BY obs_count DESC
LIMIT 10;

-- Step 3: Summary statistics
\echo ''
\echo 'Step 3: OVERALL IMPACT SUMMARY'
\echo '-------------------------------'

WITH all_breaking_taxa AS (
    -- Deactivated taxa
    SELECT DISTINCT r1.taxon_id, 'DEACTIVATED' as change_type
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.active = true AND r2.active = false
    
    UNION
    
    -- Rank changed taxa
    SELECT DISTINCT r1.taxon_id, 'RANK_CHANGED' as change_type
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.rank != r2.rank
)
SELECT 
    COUNT(DISTINCT abt.taxon_id) as total_breaking_taxa,
    COUNT(DISTINCT o.observation_uuid) as total_affected_observations,
    COUNT(DISTINCT CASE WHEN o.quality_grade = 'research' THEN o.observation_uuid END) as total_affected_rg_observations,
    ROUND(100.0 * COUNT(DISTINCT o.observation_uuid) / 
          (SELECT COUNT(*) FROM observations), 2) as pct_of_all_observations
FROM all_breaking_taxa abt
LEFT JOIN observations o ON o.taxon_id = abt.taxon_id;

\echo ''
\echo 'Distribution of affected observations by quality grade:'
WITH all_breaking_taxa AS (
    SELECT DISTINCT r1.taxon_id
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE (r1.active = true AND r2.active = false) OR r1.rank != r2.rank
)
SELECT 
    COALESCE(o.quality_grade, 'NULL') as quality_grade,
    COUNT(DISTINCT o.observation_uuid) as affected_observations
FROM all_breaking_taxa abt
LEFT JOIN observations o ON o.taxon_id = abt.taxon_id
GROUP BY o.quality_grade
ORDER BY affected_observations DESC;

-- Step 4: Check impact on commonly used clades
\echo ''
\echo 'Step 4: Impact on major clades (Aves, Mammalia, Plantae, etc.)'
\echo '----------------------------------------------------------------'

WITH all_breaking_taxa AS (
    SELECT DISTINCT r1.taxon_id, r1.ancestry
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE (r1.active = true AND r2.active = false) OR r1.rank != r2.rank
),
clade_impacts AS (
    SELECT 
        CASE 
            WHEN abt.ancestry LIKE '%/3/%' THEN 'Aves'
            WHEN abt.ancestry LIKE '%/40151/%' THEN 'Mammalia'
            WHEN abt.ancestry LIKE '%/47120/%' THEN 'Plantae'
            WHEN abt.ancestry LIKE '%/26036/%' THEN 'Amphibia'
            WHEN abt.ancestry LIKE '%/47115/%' THEN 'Fungi'
            WHEN abt.ancestry LIKE '%/1/%' THEN 'Animalia'
            ELSE 'Other'
        END as major_clade,
        COUNT(DISTINCT o.observation_uuid) as affected_obs
    FROM all_breaking_taxa abt
    LEFT JOIN observations o ON o.taxon_id = abt.taxon_id
    GROUP BY major_clade
)
SELECT * FROM clade_impacts
ORDER BY affected_obs DESC;

\echo ''
\echo '=== END OF IMPACT ANALYSIS ==='