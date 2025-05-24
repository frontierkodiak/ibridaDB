# Catalog of Life Integration - TODO List

## Directory Structure and Setup
- [x] Create top-level `models/` directory
- [x] Create `scripts/ingest_coldp/` directory
- [x] Move model files from `dbTools/taxa/models/` to top-level `models/`
- [x] Create base SQLAlchemy models

## Phase 1: Load ColDP Data
- [x] Create `load_tables.py` to import ColDP data
- [x] Implement table creation logic for all ColDP entities
- [x] Implement TSV parsing and database loading logic

## Phase 2: Mapping and Populating
- [x] Create `map_taxa.py` with exact name+rank matching
- [x] Create `map_taxa.py` with exact name-only matching
- [x] Implement fuzzy matching logic in `map_taxa.py`
  - [x] Integrate the rapidfuzz library for Levenshtein distance calculations
  - [x] Tune the match threshold to minimize false positives
  - [x] Add robust homonym resolution by checking ancestor ranks
  - [x] Add debug mode for monitoring fuzzy match quality
- [x] Update `ColdpNameUsage` model to include taxonomic hierarchy fields
- [x] Create `populate_common_names.py` for direct taxa common names
- [x] Implement logic for populating ancestor taxa common names
- [ ] Verify SQL update statements work with the actual database schema

## Phase 3: Wrapper Script and Documentation
- [x] Create `wrapper_ingest_coldp.sh` script
- [x] Add error handling for missing data files and database errors
- [x] Add options to bypass specific steps when re-running
- [ ] Update `docs/schemas.md` with ColDP table definitions
- [ ] Create new `docs/coldp_integration.md` documentation

## Testing and Validation
- [ ] Test load_tables.py with sample ColDP data
- [ ] Test map_taxa.py with a small subset of taxa to verify matching quality
- [ ] Test fuzzy matching algorithm with different threshold values
- [ ] Test populate_common_names.py to ensure proper SQL updates
- [ ] Run full end-to-end test with wrapper_ingest_coldp.sh
- [ ] Verify mapping quality with a sample of 100 species
- [ ] Check for missing common names in popular taxa

## SDK Development Support
- [ ] Create script to dump all database table schemas to text file
  - Use PostgreSQL information_schema or psql \d+ commands
  - Include all table structures, constraints, indexes, and relationships
  - Output format suitable for SDK code generation
  - Consider creating SQL DDL export and JSON schema formats
  - Include documentation about each table's purpose
- [ ] Document database access patterns and common queries
- [ ] Create sample queries for SDK development

## Future Work
- [ ] Further optimize fuzzy matching algorithm performance for large datasets
- [ ] Develop an iterative/multi-pass fuzzy matching process for improved quality
- [ ] Add support for more ColDP entities (SpeciesInteraction, etc.)
- [ ] Integrate with Alembic migrations for schema management
- [ ] Add incremental update logic for new ColDP releases
- [ ] Create visualization/monitoring tools for match quality
- [ ] Add automatic validation and crosscheck against taxonomic authorities