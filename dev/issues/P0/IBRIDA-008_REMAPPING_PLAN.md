# IBRIDA-008: Deferred Remapping Plan

## Summary
Full remapping plan developed but **TABLED** for future execution. This document preserves the complete plan.

## Key Findings
- **12,255 breaking changes** between r1 and r2 taxonomy
- **25 high-observation taxa** (>25 obs) in key clades affected
- Most impacted: Mammalia (10,948 obs), Reptilia (2,804 obs), Angiospermae (1,801 obs), Insecta (1,568 obs)

## Remapping Strategy (For Future Execution)

### Phase 1: Backup
```sql
CREATE TABLE observations_r1_backup AS 
SELECT observation_uuid, taxon_id FROM observations;
```

### Phase 2: Build Rules
Created in `r1_r2_remap_rules` table with confidence levels:
- **HIGH**: Subspecies→Species when parent active
- **MEDIUM**: Genus→Family for deactivated genera  
- **LOW**: Complex reorganizations needing review

### Phase 3: Execute
```bash
# Full script ready at:
/home/caleb/repo/ibridaDB/scripts/execute_r1_r2_remapping.sh
```

### Phase 4: Reversal (if needed)
```sql
UPDATE observations o
SET taxon_id = b.original_taxon_id
FROM observations_r1_backup b
WHERE o.observation_uuid = b.observation_uuid;
```

## High-Impact Taxa Requiring Remapping

| Taxon | Observations | Current Issue | Proposed Remap |
|-------|--------------|---------------|----------------|
| Thomomys bottae | 7,692 | Species deactivated | → Thomomys (genus) |
| Trachylepis margaritifera | 1,603 | Species deactivated | → Trachylepis (genus) |
| Yucca brevifolia brevifolia | 1,584 | Variety deactivated | → Yucca brevifolia (species) |
| Vicugna vicugna | 1,399 | Species deactivated | → Vicugna or Lama (needs review) |
| Lutrogale perspicillata | 1,216 | Species deactivated | → Lutrogale (genus) |
| Ontholestes (4 species) | 1,568 | Entire genus deactivated | → Staphylininae (subfamily) |

## Tables Created
1. `r1_r2_taxa_mapping` - Documents all 12,255 changes
2. `r1_r2_remap_rules` - Remapping logic with confidence scores
3. `observations_r1_backup` - Ready to create when executing

## Why Tabled
- More urgent needs with expanded_taxa and TaxonomyService
- Remapping can be executed later with full reversibility
- Mixed taxonomy acceptable short-term

## When to Execute Remapping
Consider executing when:
1. Export inconsistencies become problematic
2. Before next major update (r3)
3. After expanded_taxa regeneration stabilizes

## Files for Reference
- `/scripts/execute_r1_r2_remapping.sh` - Complete execution script
- `/scripts/r1_r2_remapping_strategy.sql` - Analysis queries
- `/scripts/create_taxa_mapping_artifact.sql` - Mapping documentation
- This document - Strategic overview

## Current Path Forward
1. **Import r2 WITHOUT remapping** (mixed taxonomy accepted)
2. **Regenerate expanded_taxa** with r2 taxonomy
3. **Execute remapping later** if/when needed using this plan