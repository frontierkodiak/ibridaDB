# Expanded Taxa Indexes - Master Reference

Generated: 2025-09-07

## Current Production Indexes (18 total)

The `expanded_taxa` table has the following indexes as of today:

### Primary Key
```sql
CREATE UNIQUE INDEX expanded_taxa_pkey 
ON public.expanded_taxa USING btree ("taxonID")
```

### Core Column Indexes
```sql
-- Basic lookups
CREATE INDEX idx_expanded_taxa_taxonid ON expanded_taxa ("taxonID")  -- ⚠️ REDUNDANT with PK
CREATE INDEX idx_expanded_taxa_name ON expanded_taxa (name)  -- ⚠️ OPTIONAL - not used by Typus
CREATE INDEX idx_expanded_taxa_ranklevel ON expanded_taxa ("rankLevel")

-- Immediate ancestors
CREATE INDEX idx_immediate_ancestor_taxon_id ON expanded_taxa ("immediateAncestor_taxonID")
CREATE INDEX idx_immediate_major_ancestor_taxon_id ON expanded_taxa ("immediateMajorAncestor_taxonID")
```

### Taxonomic Level Indexes (for clade filtering)
```sql
CREATE INDEX idx_expanded_taxa_l10_taxonid ON expanded_taxa ("L10_taxonID")  -- species
CREATE INDEX idx_expanded_taxa_l20_taxonid ON expanded_taxa ("L20_taxonID")  -- genus
CREATE INDEX idx_expanded_taxa_l30_taxonid ON expanded_taxa ("L30_taxonID")  -- tribe
CREATE INDEX idx_expanded_taxa_l40_taxonid ON expanded_taxa ("L40_taxonID")  -- order
CREATE INDEX idx_expanded_taxa_l50_taxonid ON expanded_taxa ("L50_taxonID")  -- class
CREATE INDEX idx_expanded_taxa_l60_taxonid ON expanded_taxa ("L60_taxonID")  -- subphylum
CREATE INDEX idx_expanded_taxa_l70_taxonid ON expanded_taxa ("L70_taxonID")  -- kingdom
```

### NEW Text Search Indexes (Added 2025-09-07 for Typus)
```sql
-- Extension required
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Prefix search patterns (LIKE 'prefix%')
CREATE INDEX idx_expanded_taxa_lower_name_pattern 
ON expanded_taxa (lower(name) text_pattern_ops)

CREATE INDEX idx_expanded_taxa_lower_common_pattern 
ON expanded_taxa (lower("commonName") text_pattern_ops)

-- Substring search (LIKE '%substring%')
CREATE INDEX idx_expanded_taxa_lower_name_trgm 
ON expanded_taxa USING gin (lower(name) gin_trgm_ops)

CREATE INDEX idx_expanded_taxa_lower_common_trgm 
ON expanded_taxa USING gin (lower("commonName") gin_trgm_ops)

-- Compound for rank-filtered name searches
CREATE INDEX idx_expanded_taxa_rank_name 
ON expanded_taxa ("rankLevel", lower(name))
```

## Index Sizes
- Primary + basic: ~500MB
- Taxonomic level indexes: ~50MB each (350MB total)
- Text search indexes: ~200MB each (800MB total for GIN)
- **Total index footprint: ~6.5GB** (vs 12GB table)

## Documentation Status

### Out of Date
- `/home/caleb/repo/ibridaDB/docs/expanded_taxa.md` - Lists only original indexes, missing text search indexes
- `/home/caleb/repo/ibridaDB/models/expanded_taxa.py` - SQLAlchemy model doesn't define indexes
- `/home/caleb/repo/typus/typus/orm/expanded_taxa.py` - Typus ORM model doesn't define indexes

### Canonical Source
The database itself is the source of truth. Query with:
```sql
-- List all indexes
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'expanded_taxa' 
ORDER BY indexname;

-- Get sizes
SELECT 
    indexname,
    pg_size_pretty(pg_relation_size(indexname::regclass)) as size
FROM pg_indexes 
WHERE tablename = 'expanded_taxa';
```

## Export Schema Script
To export the complete DDL including indexes:
```bash
docker exec ibridaDB pg_dump -U postgres -d ibrida-v0 \
    --schema-only \
    --table=expanded_taxa \
    > expanded_taxa_schema.sql
```

## Notes for Migration to Typus ORM

The Typus ORM model (`/home/caleb/repo/typus/typus/orm/expanded_taxa.py`) should eventually include index definitions using SQLAlchemy's Index construct:

```python
from sqlalchemy import Index

class ExpandedTaxa(Base):
    __tablename__ = "expanded_taxa"
    
    # ... column definitions ...
    
    __table_args__ = (
        Index('idx_expanded_taxa_ranklevel', 'rankLevel'),
        Index('idx_expanded_taxa_lower_name_pattern', 
              func.lower(name), 
              postgresql_using='btree',
              postgresql_ops={'lower': 'text_pattern_ops'}),
        # ... etc
    )
```

However, since indexes are typically managed at the database level (not by ORMs), keeping them documented here is reasonable.

## Index Optimization Notes

### Potentially Redundant Indexes
- **`idx_expanded_taxa_taxonid`** - REDUNDANT with primary key, can be dropped
- **`idx_expanded_taxa_name`** - OPTIONAL, not needed for Typus (which uses `lower(name)`)

### Essential vs Optional
**Essential for Typus:**
- Text pattern ops indexes (`lower(name)`, `lower(commonName)`)
- Rank level index
- Compound rank+name index

**Optional based on usage:**
- Trigram GIN indexes (needed only for substring search)
- Per-major-rank indexes (L10, L20, etc.) - useful for clade filtering but large footprint

## Typus Index Management

Typus provides an index helper tool (v0.4.0+) to ensure required indexes exist:

### CLI Usage
```bash
# Ensure all recommended indexes
uv run typus-pg-ensure-indexes --dsn "$POSTGRES_DSN"

# Include optional trigram indexes
uv run typus-pg-ensure-indexes --dsn "$POSTGRES_DSN" --ensure-trgm
```

### Python API
```python
from typus.services.pg_index_helper import ensure_expanded_taxa_indexes

await ensure_expanded_taxa_indexes(
    dsn,
    include_major_rank_indexes=True,  # L10, L20, etc.
    include_pattern_indexes=True,     # text_pattern_ops
    include_trigram_indexes=True,     # GIN trigram
    ensure_pg_trgm_extension=False    # requires superuser
)
```

### What Typus Creates
- Core functional indexes for search
- Skips redundant `idx_expanded_taxa_taxonid`
- Optionally creates trigram indexes if substring search needed
- See Typus documentation for current details

## Recommendations

1. **Keep this file as master reference** - Update when indexes change
2. **Don't define indexes in ORM models** - They're deployment-specific
3. **Use database as source of truth** - Query pg_indexes for current state
4. **Use Typus helper for consistency** - Ensures optimal index set
5. **Consider dropping redundant indexes** - Save ~50MB by removing `idx_expanded_taxa_taxonid`