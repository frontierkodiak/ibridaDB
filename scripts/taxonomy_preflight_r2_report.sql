-- IBRIDA-008: Taxonomy Preflight (report-only)
-- Compares r1 taxa with r2 staging taxa for breaking changes

\timing on
\set ON_ERROR_STOP on

-- Set staging schema if not provided
\if :{?stg_schema}
\else
\set stg_schema 'stg_inat_20250827'
\endif

\echo 'Using staging schema :' :stg_schema

-- Step 1: Find cutoff date from existing observations
\echo 'Step 1: Finding r1 cutoff date (max observed_on)...'
CREATE TEMP TABLE r1_cutoff AS
SELECT MAX(observed_on) as max_date FROM observations;

\echo 'R1 cutoff date:'
SELECT * FROM r1_cutoff;

-- Step 2: Identify NEW observations in r2 (observed after cutoff or not present)
\echo 'Step 2: Identifying new r2 observations...'
CREATE TEMP TABLE r2_new_obs AS
SELECT DISTINCT observation_uuid, taxon_id
FROM :stg_schema.observations o
WHERE o.observed_on > (SELECT max_date FROM r1_cutoff)
   OR NOT EXISTS (SELECT 1 FROM observations r1 WHERE r1.observation_uuid = o.observation_uuid);

\echo 'Count of new r2 observations:'
SELECT COUNT(*) as new_obs_count FROM r2_new_obs;

-- Step 3: Get unique taxa referenced by new observations
\echo 'Step 3: Finding taxa referenced by new observations...'
CREATE TEMP TABLE r2_new_taxa AS
SELECT DISTINCT taxon_id FROM r2_new_obs WHERE taxon_id IS NOT NULL;

\echo 'Count of unique taxa in new observations:'
SELECT COUNT(*) as new_taxa_count FROM r2_new_taxa;

-- Step 4: Compare taxa between r1 and r2 for these taxon_ids
\echo 'Step 4: Comparing taxa between r1 and r2...'
CREATE TEMP TABLE taxa_diffs AS
SELECT 
    COALESCE(r1.taxon_id, r2.taxon_id) as taxon_id,
    r1.name as r1_name,
    r2.name as r2_name,
    r1.ancestry as r1_ancestry,
    r2.ancestry as r2_ancestry,
    r1.rank_level as r1_rank_level,
    r2.rank_level as r2_rank_level,
    r1.rank as r1_rank,
    r2.rank as r2_rank,
    r1.active as r1_active,
    r2.active as r2_active,
    CASE 
        WHEN r1.taxon_id IS NULL THEN 'NEW_TAXON'
        WHEN r2.taxon_id IS NULL THEN 'REMOVED_TAXON'
        WHEN r1.ancestry != r2.ancestry THEN 'BREAKING_ANCESTRY'
        WHEN r1.rank_level != r2.rank_level THEN 'BREAKING_RANK_LEVEL'
        WHEN r1.rank != r2.rank THEN 'BREAKING_RANK'
        WHEN r1.active = true AND r2.active = false THEN 'BREAKING_DEACTIVATION'
        WHEN r1.name != r2.name THEN 'NONBREAKING_NAME'
        WHEN r1.active = false AND r2.active = true THEN 'NONBREAKING_REACTIVATION'
        ELSE 'NO_CHANGE'
    END as change_type
FROM 
    (SELECT * FROM taxa WHERE taxon_id IN (SELECT taxon_id FROM r2_new_taxa)) r1
FULL OUTER JOIN 
    (SELECT * FROM :stg_schema.taxa WHERE taxon_id IN (SELECT taxon_id FROM r2_new_taxa)) r2
ON r1.taxon_id = r2.taxon_id
WHERE 
    r1.taxon_id IS NULL OR r2.taxon_id IS NULL OR
    r1.name != r2.name OR r1.ancestry != r2.ancestry OR 
    r1.rank_level != r2.rank_level OR r1.rank != r2.rank OR 
    r1.active != r2.active;

-- Step 5: Report findings
\echo ''
\echo '=== TAXONOMY PREFLIGHT RESULTS (REPORT) ==='
\echo ''
\echo 'Summary by change type:'
SELECT change_type, COUNT(*) as count 
FROM taxa_diffs 
GROUP BY change_type 
ORDER BY 
    CASE 
        WHEN change_type LIKE 'BREAKING%' THEN 1
        WHEN change_type = 'REMOVED_TAXON' THEN 2
        WHEN change_type = 'NEW_TAXON' THEN 3
        ELSE 4
    END;

\echo ''
\echo 'BREAKING changes detail (sample):'
SELECT taxon_id, r1_name, r2_name, change_type
FROM taxa_diffs 
WHERE change_type LIKE 'BREAKING%' OR change_type = 'REMOVED_TAXON'
ORDER BY change_type, taxon_id
LIMIT 20;

\echo ''
\echo 'Total BREAKING changes:'
SELECT COUNT(*) as breaking_count
FROM taxa_diffs 
WHERE change_type LIKE 'BREAKING%' OR change_type = 'REMOVED_TAXON';

-- Export CSVs for review
\echo ''
\echo 'Exporting CSVs...'
\copy (SELECT * FROM taxa_diffs WHERE change_type LIKE 'BREAKING%' OR change_type = 'REMOVED_TAXON' ORDER BY change_type, taxon_id) TO '/tmp/r2_taxa_breaking.csv' CSV HEADER;
\copy (SELECT * FROM taxa_diffs WHERE change_type = 'NONBREAKING_NAME' ORDER BY taxon_id) TO '/tmp/r2_taxa_nameonly.csv' CSV HEADER;
\copy (SELECT * FROM taxa_diffs WHERE change_type = 'NEW_TAXON' ORDER BY taxon_id) TO '/tmp/r2_taxa_new.csv' CSV HEADER;

\echo ''
\echo 'CSV files exported to /tmp/'
\echo 'NOTE: This script does NOT block on breaking changes; review before proceeding.'
