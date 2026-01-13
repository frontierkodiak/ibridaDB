#!/bin/bash
# Execute R1→R2 taxonomy remapping
# This script remaps existing observations to r2 taxonomy

set -e  # Exit on error

echo "============================================"
echo "R1→R2 TAXONOMY REMAPPING EXECUTION SCRIPT"
echo "============================================"
echo ""
echo "This will remap existing observations from r1 to r2 taxonomy"
echo "The process is REVERSIBLE via the backup table"
echo ""
read -p "Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Database connection
DB_NAME="ibrida-v0"
DB_USER="postgres"
CONTAINER="ibridaDB"

echo ""
echo "Step 1: Creating backup of current observation taxonomy..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    CREATE TABLE IF NOT EXISTS observations_r1_backup AS 
    SELECT 
        observation_uuid, 
        taxon_id as original_taxon_id,
        NOW() as backup_date
    FROM observations;
    
    CREATE INDEX idx_obs_backup_uuid ON observations_r1_backup(observation_uuid);
    CREATE INDEX idx_obs_backup_taxon ON observations_r1_backup(original_taxon_id);
"

echo "Backup created. Checking row count..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    SELECT COUNT(*) as backed_up_observations FROM observations_r1_backup;
"

echo ""
echo "Step 2: Creating and populating remapping rules..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME << 'EOF'
-- Create remapping rules table
CREATE TABLE IF NOT EXISTS r1_r2_remap_rules (
    old_taxon_id INTEGER PRIMARY KEY,
    new_taxon_id INTEGER,
    remap_type VARCHAR(50),
    old_name VARCHAR(255),
    new_name VARCHAR(255),
    confidence VARCHAR(20),
    observation_count INTEGER DEFAULT 0,
    notes TEXT
);

TRUNCATE r1_r2_remap_rules;

-- Rule 1: RANK_CHANGED taxa stay the same (no observation update needed)
INSERT INTO r1_r2_remap_rules (
    old_taxon_id, new_taxon_id, remap_type, 
    old_name, new_name, confidence, notes
)
SELECT 
    r1.taxon_id,
    r1.taxon_id,  -- Same ID, just metadata changed
    'RANK_CHANGE_ONLY',
    r1.name,
    r2.name,
    'HIGH',
    'Rank changed from ' || r1.rank || ' to ' || r2.rank || ' - no remap needed'
FROM taxa r1
JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
WHERE r1.rank != r2.rank
ON CONFLICT DO NOTHING;

-- Rule 2: Map deactivated subspecies/varieties to parent species
-- Extract parent from ancestry string
WITH subspecies_to_species AS (
    SELECT 
        r1.taxon_id as old_id,
        r1.name as old_name,
        r1.ancestry,
        r1.rank,
        -- Extract immediate parent ID from ancestry
        REGEXP_REPLACE(r1.ancestry, '^.*?/(\d+)/' || r1.taxon_id::text || '$', '\1')::INTEGER as parent_id
    FROM taxa r1
    JOIN stg_inat_20250827.taxa r2 ON r1.taxon_id = r2.taxon_id
    WHERE r1.active = true 
      AND r2.active = false
      AND r1.rank IN ('subspecies', 'variety', 'form')
)
INSERT INTO r1_r2_remap_rules (
    old_taxon_id, new_taxon_id, remap_type,
    old_name, new_name, confidence, notes
)
SELECT 
    s.old_id,
    s.parent_id,
    'SUBSPECIES_TO_SPECIES',
    s.old_name,
    p.name,
    CASE 
        WHEN p.active = true THEN 'HIGH'
        ELSE 'LOW'
    END,
    'Deactivated ' || s.rank || ' mapped to parent species'
FROM subspecies_to_species s
LEFT JOIN stg_inat_20250827.taxa p ON s.parent_id = p.taxon_id
WHERE p.taxon_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Rule 3: Handle specific known cases
-- Ontholestes genus deactivated - map to subfamily Staphylininae (359911)
INSERT INTO r1_r2_remap_rules VALUES 
    (47945, 359911, 'GENUS_TO_SUBFAMILY', 'Ontholestes', 'Staphylininae', 'MEDIUM', 0, 'Genus deactivated, mapped to subfamily'),
    (47946, 359911, 'SPECIES_TO_SUBFAMILY', 'Ontholestes brasilianus', 'Staphylininae', 'LOW', 0, 'Via deactivated genus'),
    (47947, 359911, 'SPECIES_TO_SUBFAMILY', 'Ontholestes cingulatus', 'Staphylininae', 'LOW', 0, 'Via deactivated genus'),
    (47948, 359911, 'SPECIES_TO_SUBFAMILY', 'Ontholestes haroldi', 'Staphylininae', 'LOW', 0, 'Via deactivated genus'),
    (47952, 359911, 'SPECIES_TO_SUBFAMILY', 'Ontholestes tessellatus', 'Staphylininae', 'LOW', 0, 'Via deactivated genus')
ON CONFLICT DO NOTHING;

-- Update observation counts
UPDATE r1_r2_remap_rules r
SET observation_count = (
    SELECT COUNT(*) FROM observations o WHERE o.taxon_id = r.old_taxon_id
);

-- Show remapping summary
SELECT 
    remap_type,
    confidence,
    COUNT(*) as rule_count,
    SUM(observation_count) as total_observations
FROM r1_r2_remap_rules
GROUP BY remap_type, confidence
ORDER BY SUM(observation_count) DESC;
EOF

echo ""
echo "Step 3: Preview high-impact remappings (>100 observations)..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    SELECT 
        old_taxon_id,
        old_name,
        new_taxon_id,
        new_name,
        remap_type,
        confidence,
        observation_count
    FROM r1_r2_remap_rules
    WHERE observation_count > 100
    ORDER BY observation_count DESC
    LIMIT 20;
"

echo ""
read -p "Proceed with remapping? (yes/no): " confirm2
if [ "$confirm2" != "yes" ]; then
    echo "Aborted at remapping stage. Backup preserved."
    exit 1
fi

echo ""
echo "Step 4: Executing remapping (HIGH confidence only first)..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    UPDATE observations o
    SET taxon_id = r.new_taxon_id
    FROM r1_r2_remap_rules r
    WHERE o.taxon_id = r.old_taxon_id
      AND r.confidence = 'HIGH'
      AND r.old_taxon_id != r.new_taxon_id;  -- Skip RANK_CHANGE_ONLY
    
    SELECT 'Remapped', COUNT(*), 'observations with HIGH confidence'
    FROM observations o
    JOIN r1_r2_remap_rules r ON o.taxon_id = r.new_taxon_id
    WHERE r.confidence = 'HIGH';
"

echo ""
echo "Step 5: Creating remapping audit log..."
docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c "
    CREATE TABLE IF NOT EXISTS r1_r2_remap_audit (
        observation_uuid UUID,
        old_taxon_id INTEGER,
        new_taxon_id INTEGER,
        remap_type VARCHAR(50),
        confidence VARCHAR(20),
        remapped_at TIMESTAMP DEFAULT NOW()
    );
    
    INSERT INTO r1_r2_remap_audit
    SELECT 
        o.observation_uuid,
        b.original_taxon_id,
        o.taxon_id,
        r.remap_type,
        r.confidence,
        NOW()
    FROM observations o
    JOIN observations_r1_backup b ON o.observation_uuid = b.observation_uuid
    JOIN r1_r2_remap_rules r ON b.original_taxon_id = r.old_taxon_id
    WHERE o.taxon_id != b.original_taxon_id;
    
    SELECT COUNT(*) as remapped_observations FROM r1_r2_remap_audit;
"

echo ""
echo "============================================"
echo "REMAPPING COMPLETE"
echo "============================================"
echo ""
echo "To REVERSE the remapping if needed:"
echo "  docker exec $CONTAINER psql -U $DB_USER -d $DB_NAME -c \\"
echo "    UPDATE observations o"
echo "    SET taxon_id = b.original_taxon_id"
echo "    FROM observations_r1_backup b"
echo "    WHERE o.observation_uuid = b.observation_uuid;\""
echo ""
echo "Backup tables preserved:"
echo "  - observations_r1_backup (full backup)"
echo "  - r1_r2_remap_rules (mapping rules)"
echo "  - r1_r2_remap_audit (what was changed)"
echo ""