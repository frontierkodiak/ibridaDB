# ibrida Database Reproduction Guide

## Overview
This guide documents the end-to-end process for **reproducing** and **exporting** from the ibrida database, which is derived from iNaturalist open data dumps. The database uses a versioning system with two components:
- **Version (v#)**: Indicates structural changes (schema revisions) to the database.
- **Release (r#)**: Indicates distinct data releases from iNaturalist under the same schema version.

For example:
- **v0r0**: June 2024 iNat data release
- **v0r1**: December 2024 iNat data release (adds `anomaly_score` column to `observations`)

## System Architecture
The pipeline is split into two phases:
1. **Database Initialization** (`ingest/`)
2. **Data Export** (`export/`)

Each phase has:
- Common scripts for shared logic
- Release- or job-specific *wrapper scripts* that set environment variables for that particular run

## 1. Database Initialization (ingest/)
### Directory Structure

```
dbTools/ingest/v0/
├── common/
│   ├── geom.sh         # Geometry calculations
│   ├── vers_origin.sh  # Version/origin updates
│   └── main.sh         # Core ingestion logic
├── r0/
│   ├── wrapper.sh      # June 2024 release
│   └── structure.sql   # schema for r0
└── r1/
    ├── wrapper.sh      # December 2024 release
    └── structure.sql   # schema for r1 (adds anomaly_score)
```

### Running the Ingestion Process
1. **Make scripts executable**:
    ```bash
    chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/*.sh
    chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r0/wrapper.sh
    chmod +x /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh
    ```
2. **Run**:
    ```bash
    # For June 2024 (r0)
    /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r0/wrapper.sh

    # For December 2024 (r1)
    /home/caleb/repo/ibridaDB/dbTools/ingest/v0/r1/wrapper.sh
    ```

## 2. Data Export (export/)
The export pipeline allows flexible subsetting of the DB by region, minimum threshold, clade, etc. For additional detail, see [export.md](export.md).

### Directory Structure
```
dbTools/export/v0/
├── common/
│   ├── main.sh            # Orchestrates creation or skipping of base tables; final summary
│   ├── regional_base.sh   # Region-based table creation, ancestor-aware logic
│   ├── cladistic.sh       # Taxonomic filtering, partial-rank wiping, CSV export
│   └── functions.sh       # Shared shell functions
├── r0/
│   └── wrapper.sh         # Example job wrapper for June 2024 export
├── r1/
│   └── wrapper.sh         # Example job wrapper for December 2024 export
└── export.md              # Detailed usage documentation (v1)
```

### Export Workflow
1. **User creates/edits a wrapper script** (e.g., `r1/my_special_wrapper.sh`) to set:
   - `REGION_TAG`, `MIN_OBS`, `MAX_RN`, `PRIMARY_ONLY`
   - Optional toggles like `INCLUDE_OUT_OF_REGION_OBS`, `RG_FILTER_MODE`, `ANCESTOR_ROOT_RANKLEVEL`, `MIN_OCCURRENCES_PER_RANK`
   - A unique `EXPORT_GROUP` name
2. **Run** that wrapper. The pipeline will:
   1. **(regional_base.sh)** Build base tables of in-threshold species + ancestors, optionally bounding to region or not, depending on `INCLUDE_OUT_OF_REGION_OBS`.
   2. **(cladistic.sh)** Filter final observations by clade or metaclade, optionally wipe partial ranks, and do a random-sample CSV export.
   3. **(main.sh)** Write a summary file enumerating environment variables, row counts, timing, etc.

3. **Check** `/datasets/ibrida-data/exports` for final CSV output (organized by `VERSION_VALUE` / `RELEASE_VALUE` / any job-specific subdirectory).

### Drafting a New Wrapper
It is **recommended** to create a separate wrapper script for each new export job. For instance:
```bash
#!/bin/bash

export WRAPPER_PATH="$0"

export DB_USER="postgres"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r1"
export ORIGIN_VALUE="iNat-Dec2024"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"

export REGION_TAG="NAfull"
export MIN_OBS=50
export MAX_RN=3000
export PRIMARY_ONLY=true

export CLADE="amphibia"
export EXPORT_GROUP="amphibia_test"

export INCLUDE_OUT_OF_REGION_OBS=false
export RG_FILTER_MODE="ALL"
export ANCESTOR_ROOT_RANKLEVEL=40
export MIN_OCCURRENCES_PER_RANK=30

# other optional vars, e.g. PROCESS_OTHER, SKIP_REGIONAL_BASE, etc.

export DB_CONTAINER="ibridaDB"
export HOST_EXPORT_BASE_PATH="/datasets/ibrida-data/exports"
export CONTAINER_EXPORT_BASE_PATH="/exports"
export EXPORT_SUBDIR="${VERSION_VALUE}/${RELEASE_VALUE}/myamphibia_job"
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/export/v0"

source "${BASE_DIR}/common/functions.sh"

/home/caleb/repo/ibridaDB/dbTools/export/v0/common/main.sh
```
Then `chmod +x` this file and run it to generate a new job.

### Example Outputs
The final CSV and summary are placed in a subdirectory (e.g. `v0/r1/myamphibia_job`). A typical summary file `amphibia_test_export_summary.txt` includes:
- Region: NAfull
- MIN_OBS: 50
- RG_FILTER_MODE: ALL
- Observations: 10,402
- Unique Taxa: 927
- Timings for each step

### Further Reading
- **[export.md](export/v0/export.md)** for a deeper parameter reference (v1).
- **clade_defns.sh** for built-in definitions of macroclades, clades, and metaclades.

## Overall Flow
Below is a schematic of the entire ingest→export pipeline. For details on the ingest side, see [Ingestion docs](#database-initialization-ingest):
```
Ingest (ingest/v0/) --> Database --> Export (export/v0/)
```
In the export sub-phase, each new wrapper script can define a distinct job. Summaries and CSVs are stored in `HOST_EXPORT_BASE_PATH` for easy retrieval and analysis.

## Notes on Schema
- **v0r1** adds the `anomaly_score numeric(15,6)` column to `observations`.
- The export scripts automatically check if that column is present based on `RELEASE_VALUE`.
- If partial-labeled data is desired (coarse ranks for rare species), see the advanced features in `regional_base.sh` (ancestor logic) and `cladistic.sh` (partial-rank wiping logic).

**Notes**:
- The ingest side is unchanged for v0→v0r1 except for adding columns and data updates.
- The export side is significantly more flexible now, supporting ancestor‐aware logic and partial-labeled data.  
- Each new export job typically has its own wrapper script referencing the relevant `VERSION_VALUE`, `RELEASE_VALUE`, region, and clade parameters.