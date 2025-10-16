-- Check actual observation impact of breaking changes
-- Focus on taxa that have observations in our database

\timing on
\echo 'OBSERVATION IMPACT ANALYSIS'
\echo '==========================='
\echo ''

-- Create temp table of breaking taxa for efficiency
CREATE TEMP TABLE breaking_taxa AS
SELECT 
    r1.taxon_id,
    r1.name,
    r1.rank,
    CASE 
        WHEN r1.active = true AND r2.active = false THEN 'DEACTIVATED'
        WHEN r1.rank != r2.rank THEN 'RANK_CHANGED'
    END as change_type
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
WHERE (r1.active = true AND r2.active = false) OR r1.rank != r2.rank;

CREATE INDEX idx_breaking_taxa ON breaking_taxa(taxon_id);
ANALYZE breaking_taxa;

\echo 'Breaking taxa summary:'
SELECT change_type, COUNT(*) as taxa_count
FROM breaking_taxa
GROUP BY change_type;

\echo ''
\echo 'Checking how many breaking taxa actually have observations:'
SELECT 
    bt.change_type,
    COUNT(DISTINCT bt.taxon_id) as total_taxa,
    COUNT(DISTINCT CASE WHEN o.taxon_id IS NOT NULL THEN bt.taxon_id END) as taxa_with_obs,
    COUNT(DISTINCT o.observation_uuid) as total_observations
FROM breaking_taxa bt
LEFT JOIN observations o ON bt.taxon_id = o.taxon_id
GROUP BY bt.change_type;

\echo ''
\echo 'Top 20 impacted taxa by observation count:'
SELECT 
    bt.taxon_id,
    bt.name,
    bt.rank,
    bt.change_type,
    COUNT(o.observation_uuid) as obs_count
FROM breaking_taxa bt
JOIN observations o ON bt.taxon_id = o.taxon_id
GROUP BY bt.taxon_id, bt.name, bt.rank, bt.change_type
ORDER BY obs_count DESC
LIMIT 20;

\echo ''
\echo 'Impact on research-grade observations:'
SELECT 
    bt.change_type,
    COUNT(DISTINCT o.observation_uuid) as total_obs,
    COUNT(DISTINCT CASE WHEN o.quality_grade = 'research' THEN o.observation_uuid END) as research_grade_obs,
    COUNT(DISTINCT CASE WHEN o.quality_grade = 'needs_id' THEN o.observation_uuid END) as needs_id_obs
FROM breaking_taxa bt
JOIN observations o ON bt.taxon_id = o.taxon_id
GROUP BY bt.change_type;

\echo ''
\echo 'FINAL SUMMARY:'
SELECT 
    COUNT(DISTINCT o.observation_uuid) as total_affected_obs,
    ROUND(100.0 * COUNT(DISTINCT o.observation_uuid) / 
          (SELECT COUNT(*) FROM observations), 3) as pct_of_all_obs
FROM breaking_taxa bt
JOIN observations o ON bt.taxon_id = o.taxon_id;

DROP TABLE breaking_taxa;