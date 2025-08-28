# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

ibridaDB is a modular, reproducible database system designed to ingest, process, and export biodiversity observations from iNaturalist open data dumps. It leverages PostgreSQL with PostGIS to store and query geospatial data with specialized pipelines for:

- **Data Ingestion:** Importing CSV dumps, calculating geospatial geometries, updating metadata
- **Elevation Integration:** Enriching observations with elevation data from MERIT DEM tiles
- **Data Export:** Filtering observations by region and taxonomic clade, performing advanced ancestor searches, and exporting curated CSV files
- **Taxonomy Enrichment:** Integrating taxonomic data from Catalog of Life Data Package (ColDP) to add common names and additional taxonomic information

## Database Connection Information

The database runs in a Docker container. Here's how to connect to it:

```bash
# Database connection details
DB_USER=postgres
DB_PASSWORD=ooglyboogly69
DB_HOST=localhost
DB_PORT=5432
DB_NAME=ibrida-v0-r1

# Connect using psql through Docker
docker exec -it ibridaDB psql -U postgres -d ibrida-v0-r1

# Run SQL commands from outside
docker exec ibridaDB psql -U postgres -d ibrida-v0-r1 -c "SELECT COUNT(*) FROM observations"

# Backup a table
docker exec ibridaDB pg_dump -U postgres -d ibrida-v0-r1 -t observations > observations_backup.sql
```

## Key Concepts

- **Versioning:** The system uses dual versioning:
  - `VERSION_VALUE` (e.g., "v0"): Database structure/schema version
  - `RELEASE_VALUE` (e.g., "r1"): Data release identifier
  
- **Region & Clade Filtering:** The export pipeline allows filtering based on:
  - Geographic regions (defined by bounding boxes)
  - Taxonomic clades or metaclades
  - Minimum observation thresholds

## ColDP Integration

The Catalog of Life Data Package (ColDP) integration is a newer component that enriches the existing iNaturalist taxonomy with standardized taxonomy and common names from the Catalog of Life.

### ColDP Pipeline Structure

- **Scripts directory:** `/home/caleb/repo/ibridaDB/scripts/ingest_coldp/`
  - `load_tables.py` - Imports raw TSV files from ColDP into staging tables
  - `map_taxa.py` - Maps iNaturalist taxa to Catalog of Life taxa using exact and fuzzy matching
  - `map_taxa_parallel.py` - Parallelized version of map_taxa.py for faster processing
  - `populate_common_names.py` - Updates the expanded_taxa table with common names from ColDP
  - `wrapper_ingest_coldp.sh` - Orchestrates the entire ColDP integration process
  - `wrapper_ingest_coldp_parallel.sh` - Parallelized version of the wrapper

- **Model definitions:** `/home/caleb/repo/ibridaDB/models/coldp_models.py`
  - Contains SQLAlchemy ORM models for the ColDP tables
  - Includes the following tables:
    - `coldp_name_usage_staging` - Scientific names and taxonomic hierarchy
    - `coldp_vernacular_name` - Common names in different languages
    - `coldp_distribution` - Geographic distribution information
    - `coldp_media` - Media resources like images and sounds
    - `coldp_reference` - Bibliographic references
    - `coldp_type_material` - Type specimen information

- **Mapping table:** `inat_to_coldp_taxon_map`
  - Links iNaturalist taxa (via taxonID) to Catalog of Life taxa (via ID)
  - Stores match confidence and matching method

### Mapping Workflow

1. **Data Loading:** Import all ColDP TSV files into staging tables
2. **Exact Matching:** First attempt to match taxa based on scientific name and rank
3. **Name-Only Matching:** Try matching just on scientific name for remaining taxa
4. **Fuzzy Matching:** For remaining unmatched taxa, use fuzzy string matching
5. **Homonym Resolution:** When multiple fuzzy matches exist, use taxonomic hierarchy to resolve
6. **Common Name Population:** Update expanded_taxa.commonName and LXX_commonName fields

### Known Issues and Solutions

- **Schema Issues:** Several fields in the ColDP tables were originally defined with varchar lengths that are too small for actual data:
  1. **Taxon ID Fields:** The `taxonID` fields in various tables (like `coldp_vernacular_name.taxonID`) were defined as varchar(10) but some IDs are up to 64 characters (e.g., 'H-EzEkwxHee94KsK0nR3H0').
  2. **Reference Fields:** Fields in the `coldp_reference` table contain very long values that won't fit in varchar fields of any reasonable length.
  
  **Solution:** The wrapper script now:
  1. Drops all ColDP tables (but not expanded_taxa) before each run so they're recreated with the correct schema
  2. Uses SQLAlchemy models with:
     - `varchar(64)` for most ID fields in non-reference tables
     - `Text` type for all fields in the reference table (except the primary key) to avoid any length constraints
     - `varchar(255)` for the reference table's primary key
  3. Validates the schema to catch any field length issues before loading data

- **Performance Issue:** Fuzzy matching is computationally intensive. Use the parallelized version to speed up processing by 10-12x.

### Running ColDP Integration

```bash
# Standard sequential process
./scripts/ingest_coldp/wrapper_ingest_coldp.sh

# Parallelized process (much faster)
NUM_PROCESSES=12 ./scripts/ingest_coldp/wrapper_ingest_coldp_parallel.sh

# Skip certain steps if needed
DO_LOAD_TABLES=false DO_MAP_TAXA=true DO_POPULATE_COMMON_NAMES=false ./scripts/ingest_coldp/wrapper_ingest_coldp_parallel.sh
```

## Common Commands

### Docker Setup Commands

```bash
# Build the custom Docker image (with raster2pgsql support)
cd docker
docker build -t frontierkodiak/ibridadb:latest .

# Start a Docker container (using the appropriate compose file)
cd docker/stausee
docker-compose up -d
```

### Ingestion Commands

```bash
# Make scripts executable
chmod +x dbTools/ingest/v0/common/*.sh
chmod +x dbTools/ingest/v0/r1/wrapper.sh

# Run ingestion for release r1 (with elevation data)
ENABLE_ELEVATION=true dbTools/ingest/v0/r1/wrapper.sh

# Add elevation data to an existing database
cd dbTools/ingest/v0/utils/elevation
./wrapper.sh
```

### Elevation Data Download

```bash
# Download MERIT DEM tiles (sequential)
dbTools/dem/download_merit.sh

# Download MERIT DEM tiles (parallel)
dbTools/dem/download_merit_parallel.sh 4  # Using 4 parallel downloads
```

### Export Commands

```bash
# Make scripts executable
chmod +x dbTools/export/v0/common/*.sh
chmod +x dbTools/export/v0/r1/wrapper_amphibia_all_exc_nonrg_sp_oor_elev.sh

# Run export for amphibians (with elevation data)
dbTools/export/v0/r1/wrapper_amphibia_all_exc_nonrg_sp_oor_elev.sh
```

## Architecture and Key Directories

### Ingestion Pipeline (`dbTools/ingest/v0/`)

- `common/` - Core ingestion logic:
  - `main.sh` - Orchestrates the entire ingestion process
  - `geom.sh` - Computes geospatial geometries
  - `vers_origin.sh` - Updates version and origin metadata

- `r0/`, `r1/`, etc. - Release-specific wrapper scripts and structures
  - `wrapper.sh` - Sets environment variables for a specific release
  - `structure.sql` - Database schema definition

- `utils/elevation/` - Elevation integration tools
  - `main.sh` - Orchestrates elevation data processing
  - `create_elevation_table.sh` - Creates the elevation_raster table
  - `load_dem.sh` - Loads MERIT DEM data into the database
  - `update_elevation.sh` - Updates observations with elevation values

### Export Pipeline (`dbTools/export/v0/`)

- `common/` - Core export logic:
  - `main.sh` - Orchestrates the export process
  - `regional_base.sh` - Creates region-filtered tables
  - `cladistic.sh` - Performs taxonomic filtering and CSV export
  - `clade_defns.sh` - Defines taxonomic clades and metaclades
  - `functions.sh` - Shared utility functions

- `r0/`, `r1/`, etc. - Release-specific export wrappers
  - Various wrapper scripts for different export configurations

### DEM Tools (`dbTools/dem/`)

- `download_merit.sh` - Downloads MERIT DEM tiles (sequential)
- `download_merit_parallel.sh` - Downloads MERIT DEM tiles (parallel)

### Documentation (`docs/`)

- `README.md` - High-level overview
- `export.md` - Export pipeline documentation
- `ingest.md` - Ingestion pipeline documentation
- `schemas.md` - Database schema reference
- `coldp_integration.md` - ColDP integration documentation

## Critical Environment Variables

### For Ingestion:

- `DB_USER` - PostgreSQL user name
- `VERSION_VALUE` - Database version identifier
- `RELEASE_VALUE` - Data release identifier
- `ORIGIN_VALUE` - Data source identifier
- `DB_NAME` - Name of the database to create
- `SOURCE` - Source data identifier
- `METADATA_PATH` - Path to CSV files
- `ENABLE_ELEVATION` - Toggle elevation data integration
- `DEM_DIR` - Path to DEM data

### For Export:

- Same database configuration variables as ingestion
- `REGION_TAG` - Identifies the geographic region
- `MIN_OBS` - Minimum number of observations per species
- `CLADE`/`METACLADE` - Taxonomic filter
- `MAX_RN` - Maximum observations per species in export
- `INCLUDE_OUT_OF_REGION_OBS` - Toggle inclusion of observations outside region
- `INCLUDE_ELEVATION_EXPORT` - Toggle inclusion of elevation data in exports
- `EXPORT_GROUP` - Name identifier for the export job

### For ColDP Integration:

- Database configuration variables (DB_USER, DB_PASSWORD, etc.)
- `ENABLE_FUZZY_MATCH` - Enable fuzzy matching (default: true)
- `FUZZY_THRESHOLD` - Minimum score for fuzzy matches (default: 90)
- `NUM_PROCESSES` - Number of parallel processes for fuzzy matching
- `COLDP_DIR` - Path to the ColDP data directory
- `DO_LOAD_TABLES` - Whether to load ColDP tables
- `DO_MAP_TAXA` - Whether to map taxa
- `DO_POPULATE_COMMON_NAMES` - Whether to populate common names

## Testing

As this is primarily a data processing system, there are no formal unit tests. Instead, verify that:

1. The database is created with all required tables and indexes
2. CSV files are successfully imported into tables
3. The `geom` column is correctly computed and indexed
4. If elevation was enabled, the `observations.elevation_meters` column is populated
5. Export files contain the expected number of observations and follow the required schema

## Common Workflows

1. **Basic ingestion workflow:**
   - Configure wrapper script with appropriate environment variables
   - Run ingestion wrapper
   - Verify database creation and data loading

2. **Adding elevation to existing database:**
   - Configure elevation wrapper script
   - Run elevation wrapper
   - Verify population of elevation_meters column

3. **Export workflow:**
   - Create or modify export wrapper with desired filtering parameters
   - Run export wrapper
   - Check resulting CSV files and export summary in the output directory

4. **Creating a new release:**
   - Create new release directories (`r2/` within ingest and export)
   - Copy and update wrapper scripts with new release info
   - Run the updated wrappers

5. **ColDP integration workflow:**
   - Ensure model schema is correct (especially field lengths)
   - Run parallelized wrapper script
   - Verify mappings and common name population

## Issue Tracking Workflow

### Overview
The repository uses a streamlined issue tracking system in `dev/issues/` to maintain context and state across agent sessions. All issues use frontmatter metadata defined in `.claude/schemas/frontmatter.json`.

### Workflow
1. **Issue Creation**: Create issues in appropriate priority directories (P0-P3)
2. **Active Work**: Update issue status and notes as work progresses
3. **Completion**: Mark as "closed" and move to `closed/` directory
4. **Long-term Storage**: Archive completed plan phases to `archive/`

### Issue Lifecycle & Status
- `open` → Issue identified, not yet started
- `in_progress` → Actively working on this issue  
- `blocked` → Cannot proceed (document reason in notes)
- `completed` → Work finished, verification passed
- `closed` → Issue resolved and archived

### Priority Levels
- **P0**: Critical - Blocks core functionality
- **P1**: High - Important features or significant bugs
- **P2**: Normal - Standard features and improvements  
- **P3**: Low - Nice-to-have features, minor improvements

### Creating Issues
1. Use template at `dev/issues/ISSUE_TEMPLATE.md`
2. Add proper frontmatter using `.claude/schemas/frontmatter.json`
3. Place in appropriate priority directory (P0-P3)
4. Update `dev/issues/ISSUE_TRACKER.md` when status changes

### Issue Management Rules
1. **Always check** `dev/issues/ISSUE_TRACKER.md` for current status before starting work
2. Update issue frontmatter with progress notes for context preservation
3. Move completed issues to `closed/` directory immediately
4. Archive long-term completed work to `archive/` organized by plan/theme
5. Reference related commits, file paths, and documentation entries
6. **All development work should be issue-driven** - create issues for features, bugs, and improvements

### Directory Structure
```
dev/issues/
├── ISSUE_TRACKER.md          # Master tracking document
├── ISSUE_TEMPLATE.md          # Template for new issues
├── P0/                        # Critical priority issues
├── P1/                        # High priority issues
├── P2/                        # Normal priority issues  
├── P3/                        # Low priority issues
├── closed/                    # Recently closed issues
└── archive/                   # Long-term archived issues
```

## Notes and Considerations

- This system is designed to be reproducible - the same inputs should always produce the same database
- The export pipeline supports ancestor-aware logic and partial-labeled data (see documentation)
- When using elevation data, ensure you're using the custom Docker image with `raster2pgsql` support
- Export generates detailed summaries alongside CSV files
- Config follows the single responsibility principle - wrappers should focus on one specific task
- The ColDP fuzzy matching process is highly CPU-intensive but can be parallelized effectively
- **Use issue-driven development**: All code changes should be associated with tracked issues in `dev/issues/`