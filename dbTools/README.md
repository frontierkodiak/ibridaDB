# ibrida Database Reproduction Guide

## Overview
This guide documents the step-by-step process for reproducing the ibrida database from iNaturalist open data dumps. The database uses a versioning system with two components:
- **Version (v#)**: Indicates structural changes to the database
- **Release (r#)**: Indicates different data dumps using the same structure

Current versions:
- v0r0: June 2024 iNat data release
- v0r1: December 2024 iNat data release (adds anomaly_score column to observations table)

## System Architecture
The process is divided into two main phases:
1. Database Initialization (ingest/)
2. Data Export (export/)

Each phase uses a modular structure with:
- Common scripts containing shared logic
- Release-specific wrapper scripts containing parameters

## Database Initialization
### Directory Structure
```
dbTools/ingest/v0/
├── common/                # Shared scripts
│   ├── geom.sh           # Geometry calculations
│   ├── vers_origin.sh    # Version/origin updates
│   └── main.sh           # Core ingestion logic
├── r0/
│   ├── wrapper.sh        # June 2024 release parameters
│   └── structure.sql     # Database schema for r0
└── r1/
    ├── wrapper.sh        # December 2024 release parameters
    └── structure.sql     # Database schema for r1 (includes anomaly_score)
```

### Running the Ingestion Process
Make scripts executable:
```bash
# Make common scripts executable
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/main.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/geom.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/vers_origin.sh

# Make wrapper scripts executable
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r0/wrapper.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh
```

Run ingest:
```bash
# For June 2024 data (r0)
/home/caleb/repo/ibridaDB/dbTools/ingest/v0/r0/wrapper.sh

# For December 2024 data (r1)
/home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh
```

## Data Export
### Directory Structure
```
dbTools/export/v0/
├── common/
│   ├── main.sh           # Core export logic
│   ├── regional_base.sh  # Region-specific filtering
│   └── cladistic.sh      # Taxonomic filtering
├── r0/
│   └── wrapper.sh        # June 2024 parameters
└── r1/
    └── wrapper.sh        # December 2024 parameters
```

### Export Process Steps
1. Regional base table creation:
   - Filters observations by geographic region
   - Applies minimum observation thresholds
   - Creates base tables for further filtering

2. Cladistic filtering:
   - Applies taxonomic filters based on metaclades
   - Handles special cases (e.g., excluding aquatic insects)
   - Creates filtered observation tables

3. CSV export:
   - Creates directory structure if needed
   - Sets appropriate permissions
   - Exports filtered data with photo restrictions
   - Generates export statistics and summaries

### Running the Export Process
Make scripts executable:
```bash
# Make common scripts executable
chmod +x /home/caleb/repo/ibridaDB/dbTools/export/v0/common/main.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/export/v0/common/regional_base.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/export/v0/common/cladistic.sh

# Make wrapper scripts executable
chmod +x /home/caleb/repo/ibridaDB/dbTools/export/v0/r0/wrapper.sh
chmod +x /home/caleb/repo/ibridaDB/dbTools/export/v0/r1/wrapper.sh
```

Run exports:
```bash
# For June 2024 data (r0)
/home/caleb/repo/ibridaDB/dbTools/export/v0/r0/wrapper.sh

# For December 2024 data (r1)
/home/caleb/repo/ibridaDB/dbTools/export/v0/r1/wrapper.sh
```

### Export Directory Structure
Exports are organized by version and release:
```
/datasets/ibrida-data/exports/
├── v0/
│   ├── r0/
│   │   └── primary_only_50min_3000max/
│   │       ├── primary_terrestrial_arthropoda_photos.csv
│   │       └── export_summary.txt
│   └── r1/
│       └── primary_only_50min_4000max/
│           ├── primary_terrestrial_arthropoda_photos.csv
│           └── export_summary.txt
```

### Available Export Groups
The system supports several predefined export groups:
1. primary_terrestrial_arthropoda
   - Includes Insecta and Arachnida
   - Excludes aquatic groups (Ephemeroptera, Plecoptera, Trichoptera, Odonata)
   - Parameters: MIN_OBS=50, MAX_RN=4000 (r1)

2. amphibia
   - Includes all Amphibia taxa
   - Parameters: MIN_OBS=400, MAX_RN=1000

## Schema Notes
### Release-Specific Changes
- v0r1 adds `anomaly_score numeric(15,6)` to observations table
- Export scripts automatically handle presence/absence of this column

### Metadata Columns
All tables include:
- `version`: Database structure version (e.g., "v0")
- `release`: Data release identifier (e.g., "r0", "r1")
- `origin`: Source and date of the data (e.g., "iNat-Dec2024")