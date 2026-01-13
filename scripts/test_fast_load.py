#!/usr/bin/env python3
"""Quick test of fast loading approach with taxa table."""

import polars as pl
import psycopg2
from io import StringIO
import time

print("🔌 Connecting to database...")
conn = psycopg2.connect(
    host="localhost",
    database="ibrida-v0",
    user="postgres",
    password="ooglyboogly69"
)

try:
    # Drop and recreate staging schema
    print("📦 Creating UNLOGGED staging table...")
    with conn.cursor() as cur:
        cur.execute("DROP SCHEMA IF EXISTS stg_inat_20250827 CASCADE;")
        cur.execute("CREATE SCHEMA stg_inat_20250827;")
        cur.execute("""
            CREATE UNLOGGED TABLE stg_inat_20250827.taxa (
                taxon_id integer NOT NULL,
                ancestry text,
                rank_level double precision,
                rank character varying(255),
                name character varying(255),
                active boolean
            );
        """)
        conn.commit()
    
    # Load taxa CSV with Polars
    print("📊 Reading taxa.csv with Polars...")
    start = time.time()
    
    df = pl.read_csv(
        "/datasets/ibrida-data/intake/Aug2025/taxa.csv",
        separator='\t',
        null_values=['', 'NULL', '\\N'],
        schema_overrides={
            'taxon_id': pl.Int32,
            'ancestry': pl.Utf8,
            'rank_level': pl.Float64,  # This is the fix - it has decimal values
            'rank': pl.Utf8,
            'name': pl.Utf8,
            'active': pl.Boolean
        }
    )
    
    print(f"  Loaded {len(df):,} rows in {time.time()-start:.1f}s")
    
    # Convert to CSV string
    print("📝 Converting to CSV format...")
    output = StringIO()
    df.write_csv(output, separator='\t', null_value='')
    output.seek(0)
    
    # Stream to PostgreSQL
    print("💾 Streaming to PostgreSQL...")
    start = time.time()
    
    with conn.cursor() as cur:
        cur.copy_expert(
            """COPY stg_inat_20250827.taxa 
               (taxon_id, ancestry, rank_level, rank, name, active)
               FROM STDIN WITH (FORMAT CSV, DELIMITER E'\\t', NULL '')""",
            output
        )
        conn.commit()
    
    elapsed = time.time() - start
    
    # Verify
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM stg_inat_20250827.taxa")
        count = cur.fetchone()[0]
    
    print(f"✅ Success! Loaded {count:,} rows in {elapsed:.1f}s")
    print(f"   Speed: {count/elapsed:.0f} rows/sec")
    
finally:
    conn.close()