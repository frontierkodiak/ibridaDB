# ibridaDB Ingestion Documentation

This document provides a detailed overview of the ibridaDB ingestion pipeline. It covers the steps to load iNaturalist data into a spatially enabled PostgreSQL/PostGIS database, how the elevation integration is handled, and how to run the ingestion process using the provided wrapper scripts.

---

## 1. Overview of the Ingestion Flow

The ingestion pipeline for ibridaDB is designed to:
- **Initialize the Database:** Create a new database using a template (typically a PostGIS-enabled template).
- **Import Data:** Load CSV data for observations, photos, taxa, and observers from iNaturalist data dumps.
- **Compute Geometries:** Generate geospatial geometry columns from the latitude and longitude fields.
- **Update Metadata:** Populate additional columns such as `origin`, `version`, and `release` on each table.
- **Integrate Elevation (Optional):**  
  - **Fresh Ingestion Scenario:** If you are initializing a new database and want to include elevation data, the main ingestion script (in `common/main.sh`) can trigger the elevation pipeline automatically when `ENABLE_ELEVATION=true` is set.
  - **Existing Database Scenario:** If your database already exists and lacks elevation data, you can run the elevation wrapper (in `utils/elevation/wrapper.sh`) to update the observations with DEM-derived elevation values.

After the ingestion steps are complete, the database is ready for further processing or for exporting subsets of observations using the export pipeline.

---

## 2. Environment Variables

The ingestion pipeline is controlled by several environment variables. The key ones include:

### Database and General Settings
- **`DB_USER`**  
  PostgreSQL user (typically `"postgres"`).

- **`DB_TEMPLATE`**  
  Template database name (e.g., `"template_postgis"`) used to create the new database.

- **`NUM_PROCESSES`**  
  Number of parallel processes to use for tasks such as geometry calculations and metadata updates.

- **`BASE_DIR`**  
  Root directory of the ingestion tools (e.g., `/home/caleb/repo/ibridaDB/dbTools/ingest/v0`).

- **`SOURCE`**  
  Source identifier for the iNaturalist data (e.g., `"Dec2024"`, `"Feb2025"`).

- **`METADATA_PATH`**  
  Path to the CSV files containing iNaturalist data (e.g., `/datasets/ibrida-data/intake/Dec2024`).

### Versioning and Release
- **`ORIGIN_VALUE`**  
  Describes the data provenance (e.g., `"iNat-Dec2024"`).

- **`VERSION_VALUE`**  
  Database version identifier (e.g., `"v0"`).

- **`RELEASE_VALUE`**  
  Data release identifier (e.g., `"r1"`).

- **`DB_NAME`**  
  Name of the new database (e.g., `"ibrida-v0-r1"`).

- **`DB_CONTAINER`**  
  Name of the Docker container running PostgreSQL (e.g., `"ibridaDB"`).

### Elevation Integration Settings
- **`ENABLE_ELEVATION`**  
  If set to `"true"`, the ingestion process will invoke the elevation pipeline.  
  - *Fresh Ingestion:* When creating a new database, the main ingestion script calls the elevation pipeline after geometry calculation.  
  - *Existing DB Update:* You may also run the elevation wrapper separately to add or update elevation values.
- **`DEM_DIR`**  
  Path to the directory containing the MERIT DEM `.tar` files (e.g., `"/datasets/dem/merit"`).
- **`EPSG`**  
  EPSG code for the DEM data (default: `"4326"`).
- **`TILE_SIZE`**  
  Tile size for processing DEM data (default: `"100x100"`).

---

## 3. Ingestion Flow Details

### A. Database Initialization and CSV Import

1. **Database Creation:**  
   - The ingestion pipeline starts by dropping any existing database with the target name and creating a fresh database using the specified template.
2. **Table Creation:**  
   - Tables are created using a provided structure SQL file (e.g., `r1/structure.sql`).
3. **Data Import:**  
   - The pipeline imports CSV files for observations, photos, taxa, and observers into the respective tables using PostgreSQL’s `COPY` command.
4. **Index Creation:**  
   - Key indexes are created to optimize spatial and text-based queries (including geospatial indexes on the geometry column).

### B. Geometry Calculation

- The script `common/geom.sh` is executed in parallel to compute the `geom` column on the `observations` table from the `latitude` and `longitude` fields.
- A PostGIS GIST index is then created on the new geometry column to speed up spatial queries.

### C. Metadata Update

- The script `common/vers_origin.sh` is run to add and populate the `origin`, `version`, and `release` columns on all tables.
- This process is executed in parallel across tables to speed up the update.

### D. Elevation Integration

The elevation pipeline can be integrated in one of two ways:

#### 1. During Fresh Ingestion
- **Integration via Main Ingestion Script:**  
  When the environment variable `ENABLE_ELEVATION` is set to `"true"`, the main ingestion script (`common/main.sh`) calls the elevation pipeline after geometry calculation. This pipeline performs the following steps:
  - **Create Elevation Table:**  
    The script `utils/elevation/create_elevation_table.sh` ensures that the `elevation_raster` table exists.
  - **Load DEM Data:**  
    The script `utils/elevation/load_dem.sh` extracts DEM tiles from `.tar` archives and loads them into the `elevation_raster` table using `raster2pgsql` (which requires the custom Docker image).
  - **Update Elevation Values:**  
    Finally, `utils/elevation/update_elevation.sh` updates the `observations.elevation_meters` column for each observation based on a spatial join with the DEM data.

#### 2. Updating an Existing Database
- **Separate Elevation Wrapper:**  
  If you have an existing database (e.g., from a previous release) and you need to add or update elevation values, you can run the elevation wrapper script located at `utils/elevation/wrapper.sh`. This script sets the appropriate environment variables and calls the elevation main script to update the database.

---

## 4. Example Wrapper Usage

Below is an example wrapper script for a fresh ingestion (with elevation enabled):

```bash
#!/bin/bash
# Example: dbTools/ingest/v0/r1/wrapper.sh

# Setup logging
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/wrapper_$(date +%Y%m%d_%H%M%S).log"
echo "Starting ingestion at $(date)" > "${LOG_FILE}"

# Export environment variables
export DB_USER="postgres"
export DB_TEMPLATE="template_postgis"
export NUM_PROCESSES=16
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/v0"
export SOURCE="Feb2025"
export METADATA_PATH="/datasets/ibrida-data/intake/Feb2025"
export ORIGIN_VALUE="iNat-Feb2025"
export VERSION_VALUE="v0"
export RELEASE_VALUE="r2"
export DB_NAME="ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"
export DB_CONTAINER="ibridaDB"
export STRUCTURE_SQL="${BASE_DIR}/r2/structure.sql"

# Enable elevation integration in this ingestion
export ENABLE_ELEVATION=true
export DEM_DIR="/datasets/dem/merit"
export EPSG="4326"
export TILE_SIZE="100x100"

# Execute the main ingestion script
/home/caleb/repo/ibridaDB/dbTools/ingest/v0/common/main.sh

# End of wrapper
echo "Ingestion process complete at $(date)" >> "${LOG_FILE}"
```

For an existing database update, simply run the elevation wrapper:

```bash
#!/bin/bash
# Example: dbTools/ingest/v0/utils/elevation/wrapper.sh

export DB_NAME="ibrida-v0-r1"
export DB_USER="postgres"
export DB_CONTAINER="ibridaDB"
export DEM_DIR="/datasets/dem/merit"
export NUM_PROCESSES=16
export EPSG="4326"
export TILE_SIZE="100x100"
export BASE_DIR="/home/caleb/repo/ibridaDB/dbTools/ingest/v0"

./utils/elevation/main.sh "$DB_NAME" "$DB_USER" "$DB_CONTAINER" "$DEM_DIR" "$NUM_PROCESSES" "$EPSG" "$TILE_SIZE"
```

---

## 5. Verifying Success

After running the ingestion process, verify that:

- The database is created with all required tables and indexes.
- The CSV files have been successfully imported into the tables.
- The `geom` column on `observations` is correctly computed and indexed.
- If elevation was enabled, the `elevation_raster` table exists and the `observations.elevation_meters` column is populated (for rows with valid DEM coverage).
- Log messages and notifications (if configured) confirm each step’s completion.

---

## Final Notes

- This document covers the ingestion side of ibridaDB. For exporting subsets of the data, please see [export.md](../export/export.md) for detailed instructions on the export pipeline.
- Ensure that you use the custom Docker image (with `raster2pgsql` installed) when running ingestion with elevation data.
- For new releases, adjust your wrapper scripts as needed and consider setting up separate directories (e.g., r1, r2) to maintain versioning consistency.

Happy Ingesting!