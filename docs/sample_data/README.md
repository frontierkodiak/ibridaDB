# Sample Data for Testing

This directory contains sample data files that can be used for unit testing with SQLite or other lightweight database solutions. These samples are extracted from the ibridaDB database and provide realistic data structures and relationships for testing.

## Files Included

### ColDP Tables

These files contain samples from the Catalog of Life Data Package (ColDP) tables:

- `coldp_name_usage.tsv`: Scientific names and taxonomic information
- `coldp_vernacular_name.tsv`: Common names in various languages
- `coldp_distribution.tsv`: Geographic distribution information
- `coldp_media.tsv`: Links to images, sounds, and other media
- `coldp_reference.tsv`: Bibliographic references
- `coldp_type_material.tsv`: Type specimen information

### Mapping and Taxa Tables

- `inat_to_coldp_taxon_map.tsv`: Crosswalk between iNaturalist taxa and Catalog of Life taxa
- `expanded_taxa_sample.tsv`: Basic sample of the expanded_taxa table with taxonomic hierarchies and common names
- `expanded_taxa_lca_sample.tsv`: Specialized sample containing the full taxonomy for bees (Anthophila) and wasps (Vespoidea), designed for testing Lowest Common Ancestor (LCA) algorithms and taxonomic distance calculations

## Usage for SQLite Testing

These files can be used to create a lightweight SQLite database for unit testing, particularly for the typus SDK. Here's an example of how to load them into SQLite:

```python
import sqlite3
import pandas as pd

# Create SQLite connection
conn = sqlite3.connect('test_db.sqlite')

# Load each TSV file into a table
for table_name in ['coldp_name_usage', 'coldp_vernacular_name', 'coldp_distribution', 
                  'coldp_media', 'coldp_reference', 'coldp_type_material',
                  'inat_to_coldp_taxon_map', 'expanded_taxa_sample']:
    df = pd.read_csv(f'{table_name}.tsv', sep='\t')
    df.to_sql(table_name, conn, if_exists='replace', index=False)
    
# Optionally load the specialized LCA sample data
df_lca = pd.read_csv('expanded_taxa_lca_sample.tsv', sep='\t')
df_lca.to_sql('expanded_taxa', conn, if_exists='replace', index=False)

# Create view for expanded_taxa_cmn if needed
conn.execute('''
CREATE VIEW IF NOT EXISTS expanded_taxa_cmn AS
SELECT * FROM expanded_taxa_sample
''')

conn.commit()
conn.close()
```

## Table Relationships

The relationships between these tables mirror those in the full database:

- `inat_to_coldp_taxon_map.inat_taxon_id` → `expanded_taxa_sample.taxonID`
- `inat_to_coldp_taxon_map.col_taxon_id` → `coldp_name_usage.ID`
- `coldp_vernacular_name.taxonID` → `coldp_name_usage.ID`
- `coldp_distribution.taxonID` → `coldp_name_usage.ID`
- `coldp_media.taxonID` → `coldp_name_usage.ID`
- `coldp_reference.ID` is referenced by other tables' `referenceID` fields

## Notes

- These samples contain a limited subset of records for testing purposes
- All data relationships are preserved to allow for testing of joins and foreign key relationships
- The expanded_taxa_sample table includes full taxonomic hierarchies with common names for testing
- These files can be easily imported into a SQLite database or any other database system

## Lowest Common Ancestor (LCA) Testing

The `expanded_taxa_lca_sample.tsv` file contains a carefully selected set of taxa from the honey bee (Apis) and wasp (Vespa/Vespula) lineages, which can be used to test:

1. **Lowest Common Ancestor (LCA) functionality** - For example:
   - LCA of Apis mellifera (47219) and Vespa crabro (54327) is Hymenoptera (47201)
   - LCA of Bombus (52775) and Apis (47220) is Apidae (47221)
   - LCA of Vespula (61356) and Vespa (54328) is Vespidae (52747)

2. **Taxonomic Distance Calculation** - For calculating both inclusive and exclusive distance:
   - Distance from Apis mellifera to Vespa crabro (inclusive of rank boundaries)
   - Distance from Bombus to Apis (excluding minor ranks)

3. **Rank-Level Navigation** - For traversing up and down the taxonomy at specific rank levels:
   - Finding all species under Apidae
   - Finding the order of any given species
   - Extracting the full lineage of a taxon

When using this sample for LCA testing, the taxonID field (630955 in the error message) is correctly included in the dataset.

### Regenerating the LCA Sample Data

To regenerate or update the LCA sample data, a SQL query file is provided in `generate_lca_sample.sql`. This file contains the following query that exports ALL columns from the expanded_taxa table for selected taxa:

```sql
-- SQL query for generating LCA sample data
-- Export all columns for the specified taxa

COPY (
    SELECT *
    FROM expanded_taxa t
    WHERE
        -- Include targeted taxa IDs and names for bees, wasps, and their ancestors
        t."taxonID" IN (630955, 47201, 47216, 47337, 47338, 184884, 47369, 47218, 52747, 52775, 295935)
        OR t."name" IN ('Hymenoptera', 'Anthophila', 'Apis', 'Apis mellifera', 'Apidae', 'Animalia', 'Arthropoda', 'Insecta',
                        'Vespidae', 'Vespa', 'Vespa mandarinia', 'Vespoidea', 'Scoliidae', 'Vespa crabro', 'Vespinae', 'Vespula', 'Vespula vulgaris')
) TO '/tmp/expanded_taxa_lca_sample.tsv' WITH (FORMAT CSV, DELIMITER E'\t', HEADER TRUE);
```

To run this query and generate the sample data:

```bash
# Copy the SQL file to the Docker container
docker cp docs/sample_data/generate_lca_sample.sql ibridaDB:/tmp/

# Execute the SQL query
docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -f /tmp/generate_lca_sample.sql

# Copy the results back from the container
docker cp ibridaDB:/tmp/expanded_taxa_lca_sample.tsv docs/sample_data/expanded_taxa_lca_sample.tsv
```

This process ensures the sample includes all columns from the expanded_taxa table, including all rank levels (L5 through L70) with their taxonID, name, and commonName fields, which is critical for accurate LCA testing.