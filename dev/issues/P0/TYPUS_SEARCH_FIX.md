# P0: Typus Search Timeout Fix

## Problem
Typus TaxonomyService name searches are timing out on Postgres backend due to missing indexes on `expanded_taxa` table (18GB, 1.3M rows).

## Root Cause
The `expanded_taxa` table has **ONLY a primary key index** - no indexes for:
- `LOWER(name) LIKE 'prefix%'` queries
- `rankLevel` filtering  
- `commonName` searches

## Solution (In Progress)
Creating these critical indexes (running in background):

### Priority 1 - Most Critical (Building Now)
```sql
-- rankLevel filter (bash_5 - running)
CREATE INDEX CONCURRENTLY idx_expanded_taxa_ranklevel 
ON expanded_taxa ("rankLevel");

-- Prefix search on name (bash_6 - running) 
CREATE INDEX CONCURRENTLY idx_expanded_taxa_lower_name_pattern
ON expanded_taxa (lower(name) text_pattern_ops);
```

### Priority 2 - Also Important
```sql
-- Common name prefix search
CREATE INDEX idx_expanded_taxa_lower_common_pattern
ON expanded_taxa (lower("commonName") text_pattern_ops);

-- Compound for rank+name queries
CREATE INDEX idx_expanded_taxa_rank_name
ON expanded_taxa ("rankLevel", lower(name));
```

### Priority 3 - Nice to Have (for substring search)
```sql
-- GIN trigram indexes (large, slow to build)
CREATE INDEX idx_expanded_taxa_lower_name_trgm
ON expanded_taxa USING gin (lower(name) gin_trgm_ops);

CREATE INDEX idx_expanded_taxa_lower_common_trgm
ON expanded_taxa USING gin (lower("commonName") gin_trgm_ops);
```

## Timeline
- **rankLevel index**: ~5-10 minutes (simple B-tree on 1.3M rows)
- **lower(name) pattern index**: ~15-30 minutes (functional index on text)
- **Total for critical fixes**: ~30-45 minutes

## Immediate Workaround (if needed urgently)
While indexes build, you could:
1. Switch Typus tests to SQLite backend temporarily
2. Add statement_timeout to avoid hanging: `SET statement_timeout = '5s';`
3. Limit search to exact matches only (no LIKE queries)

## Verification
Once indexes complete, test with:
```sql
EXPLAIN ANALYZE
SELECT "taxonID", name 
FROM expanded_taxa
WHERE LOWER(name) LIKE 'apis%' 
  AND "rankLevel" = 20
LIMIT 10;
```

Should show:
- Index Scan using idx_expanded_taxa_lower_name_pattern
- Execution time < 50ms (vs timeout currently)

## Status
- ✅ pg_trgm extension added
- 🔄 rankLevel index building (bash_5)
- 🔄 lower(name) pattern index building (bash_6)
- ⏳ Other indexes queued

## Impact
Once complete, Typus search queries will go from **timeout (>30s)** to **<50ms**.