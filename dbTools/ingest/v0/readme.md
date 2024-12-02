```markdown
dbTools/ingest/v0/
├── common/
│   ├── geom.sh           # Geometry calculations
│   ├── vers_origin.sh    # Version/origin updates
│   └── main.sh           # Core ingestion logic
├── r0/
│   └── wrapper.sh        # r0-specific parameters
└── r1/
    └── wrapper.sh        # r1-specific parameters
```

# ibrida Database Reproduction Guide

## Overview
This guide documents the step-by-step process for reproducing the ibrida database from iNaturalist open data dumps. The database uses a versioning system with two components:
- **Version (v#)**: Indicates structural changes to the database
- **Release (r#)**: Indicates different data dumps using the same structure

Current versions:
- v0r0: June 2024 iNat data release
- v0r1: December 2024 iNat data release (adds anomaly_score column to observations table)

## Directory Structure
```
dbTools/ingest/v0/
├── common/                # Shared scripts
│   ├── geom.sh           # Geometry calculations
│   ├── vers_origin.sh    # Version/origin updates
│   └── main.sh           # Core ingestion logic
├── r0/
│   └── wrapper.sh        # June 2024 release parameters
└── r1/
    └── wrapper.sh        # December 2024 release parameters
```

## Database Initialization and Data Ingestion
The initialization and ingestion process uses a modular system with wrapper scripts for version-specific parameters and common scripts for shared logic.

### Setup Release-Specific Parameters
Each release has its own wrapper script that defines:
- Database name (e.g., `ibrida-v0r1`)
- Source information
- Version and release values
- Input/output paths

### Running the Ingestion Process
```bash
# Make scripts executable
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/main.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/geom.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/vers_origin.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh

# Run ingest process for latest release
/home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh
```

### Ingestion Process Steps
1. `wrapper.sh` sets release-specific parameters
2. `main.sh` executes the core ingestion logic:
   - Creates the database
   - Sets up tables and indexes
   - Imports data from CSV files
   - Adds and calculates geometry columns (via `geom.sh`)
   - Sets version, release, and origin information (via `vers_origin.sh`)
3. Parallel processing is used for geometry calculations and metadata updates

### Database Schema
Each table includes these metadata columns:
- `version`: Database structure version (e.g., "v0")
- `release`: Data release identifier (e.g., "r0", "r1")
- `origin`: Source and date of the data (e.g., "iNat-Dec2024")

### Important Indices
Core indices:
- Primary key indices on all tables
- Geospatial index on observations (`observations_geom`)
- Foreign key indices for joins
- Full-text search indices for metadata columns
- Composite index for version/release queries (`idx_obs_version_release`)

## Adding a New Release
To add a new release:

1. Create a new release directory and wrapper script:
```bash
mkdir -p /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r{N}
cp /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r{N}/
```

2. Update parameters in the new wrapper script:
- SOURCE
- RELEASE_VALUE
- Other release-specific paths/values

3. Run the ingestion process as described above

## Export Process
[To be added as we implement the export steps...]