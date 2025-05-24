# ColDP Integration Documentation

This document provides detailed information about the integration of Catalog of Life Data Package (ColDP) data into ibridaDB. It covers the data ingestion process, mapping to iNaturalist taxa, and the use of ColDP data to enhance biodiversity information.

## Overview

The ColDP integration pipeline consists of three main steps:

1. **Loading ColDP Tables**: Ingesting the raw TSV files from a ColDP export into staging tables
2. **Mapping to iNaturalist Taxa**: Creating a mapping between iNaturalist taxa and ColDP taxa through exact and fuzzy matching
3. **Enriching Expanded Taxa**: Updating the expanded_taxa table with common names and other data from ColDP

## ColDP Data Structure

ColDP (Catalog of Life Data Package) is a standardized format for sharing taxonomic data. It consists of several TSV files, each representing a different aspect of taxonomic information. The key files ingested by ibridaDB include:

- **NameUsage.tsv**: Core taxonomic information (scientific names, status, hierarchy)
- **VernacularName.tsv**: Common names in various languages
- **Distribution.tsv**: Geographic distribution information
- **Media.tsv**: Links to images, sounds, and other media
- **Reference.tsv**: Bibliographic references
- **TypeMaterial.tsv**: Type specimen information

## Database Tables

### 1. ColDP Staging Tables

These tables directly mirror the structure of the ColDP TSV files, serving as the initial landing point for the data.

#### ColdpNameUsage

**Purpose**: Stores scientific names and taxonomic information from the ColDP NameUsage.tsv file.

**Schema**:
```sql
CREATE TABLE coldp_name_usage_staging (
    ID                  VARCHAR(64) PRIMARY KEY,
    scientificName      TEXT INDEX,
    authorship          TEXT,
    rank                VARCHAR(50) INDEX,
    status              VARCHAR(50) INDEX,
    parentID            VARCHAR(64),
    
    -- Name components
    uninomial           TEXT,
    genericName         TEXT,
    infragenericEpithet TEXT,
    specificEpithet     TEXT,
    infraspecificEpithet TEXT,
    basionymID          VARCHAR(64),
    
    -- Higher taxonomy for homonym resolution
    family              TEXT,
    order               TEXT,
    class_              TEXT,
    phylum              TEXT,
    kingdom             TEXT
);
```

**Key Fields**:
- `ID`: Primary identifier from Catalog of Life
- `scientificName`: Full scientific name including authorship
- `rank`: Taxonomic rank (e.g., "species", "genus")
- `status`: Status of the name (e.g., "accepted", "synonym")
- Taxonomic hierarchy fields (family, order, class_, etc.) to help resolve homonyms

#### ColdpVernacularName

**Purpose**: Stores common names for taxa in various languages.

**Schema**:
```sql
CREATE TABLE coldp_vernacular_name (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    taxonID          VARCHAR(10) INDEX NOT NULL,
    sourceID         VARCHAR(10),
    name             TEXT NOT NULL,
    transliteration  TEXT,
    language         VARCHAR(3),      -- ISO‑639‑3
    preferred        BOOLEAN,
    country          VARCHAR(10),     -- ISO‑3166‑1‑alpha‑2
    area             TEXT,
    sex              VARCHAR(20),
    referenceID      VARCHAR(64),
    remarks          TEXT
);
```

**Key Fields**:
- `id`: Auto-incrementing primary key
- `taxonID`: Foreign key to ColdpNameUsage.ID
- `name`: The vernacular/common name
- `language`: ISO 639-3 language code (e.g., "eng" for English)
- `preferred`: Boolean flag indicating if this is the preferred common name

#### ColdpDistribution

**Purpose**: Contains geographic distribution information for taxa.

**Schema**:
```sql
CREATE TABLE coldp_distribution (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    taxonID        VARCHAR(10) INDEX,
    sourceID       VARCHAR(10),
    areaID         VARCHAR(10),
    area           TEXT,
    gazetteer      VARCHAR(10),
    status         VARCHAR(25),     -- e.g. native, introduced
    referenceID    VARCHAR(64),
    remarks        TEXT
);
```

#### ColdpMedia

**Purpose**: Links to images, sounds, videos, and other media for taxa.

**Schema**:
```sql
CREATE TABLE coldp_media (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    taxonID        VARCHAR(10) INDEX,
    sourceID       VARCHAR(10),
    url            TEXT NOT NULL,
    type           VARCHAR(50),     -- stillImage, sound, video …
    format         VARCHAR(50),     -- MIME type or file suffix
    title          TEXT,
    created        DATE,
    creator        TEXT,
    license        VARCHAR(100),
    link           TEXT,           -- landing page
    remarks        TEXT
);
```

#### ColdpReference

**Purpose**: Stores bibliographic references for taxonomic information.

**Schema**:
```sql
CREATE TABLE coldp_reference (
    ID                  VARCHAR(64) PRIMARY KEY,   -- UUID or short key
    alternativeID       VARCHAR(64),
    sourceID            VARCHAR(10),
    citation            TEXT,
    type                VARCHAR(30),
    author              TEXT,
    editor              TEXT,
    title               TEXT,
    titleShort          TEXT,
    containerAuthor     TEXT,
    containerTitle      TEXT,
    containerTitleShort TEXT,
    issued              VARCHAR(50),
    accessed            VARCHAR(50),
    collectionTitle     TEXT,
    collectionEditor    TEXT,
    volume              VARCHAR(30),
    issue               VARCHAR(30),
    edition             VARCHAR(30),
    page                VARCHAR(50),
    publisher           TEXT,
    publisherPlace      TEXT,
    version             VARCHAR(30),
    isbn                VARCHAR(20),
    issn                VARCHAR(20),
    doi                 VARCHAR(100),
    link                TEXT,
    remarks             TEXT
);
```

#### ColdpTypeMaterial

**Purpose**: Information about type specimens for taxonomic names.

**Schema**:
```sql
CREATE TABLE coldp_type_material (
    ID                  VARCHAR(64) PRIMARY KEY,
    nameID              VARCHAR(10) INDEX,
    sourceID            VARCHAR(10),
    citation            TEXT,
    status              VARCHAR(50),
    referenceID         VARCHAR(64),
    page                VARCHAR(50),
    country             VARCHAR(2),
    locality            TEXT,
    latitude            NUMERIC(9,5),
    longitude           NUMERIC(9,5),
    altitude            VARCHAR(50),
    sex                 VARCHAR(12),
    host                TEXT,
    associatedSequences TEXT,
    date                DATE,
    collector           TEXT,
    institutionCode     VARCHAR(25),
    catalogNumber       VARCHAR(50),
    link                TEXT,
    remarks             TEXT
);
```

### 2. Mapping Table

#### InatToColdpMap

**Purpose**: Cross-reference between iNaturalist taxa and Catalog of Life taxa, enabling integration of ColDP data with iNaturalist observations.

**Schema**:
```sql
CREATE TABLE inat_to_coldp_taxon_map (
    inat_taxon_id       INTEGER REFERENCES expanded_taxa(taxonID),
    col_taxon_id        VARCHAR(64) REFERENCES coldp_name_usage_staging(ID),
    match_type          VARCHAR(50) NOT NULL,  -- exact_name_rank, exact_name_only, fuzzy_name
    match_score         FLOAT,
    inat_scientific_name TEXT,
    col_scientific_name TEXT,
    PRIMARY KEY (inat_taxon_id, col_taxon_id)
);
```

**Key Fields**:
- `inat_taxon_id`: References the taxonID in expanded_taxa
- `col_taxon_id`: References the ID in coldp_name_usage_staging
- `match_type`: Describes how the match was made:
  - `exact_name_rank_accepted`: Exact match on name and rank with accepted status
  - `exact_name_rank_other_status`: Exact match on name and rank with non-accepted status
  - `exact_name_only_accepted`: Exact match on name only with accepted status
  - `exact_name_only_other_status`: Exact match on name only with non-accepted status
  - `fuzzy_name_single_match`: Single fuzzy match above threshold
  - `fuzzy_name_highest_score`: Highest scoring fuzzy match when multiple matches exist
  - `fuzzy_name_with_ancestors`: Fuzzy match using ancestor data to resolve homonyms
  - `fuzzy_name_no_ancestors`: Fuzzy match without ancestor data
- `match_score`: Confidence score (1.0 for exact matches, < 1.0 for fuzzy matches)

## Integration Process

### 1. Loading ColDP Data

The ColDP data loading process is handled by the `load_tables.py` script, which:

1. Creates the necessary tables in the database
2. Reads the TSV files from the ColDP export
3. Processes and cleans the data
4. Loads the data into the corresponding tables

### 2. Mapping Taxa

The mapping process is handled by the `map_taxa.py` script, which employs a multi-stage matching approach:

1. **Exact Name + Rank Matching**: First attempts to find exact matches on both scientific name and taxonomic rank, prioritizing taxa with "accepted" status
2. **Exact Name-Only Matching**: For taxa without exact name+rank matches, attempts to match on scientific name alone
3. **Fuzzy Matching**: For remaining unmatched taxa, uses fuzzy string matching with the rapidfuzz library
4. **Homonym Resolution**: When multiple fuzzy matches exist, uses taxonomic hierarchy information to resolve homonyms

The mapping results are stored in the `inat_to_coldp_taxon_map` table, which acts as a bridge between iNaturalist and Catalog of Life taxonomies.

### 3. Populating Common Names

Once the mapping is complete, the `populate_common_names.py` script:

1. Uses the mapping to identify corresponding ColDP taxa for iNaturalist taxa
2. Retrieves preferred common names from the `coldp_vernacular_name` table
3. Updates the `commonName` field in the `expanded_taxa` table
4. Additionally updates the `LXX_commonName` fields for ancestral ranks

## Usage Examples

### Retrieving Common Names for a Taxon

```sql
-- Get the common name for a specific taxon
SELECT t.taxonID, t.name, t.commonName
FROM expanded_taxa t
WHERE t.taxonID = 12345;

-- Get all taxa with common names from a specific family
SELECT t.taxonID, t.name, t.commonName
FROM expanded_taxa t
WHERE t.L30_taxonID = 67890 -- Family taxon ID
AND t.commonName IS NOT NULL;
```

### Finding Taxa with Distribution Information

```sql
-- Get distribution information for a specific taxon
SELECT t.name, d.area, d.status
FROM expanded_taxa t
JOIN inat_to_coldp_taxon_map m ON t.taxonID = m.inat_taxon_id
JOIN coldp_distribution d ON m.col_taxon_id = d.taxonID
WHERE t.taxonID = 12345;
```

### Accessing Media Links

```sql
-- Get media links for a specific taxon
SELECT t.name, m.type, m.url, m.license
FROM expanded_taxa t
JOIN inat_to_coldp_taxon_map map ON t.taxonID = map.inat_taxon_id
JOIN coldp_media m ON map.col_taxon_id = m.taxonID
WHERE t.taxonID = 12345;
```

## Performance Considerations

- The fuzzy matching process is computationally intensive and may take significant time for large taxonomic datasets
- Batch processing (1,000 records at a time) is used to manage memory usage during fuzzy matching
- Indexes are created on frequently queried columns to improve performance
- The mapping table facilitates efficient joins between iNaturalist and ColDP data

## Future Enhancements

Potential future enhancements to the ColDP integration include:

1. Improved homonym resolution using more advanced techniques
2. Integration of additional ColDP data types (e.g., specimens, interactions)
3. Periodic synchronization with updated ColDP releases
4. Extension to other taxonomic authorities beyond Catalog of Life

## References

- [Catalog of Life Data Package (ColDP) Specification](https://github.com/CatalogueOfLife/coldp)
- [Rapidfuzz Documentation](https://github.com/maxbachmann/RapidFuzz)