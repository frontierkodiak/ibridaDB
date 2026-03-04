-- Simplified check for high-observation taxa (>25 obs) affected by breaking changes

\timing on
\echo '=== HIGH OBSERVATION TAXA IMPACT CHECK ==='
\echo ''

-- Step 1: Find all breaking taxa
CREATE TEMP TABLE breaking_taxa AS
SELECT 
    r1.taxon_id,
    r1.name,
    r1.rank,
    r1.ancestry,
    r1.active as r1_active,
    r2.active as r2_active,
    r1.rank as r1_rank,
    r2.rank as r2_rank
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
WHERE (r1.active = true AND r2.active = false) OR r1.rank != r2.rank;

CREATE INDEX idx_bt_taxon ON breaking_taxa(taxon_id);
ANALYZE breaking_taxa;

\echo 'Total breaking taxa:'
SELECT COUNT(*) FROM breaking_taxa;

-- Step 2: Sample check - count observations for first 100 breaking taxa
\echo ''
\echo 'Sample: observation counts for first 100 breaking taxa'
WITH sample AS (
    SELECT taxon_id, name, rank FROM breaking_taxa LIMIT 100
)
SELECT 
    s.taxon_id,
    s.name,
    s.rank,
    COUNT(o.observation_uuid) as obs_count
FROM sample s
LEFT JOIN observations o ON s.taxon_id = o.taxon_id
GROUP BY s.taxon_id, s.name, s.rank
HAVING COUNT(o.observation_uuid) > 25
ORDER BY obs_count DESC;

-- Step 3: Check specific key clades
\echo ''
\echo 'Checking Angiospermae breaking taxa (ancestry contains /47125/):'
SELECT taxon_id, name, rank,
    CASE 
        WHEN r1_active = true AND r2_active = false THEN 'DEACTIVATED'
        WHEN r1_rank != r2_rank THEN 'RANK_CHANGED'
    END as change_type
FROM breaking_taxa
WHERE ancestry LIKE '%/47125/%'
LIMIT 20;

\echo ''
\echo 'Checking Aves breaking taxa (ancestry contains /3/):'
SELECT taxon_id, name, rank,
    CASE 
        WHEN r1_active = true AND r2_active = false THEN 'DEACTIVATED'
        WHEN r1_rank != r2_rank THEN 'RANK_CHANGED'
    END as change_type
FROM breaking_taxa
WHERE ancestry LIKE '%/3/%'
LIMIT 20;

\echo ''
\echo 'Checking Mammalia breaking taxa (ancestry contains /40151/):'
SELECT taxon_id, name, rank,
    CASE 
        WHEN r1_active = true AND r2_active = false THEN 'DEACTIVATED'
        WHEN r1_rank != r2_rank THEN 'RANK_CHANGED'
    END as change_type
FROM breaking_taxa
WHERE ancestry LIKE '%/40151/%'
LIMIT 20;

\echo ''
\echo 'Checking Amphibia breaking taxa (ancestry contains /20978/):'
SELECT taxon_id, name, rank,
    CASE 
        WHEN r1_active = true AND r2_active = false THEN 'DEACTIVATED'
        WHEN r1_rank != r2_rank THEN 'RANK_CHANGED'
    END as change_type
FROM breaking_taxa
WHERE ancestry LIKE '%/20978/%'
LIMIT 20;

\echo ''
\echo 'Checking Reptilia breaking taxa (ancestry contains /26036/):'
SELECT taxon_id, name, rank,
    CASE 
        WHEN r1_active = true AND r2_active = false THEN 'DEACTIVATED'
        WHEN r1_rank != r2_rank THEN 'RANK_CHANGED'
    END as change_type
FROM breaking_taxa
WHERE ancestry LIKE '%/26036/%'
LIMIT 20;

\echo ''
\echo 'Checking Insecta breaking taxa (ancestry contains /47158/):'
SELECT taxon_id, name, rank,
    CASE 
        WHEN r1_active = true AND r2_active = false THEN 'DEACTIVATED'
        WHEN r1_rank != r2_rank THEN 'RANK_CHANGED'
    END as change_type
FROM breaking_taxa
WHERE ancestry LIKE '%/47158/%'
LIMIT 20;

-- Step 4: Count breaking taxa by major clade
\echo ''
\echo 'BREAKING TAXA COUNT BY MAJOR CLADE:'
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
    COUNT(*) as breaking_taxa_count
FROM breaking_taxa
GROUP BY clade
ORDER BY breaking_taxa_count DESC;

DROP TABLE breaking_taxa;