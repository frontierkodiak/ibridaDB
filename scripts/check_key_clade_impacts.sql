-- Check impact on KEY CLADES for taxa with >25 observations
-- Focus on: angiospermae, primary_terrestrial_arthropoda (insecta + arachnida), 
-- aves, reptilia, mammalia, amphibia

\timing on
\echo '=== KEY CLADE IMPACT ANALYSIS ==='
\echo ''

-- First create temp table of breaking taxa with observation counts
CREATE TEMP TABLE breaking_taxa_with_counts AS
SELECT 
    r1.taxon_id,
    r1.name,
    r1.rank,
    r1.ancestry,
    CASE 
        WHEN r1.active = true AND r2.active = false THEN 'DEACTIVATED'
        WHEN r1.rank != r2.rank THEN 'RANK_CHANGED'
    END as change_type,
    COUNT(o.observation_uuid) as obs_count
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
LEFT JOIN observations o ON r1.taxon_id = o.taxon_id
WHERE (r1.active = true AND r2.active = false) OR r1.rank != r2.rank
GROUP BY r1.taxon_id, r1.name, r1.rank, r1.ancestry, r2.active, r2.rank;

CREATE INDEX idx_btc_obs ON breaking_taxa_with_counts(obs_count);
ANALYZE breaking_taxa_with_counts;

\echo 'Total breaking taxa with >25 observations:'
SELECT COUNT(*) as taxa_count, SUM(obs_count) as total_obs
FROM breaking_taxa_with_counts
WHERE obs_count > 25;

\echo ''
\echo 'Breaking taxa with >25 obs by change type:'
SELECT change_type, COUNT(*) as taxa_count, SUM(obs_count) as total_obs
FROM breaking_taxa_with_counts
WHERE obs_count > 25
GROUP BY change_type;

\echo ''
\echo 'KEY CLADE IMPACTS (taxa with >25 obs):'
\echo '======================================='

\echo ''
\echo '1. ANGIOSPERMAE (flowering plants, L57=47125):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count
FROM breaking_taxa_with_counts
WHERE obs_count > 25
  AND ancestry LIKE '%/47125/%'
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo '2. AVES (birds, L50=3):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count
FROM breaking_taxa_with_counts
WHERE obs_count > 25
  AND ancestry LIKE '%/3/%'
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo '3. MAMMALIA (L50=40151):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count
FROM breaking_taxa_with_counts
WHERE obs_count > 25
  AND ancestry LIKE '%/40151/%'
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo '4. AMPHIBIA (L50=20978):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count
FROM breaking_taxa_with_counts
WHERE obs_count > 25
  AND ancestry LIKE '%/20978/%'
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo '5. REPTILIA (L50=26036):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count
FROM breaking_taxa_with_counts
WHERE obs_count > 25
  AND ancestry LIKE '%/26036/%'
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo '6. INSECTA (L50=47158):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count
FROM breaking_taxa_with_counts
WHERE obs_count > 25
  AND ancestry LIKE '%/47158/%'
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo '7. ARACHNIDA (L50=47119):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count
FROM breaking_taxa_with_counts
WHERE obs_count > 25
  AND ancestry LIKE '%/47119/%'
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo 'SUMMARY BY MAJOR GROUP (>25 obs only):'
WITH clade_summary AS (
    SELECT 
        CASE 
            WHEN ancestry LIKE '%/47125/%' THEN 'Angiospermae'
            WHEN ancestry LIKE '%/3/%' THEN 'Aves'
            WHEN ancestry LIKE '%/40151/%' THEN 'Mammalia'
            WHEN ancestry LIKE '%/20978/%' THEN 'Amphibia'
            WHEN ancestry LIKE '%/26036/%' THEN 'Reptilia'
            WHEN ancestry LIKE '%/47158/%' THEN 'Insecta'
            WHEN ancestry LIKE '%/47119/%' THEN 'Arachnida'
            ELSE 'Other'
        END as clade,
        COUNT(*) as affected_taxa,
        SUM(obs_count) as total_observations
    FROM breaking_taxa_with_counts
    WHERE obs_count > 25
    GROUP BY clade
)
SELECT * FROM clade_summary
ORDER BY total_observations DESC;

\echo ''
\echo 'Top 30 affected taxa overall (>25 obs):'
SELECT 
    taxon_id,
    name,
    rank,
    change_type,
    obs_count,
    CASE 
        WHEN ancestry LIKE '%/47125/%' THEN 'Angiospermae'
        WHEN ancestry LIKE '%/3/%' THEN 'Aves'
        WHEN ancestry LIKE '%/40151/%' THEN 'Mammalia'
        WHEN ancestry LIKE '%/20978/%' THEN 'Amphibia'
        WHEN ancestry LIKE '%/26036/%' THEN 'Reptilia'
        WHEN ancestry LIKE '%/47158/%' THEN 'Insecta'
        WHEN ancestry LIKE '%/47119/%' THEN 'Arachnida'
        ELSE 'Other'
    END as major_clade
FROM breaking_taxa_with_counts
WHERE obs_count > 25
ORDER BY obs_count DESC
LIMIT 30;

DROP TABLE breaking_taxa_with_counts;