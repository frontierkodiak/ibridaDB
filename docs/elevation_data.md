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

```sql
CREATE TABLE elevation_raster (
    rid SERIAL PRIMARY KEY,      -- Unique raster tile ID
    rast raster,                  -- PostGIS raster data
    filename TEXT                 -- Original source filename
);
```

### Storage Statistics
- **Number of tiles**: 2,302,331
- **Total size**: 155 GB
- **Tile dimensions**: 100x100 pixels (configured via TILE_SIZE parameter)
- **Pixel resolution**: 0.00083333° (~90m at equator)
- **SRID**: 4326 (WGS84 geographic coordinates)

### Spatial Index

The table uses a GIST index on the convex hull of each raster tile for efficient spatial queries:

```sql
CREATE INDEX elevation_raster_st_convexhull_idx
    ON elevation_raster
    USING gist (ST_ConvexHull(rast));
```

**Note**: Due to repeated ingestion runs, there are currently over 1000 duplicate indexes that should be cleaned up.

## Data Ingestion Pipeline

### 1. Download MERIT DEM Tiles
```bash
# Sequential download
dbTools/dem/download_merit.sh

# Parallel download (faster)
dbTools/dem/download_merit_parallel.sh 4
```

### 2. Load into Database
The elevation ingestion is handled by scripts in `dbTools/ingest/v0/utils/elevation/`:

```bash
# Wrapper script with configuration
./dbTools/ingest/v0/utils/elevation/wrapper.sh
```

This orchestrates three steps:
1. **Create table**: Creates `elevation_raster` table with spatial index
2. **Load DEM data**: Uses `raster2pgsql` to tile and import GeoTIFF files
3. **Update observations**: Populates `observations.elevation_meters` column

### Key Configuration Parameters
- `DEM_DIR`: Path to MERIT DEM tar files (`/datasets/dem/merit`)
- `TILE_SIZE`: Raster tile size for PostGIS (`100x100`)
- `EPSG`: Coordinate system (`4326` for WGS84)
- `NUM_PROCESSES`: Parallel processes for updating observations (`16`)

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

## Performance Characteristics

- **Single point lookup**: ~500ms (includes query planning)
- **Batch updates**: Parallelized across 16 processes
- **Index performance**: GIST index enables efficient bounding box filtering
- **Memory usage**: Tiles are loaded on-demand, not all at once

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
3. **Query Performance**: Single-point lookups take ~500ms
4. **Storage Size**: 155GB is substantial for raster data
5. **Index Duplication**: Current setup has created many duplicate indexes

## Future Improvements

1. **Index Cleanup**: Remove duplicate GIST indexes
2. **Performance Optimization**: 
   - Consider pyramid/overview tables for different zoom levels
   - Implement caching layer for frequently accessed regions
   - Use prepared statements for repeated queries
3. **Data Validation**: Add checks for elevation outliers
4. **Compression**: Investigate raster compression options
5. **Batch API**: Implement efficient batch elevation lookup for multiple points