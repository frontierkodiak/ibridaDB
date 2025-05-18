# Catalog of Life Integration - CHANGELOG

This document tracks completed tasks and changes related to the Catalog of Life (ColDP) data integration project.

## [Unreleased]

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

### Changed
- Updated model import paths to use the new top-level models directory
- Enhanced ColdpNameUsage model to include taxonomic hierarchy fields
- Enhanced wrapper script with configuration options to enable/disable steps and fuzzy matching
- Improved mapping algorithm to prioritize accepted names from Catalog of Life
- Implemented batch processing for fuzzy matching to handle large datasets

### Fixed
- None yet

## [Future Release]
This section will be populated as tasks are completed and ready for release.