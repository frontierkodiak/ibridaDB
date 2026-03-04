-- R1→R2 Taxonomy Remapping Strategy
-- REVERSIBLE remapping to maintain single taxonomy version

\timing on
\echo 'R1→R2 REMAPPING STRATEGY'
\echo '========================'
\echo ''

-- Step 1: Create backup of original taxon_ids before remapping
CREATE TABLE IF NOT EXISTS observations_r1_taxonomy_backup (
    observation_uuid UUID PRIMARY KEY,
    original_taxon_id INTEGER,
    remapped_taxon_id INTEGER,
    remap_type VARCHAR(50),
    remap_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Step 2: Analyze remapping needs
\echo 'Analyzing remapping requirements...'
\echo ''

-- 2A. RANK_CHANGED taxa (easy - same taxon, different rank)
\echo 'RANK_CHANGED taxa (can remap in-place):'
SELECT 
    r1.taxon_id,
    r1.name,
    r1.rank || ' → ' || r2.rank as rank_change,
    COUNT(o.observation_uuid) as affected_obs
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
LEFT JOIN observations o ON o.taxon_id = r1.taxon_id
WHERE r1.rank != r2.rank
GROUP BY r1.taxon_id, r1.name, r1.rank, r2.rank
HAVING COUNT(o.observation_uuid) > 0
ORDER BY COUNT(o.observation_uuid) DESC
LIMIT 10;

-- 2B. DEACTIVATED taxa (complex - need to find replacement)
\echo ''
\echo 'DEACTIVATED taxa (need replacement mapping):'
WITH deactivated AS (
    SELECT 
        r1.taxon_id,
        r1.name,
        r1.rank,
        r1.ancestry,
        COUNT(o.observation_uuid) as affected_obs
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    LEFT JOIN observations o ON o.taxon_id = r1.taxon_id
    WHERE r1.active = true AND r2.active = false
    GROUP BY r1.taxon_id, r1.name, r1.rank, r1.ancestry
    HAVING COUNT(o.observation_uuid) > 0
)
SELECT 
    d.taxon_id,
    d.name,
    d.rank,
    d.affected_obs,
    -- Try to find parent that's still active
    CASE 
        WHEN d.rank = 'subspecies' THEN 'Map to species level'
        WHEN d.rank = 'variety' THEN 'Map to species level'
        WHEN d.rank = 'species' THEN 'Map to genus level'
        WHEN d.rank = 'genus' THEN 'Map to family level'
        ELSE 'Needs manual review'
    END as suggested_action
FROM deactivated d
ORDER BY d.affected_obs DESC
LIMIT 20;

-- Step 3: Create remapping rules table
CREATE TABLE IF NOT EXISTS r1_r2_remapping_rules (
    old_taxon_id INTEGER PRIMARY KEY,
    new_taxon_id INTEGER,
    remap_type VARCHAR(50), -- 'RANK_CHANGE', 'DEACTIVATED_TO_PARENT', 'DEACTIVATED_TO_SYNONYM'
    old_name VARCHAR(255),
    new_name VARCHAR(255),
    confidence VARCHAR(20), -- 'HIGH', 'MEDIUM', 'LOW'
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Step 4: For RANK_CHANGED taxa, mapping is simple (same taxon_id)
\echo ''
\echo 'Creating RANK_CHANGE mappings (1:1)...'
INSERT INTO r1_r2_remapping_rules (old_taxon_id, new_taxon_id, remap_type, old_name, new_name, confidence)
SELECT 
    r1.taxon_id as old_taxon_id,
    r1.taxon_id as new_taxon_id, -- Same ID, just rank changed
    'RANK_CHANGE' as remap_type,
    r1.name as old_name,
    r2.name as new_name,
    'HIGH' as confidence
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
WHERE r1.rank != r2.rank
ON CONFLICT (old_taxon_id) DO NOTHING;

-- Step 5: For DEACTIVATED subspecies/varieties, map to species
\echo ''
\echo 'Creating DEACTIVATED subspecies→species mappings...'
WITH deactivated_subspecies AS (
    SELECT 
        r1.taxon_id,
        r1.name,
        r1.ancestry,
        -- Extract parent species ID from ancestry
        CASE 
            WHEN r1.rank IN ('subspecies', 'variety', 'form') THEN
                -- Get the last number before this taxon_id in ancestry
                SUBSTRING(r1.ancestry FROM '.*?/(\d+)/' || r1.taxon_id::text)::INTEGER
            ELSE NULL
        END as parent_species_id
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.active = true AND r2.active = false
      AND r1.rank IN ('subspecies', 'variety', 'form')
)
INSERT INTO r1_r2_remapping_rules (old_taxon_id, new_taxon_id, remap_type, old_name, new_name, confidence, notes)
SELECT 
    ds.taxon_id as old_taxon_id,
    ds.parent_species_id as new_taxon_id,
    'DEACTIVATED_TO_PARENT' as remap_type,
    ds.name as old_name,
    t.name as new_name,
    'MEDIUM' as confidence,
    'Auto-mapped subspecies/variety to parent species'
FROM deactivated_subspecies ds
LEFT JOIN stg_inat_20250827.taxa t ON ds.parent_species_id = t.taxon_id
WHERE ds.parent_species_id IS NOT NULL
  AND t.active = true -- Parent is still active
ON CONFLICT (old_taxon_id) DO NOTHING;

-- Step 6: Summary of remapping rules
\echo ''
\echo 'REMAPPING RULES SUMMARY:'
SELECT 
    remap_type,
    confidence,
    COUNT(*) as rule_count
FROM r1_r2_remapping_rules
GROUP BY remap_type, confidence
ORDER BY remap_type, confidence;

\echo ''
\echo 'Sample remapping rules:'
SELECT old_taxon_id, old_name, new_taxon_id, new_name, remap_type, confidence
FROM r1_r2_remapping_rules
ORDER BY 
    CASE confidence 
        WHEN 'HIGH' THEN 1
        WHEN 'MEDIUM' THEN 2
        ELSE 3
    END
LIMIT 20;

\echo ''
\echo 'Observations that will be remapped:'
SELECT 
    r.remap_type,
    COUNT(DISTINCT o.observation_uuid) as observations_to_remap
FROM r1_r2_remapping_rules r
JOIN observations o ON o.taxon_id = r.old_taxon_id
GROUP BY r.remap_type;

\echo ''
\echo '=== REMAPPING READY ==='
\echo 'To execute remapping:'
\echo '1. Backup observations: INSERT INTO observations_r1_taxonomy_backup'
\echo '2. Update observations: UPDATE observations SET taxon_id = new_taxon_id'
\echo '3. To reverse: UPDATE observations SET taxon_id = original_taxon_id FROM backup'