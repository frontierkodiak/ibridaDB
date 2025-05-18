# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

ibridaDB is a modular, reproducible database system designed to ingest, process, and export biodiversity observations from iNaturalist open data dumps. It leverages PostgreSQL with PostGIS to store and query geospatial data with specialized pipelines for:

- **Data Ingestion:** Importing CSV dumps, calculating geospatial geometries, updating metadata
- **Elevation Integration:** Enriching observations with elevation data from MERIT DEM tiles
- **Data Export:** Filtering observations by region and taxonomic clade, performing advanced ancestor searches, and exporting curated CSV files

## Key Concepts

- **Versioning:** The system uses dual versioning:
  - `VERSION_VALUE` (e.g., "v0"): Database structure/schema version
  - `RELEASE_VALUE` (e.g., "r1"): Data release identifier
  
- **Region & Clade Filtering:** The export pipeline allows filtering based on:
  - Geographic regions (defined by bounding boxes)
  - Taxonomic clades or metaclades
  - Minimum observation thresholds

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

## Notes and Considerations

- This system is designed to be reproducible - the same inputs should always produce the same database
- The export pipeline supports ancestor-aware logic and partial-labeled data (see documentation)
- When using elevation data, ensure you're using the custom Docker image with `raster2pgsql` support
- Export generates detailed summaries alongside CSV files
- Config follows the single responsibility principle - wrappers should focus on one specific task