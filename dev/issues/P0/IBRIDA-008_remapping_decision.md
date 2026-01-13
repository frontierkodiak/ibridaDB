# IBRIDA-008: REVISED DECISION - Proceed with Remapping

## Correction on iNaturalist Approach

You're correct - iNaturalist **DOES actively remap** observations when taxonomy changes:
- **Swaps/Merges**: Automatic 1:1 remapping
- **Splits**: Uses atlases or bumps to common ancestor
- They maintain a **single evolving taxonomy**, not mixed versions

## Revised Decision: **REMAP NOW**

### Why Remap:
1. **Matches iNaturalist's actual approach** - single consistent taxonomy
2. **Cleaner exports** - no mixed taxonomy versions
3. **Reproducibility preserved** - via backup + reversible mapping
4. **Avoids accumulating debt** - each monthly update would add more drift

### Remapping Strategy:

#### 1. RANK_CHANGED Taxa (594 taxa)
- **Simple**: Keep same taxon_id, taxonomy metadata updates automatically
- **No observation updates needed** for rank changes

#### 2. DEACTIVATED Taxa (11,661 taxa)
Remapping hierarchy:
- **Subspecies/Variety → Species** (when species still active)
- **Species → Genus** (when genus still active)
- **Genus → Family** (when family still active)
- **Otherwise → mark as unmapped** for manual review

#### 3. Implementation Plan:

```sql
-- A. Create backup table
CREATE TABLE observations_r1_backup AS 
SELECT observation_uuid, taxon_id FROM observations;

-- B. Create remapping rules
CREATE TABLE r1_r2_remap_rules (
    old_taxon_id INTEGER PRIMARY KEY,
    new_taxon_id INTEGER,
    remap_type VARCHAR(50),
    confidence VARCHAR(20)
);

-- C. Execute remapping
UPDATE observations o
SET taxon_id = r.new_taxon_id
FROM r1_r2_remap_rules r
WHERE o.taxon_id = r.old_taxon_id;

-- D. To reverse (if needed)
UPDATE observations o
SET taxon_id = b.taxon_id
FROM observations_r1_backup b
WHERE o.observation_uuid = b.observation_uuid;
```

### High-Impact Remappings:

| Old Taxon | Type | Observations | Remap To |
|-----------|------|--------------|----------|
| Thomomys bottae (species) | DEACTIVATED | 7,692 | → Thomomys (genus) |
| Yucca brevifolia brevifolia (variety) | DEACTIVATED | 1,584 | → Yucca brevifolia (species) |
| Vicugna vicugna (species) | DEACTIVATED | 1,399 | → Vicugna (genus) or Lama? |
| Trachylepis margaritifera (species) | DEACTIVATED | 1,603 | → Trachylepis (genus) |
| Ontholestes cingulatus (species) | DEACTIVATED | 1,091 | → Ontholestes (genus) - but genus also deactivated! |

### Special Cases Needing Attention:

1. **Ontholestes** - Entire genus deactivated (1,568 obs)
   - Need to map to family or higher level
   
2. **Vicugna/Lama** - Genus merger situation
   - May need species-level remapping rules

3. **Multiple subspecies → species** 
   - Leptophis ahaetulla subspecies (425 obs total)
   - Need to verify parent species is active

### Advantages of Remapping Now:
1. ✅ Single taxonomy version (like iNaturalist)
2. ✅ Clean exports without version conflicts
3. ✅ Reversible via backup table
4. ✅ Sets precedent for future monthly updates

### Risks & Mitigations:
- **Risk**: Some remappings may be imperfect
- **Mitigation**: Keep backup + document all remapping decisions

- **Risk**: Complex genus/family reorganizations
- **Mitigation**: Flag low-confidence remappings for review

## Final Recommendation:

**PROCEED WITH REMAPPING** using this approach:

1. Create `observations_r1_backup` table
2. Build `r1_r2_remap_rules` with confidence levels
3. Execute high-confidence remappings first
4. Review low-confidence cases manually
5. Document all decisions in remapping table

This aligns with iNaturalist's approach while maintaining full reversibility via our backup.