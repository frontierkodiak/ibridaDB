-- Cleanup script for duplicate elevation_raster indexes
-- The ingestion bug created 1000+ duplicate GIST indexes
-- We only need ONE: elevation_raster_st_convexhull_idx

-- First, verify we have the indexes
SELECT COUNT(*) as duplicate_index_count
FROM pg_indexes 
WHERE tablename = 'elevation_raster' 
  AND indexname LIKE 'elevation_raster_st_convexhull_idx%'
  AND indexname != 'elevation_raster_st_convexhull_idx';

-- Generate DROP statements for all duplicates
SELECT 'DROP INDEX IF EXISTS ' || indexname || ';' as drop_statement
FROM pg_indexes 
WHERE tablename = 'elevation_raster' 
  AND indexname LIKE 'elevation_raster_st_convexhull_idx%'
  AND indexname != 'elevation_raster_st_convexhull_idx'
ORDER BY indexname;

-- After reviewing, you can run this to drop all duplicates:
DO $$
DECLARE
    idx_name TEXT;
BEGIN
    FOR idx_name IN 
        SELECT indexname 
        FROM pg_indexes 
        WHERE tablename = 'elevation_raster' 
          AND indexname LIKE 'elevation_raster_st_convexhull_idx%'
          AND indexname != 'elevation_raster_st_convexhull_idx'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || idx_name;
        RAISE NOTICE 'Dropped index: %', idx_name;
    END LOOP;
END $$;

-- Verify only one index remains
SELECT indexname, pg_size_pretty(pg_relation_size(indexname::regclass)) as size
FROM pg_indexes 
WHERE tablename = 'elevation_raster'
ORDER BY indexname;