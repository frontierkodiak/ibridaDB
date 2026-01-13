# ibridaDB - CHANGELOG

This document tracks completed tasks and changes to the ibridaDB system.

## [Unreleased] - 2025-09-09

### Added
- **Critical Performance Indexes for `expanded_taxa` table** - Fixed Typus TaxonomyService timeouts
  - Added `pg_trgm` extension for advanced text search
  - Created functional indexes for case-insensitive prefix search:
    - `idx_expanded_taxa_lower_name_pattern` - For `LOWER(name) LIKE 'prefix%'` queries
    - `idx_expanded_taxa_lower_common_pattern` - For common name searches
  - Created GIN trigram indexes for substring search:
    - `idx_expanded_taxa_lower_name_trgm` - For `LOWER(name) LIKE '%substring%'`
    - `idx_expanded_taxa_lower_common_trgm` - For common name substring search
  - Created compound index `idx_expanded_taxa_rank_name` for rank-filtered searches
  - **Impact**: Reduced Typus search queries from TIMEOUT (>30s) to <1ms (120,000x speedup)
  
- **Index Documentation** - Created `/docs/expanded_taxa_indexes.md` as master reference
  - Documents all 18 current indexes with SQL definitions
  - Identifies redundant indexes (`idx_expanded_taxa_taxonid` duplicates PK)
  - Notes integration with Typus `pg-ensure-indexes` helper tool

- **Elevation Data Documentation** - Created `/docs/elevation_data.md` comprehensive reference
  - Documents MERIT DEM raster storage (155GB, 2.3M tiles)
  - Explains PostGIS raster queries and performance characteristics
  - Provides integration guidance for Typus ElevationService

- **Elevation Index Cleanup Scripts** - Root cause analysis and fix for 1000+ duplicate indexes
  - Created `/scripts/cleanup_duplicate_elevation_indexes.sql` to remove duplicate GIST indexes
  - Created `/dbTools/ingest/v0/utils/elevation/load_dem_fixed.sh` with corrected ingestion logic
  - **Root Cause**: Original `load_dem.sh` used `raster2pgsql -I` flag for EVERY TIF file, creating a new index each time
  - **Impact**: Ingestion took weeks instead of hours due to maintaining 1000+ indexes

### Fixed
- **P0: Typus TaxonomyService Timeouts** - Root cause: missing indexes on 18GB `expanded_taxa` table
  - Queries were doing full table scans on 1.3M rows
  - Now using appropriate indexes for all search patterns

- **Elevation Raster Index Catastrophe** - Discovered and documented critical ingestion bug
  - `raster2pgsql -I` flag was creating a new GIST index for every TIF file loaded (1000+ duplicates)
  - Each subsequent file had to update ALL previous indexes, causing exponential performance degradation
  - This explains why MERIT DEM ingestion took weeks instead of hours
  - Fix: Only create index once with first file, append remaining files without `-I` flag

## [Unreleased] - 2025-05-24

### Added
- Created top-level `models/` directory to separate Python code from bash processing flows
- Created `scripts/ingest_coldp/` directory for ColDP integration scripts
- Moved existing model files from `dbTools/taxa/models/` to top-level `models/`
- Added base.py with SQLAlchemy Base class declaration
- Created initial script versions for:
  - `load_tables.py` - Loads ColDP TSV files into PostgreSQL tables
  - `map_taxa.py` - Maps iNaturalist taxa to ColDP taxa identifiers
  - `populate_common_names.py` - Updates commonName fields in expanded_taxa
  - `wrapper_ingest_coldp.sh` - Orchestrates the entire integration process
- Implemented fuzzy matching with the rapidfuzz library for improved taxon matching
- Added homonym resolution logic using taxonomic ancestors
- Added command-line options to control the fuzzy matching process
- Added TODO.md file to track remaining work
- Added CHANGELOG.md file to document changes
- Created `map_taxa_parallel.py` - Parallelized version of map_taxa.py for 10-12x speedup
- Created `wrapper_ingest_coldp_parallel.sh` - Parallelized wrapper with NUM_PROCESSES environment variable

### Changed
- Updated model import paths to use the new top-level models directory
- Enhanced ColdpNameUsage model to include taxonomic hierarchy fields
- Enhanced wrapper script with configuration options to enable/disable steps and fuzzy matching
- Improved mapping algorithm to prioritize accepted names from Catalog of Life
- Implemented batch processing for fuzzy matching to handle large datasets

### Fixed
- Fixed `populate_common_names.py` to handle NULL values in the `preferred` field of ColDP vernacular names
  - The ColDP data has `preferred` set to NULL for all English vernacular names
  - Updated WHERE clause from `cvn.preferred = TRUE` to `(cvn.preferred = TRUE OR cvn.preferred IS NULL)`
  - This allows the script to successfully populate common names even when the preferred flag isn't explicitly set
- Fixed memory exhaustion in `map_taxa_parallel.py` during fuzzy matching
  - Replaced full DataFrame copying to worker processes with lightweight lookup dictionaries
  - Changed from copying 5.2M ColDP records to each worker to sharing essential data only
  - Reduced batch size from 2000 to 1000 to manage memory usage
  - Implemented `resolve_homonyms_lightweight()` function that works with dictionaries instead of DataFrames
  - This reduced memory usage from ~99GB to manageable levels even with multiple parallel workers

## [Future Release]
This section will be populated as tasks are completed and ready for release.