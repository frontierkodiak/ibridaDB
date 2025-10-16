# IBRIDA-008: FINAL DECISION - Taxa with >25 Observations ARE Affected

## IRONCLAD FINDINGS

### YES - Key Clades ARE Impacted

**25 taxa with >25 observations are affected by breaking changes**, specifically:

#### MAMMALIA (9 taxa, 10,948 observations):
- **Thomomys bottae** (7,692 obs) - pocket gopher - DEACTIVATED
- **Vicugna vicugna** (1,399 obs) - vicuña - DEACTIVATED  
- **Lutrogale perspicillata** (1,216 obs) - smooth-coated otter - DEACTIVATED
- **Aonyx capensis** (250 obs) - African clawless otter - DEACTIVATED
- **Vicugna** genus (142 obs) - DEACTIVATED
- **Eptesicus furinalis** (124 obs) - bat species - DEACTIVATED
- Plus 3 more Thomomys/Allactaga species

#### REPTILIA (9 taxa, 2,804 observations):
- **Trachylepis margaritifera** (1,603 obs) - rainbow skink - DEACTIVATED
- **Pristurus rupestris** (374 obs) - rock gecko - RANK_CHANGED to complex
- **Leptophis ahaetulla occidentalis** (315 obs) - parrot snake - DEACTIVATED
- **Homopholis walbergii** (277 obs) - Wahlberg's gecko - DEACTIVATED
- Plus 5 more snake/gecko subspecies

#### ANGIOSPERMAE (3 taxa, 1,801 observations):
- **Yucca brevifolia brevifolia** (1,584 obs) - Joshua tree variety - DEACTIVATED
- **Collinsia heterophylla heterophylla** (116 obs) - RANK_CHANGED subspecies→variety
- **Acer rubrum drummondii** (101 obs) - RANK_CHANGED subspecies→variety

#### INSECTA (4 taxa, 1,568 observations):
- **Ontholestes cingulatus** (1,091 obs) - rove beetle - DEACTIVATED
- **Ontholestes tessellatus** (267 obs) - rove beetle - DEACTIVATED
- **Ontholestes** genus (144 obs) - DEACTIVATED
- **Ontholestes haroldi** (66 obs) - rove beetle - DEACTIVATED

#### NOT IMPACTED (or minimal):
- **AVES** - Only 10 breaking taxa total, none with >25 obs
- **AMPHIBIA** - 68 breaking taxa but none with >25 obs

## DECISION: Proceed with Documented Non-Remapping

Given that key clades ARE affected, we will:

### 1. Create Mapping Artifact ✅
- Table `r1_r2_taxa_mapping` created with all 12,255 breaking changes
- Documents which taxa changed and how
- Enables future remapping if needed

### 2. Proceed WITHOUT Immediate Remapping
- Import r2 observations with r2 taxonomy
- Keep r1 observations unchanged
- Accept mixed taxonomy versions in the same table

### 3. Document Impact for Future Reference
Key impacts to be aware of:
- **Thomomys bottae** (pocket gopher) - 7,692 observations will have inconsistent taxonomy
- **Vicugna** (vicuña) - genus/species split affects 1,541 observations
- **Yucca brevifolia** (Joshua tree) - variety deactivation affects 1,584 observations
- **Ontholestes** (rove beetles) - genus deactivation affects 1,568 observations

### 4. Mitigation Strategy
- For future exports requiring consistency, filter by single release
- Regenerate `expanded_taxa` after r2 import
- Consider batch remapping for high-impact taxa if issues arise

## Rationale for Non-Remapping

1. **Scale**: While impactful taxa exist, they represent <0.01% of 180M observations
2. **Complexity**: Remapping would require complex logic for genus→species splits
3. **Precedent**: iNaturalist handles taxonomy drift this way
4. **Reversibility**: We have the mapping artifact to remap later if needed
5. **Backup**: `ibrida-v0-r1` database preserved for r1 reproducibility

## Next Steps

1. ✅ Mapping artifact created (`r1_r2_taxa_mapping` table)
2. → Proceed with IBRIDA-009 (r2 delta import)
3. → Regenerate `expanded_taxa` with r2 taxonomy
4. → Document in release notes which clades have taxonomy inconsistencies

## Note for Future Exports

When exporting these clades, be aware:
- **Mammalia exports** may have Thomomys/Vicugna inconsistencies
- **Reptilia exports** may have gecko/snake subspecies issues  
- **Angiospermae exports** may have variety/subspecies confusion
- **Insecta exports** will miss Ontholestes observations if filtering by genus

Consider adding a `taxonomy_version` or `release_id` filter to exports when consistency is critical.