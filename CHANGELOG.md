# Catalog of Life Integration - CHANGELOG

This document tracks completed tasks and changes related to the Catalog of Life (ColDP) data integration project.

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