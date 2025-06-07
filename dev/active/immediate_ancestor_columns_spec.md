# Specification: Immediate Ancestor Columns for expanded_taxa

**Date:** 2025-05-24  
**Author:** Claude Code  
**Status:** Draft

## Overview

This specification proposes adding four new columns to the `expanded_taxa` table to provide direct access to immediate ancestor information, improving efficiency for downstream applications that frequently need parent taxon data.

## Motivation

Currently, to find the immediate parent of a taxon, downstream applications must iterate through all L*_taxonID columns (L5, L10, L11, etc.) to find the first non-null value. This is inefficient, especially when performed frequently. By pre-computing and storing immediate ancestor information, we can:

1. Reduce client-side processing overhead
2. Simplify parent lookup logic in applications
3. Enable more efficient queries for parent-child relationships
4. Support applications that need to distinguish between major-rank and any-rank parents

## Proposed Columns

### 1. Immediate Major-Rank Ancestor
- **Column Name:** `immediateMajorAncestor_taxonID` (Integer)
- **Column Name:** `immediateMajorAncestor_rankLevel` (Float)
- **Description:** The nearest ancestor with a rankLevel that is a multiple of 10

### 2. Immediate Ancestor (Any Rank)
- **Column Name:** `immediateAncestor_taxonID` (Integer)
- **Column Name:** `immediateAncestor_rankLevel` (Float)
- **Description:** The immediate parent taxon, regardless of whether it's a major or minor rank

### Column Placement
Insert these columns after `taxonActive` and before the L5_* columns:
```
taxonID
rankLevel
rank
name
commonName
taxonActive
immediateMajorAncestor_taxonID     <-- NEW
immediateMajorAncestor_rankLevel   <-- NEW
immediateAncestor_taxonID          <-- NEW
immediateAncestor_rankLevel        <-- NEW
L5_taxonID
...
```

## Implementation Logic

### Computing Immediate Ancestor
1. For each taxon, find the L*_taxonID column with the smallest rankLevel that is greater than the taxon's own rankLevel
2. This represents the immediate parent in the taxonomic hierarchy

### Computing Immediate Major-Rank Ancestor
1. For each taxon, find the L*_taxonID column where:
   - The rankLevel is a multiple of 10 (major rank)
   - The rankLevel is the smallest value greater than the taxon's own rankLevel
2. If the immediate ancestor is already a major rank, both sets of columns will have the same values

### Special Cases
- **Root taxa (e.g., Animalia):** All four columns will be NULL
- **Direct children of root:** immediateAncestor columns will point to root, immediateMajorAncestor may be NULL if root isn't a major rank
- **Taxa at major ranks:** If their immediate parent is also a major rank, both column sets will be identical

## Algorithm Pseudocode

```python
def compute_immediate_ancestors(taxon_row):
    taxon_rank = taxon_row.rankLevel
    
    # Find immediate ancestor (any rank)
    immediate_ancestor_id = None
    immediate_ancestor_rank = None
    min_rank_diff = float('inf')
    
    for rank_level in [5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30, 32, 33, 33.5, 34, 34.5, 35, 37, 40, 43, 44, 45, 47, 50, 53, 57, 60, 67, 70]:
        col_name = f"L{str(rank_level).replace('.', '_')}_taxonID"
        ancestor_id = getattr(taxon_row, col_name)
        
        if ancestor_id is not None and rank_level > taxon_rank:
            if rank_level - taxon_rank < min_rank_diff:
                min_rank_diff = rank_level - taxon_rank
                immediate_ancestor_id = ancestor_id
                immediate_ancestor_rank = rank_level
    
    # Find immediate major-rank ancestor
    immediate_major_ancestor_id = None
    immediate_major_ancestor_rank = None
    
    for rank_level in [10, 20, 30, 40, 50, 60, 70]:
        col_name = f"L{rank_level}_taxonID"
        ancestor_id = getattr(taxon_row, col_name)
        
        if ancestor_id is not None and rank_level > taxon_rank:
            immediate_major_ancestor_id = ancestor_id
            immediate_major_ancestor_rank = rank_level
            break
    
    return {
        'immediateAncestor_taxonID': immediate_ancestor_id,
        'immediateAncestor_rankLevel': immediate_ancestor_rank,
        'immediateMajorAncestor_taxonID': immediate_major_ancestor_id,
        'immediateMajorAncestor_rankLevel': immediate_major_ancestor_rank
    }
```

## TODOs

- [ ] **IMPORTANT:** Update the corresponding ORM model in `polli-typus` module to include these new columns for v0.2.0
- [ ] Create migration script to add columns to existing expanded_taxa table
- [ ] Create population script to compute and fill values for all existing taxa
- [ ] Add indexes on new taxonID columns for efficient lookups
- [ ] Update any existing documentation about expanded_taxa schema
- [ ] Export TSV of complete expanded_taxa table for SQLite deployments

## SQLite Export Considerations

### Size Estimates
- Current expanded_taxa: ~1.34M rows × ~111 columns
- With common names populated: Additional string data per row
- With 4 new columns: Minimal increase (2 integers + 2 floats per row)
- Estimated TSV size: 2-4 GB uncompressed (needs verification after implementation)

### Optimization Options for SQLite
1. **Full table export:** Simple TSV export, largest size but preserves all data
2. **Selective column export:** Exclude rarely-used ancestor columns for smaller footprint
3. **Normalized export:** Split into multiple tables (taxa, ancestors) to reduce redundancy
4. **Compressed format:** Use gzip compression for ~70-80% size reduction

### Recommendations
1. Start with full TSV export to establish baseline size
2. If size is problematic (>5GB), consider:
   - Creating a "lite" version without all ancestor columns
   - Using compression for distribution
   - Implementing lazy-loading of ancestor data in client applications

## Performance Considerations

### Benefits
- O(1) parent lookup instead of O(n) where n = number of rank levels
- Reduced network traffic for client-server architectures
- Simplified client code

### Trade-offs
- Increased storage: ~16 bytes per row (4 columns × 4 bytes each)
- One-time computation cost during initial population
- Maintenance overhead when taxonomic hierarchy changes

## Next Steps

1. Review and approve this specification
2. Update expanded_taxa.py ORM model
3. Create and test population script
4. Run population after common names are fully populated
5. Export TSV for SQLite deployments
6. Update polli-typus ORM model

## Notes

- This change maintains backward compatibility - existing columns are unchanged
- The redundancy between immediate and immediateMajor ancestors is intentional for query efficiency
- Consider adding database triggers to maintain these columns if taxa hierarchy is updated dynamically