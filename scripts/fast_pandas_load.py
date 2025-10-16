#!/usr/bin/env python3
"""Fast load using pandas + psycopg2 (more robust for malformed CSVs)."""

import pandas as pd
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
    print("📦 Creating staging schema and UNLOGGED tables...")
    with conn.cursor() as cur:
        cur.execute("DROP SCHEMA IF EXISTS stg_inat_20250827 CASCADE;")
        cur.execute("CREATE SCHEMA stg_inat_20250827;")
        
        # Create all UNLOGGED tables
        cur.execute("""
            CREATE UNLOGGED TABLE stg_inat_20250827.observations (
                observation_uuid uuid,
                observer_id integer,
                latitude numeric(15,10),
                longitude numeric(15,10),
                positional_accuracy integer,
                taxon_id integer,
                quality_grade varchar(255),
                observed_on date,
                anomaly_score double precision
            );
        """)
        
        cur.execute("""
            CREATE UNLOGGED TABLE stg_inat_20250827.photos (
                photo_uuid uuid,
                photo_id integer,
                observation_uuid uuid,
                observer_id integer,
                extension varchar(5),
                license varchar(255),
                width smallint,
                height smallint,
                position smallint
            );
        """)
        
        cur.execute("""
            CREATE UNLOGGED TABLE stg_inat_20250827.observers (
                observer_id integer,
                login varchar(255),
                name varchar(255)
            );
        """)
        
        cur.execute("""
            CREATE UNLOGGED TABLE stg_inat_20250827.taxa (
                taxon_id integer,
                ancestry text,
                rank_level double precision,
                rank varchar(255),
                name varchar(255),
                active boolean
            );
        """)
        conn.commit()
    
    # Function to load a table
    def load_table(csv_path, table_name, columns):
        print(f"\n📊 Loading {table_name} from {csv_path}")
        start = time.time()
        
        # Read with pandas in chunks for large files
        chunk_size = 1_000_000 if 'photos' in table_name else None
        
        if chunk_size:
            total_rows = 0
            for i, chunk in enumerate(pd.read_csv(
                csv_path, 
                sep='\t', 
                chunksize=chunk_size,
                na_values=['', 'NULL', '\\N'],
                on_bad_lines='skip'
            )):
                # Convert to CSV string
                output = StringIO()
                chunk.to_csv(output, sep='\t', index=False, header=False, na_rep='')
                output.seek(0)
                
                # Stream to PostgreSQL
                with conn.cursor() as cur:
                    cur.copy_expert(
                        f"""COPY stg_inat_20250827.{table_name} ({','.join(columns)})
                           FROM STDIN WITH (FORMAT CSV, DELIMITER E'\\t', NULL '')""",
                        output
                    )
                
                total_rows += len(chunk)
                print(f"  Chunk {i+1}: {len(chunk):,} rows (total: {total_rows:,})")
                
                # Commit every few chunks
                if i % 5 == 0:
                    conn.commit()
            
            conn.commit()
            elapsed = time.time() - start
            print(f"  ✓ Loaded {total_rows:,} rows in {elapsed:.1f}s ({total_rows/elapsed:.0f} rows/sec)")
            
        else:
            # Load smaller tables in one shot
            df = pd.read_csv(
                csv_path, 
                sep='\t',
                na_values=['', 'NULL', '\\N'],
                on_bad_lines='skip'
            )
            
            # Convert to CSV string
            output = StringIO()
            df.to_csv(output, sep='\t', index=False, header=False, na_rep='')
            output.seek(0)
            
            # Stream to PostgreSQL
            with conn.cursor() as cur:
                cur.copy_expert(
                    f"""COPY stg_inat_20250827.{table_name} ({','.join(columns)})
                       FROM STDIN WITH (FORMAT CSV, DELIMITER E'\\t', NULL '')""",
                    output
                )
            
            conn.commit()
            elapsed = time.time() - start
            print(f"  ✓ Loaded {len(df):,} rows in {elapsed:.1f}s ({len(df)/elapsed:.0f} rows/sec)")
    
    # Load all tables
    base_path = "/datasets/ibrida-data/intake/Aug2025"
    
    # Start with small tables
    load_table(
        f"{base_path}/taxa.csv", 
        "taxa",
        ["taxon_id", "ancestry", "rank_level", "rank", "name", "active"]
    )
    
    load_table(
        f"{base_path}/observers.csv",
        "observers", 
        ["observer_id", "login", "name"]
    )
    
    # Then large tables
    load_table(
        f"{base_path}/observations.csv",
        "observations",
        ["observation_uuid", "observer_id", "latitude", "longitude", 
         "positional_accuracy", "taxon_id", "quality_grade", "observed_on", "anomaly_score"]
    )
    
    load_table(
        f"{base_path}/photos.csv",
        "photos",
        ["photo_uuid", "photo_id", "observation_uuid", "observer_id",
         "extension", "license", "width", "height", "position"]
    )
    
    # Verify
    print("\n✅ Verification:")
    with conn.cursor() as cur:
        for table in ["observations", "photos", "observers", "taxa"]:
            cur.execute(f"SELECT COUNT(*) FROM stg_inat_20250827.{table}")
            count = cur.fetchone()[0]
            print(f"  {table}: {count:,} rows")
    
    print("\n🎉 All tables loaded successfully!")
    
finally:
    conn.close()