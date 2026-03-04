-- Fix Typus name search timeouts by adding proper indexes to expanded_taxa
-- This addresses the P0 issue blocking TaxonomyService

\timing on
\echo '=== FIXING TYPUS SEARCH INDEXES ==='
\echo ''

-- Step 1: Add pg_trgm extension for advanced text search
\echo 'Step 1: Adding pg_trgm extension...'
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Step 2: Add text_pattern_ops indexes for FAST prefix searches (LIKE 'apis%')
\echo ''
\echo 'Step 2: Creating prefix search indexes (text_pattern_ops)...'

-- Scientific name prefix search
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_lower_name_pattern
  ON expanded_taxa (lower(name) text_pattern_ops);

-- Common name prefix search
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_lower_common_pattern
  ON expanded_taxa (lower("commonName") text_pattern_ops);

-- Step 3: Add basic B-tree index on rankLevel for filtering
\echo ''
\echo 'Step 3: Creating rankLevel index for filtering...'
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_ranklevel
  ON expanded_taxa ("rankLevel");

-- Step 4: Add GIN trigram indexes for substring searches
\echo ''
\echo 'Step 4: Creating trigram indexes for substring search...'

-- Scientific name substring search
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_lower_name_trgm
  ON expanded_taxa USING gin (lower(name) gin_trgm_ops);

-- Common name substring search
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_lower_common_trgm
  ON expanded_taxa USING gin (lower("commonName") gin_trgm_ops);

-- Step 5: Additional useful indexes for Typus queries
\echo ''
\echo 'Step 5: Adding additional performance indexes...'

-- Compound index for rank-filtered searches
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_rank_name
  ON expanded_taxa ("rankLevel", lower(name));

-- taxonID index (if not exists) for lookups
CREATE INDEX IF NOT EXISTS idx_expanded_taxa_taxonid
  ON expanded_taxa ("taxonID");

-- Step 6: Update statistics for query planner
\echo ''
\echo 'Step 6: Analyzing table for query planner...'
ANALYZE expanded_taxa;

-- Step 7: Show index summary
\echo ''
\echo '=== INDEX SUMMARY ==='
SELECT 
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) as index_size
FROM pg_indexes 
WHERE tablename = 'expanded_taxa'
ORDER BY indexname;

-- Step 8: Test queries that were timing out
\echo ''
\echo '=== TESTING PROBLEM QUERIES ==='
\echo ''
\echo 'Test 1: Prefix search for "apis" at genus level (was timing out):'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT "taxonID", name, "commonName", "rankLevel"
FROM expanded_taxa
WHERE LOWER(name) LIKE 'apis%'
  AND "rankLevel" = 20
LIMIT 10;

\echo ''
\echo 'Test 2: General prefix search without rank filter:'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT "taxonID", name, "rankLevel"
FROM expanded_taxa
WHERE LOWER(name) LIKE 'homo%'
LIMIT 10;

\echo ''
\echo 'Test 3: Substring search (if using match="substring"):'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT "taxonID", name, "rankLevel"
FROM expanded_taxa
WHERE LOWER(name) LIKE '%apis%'
LIMIT 10;

\echo ''
\echo '=== INDEXES CREATED SUCCESSFULLY ==='
\echo 'The Typus search timeouts should now be resolved.'
\echo ''
\echo 'Key improvements:'
\echo '  ✓ Prefix searches (LIKE "apis%") now use text_pattern_ops index'
\echo '  ✓ Rank filtering now uses rankLevel index'
\echo '  ✓ Substring searches use GIN trigram index'
\echo '  ✓ Compound index for rank+name queries'
\echo ''