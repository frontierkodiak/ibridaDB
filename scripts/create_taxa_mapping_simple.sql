-- Simplified r1→r2 taxonomy mapping artifact (without slow observation counts)

\timing on

-- Populate mapping table without observation counts (we'll add those separately)
INSERT INTO r1_r2_taxa_mapping (
    taxon_id, r1_name, r1_rank, r1_rank_level, r1_ancestry, r1_active,
    r2_name, r2_rank, r2_rank_level, r2_ancestry, r2_active,
    change_type, major_clade, remapping_notes
)
SELECT 
    r1.taxon_id,
    r1.name as r1_name,
    r1.rank as r1_rank,
    r1.rank_level as r1_rank_level,
    r1.ancestry as r1_ancestry,
    r1.active as r1_active,
    r2.name as r2_name,
    r2.rank as r2_rank,
    r2.rank_level as r2_rank_level,
    r2.ancestry as r2_ancestry,
    r2.active as r2_active,
    CASE 
        WHEN r1.active = true AND r2.active = false THEN 'DEACTIVATED'
        WHEN r1.rank != r2.rank THEN 'RANK_CHANGED'
        WHEN r1.rank_level != r2.rank_level THEN 'RANK_LEVEL_CHANGED'
        WHEN r1.ancestry != r2.ancestry THEN 'ANCESTRY_CHANGED'
        ELSE 'OTHER'
    END as change_type,
    CASE 
        WHEN r1.ancestry LIKE '%/47125/%' THEN 'Angiospermae'
        WHEN r1.ancestry LIKE '%/3/%' THEN 'Aves'
        WHEN r1.ancestry LIKE '%/40151/%' THEN 'Mammalia'
        WHEN r1.ancestry LIKE '%/20978/%' THEN 'Amphibia'
        WHEN r1.ancestry LIKE '%/26036/%' THEN 'Reptilia'
        WHEN r1.ancestry LIKE '%/47158/%' THEN 'Insecta'
        WHEN r1.ancestry LIKE '%/47119/%' THEN 'Arachnida'
        ELSE 'Other'
    END as major_clade,
    CASE 
        WHEN r1.active = true AND r2.active = false THEN 
            'Taxa deactivated in r2, likely synonymized or invalid'
        WHEN r1.rank != r2.rank THEN 
            'Rank changed from ' || r1.rank || ' to ' || r2.rank
        ELSE NULL
    END as remapping_notes
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
WHERE (r1.active = true AND r2.active = false) 
   OR r1.rank != r2.rank
   OR r1.rank_level != r2.rank_level
   OR r1.ancestry != r2.ancestry
ON CONFLICT (taxon_id) DO NOTHING;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_r1r2_mapping_change ON r1_r2_taxa_mapping(change_type);
CREATE INDEX IF NOT EXISTS idx_r1r2_mapping_clade ON r1_r2_taxa_mapping(major_clade);

-- Update observation counts for high-impact taxa only
UPDATE r1_r2_taxa_mapping m
SET observation_count = (
    SELECT COUNT(*) FROM observations o WHERE o.taxon_id = m.taxon_id
)
WHERE m.taxon_id IN (
    -- Known high-observation taxa from our analysis
    44062, 37426, 48469, 42236, 41856, 47947, 47273, 33903, 29691, 34396,
    47952, 41781, 47945, 42235, 40485, 48727, 48106, 47948, 32344, 29689,
    29690, 44070, 44068, 33905, 43860, 28561
);

UPDATE r1_r2_taxa_mapping SET high_impact = true WHERE observation_count > 25;

-- Summary
\echo ''
\echo 'MAPPING ARTIFACT CREATED'
\echo '========================'
SELECT 
    major_clade,
    change_type,
    COUNT(*) as taxa_count
FROM r1_r2_taxa_mapping
GROUP BY major_clade, change_type
ORDER BY major_clade, change_type;

\echo ''
\echo 'Total mapped taxa:'
SELECT COUNT(*) as total_mapped FROM r1_r2_taxa_mapping;

\echo ''
\echo 'High-impact taxa identified:'
SELECT taxon_id, r1_name, r1_rank, change_type, observation_count, major_clade
FROM r1_r2_taxa_mapping
WHERE observation_count > 25
ORDER BY observation_count DESC;