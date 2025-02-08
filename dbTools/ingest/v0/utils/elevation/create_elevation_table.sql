-- create_elevation_table.sql
--
-- Creates the "elevation_raster" table to store MERIT DEM raster data,
-- along with a GIST index for efficient spatial lookups.

CREATE TABLE IF NOT EXISTS elevation_raster (
    rid SERIAL PRIMARY KEY,
    rast raster,
    filename TEXT
);

CREATE INDEX IF NOT EXISTS elevation_raster_st_convexhull_idx
    ON elevation_raster
    USING gist (ST_ConvexHull(rast));
