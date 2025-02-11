# ibridaDB Schemas Reference

This document provides a detailed reference for all of the schemas used in ibridaDB. It covers:

1. The core tables imported directly from iNaturalist.
2. The **expanded_taxa** table generated from the iNaturalist `taxa` table.
3. The final export table produced by the export pipeline.
4. Supplementary information on data types, indexing, and version-specific differences.
5. An appendix with sample SQL output (\d results) for quick reference.

This reference is intended to help developers and maintainers quickly understand the structure, data types, and intended usage of each table without needing to manually inspect the database.

---

## Table of Contents

1. [Core iNaturalist Tables](#core-inaturalist-tables)  
   1.1. [Observations](#observations)  
   1.2. [Photos](#photos)  
   1.3. [Observers](#observers)  
   1.4. [Taxa](#taxa)

2. [Expanded Taxa Table](#expanded-taxa-table)  
   2.1. [Purpose and Generation](#purpose-and-generation)  
   2.2. [Schema Details](#schema-details)  
   2.3. [Indexing and Performance Considerations](#indexing-and-performance-considerations)  
   2.4. [Rank-Level Mapping](#rank-level-mapping)

3. [Final Export Table Schema](#final-export-table-schema)  
   3.1. [Overview](#overview)  
   3.2. [Explicit Column List and Descriptions](#explicit-column-list-and-descriptions)  
   3.3. [Conditional Columns: elevation_meters and anomaly_score](#conditional-columns-elevation_meters-and-anomaly_score)  
   3.4. [Example Row / CSV Layout](#example-row--csv-layout)

4. [Supplementary Information](#supplementary-information)  
   4.1. [Data Types and Precision](#data-types-and-precision)  
   4.2. [Indices and Their Purposes](#indices-and-their-purposes)  
   4.3. [Version-Specific Schema Differences](#version-specific-schema-differences)

5. [Appendix: SQL Dumps and \d Outputs](#appendix-sql-dumps-and-d-output)

---

## 1. Core iNaturalist Tables

These tables are imported directly from iNaturalist open data dumps.

### Observations

**Description:**  
Contains each observation record with geospatial and temporal data.

**Key Columns:**

| Column               | Type              | Description |
|----------------------|-------------------|-------------|
| observation_uuid     | uuid              | Unique identifier for each observation. This identifier is used to link photos and can be found on iNaturalist.org. |
| observer_id          | integer           | Identifier for the observer who recorded the observation. |
| latitude             | numeric(15,10)    | Latitude of the observation. High precision (up to 10 digits after the decimal) ensures accuracy. |
| longitude            | numeric(15,10)    | Longitude of the observation. |
| positional_accuracy  | integer           | Uncertainty in meters for the location. |
| taxon_id             | integer           | Identifier linking the observation to a taxon. |
| quality_grade        | varchar(255)      | Observation quality, e.g., "research", "casual", or "needs_id". |
| observed_on          | date              | Date when the observation was made. |
| anomaly_score        | numeric(15,6)     | A computed metric for anomaly detection; available in releases r1 and later. |
| geom                 | geometry          | Geospatial column computed from latitude and longitude. |
| origin               | varchar(255)      | Metadata field populated during ingestion. |
| version              | varchar(255)      | Database structure version. |
| release              | varchar(255)      | Data release identifier. |
| **elevation_meters** | **numeric(10,2)** | *Optional:* Elevation value in meters (if elevation processing is enabled). |

### Photos

**Description:**  
Contains metadata for photos associated with observations.

**Key Columns:**

| Column           | Type           | Description |
|------------------|----------------|-------------|
| photo_uuid       | uuid           | Unique identifier for each photo. |
| photo_id         | integer        | iNaturalist photo ID. |
| observation_uuid | uuid           | Identifier linking the photo to an observation. |
| observer_id      | integer        | Identifier of the observer who took the photo. |
| extension        | varchar(5)     | Image file format (e.g., "jpeg"). |
| license          | varchar(255)   | Licensing information (e.g., Creative Commons). |
| width            | smallint       | Photo width in pixels. |
| height           | smallint       | Photo height in pixels. |
| position         | smallint       | Indicates the order of photos for an observation (position 0 indicates primary photo). |
| origin           | varchar(255)   | Metadata field. |
| version          | varchar(255)   | Database structure version. |
| release          | varchar(255)   | Data release identifier. |

### Observers

**Description:**  
Contains information about the users (observers) who record observations.

**Key Columns:**

| Column      | Type         | Description |
|-------------|--------------|-------------|
| observer_id | integer      | Unique identifier for each observer. |
| login       | varchar(255) | Unique login/username. |
| name        | varchar(255) | Observer's personal name (if provided). |
| origin      | varchar(255) | Metadata field. |
| version     | varchar(255) | Database structure version. |
| release     | varchar(255) | Data release identifier. |

### Taxa

**Description:**  
Contains the taxonomy as provided by iNaturalist.

**Key Columns:**

| Column     | Type              | Description |
|------------|-------------------|-------------|
| taxon_id   | integer           | Unique taxon identifier. |
| ancestry   | varchar(255)      | Encoded ancestral hierarchy (delimited by backslashes). |
| rank_level | double precision  | Numeric level indicating taxonomic rank. |
| rank       | varchar(255)      | Taxonomic rank (e.g., "species", "genus"). |
| name       | varchar(255)      | Scientific name of the taxon. |
| active     | boolean           | Indicates if the taxon is active in the taxonomy. |
| origin     | varchar(255)      | Metadata field. |
| version    | varchar(255)      | Database structure version. |
| release    | varchar(255)      | Data release identifier. |

---

## 2. Expanded Taxa Table

### Purpose and Generation

The **expanded_taxa** table is generated from the iNaturalist `taxa` table by the `expand_taxa.sh` script. Its purpose is to “unpack” the single-column ancestry string into discrete columns (e.g., `L5_taxonID`, `L5_name`, `L5_commonName`, etc.) so that clade-based filtering and ancestor lookups can be performed efficiently without resorting to recursive string parsing.

### Schema Details

**Core Columns:**

| Column      | Type              | Description |
|-------------|-------------------|-------------|
| taxonID     | integer           | Primary key; unique taxon identifier. |
| rankLevel   | double precision  | Numeric indicator of the taxonomic rank. |
| rank        | varchar(255)      | Taxonomic rank label. |
| name        | varchar(255)      | Scientific name of the taxon. |
| taxonActive | boolean           | Indicates whether the taxon is active. |

**Expanded Columns:**

For each rank level in the set `{5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30, 32, 33, 33.5, 34, 34.5, 35, 37, 40, 43, 44, 45, 47, 50, 53, 57, 60, 67, 70}`, the following columns are added:

- `L{level}_taxonID` (integer)
- `L{level}_name` (varchar(255))
- `L{level}_commonName` (varchar(255))

For example, for rank level 10:
- `L10_taxonID`
- `L10_name`
- `L10_commonName`

### Indexing and Performance Considerations

Indexes are created on the most frequently queried expanded columns (typically on `L10_taxonID`, `L20_taxonID`, …, `L70_taxonID`) as well as on the base columns (`taxonID`, `rankLevel`, and `name`). These indexes help to optimize the clade filtering and ancestor lookups performed by the export pipeline.

### Rank-Level Mapping

A supplemental mapping (provided in `clade_helpers.sh`) maps the column prefixes to human-readable rank names. For example:

| Prefix | Rank         |
|--------|--------------|
| L5     | subspecies   |
| L10    | species      |
| L20    | genus        |
| L40    | order        |
| L50    | class        |
| L70    | kingdom      |

A complete mapping is maintained in the code to facilitate any dynamic filtering or display of taxonomic information.

---

## 3. Final Export Table Schema

### Overview

The final export table is generated by the export pipeline (primarily via `cladistic.sh`) and is used for downstream applications such as training specimen identification models. This table is created by joining observations with photo metadata and taxonomic data from `expanded_taxa`. It includes additional computed columns for quality filtering and sampling.

### Explicit Column List and Descriptions

The final export table (named `<EXPORT_GROUP>_observations`) contains the following columns:

#### From the Observations Table

| Column               | Type              | Description |
|----------------------|-------------------|-------------|
| observation_uuid     | uuid              | Unique observation identifier. |
| observer_id          | integer           | Observer identifier. |
| latitude             | numeric(15,10)    | Latitude of the observation. |
| longitude            | numeric(15,10)    | Longitude of the observation. |
| **elevation_meters** | **numeric(10,2)** | *Optional:* Elevation in meters (included if `INCLUDE_ELEVATION_EXPORT=true`). |
| positional_accuracy  | integer           | Location uncertainty in meters. |
| taxon_id             | integer           | Identifier linking to the taxon. |
| quality_grade        | varchar(255)      | Quality grade (e.g., "research"). |
| observed_on          | date              | Date of observation. |
| anomaly_score        | numeric(15,6)     | Anomaly score (only available in r1 and later). |
| in_region            | boolean           | Computed flag indicating if the observation lies within the region bounding box. |
| expanded_taxonID     | integer           | Taxon ID from the expanded_taxa table. |
| expanded_rankLevel   | double precision  | Rank level from expanded_taxa. |
| expanded_name        | varchar(255)      | Taxon name from expanded_taxa. |
| L5_taxonID – L70_taxonID | integer       | A series of columns representing the taxonomic ancestry at various rank levels (e.g., L5_taxonID, L10_taxonID, …, L70_taxonID). |

#### From the Photos Table

| Column       | Type           | Description |
|--------------|----------------|-------------|
| photo_uuid   | uuid           | Unique photo identifier. |
| photo_id     | integer        | Photo identifier (from iNaturalist). |
| extension    | varchar(5)     | Image file format (e.g., "jpeg"). |
| license      | varchar(255)   | Licensing information. |
| width        | smallint       | Photo width (in pixels). |
| height       | smallint       | Photo height (in pixels). |
| position     | smallint       | Photo order indicator (primary photo has position 0). |

#### Additional Computed Column

| Column | Type    | Description |
|--------|---------|-------------|
| rn     | bigint  | Row number (per species partition based on `L10_taxonID`) used to cap the number of research-grade observations per species (controlled by `MAX_RN`). |

### Conditional Columns: elevation_meters and anomaly_score

- **elevation_meters:**  
  This column is included in the final export if the environment variable `INCLUDE_ELEVATION_EXPORT` is set to true and if the current release is not `"r0"`. It is positioned immediately after the `longitude` column.

- **anomaly_score:**  
  Present only in releases where it has been added (e.g., `r1` onward).

### Example Row / CSV Layout

An exported CSV row (tab-delimited) might be structured as follows:

```
observation_uuid    observer_id    latitude    longitude    elevation_meters    positional_accuracy    taxon_id    quality_grade    observed_on    anomaly_score    in_region    expanded_taxonID    expanded_rankLevel    expanded_name    L5_taxonID    L10_taxonID    ...    L70_taxonID    photo_uuid    photo_id    extension    license    width    height    position    rn
```

Each observation row is linked to one or more photo rows; the export process uses a partition-based random sampling (per species) so that only a maximum of `MAX_RN` research-grade observations per species are included.

---

## 4. Supplementary Information

### Data Types and Precision

- **Latitude and Longitude:** Stored as `numeric(15,10)`, which provides high precision (up to 10 digits after the decimal) ensuring accurate geolocation.
- **elevation_meters:** Stored as `numeric(10,2)`, capturing elevation with two decimal places.
- **anomaly_score:** Stored as `numeric(15,6)` for precise anomaly measurements.
- Standard PostgreSQL data types are used for other columns as specified.

### Indices and Their Purposes

- **Core Tables:**  
  Primary keys and indexes are created on identifiers (e.g., `observation_uuid`, `photo_uuid`, `taxon_id`) and frequently queried columns.
- **Observations Geometry:**  
  A GIST index is created on the `geom` column for fast spatial queries.
- **Expanded_Taxa:**  
  Additional indexes are created on key expanded ancestry columns (e.g., `L10_taxonID`, `L20_taxonID`, …, `L70_taxonID`) to optimize clade-based filtering.

### Version-Specific Schema Differences

- **Releases prior to r1:**  
  May not include `anomaly_score` and `elevation_meters`.
- **Current and Future Releases:**  
  Include these columns. Future schema changes will be documented here as needed.

---

## 5. Appendix: SQL Dumps and \d Outputs

Below are example outputs from PostgreSQL’s `\d` command for key tables. These serve as a quick reference for the column names and types.

### Observations Table

```sql
-- \d observations
       Column        |          Type          
---------------------+------------------------
 observation_uuid    | uuid                  
 observer_id         | integer               
 latitude            | numeric(15,10)        
 longitude           | numeric(15,10)        
 positional_accuracy | integer               
 taxon_id            | integer               
 quality_grade       | varchar(255)          
 observed_on         | date                  
 anomaly_score       | numeric(15,6)         
 geom                | geometry              
 origin              | varchar(255)          
 version             | varchar(255)          
 release             | varchar(255)
 elevation_meters    | numeric(10,2)         -- Present if enabled
```

### Photos Table

```sql
-- \d photos
      Column      |          Type          
------------------+------------------------
 photo_uuid       | uuid                   
 photo_id         | integer                
 observation_uuid | uuid                   
 observer_id      | integer                
 extension        | varchar(5)             
 license          | varchar(255)           
 width            | smallint               
 height           | smallint               
 position         | smallint               
 origin           | varchar(255)           
 version          | varchar(255)           
 release          | varchar(255)
```

### Observers Table

```sql
-- \d observers
   Column    |          Type          
-------------+------------------------
 observer_id | integer                
 login       | varchar(255)           
 name        | varchar(255)           
 origin      | varchar(255)           
 version     | varchar(255)           
 release     | varchar(255)
```

### Taxa Table

```sql
-- \d taxa
   Column   |          Type          
------------+------------------------
 taxon_id   | integer                
 ancestry   | varchar(255)           
 rank_level | double precision       
 rank       | varchar(255)           
 name       | varchar(255)           
 active     | boolean                
 origin     | varchar(255)           
 version    | varchar(255)           
 release    | varchar(255)
```

### Expanded_Taxa Table

```sql
-- \d "expanded_taxa"
      Column      |          Type          
------------------+------------------------
 taxonID          | integer    (PK)
 rankLevel        | double precision       
 rank             | varchar(255)           
 name             | varchar(255)           
 taxonActive      | boolean                
 L5_taxonID       | integer                
 L5_name          | varchar(255)           
 L5_commonName    | varchar(255)           
 L10_taxonID      | integer                
 L10_name         | varchar(255)           
 L10_commonName   | varchar(255)           
 ...              | ...                    
 L70_taxonID      | integer                
```

### Final Export Table (Example)

Assuming the export group is named `amphibia_all_exc_nonrg_sp_oor_elev`, an example output is:

```sql
-- \d "amphibia_all_exc_nonrg_sp_oor_elev_observations"
       Column              |          Type          
-----------------------------+------------------------
 observation_uuid            | uuid                  
 observer_id                 | integer               
 latitude                    | numeric(15,10)        
 longitude                   | numeric(15,10)        
 elevation_meters            | numeric(10,2)         -- Only if enabled
 positional_accuracy         | integer               
 taxon_id                    | integer               
 quality_grade               | varchar(255)          
 observed_on                 | date                  
 anomaly_score               | numeric(15,6)         -- Only for r1 and later
 in_region                   | boolean               
 expanded_taxonID            | integer               
 expanded_rankLevel          | double precision       
 expanded_name               | varchar(255)           
 L5_taxonID                  | integer               
 L10_taxonID                 | integer               
 ...                         | ...                   
 L70_taxonID                 | integer               
 photo_uuid                  | uuid                  
 photo_id                    | integer               
 extension                   | varchar(5)            
 license                     | varchar(255)          
 width                       | smallint              
 height                      | smallint              
 position                    | smallint              
 rn                          | bigint                -- For internal sampling
```

---

## Final Notes

- This document serves as the definitive reference for all table schemas within ibridaDB (other than intermediate tables).  
- It is essential for developers working on downstream processing, migration, or debugging tasks.  
- As the system evolves (new releases, additional columns, or modifications to processing logic), please update this document to maintain an accurate reference.
  - NOTE: 'regional base' tables are not documented here but quite likely should be. Necessary for debugging and understanding advances features like ancestor-aware (ancestor search), out-of-region (oor) observations of in-region taxa, etc.