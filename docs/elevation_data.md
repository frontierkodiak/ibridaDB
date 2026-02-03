# Elevation Data Documentation

## Overview

The ibridaDB system includes global elevation data from MERIT DEM (Multi-Error-Removed Improved-Terrain DEM), stored as PostGIS rasters in the `elevation_raster` table. This enables efficient elevation lookups for any geographic coordinate.

## Data Source

- **Dataset**: MERIT DEM (Multi-Error-Removed Improved-Terrain DEM)
- **Resolution**: ~90m at the equator (3 arc-seconds)
- **Coverage**: Global land areas between 90°N and 60°S
- **Format**: GeoTIFF tiles bundled in TAR archives
- **Storage Location**: `/datasets/dem/merit/`

## Database Structure

### Table: `elevation_raster`

This table is created by `raster2pgsql` (via `load_dem_fixed.sh`) and currently
contains only the core raster columns:

```sql
-- created by raster2pgsql -C
CREATE TABLE elevation_raster (
    rid  SERIAL PRIMARY KEY,  -- Unique raster tile ID
    rast raster               -- PostGIS raster data
);
```

If you want filenames stored, re-run with `raster2pgsql -F` (not currently used).

### Storage Statistics (query at runtime)
The size/row counts depend on tile size and ingestion choices. Use live queries:

```sql
SELECT reltuples::bigint AS est_rows
FROM pg_class
WHERE relname = 'elevation_raster';

\d elevation_raster  -- shows constraints, pixel type, SRID, etc.
```

Current defaults (MERIT @ 3 arc-seconds):
- **Tile dimensions**: `TILE_SIZE` (commonly 100x100; current r2 ingest uses 256x256)
- **Pixel resolution**: 0.00083333° (~90m at equator)
- **SRID**: 4326 (WGS84)

### Spatial Index

The table uses a GIST index on the convex hull of each raster tile for efficient spatial queries:

```sql
CREATE INDEX elevation_raster_st_convexhull_idx
    ON elevation_raster
    USING gist (ST_ConvexHull(rast));
```

**Note**: We now create the index once (first tile only). No duplicate indexes
should be created by `load_dem_fixed.sh`.

## Data Ingestion Pipeline

### 1. Download MERIT DEM Tiles
```bash
# Sequential download
dbTools/dem/download_merit.sh

# Parallel download (faster)
dbTools/dem/download_merit_parallel.sh 4
```

### 2. Load into Database
Use the fixed loader in `dbTools/ingest/v0/utils/elevation/`:

```bash
dbTools/ingest/v0/utils/elevation/load_dem_fixed.sh \
  /datasets/dem/merit ibrida-v0-r2 postgres ibridaDB 4326 100x100
```

This performs:
1. **Create table**: `raster2pgsql -C` creates `elevation_raster`.
2. **Create index once**: `-I` is used only for the first tile.
3. **Drop max-extent constraint**: `enforce_max_extent_rast` is removed after the
   first tile so later tiles outside the initial bounds can append.
4. **Append remaining tiles**: `raster2pgsql -a` for all subsequent tiles.

Then update observations:
```bash
dbTools/ingest/v0/utils/elevation/update_elevation.sh
```

### Key Configuration Parameters
- `DEM_DIR`: Path to MERIT DEM tar files (`/datasets/dem/merit`)
- `TILE_SIZE`: Raster tile size for PostGIS (e.g., `256x256` for faster ingest)
- `EPSG`: Coordinate system (`4326` for WGS84)
- `PARALLEL_TARS`: Number of tar files processed in parallel (default 4)
- `CREATE_INDEX_AFTER_LOAD`: Create GIST index after full load (default true)
- `NUM_PROCESSES`: Parallel processes for updating observations (`16` typical)

## Querying Elevation Data

### Basic Point Elevation Query
```sql
-- Get elevation for a specific coordinate (e.g., Los Angeles)
SELECT ST_Value(
    er.rast, 
    ST_SetSRID(ST_MakePoint(-118.2437, 34.0522), 4326)
) as elevation_meters
FROM elevation_raster er
WHERE ST_Intersects(
    er.rast, 
    ST_SetSRID(ST_MakePoint(-118.2437, 34.0522), 4326)
)
LIMIT 1;
```

### Batch Update for Observations
The update script uses parallel processing to efficiently populate elevation values:

```sql
UPDATE observations
SET elevation_meters = ST_Value(er.rast, observations.geom)
FROM elevation_raster er
WHERE ST_Intersects(er.rast, observations.geom);
```

## Performance Characteristics (observed/expected)

- **DEM load time** is dominated by `raster2pgsql` (GDAL read + tiling + inserts).
- **Index creation** can be a major bottleneck if done per-tile; we now create
  the index once.
- **Tile size** controls row count and ingest speed:
  - Smaller tiles = more rows, slower inserts, faster point lookup.
  - Larger tiles = fewer rows, faster ingest, potentially slower point lookup.

If ingest is too slow, consider:
1. Increasing `TILE_SIZE` (e.g., 256x256).
2. Deferring index creation until after all tiles load (`CREATE_INDEX_AFTER_LOAD=true`).
3. Increasing `PARALLEL_TARS` (e.g., 4–8 depending on CPU).
4. Temporarily setting `synchronous_commit=off` during ingest (already enabled in loader).

## Integration with Typus ElevationService

The draft `PostgresRasterElevation` service in Typus would query this data:

```python
class PostgresRasterElevation(ElevationService):
    async def elevation(self, lat: float, lon: float) -> Optional[float]:
        async with self._Session() as s:
            point = func.ST_SetSRID(func.ST_MakePoint(lon, lat), 4326)
            stmt = (
                select(func.ST_Value(self._tbl.c.rast, point))
                .where(func.ST_Intersects(self._tbl.c.rast, point))
                .limit(1)
            )
            val = await s.scalar(stmt)
            return float(val) if val is not None else None
```

### Implementation Considerations

1. **Table Discovery**: The service expects `elevation_raster` table in SQLAlchemy metadata
2. **Coordinate Order**: Note that PostGIS uses (lon, lat) order, not (lat, lon)
3. **NULL Handling**: Returns None for ocean/no-data areas
4. **Connection Pooling**: Uses SQLAlchemy async engine with connection pooling
5. **Performance**: ~500ms per lookup could be optimized with:
   - Connection pooling tuning
   - Prepared statements
   - Result caching for frequently queried areas

## Maintenance Tasks

### Remove Duplicate Indexes
The current database has over 1000 duplicate GIST indexes that should be cleaned:

```sql
-- List all duplicate indexes
SELECT indexname 
FROM pg_indexes 
WHERE tablename = 'elevation_raster' 
  AND indexname LIKE 'elevation_raster_st_convexhull_idx%'
  AND indexname != 'elevation_raster_st_convexhull_idx'
ORDER BY indexname;

-- Drop duplicates (keep only the first one)
DROP INDEX IF EXISTS elevation_raster_st_convexhull_idx1;
DROP INDEX IF EXISTS elevation_raster_st_convexhull_idx2;
-- ... etc
```

### Verify Coverage
Check for missing elevation data:

```sql
-- Count observations without elevation data
SELECT COUNT(*) 
FROM observations 
WHERE elevation_meters IS NULL 
  AND geom IS NOT NULL;
```

## Known Limitations

1. **Ocean Areas**: No elevation data for ocean points (returns NULL)
2. **Polar Regions**: Limited coverage above 60°N and below 60°S
3. **Storage Size**: Large; depends on tile size and full global load
4. **Max-extent constraint**: Must be dropped to allow global tiles to append

## Future Improvements

1. **Performance Optimization**: 
   - Consider larger tile sizes if ingest is too slow
   - Defer index creation until after all tiles load
   - Consider out-of-db rasters (`raster2pgsql -R`) if disk or ingest time becomes limiting
2. **Data Validation**: Add checks for elevation outliers
3. **Compression**: Investigate raster compression options
4. **Batch API**: Implement efficient batch elevation lookup for multiple points
