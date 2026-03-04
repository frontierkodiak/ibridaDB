-- Create r1→r2 taxonomy mapping artifact
-- This allows future remapping if needed

\timing on

-- Create permanent mapping table
CREATE TABLE IF NOT EXISTS r1_r2_taxa_mapping (
    taxon_id INTEGER PRIMARY KEY,
    r1_name VARCHAR(255),
    r1_rank VARCHAR(50),
    r1_rank_level FLOAT,
    r1_ancestry TEXT,
    r1_active BOOLEAN,
    r2_name VARCHAR(255),
    r2_rank VARCHAR(50),
    r2_rank_level FLOAT,
    r2_ancestry TEXT,
    r2_active BOOLEAN,
    change_type VARCHAR(50),
    observation_count INTEGER,
    research_grade_count INTEGER,
    major_clade VARCHAR(50),
    remapping_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Populate with all breaking changes
INSERT INTO r1_r2_taxa_mapping
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
    (SELECT COUNT(*) FROM observations o WHERE o.taxon_id = r1.taxon_id) as observation_count,
    (SELECT COUNT(*) FROM observations o WHERE o.taxon_id = r1.taxon_id AND o.quality_grade = 'research') as research_grade_count,
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

-- Create indexes for efficient querying
CREATE INDEX idx_r1r2_mapping_change ON r1_r2_taxa_mapping(change_type);
CREATE INDEX idx_r1r2_mapping_clade ON r1_r2_taxa_mapping(major_clade);
CREATE INDEX idx_r1r2_mapping_obs ON r1_r2_taxa_mapping(observation_count DESC);

-- Add high-impact flag for taxa with many observations
ALTER TABLE r1_r2_taxa_mapping ADD COLUMN high_impact BOOLEAN DEFAULT FALSE;
UPDATE r1_r2_taxa_mapping SET high_impact = true WHERE observation_count > 25;

-- Summary statistics
\echo ''
\echo 'R1→R2 TAXA MAPPING ARTIFACT CREATED'
\echo '===================================='
SELECT 
    major_clade,
    change_type,
    COUNT(*) as taxa_count,
    SUM(observation_count) as total_obs,
    SUM(CASE WHEN high_impact THEN 1 ELSE 0 END) as high_impact_taxa
FROM r1_r2_taxa_mapping
GROUP BY major_clade, change_type
ORDER BY SUM(observation_count) DESC
LIMIT 20;

\echo ''
\echo 'High-impact taxa (>25 obs) by clade:'
SELECT 
    major_clade,
    COUNT(*) as high_impact_taxa,
    SUM(observation_count) as total_observations,
    STRING_AGG(r1_name || ' (' || observation_count || ')', ', ' ORDER BY observation_count DESC LIMIT 3) as top_taxa
FROM r1_r2_taxa_mapping
WHERE high_impact = true
GROUP BY major_clade
ORDER BY SUM(observation_count) DESC;

\echo ''
\echo 'Mapping artifact saved to table: r1_r2_taxa_mapping'
\echo 'This can be used for future remapping operations if needed.'