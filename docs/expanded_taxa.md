# expanded_taxa Table Documentation

This document provides comprehensive documentation for the `expanded_taxa` table in ibridaDB, which serves as the foundation for taxonomic data processing and export operations.

## Overview

The `expanded_taxa` table is a derived table that transforms iNaturalist's compact taxonomy representation into an expanded format optimized for efficient querying, filtering, and analysis. It "unpacks" the ancestry string from the original `taxa` table into discrete columns for each taxonomic rank level, enabling fast clade-based filtering and ancestor lookups without recursive string parsing.

## Purpose and Generation

- **Source**: Generated from the iNaturalist `taxa` table via the `expand_taxa.sh` script
- **Primary Function**: Enable efficient taxonomic filtering and ancestor searches in the export pipeline
- **Key Enhancement**: Integrates common names from Catalog of Life Data Package (ColDP) through the ColDP integration pipeline

## Complete Table Schema

### Core Identification Columns

| Column      | Type              | Description |
|-------------|-------------------|-------------|
| taxonID     | integer           | Primary key; unique taxon identifier from iNaturalist |
| rankLevel   | double precision  | Numeric indicator of the taxonomic rank (lower numbers = higher taxonomic hierarchy) |
| rank        | varchar(255)      | Human-readable taxonomic rank label (e.g., "species", "genus", "family") |
| name        | varchar(255)      | Scientific name of the taxon |
| taxonActive | boolean           | Indicates whether the taxon is currently active in iNaturalist's taxonomy |

### Common Name Integration

| Column      | Type              | Description |
|-------------|-------------------|-------------|
| commonName  | varchar(255)      | Primary common name for the taxon (populated from ColDP integration) |

### Immediate Ancestor Columns

These columns provide direct access to parent taxa in the taxonomic hierarchy:

| Column                           | Type              | Description |
|----------------------------------|-------------------|-------------|
| immediateMajorAncestor_taxonID   | integer           | Taxon ID of the immediate major ancestor (next rank level up in major taxonomy) |
| immediateMajorAncestor_rankLevel | double precision  | Rank level of the immediate major ancestor |
| immediateAncestor_taxonID        | integer           | Taxon ID of the immediate ancestor (direct parent in taxonomy) |
| immediateAncestor_rankLevel      | double precision  | Rank level of the immediate ancestor |

### Expanded Taxonomic Hierarchy Columns

For each rank level in the set `{5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30, 32, 33, 33.5, 34, 34.5, 35, 37, 40, 43, 44, 45, 47, 50, 53, 57, 60, 67, 70}`, the following three columns are provided:

#### Column Pattern: `L{level}_*`

- **`L{level}_taxonID`** (integer): Taxon ID at the specified rank level
- **`L{level}_name`** (varchar(255)): Scientific name at the specified rank level  
- **`L{level}_commonName`** (varchar(255)): Common name at the specified rank level (from ColDP)

#### Examples:
- **L5 (subspecies level)**: `L5_taxonID`, `L5_name`, `L5_commonName`
- **L10 (species level)**: `L10_taxonID`, `L10_name`, `L10_commonName`
- **L20 (genus level)**: `L20_taxonID`, `L20_name`, `L20_commonName`
- **L40 (order level)**: `L40_taxonID`, `L40_name`, `L40_commonName`
- **L50 (class level)**: `L50_taxonID`, `L50_name`, `L50_commonName`
- **L70 (kingdom level)**: `L70_taxonID`, `L70_name`, `L70_commonName`

## Rank Level Mapping

The numeric rank levels correspond to standard taxonomic ranks:

| Level | Standard Rank    | Notes |
|-------|------------------|-------|
| 5     | subspecies       | Finest taxonomic resolution |
| 10    | species          | Primary species identification level |
| 11    | species group    | |
| 12    | species subgroup | |
| 13    | species complex  | |
| 15    | hybrid           | |
| 20    | genus            | Primary genus level |
| 24    | subgenus         | |
| 25    | section          | |
| 26    | subsection       | |
| 27    | series           | |
| 30    | tribe            | |
| 32    | subtribe         | |
| 33    | supertribe       | |
| 33.5  | subfamily        | |
| 34    | family           | |
| 34.5  | epifamily        | |
| 35    | superfamily      | |
| 37    | infraorder       | |
| 40    | order            | |
| 43    | suborder         | |
| 44    | infraorder       | |
| 45    | superorder       | |
| 47    | infraclass       | |
| 50    | class            | |
| 53    | subclass         | |
| 57    | superclass       | |
| 60    | subphylum        | |
| 67    | phylum           | |
| 70    | kingdom          | Broadest taxonomic category |

## Indexing Strategy

The table includes strategic indexing for optimal query performance:

### Primary Index
- **`expanded_taxa_pkey`**: Primary key on `taxonID`

### Core Column Indexes
- **`idx_expanded_taxa_name`**: B-tree index on `name` for scientific name lookups
- **`idx_expanded_taxa_ranklevel`**: B-tree index on `rankLevel` for rank-based filtering
- **`idx_expanded_taxa_taxonid`**: B-tree index on `taxonID` for ID-based lookups

### Taxonomic Level Indexes
Optimized for clade-based filtering:
- **`idx_expanded_taxa_l10_taxonid`**: Species-level filtering
- **`idx_expanded_taxa_l20_taxonid`**: Genus-level filtering
- **`idx_expanded_taxa_l30_taxonid`**: Tribe-level filtering
- **`idx_expanded_taxa_l40_taxonid`**: Order-level filtering
- **`idx_expanded_taxa_l50_taxonid`**: Class-level filtering
- **`idx_expanded_taxa_l60_taxonid`**: Subphylum-level filtering
- **`idx_expanded_taxa_l70_taxonid`**: Kingdom-level filtering

### Immediate Ancestor Indexes
For efficient ancestor lookups:
- **`idx_immediate_ancestor_taxon_id`**: B-tree index on `immediateAncestor_taxonID`
- **`idx_immediate_major_ancestor_taxon_id`**: B-tree index on `immediateMajorAncestor_taxonID`

## Common Use Cases

### 1. Species-Level Filtering
```sql
SELECT * FROM expanded_taxa 
WHERE L10_taxonID = 12345;
```

### 2. Clade-Based Filtering (e.g., all birds)
```sql
SELECT * FROM expanded_taxa 
WHERE L50_taxonID = 3; -- Aves class
```

### 3. Finding All Taxa with Common Names
```sql
SELECT taxonID, name, commonName 
FROM expanded_taxa 
WHERE commonName IS NOT NULL;
```

### 4. Ancestor Lookup
```sql
SELECT child.name, parent.name as parent_name
FROM expanded_taxa child
JOIN expanded_taxa parent ON child.immediateAncestor_taxonID = parent.taxonID
WHERE child.taxonID = 12345;
```

### 5. Taxonomic Hierarchy Traversal
```sql
SELECT 
    name as species_name,
    L20_name as genus,
    L34_name as family,
    L40_name as order,
    L50_name as class,
    L70_name as kingdom
FROM expanded_taxa 
WHERE rankLevel = 10 -- species level
LIMIT 10;
```

## Integration with Other Tables

### ColDP Integration
- **Source**: Common names populated via `inat_to_coldp_taxon_map` table
- **Process**: ColDP integration scripts map iNaturalist taxa to Catalog of Life taxa and populate common name fields
- **Coverage**: Both the general `commonName` field and rank-specific `LXX_commonName` fields

### Export Pipeline Integration
- **Primary Use**: Foundation table for all export operations
- **Filtering**: Enables efficient clade-based filtering in export pipeline
- **Joins**: Joined with `observations` table via `taxon_id` = `taxonID`

### Foreign Key Relationships
- **Referenced by**: `inat_to_coldp_taxon_map.inat_taxon_id` → `expanded_taxa.taxonID`
- **References**: Implicit relationships through `LXX_taxonID` columns to other taxa within the same table

## Data Quality Considerations

### Completeness
- **Core Fields**: All taxa should have `taxonID`, `name`, `rank`, and `rankLevel`
- **Hierarchy Fields**: `LXX_*` columns populated based on actual taxonomic position
- **Common Names**: May be NULL for taxa without ColDP mappings

### Data Consistency
- **Active Taxa**: Filter on `taxonActive = true` for current taxonomy
- **Rank Levels**: Consistent with iNaturalist's taxonomic hierarchy
- **Ancestor Relationships**: Validated through immediate ancestor columns

## Performance Optimization Tips

1. **Use Indexed Columns**: Always filter on indexed `LXX_taxonID` columns for clade filtering
2. **Rank-Level Filtering**: Use `rankLevel` for efficient rank-based queries
3. **Common Name Searches**: Consider using ILIKE with indexes for case-insensitive searches
4. **Batch Operations**: For large taxonomy updates, use batch operations with appropriate transaction boundaries

## Version History

### v0r1 Enhancements
- **Added**: Four immediate ancestor columns for enhanced lineage tracking
- **Enhanced**: Complete ColDP integration with common names at all taxonomic levels
- **Improved**: Extended indexing strategy for immediate ancestor lookups

### Previous Versions
- **v0r0**: Basic expanded taxonomy without common names or immediate ancestor tracking

## Maintenance and Updates

The `expanded_taxa` table is regenerated during the ingestion pipeline and updated during ColDP integration. Key maintenance operations:

1. **Ingestion**: Table recreated from latest iNaturalist taxonomy dump
2. **ColDP Integration**: Common names populated/updated via ColDP mapping process
3. **Index Maintenance**: Indexes automatically maintained during updates
4. **Validation**: Post-update validation ensures data integrity and completeness

For detailed operational procedures, see the main [ingestion documentation](ingest.md) and [ColDP integration documentation](coldp_integration.md).