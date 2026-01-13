#!/usr/bin/env python3
"""
Materialize anthophila_flat/ directory and insert kept items into media table.

Creates hardlinks/copies of kept anthophila images into a flat directory structure
and inserts metadata into the media table for database integration.

Usage:
  uv run python3 scripts/materialize_anthophila_flat.py \
    --manifest anthophila_duplicates.csv \
    --flat-dir /datasets/ibrida-data/anthophila_flat \
    --db-connection "postgresql://postgres:ooglyboogly69@localhost/ibrida-v0"
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Dict, List
import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor
from tqdm import tqdm

def connect_to_database(connection_string: str):
    """Connect to PostgreSQL database."""
    try:
        conn = psycopg2.connect(connection_string)
        return conn
    except psycopg2.Error as e:
        print(f"Error connecting to database: {e}")
        raise

def load_dedup_manifest(manifest_path: Path) -> pd.DataFrame:
    """Load deduplication results CSV."""
    print(f"Loading deduplication results from {manifest_path}")
    df = pd.read_csv(manifest_path)
    
    # Filter to only kept items
    kept_df = df[df['keep_flag'] == True].copy()
    print(f"Found {len(kept_df)} kept items out of {len(df)} total")
    
    return kept_df

def create_flat_directory(flat_dir: Path):
    """Create the flat directory structure."""
    flat_dir.mkdir(parents=True, exist_ok=True)
    print(f"Created/verified flat directory: {flat_dir}")

def create_sidecar_metadata(row: pd.Series) -> Dict:
    """Create sidecar JSONB metadata for media table."""
    sidecar = {
        "original_path": row['original_path'],
        "source_tag": row['source_tag'],
        "sha256": row['sha256'],
        "phash": row.get('phash', ''),
        "scientific_name_norm": row['scientific_name_norm'],
        "width": int(row['width']) if pd.notna(row['width']) else None,
        "height": int(row['height']) if pd.notna(row['height']) else None,
        "file_bytes": int(row['file_bytes']) if pd.notna(row['file_bytes']) else None,
        "id_core": int(row['id_core']) if pd.notna(row['id_core']) else None,
        "id_type_guess": row.get('id_type_guess', ''),
        "ingestion_timestamp": "2025-08-29T00:00:00Z"  # Placeholder
    }
    return sidecar

def materialize_files(kept_df: pd.DataFrame, flat_dir: Path, use_hardlinks: bool = True):
    """Copy or hardlink files to flat directory."""
    
    materialized_files = []
    failed_files = []
    
    print(f"Materializing {len(kept_df)} files to {flat_dir}")
    print(f"Using {'hardlinks' if use_hardlinks else 'copies'}")
    
    for _, row in tqdm(kept_df.iterrows(), total=len(kept_df), desc="Materializing"):
        original_path = Path(row['original_path'])
        flat_name = row['flat_name']
        target_path = flat_dir / flat_name
        
        try:
            if not original_path.exists():
                print(f"Warning: Original file not found: {original_path}")
                failed_files.append(row['asset_uuid'])
                continue
                
            if target_path.exists():
                print(f"Warning: Target already exists, skipping: {target_path}")
                continue
            
            if use_hardlinks:
                try:
                    os.link(str(original_path), str(target_path))
                except OSError as e:
                    # Fallback to copy if hardlink fails (different filesystems)
                    print(f"Hardlink failed, copying instead: {e}")
                    shutil.copy2(str(original_path), str(target_path))
            else:
                shutil.copy2(str(original_path), str(target_path))
            
            materialized_files.append({
                'asset_uuid': row['asset_uuid'],
                'original_path': str(original_path),
                'flat_path': str(target_path),
                'flat_name': flat_name
            })
            
        except Exception as e:
            print(f"Error materializing {original_path}: {e}")
            failed_files.append(row['asset_uuid'])
    
    print(f"Materialization complete: {len(materialized_files)} files, {len(failed_files)} failed")
    return materialized_files, failed_files

def insert_media_records(kept_df: pd.DataFrame, materialized_files: List[Dict], 
                        flat_dir: Path, db_conn):
    """Insert media records into database."""
    
    print(f"Inserting {len(materialized_files)} media records...")
    
    # Create mapping of asset_uuid to materialized file info
    materialized_map = {f['asset_uuid']: f for f in materialized_files}
    
    # Prepare insert data
    insert_data = []
    
    for _, row in kept_df.iterrows():
        if row['asset_uuid'] not in materialized_map:
            continue  # Skip files that failed to materialize
            
        mat_file = materialized_map[row['asset_uuid']]
        
        # Create file:// URI
        file_uri = f"file://{mat_file['flat_path']}"
        
        # Create sidecar metadata
        sidecar = create_sidecar_metadata(row)
        
        media_record = {
            'dataset': 'anthophila',
            'release': 'r2', 
            'source_tag': row['source_tag'],
            'uri': file_uri,
            'license': 'unknown',  # As specified in requirements
            'sha256_hex': row['sha256'],
            'sidecar': json.dumps(sidecar)
        }
        
        insert_data.append(media_record)
    
    if not insert_data:
        print("No records to insert")
        return 0
    
    # Batch insert into media table
    with db_conn.cursor() as cursor:
        insert_query = """
        INSERT INTO media (dataset, release, source_tag, uri, license, sha256_hex, sidecar)
        VALUES (%(dataset)s, %(release)s, %(source_tag)s, %(uri)s, %(license)s, %(sha256_hex)s, %(sidecar)s)
        ON CONFLICT (sha256_hex) DO UPDATE SET
            dataset = EXCLUDED.dataset,
            release = EXCLUDED.release,
            source_tag = EXCLUDED.source_tag,
            uri = EXCLUDED.uri,
            license = EXCLUDED.license,
            sidecar = EXCLUDED.sidecar
        """
        
        cursor.executemany(insert_query, insert_data)
        db_conn.commit()
        
        inserted_count = cursor.rowcount
    
    print(f"Inserted/updated {inserted_count} media records")
    return inserted_count

def verify_results(flat_dir: Path, expected_count: int, db_conn):
    """Verify materialization and database insertion results."""
    
    # Check flat directory
    actual_files = list(flat_dir.glob("*.jpg"))
    print(f"\nVERIFICATION:")
    print(f"Expected files: {expected_count}")
    print(f"Actual files in {flat_dir}: {len(actual_files)}")
    
    # Check media table
    with db_conn.cursor() as cursor:
        cursor.execute("""
        SELECT COUNT(*) as count 
        FROM media 
        WHERE dataset = 'anthophila' AND release = 'r2'
        """)
        db_count = cursor.fetchone()[0]
        
    print(f"Media table records (anthophila r2): {db_count}")
    
    success = (len(actual_files) == expected_count and db_count == expected_count)
    print(f"Verification: {'PASSED' if success else 'FAILED'}")
    
    return success

def main():
    parser = argparse.ArgumentParser(description="Materialize anthophila flat directory and insert into media")
    parser.add_argument(
        "--manifest",
        required=True,
        help="Path to deduplication results CSV (from deduplicate_anthophila.py)"
    )
    parser.add_argument(
        "--flat-dir",
        default="/datasets/ibrida-data/anthophila_flat",
        help="Path to create flat directory"
    )
    parser.add_argument(
        "--db-connection", 
        default="postgresql://postgres:ooglyboogly69@localhost/ibrida-v0",
        help="PostgreSQL connection string"
    )
    parser.add_argument(
        "--use-copies",
        action="store_true",
        help="Use file copies instead of hardlinks"
    )
    
    args = parser.parse_args()
    
    manifest_path = Path(args.manifest)
    flat_dir = Path(args.flat_dir)
    
    if not manifest_path.exists():
        print(f"Error: Manifest file not found: {manifest_path}")
        return 1
    
    # Connect to database
    try:
        db_conn = connect_to_database(args.db_connection)
    except Exception as e:
        print(f"Failed to connect to database: {e}")
        return 1
    
    try:
        # Load deduplication results
        kept_df = load_dedup_manifest(manifest_path)
        
        if len(kept_df) == 0:
            print("No kept files found to materialize")
            return 1
        
        # Create flat directory
        create_flat_directory(flat_dir)
        
        # Materialize files
        use_hardlinks = not args.use_copies
        materialized_files, failed_files = materialize_files(
            kept_df, flat_dir, use_hardlinks
        )
        
        if not materialized_files:
            print("No files were successfully materialized")
            return 1
        
        # Insert media records
        inserted_count = insert_media_records(
            kept_df, materialized_files, flat_dir, db_conn
        )
        
        # Verify results
        success = verify_results(flat_dir, len(materialized_files), db_conn)
        
        print(f"\nMaterialization complete!")
        print(f"Files materialized: {len(materialized_files)}")
        print(f"Database records: {inserted_count}")
        print(f"Failed files: {len(failed_files)}")
        
        return 0 if success else 1
        
    finally:
        db_conn.close()

if __name__ == "__main__":
    exit(main())