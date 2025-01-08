# ibridaDB Export Reference

This document describes the key parameters that drive the **v1** export process in our `ibridaDB` pipeline. The parameters are split into three logical groups, reflecting their usage and declaration in `wrapper.sh`: **Database Config**, **Export Parameters**, and **Paths**.

## 1. Database Config

These environment variables specify how the export scripts connect to the database and handle versioning.

### `DB_USER`
- **Description**: The database user that executes SQL commands.
- **Default**: `"postgres"`

### `VERSION_VALUE`
- **Description**: The string identifier for the data version being exported (e.g., `"v0"`).  
- **Usage**: Combined with `RELEASE_VALUE` to construct the `DB_NAME`, and also embedded in logs or summary files.

### `RELEASE_VALUE`
- **Description**: Further disambiguates the release within the version (e.g., `"r1"`).
- **Usage**: Combined with `VERSION_VALUE` to construct the `DB_NAME`; also used for conditional logic in `functions.sh` (e.g., deciding whether to append `anomaly_score` columns).

### `ORIGIN_VALUE`
- **Description**: Documents the source of the data (e.g., `"iNat-Dec2024"`).  
- **Usage**: Potentially used to label data, but currently only logged or stored in summary contexts.

### `DB_NAME`
- **Description**: The actual database name to which SQL commands are directed.  
- **Constructed**: Typically `"ibrida-${VERSION_VALUE}-${RELEASE_VALUE}"` (e.g., `"ibrida-v0-r1"`).

---

## 2. Export Parameters

These variables control which data are included in the export and how they are sampled or filtered.

### `REGION_TAG`
- **Description**: Identifies a particular broad region (e.g., `"NAfull"`, `"EURfull"`) that will define bounding box coordinates.  
- **Usage**: Affected by the `set_region_coordinates()` function in `regional_base.sh`, which sets `XMIN`, `YMIN`, `XMAX`, `YMAX`.  
- **Example**: `"NAfull"` for North America bounding box.

### `MIN_OBS`
- **Description**: The minimum number of observations required for a species to be included in the regional tables.  
- **Intended Behavior**: 
  - In `regional_base.sh`, species (rank_level == 10) must have at least `MIN_OBS` **research-grade** observations to be included in `<REGION_TAG>_min${MIN_OBS}_all_taxa` and subsequent tables.  
  - Practically, the code checks for `HAVING COUNT(o2.observation_uuid) >= ${MIN_OBS}` and also filters out non-research-grade observations if `t.rank_level = 10`.  
- **Default**: `50`  
- **Note**: If a taxon is not strictly species rank, the code uses a looser condition, but for true species (rank_level=10), it must meet the threshold. 

### `MAX_RN`
- **Description**: The maximum number of **research-grade** observations that will be **sampled per species** in the final CSV export.  
- **Usage**:
  - In `cladistic.sh`, a partition-based random sampling ensures up to `MAX_RN` observations per species (`L10_taxonID`).  
  - Observations with `L10_taxonID IS NULL` are exempt from this cap (they are not strictly species-level).  
- **Default**: `4000`

### `PRIMARY_ONLY`
- **Description**: Controls whether to only export `position=0` (the “primary” or first) photo per observation, or *all* photos.  
- **Usage**:
  - In `cladistic.sh`, the `COPY` statements either require `p.position = 0` or allow all positions, based on `PRIMARY_ONLY=true/false`.  
- **Typical Values**: `true` (only primary photo) or `false` (all photos).

### `METACLADE`
- **Description**: A specialized grouping of clades, combining multiple lineages. Often something like `"primary_terrestrial_arthropoda"`.  
- **Usage**:
  - In `clade_defns.sh`, a `METACLADES["primary_terrestrial_arthropoda"] = ...` expression defines which taxonIDs to include.  
  - If `METACLADE` is set, it overrides `CLADE` or `MACROCLADE` when building the final condition.

### `EXPORT_GROUP`
- **Description**: The name or label for the final exported dataset (e.g., `"primary_terrestrial_arthropoda"`).  
- **Usage**:
  - Used to build the final table name (`<EXPORT_GROUP>_observations`) in `cladistic.sh`.  
  - Also appended to output CSV filenames and summary messages.

### `PROCESS_OTHER`
- **Description**: A boolean-like flag (default `false`) indicating whether to run additional extra steps.  
- **Usage**:
  - Not deeply integrated in the current code, but can be used to skip or include extra logic if set to `true`.

### `SKIP_REGIONAL_BASE`
- **Description**: Allows the user to **skip** dropping and recreating the regional base tables if they **already exist** and are **non-empty**.  
- **Usage**:
  - In `main.sh`, if `SKIP_REGIONAL_BASE=true`, the script checks if `<REGION_TAG>_min${MIN_OBS}_all_taxa_obs` exists and has at least one row. If so, it skips calling `regional_base.sh`. Otherwise, it recreates the table as normal.  
  - Saves time when multiple clade exports reference the same region-based table.  
- **Default**: `false`

---

## 3. Paths

These variables handle filesystem or container paths for storing exports and controlling Docker context.

### `DB_CONTAINER`
- **Description**: The name of the Docker container running PostgreSQL (e.g., `"ibridaDB"`).  
- **Usage**:
  - `functions.sh` uses it in `execute_sql()` to run `docker exec ${DB_CONTAINER} ...`.

### `HOST_EXPORT_BASE_PATH`
- **Description**: The base path on the **host** for storing final exports (mapped into the container).  
- **Default**: `"/datasets/ibrida-data/exports"`.

### `CONTAINER_EXPORT_BASE_PATH`
- **Description**: The base path **inside** the Docker container that maps to `HOST_EXPORT_BASE_PATH`.  
- **Default**: `"/exports"`.

### `EXPORT_SUBDIR`
- **Description**: A dynamic subdirectory that includes the version, release, and other parameters (e.g., `"v0/r1/primary_only_50min_4000max"`).  
- **Usage**:
  - Combined with `HOST_EXPORT_BASE_PATH` for writing to disk from the host perspective, and with `CONTAINER_EXPORT_BASE_PATH` for writing to disk from within the container.  
  - E.g., final container path is `"$CONTAINER_EXPORT_BASE_PATH/$EXPORT_SUBDIR"`, final host path is `"$HOST_EXPORT_BASE_PATH/$EXPORT_SUBDIR"`.

### `BASE_DIR`
- **Description**: The top-level directory for the export scripts inside the container (e.g., `"/home/caleb/repo/ibridaDB/dbTools/export/v0"`).  
- **Usage**:  
  - Scripts in `wrapper.sh` or `main.sh` reference subdirectories within `BASE_DIR`, e.g., `BASE_DIR/common/functions.sh` or `BASE_DIR/common/regional_base.sh`.  

---

## Flow of Parameter Usage

1. **Wrapper Script** (`wrapper.sh`):  
   - Defines the environment variables documented above.  
   - Logs them and calls `main.sh`.

2. **Main Script** (`main.sh`):  
   - Validates required variables.  
   - Creates the export directory.  
   - **If `SKIP_REGIONAL_BASE=true`, checks if the existing region-based table is present and non-empty. Otherwise, or if the table is missing or empty, runs `regional_base.sh`.**  
   - Calls `cladistic.sh` to filter and export the final CSV.  
   - Generates a final `export_summary.txt`.

3. **regional_base.sh**:  
   - Uses `REGION_TAG` to set bounding box coordinates.  
   - Applies `MIN_OBS` to exclude species with fewer than the required number of research-grade observations.  
   - Produces `<REGION_TAG>_min${MIN_OBS}_all_taxa_obs`.

4. **cladistic.sh**:  
   - Applies `METACLADE`, `CLADE`, or `MACROCLADE` logic to define taxonomic filters.  
   - Joins the regional table to `expanded_taxa`, producing `<EXPORT_GROUP>_observations`.  
   - Randomly samples up to `MAX_RN` observations **per species** (defined by `L10_taxonID`) in the final CSV, with `PRIMARY_ONLY` restricting photos if desired.

5. **export_per_species_snippet.sh** (Optional):  
   - A shortcut script to export a final CSV from an already-existing `<EXPORT_GROUP>_observations` table without re-creating upstream tables or re-running the entire flow.
