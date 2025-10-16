# IBRIDA-008: Taxonomy Breaking Changes - Decision Document

## Executive Summary
The r2 taxonomy update contains **12,255 breaking changes** (11,661 deactivations + 594 rank changes). These changes affect existing observations and require a strategic decision on how to proceed.

## Key Findings

### 1. Scale of Breaking Changes
- **11,661 taxa deactivated** (mostly species: 8,161)
- **594 rank changes** (mostly subspecies→variety: 330)
- **48,576 new taxa** added in r2

### 2. Nature of Deactivated Taxa
From our sample analysis, most deactivated taxa are:
- Obscure species with few/no observations
- Subspecies being consolidated or renamed
- Genera being merged (e.g., Vicugna, Aonyx)

Sample observation counts for deactivated taxa:
- Most have 0-10 observations
- Some subspecies have 50-300 observations
- A few genera have 100+ observations

### 3. Estimated Impact
- At least **17,000+ observations** affected (extrapolating from sample)
- Likely <1% of total observations (180M total)
- Most affected observations are non-research grade or rare taxa

### 4. Types of Changes
Most common patterns:
- **Species deactivations**: Synonymization, invalid taxa
- **Subspecies→variety**: Botanical rank standardization  
- **Genus mergers**: Taxonomic consolidation

## Options for Moving Forward

### Option A: Full Remapping (Clean but Expensive)
1. Accept all r2 taxonomy changes
2. Remap affected r1 observations to new taxa
3. Regenerate expanded_taxa table
4. **Pros**: Single consistent taxonomy version
5. **Cons**: Breaks r1 reproducibility, requires complex remapping logic

### Option B: Dual Taxonomy (Keep r1 + r2 Separate)
1. Keep r1 observations with r1 taxonomy
2. Add r2 observations with r2 taxonomy
3. Flag observations by taxonomy version
4. **Pros**: Preserves r1 reproducibility
5. **Cons**: Mixed taxonomy in same table, complex exports

### Option C: Selective Import (Skip Breaking Taxa)
1. Import only r2 observations with non-breaking taxa
2. Skip observations referencing changed taxa
3. **Pros**: Simple, safe
4. **Cons**: Loses data, incomplete r2 import

### Option D: Accept Changes As-Is (Pragmatic)
1. Accept that deactivated taxa won't match
2. Import r2 observations with new taxonomy
3. Document the inconsistency
4. **Pros**: Simple to implement
5. **Cons**: Some queries may return unexpected results

## Recommendation

**Proceed with Option D (Accept Changes As-Is) with mitigations:**

1. **Import r2 observations** with r2 taxonomy
2. **Keep r1 observations** unchanged (no remapping)
3. **Regenerate expanded_taxa** after import to reflect r2 taxonomy
4. **Document breaking changes** in a `taxa_changes_r1_r2` table
5. **Add release tracking** to identify which observations use which taxonomy version

### Rationale:
- Most deactivated taxa have minimal observations
- The affected observations (<1%) don't justify complex remapping
- iNaturalist's taxonomy evolves naturally - we should follow their lead
- We have the r1 backup for reproducibility if needed
- Future exports can filter by release if taxonomy consistency is critical

### Mitigation Strategy:
1. Create `taxa_breaking_changes` table documenting all changes
2. Add `release_id` to observation queries when taxonomy consistency matters
3. For critical exports (research datasets), can filter to single release
4. Consider future monthly updates will have similar (smaller) changes

## Next Steps
1. ✅ Document decision in IBRIDA-008
2. Proceed with IBRIDA-009 (r2 delta import) WITHOUT remapping
3. After import, regenerate expanded_taxa with r2 taxonomy
4. Create documentation table of breaking changes for reference

## Note for Future
This pattern (taxonomy drift) will occur with every iNaturalist update. We should:
- Expect 100-1000s of taxonomy changes monthly
- Design pipelines to handle mixed taxonomy versions
- Consider taxonomy version tracking in core schema