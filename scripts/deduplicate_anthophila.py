#!/usr/bin/env python3
"""
Two-pass deduplication for anthophila dataset.

Pass A: ID-based matching (observation_id vs photos.observation_id)
Pass B: Hash-based matching (sha256/phash vs photos table)

Usage: 
  uv run python3 scripts/deduplicate_anthophila.py \
    --manifest anthophila_manifest.csv \
    --output anthophila_duplicates.csv \
    --db-connection "postgresql://postgres:ooglyboogly69@localhost/ibrida-v0"
"""

import argparse
import csv
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Set
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

def load_manifest(manifest_path: Path) -> pd.DataFrame:
    """Load anthophila manifest CSV."""
    print(f"Loading manifest from {manifest_path}")
    df = pd.read_csv(manifest_path)
    print(f"Loaded {len(df)} entries from manifest")
    return df

def pass_a_id_matching(manifest_df: pd.DataFrame, db_conn) -> Dict[str, Tuple[str, str]]:
    """
    Pass A: Match anthophila observation IDs against database.
    
    Returns: dict mapping asset_uuid to (dup_reason, matched_key)
    """
    duplicates = {}
    
    # Get unique observation IDs from manifest
    obs_ids = manifest_df[
        (manifest_df['id_type_guess'] == 'inat_observation_id') & 
        (manifest_df['id_core'].notna())
    ]['id_core'].unique()
    
    if len(obs_ids) == 0:
        print("No observation IDs found for Pass A matching")
        return duplicates
        
    print(f"Pass A: Checking {len(obs_ids)} unique observation IDs against database...")
    
    # Build query to check if these observation IDs exist
    obs_ids_str = ','.join(str(int(obs_id)) for obs_id in obs_ids)
    
    query = f"""
    SELECT DISTINCT observation_id 
    FROM observations 
    WHERE observation_id IN ({obs_ids_str})
    """
    
    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(query)
        existing_obs_ids = set(row['observation_id'] for row in cursor.fetchall())
    
    print(f"Found {len(existing_obs_ids)} existing observation IDs in database")
    
    # Mark anthophila entries that match existing observation IDs
    for _, row in manifest_df.iterrows():
        if (row['id_type_guess'] == 'inat_observation_id' and 
            pd.notna(row['id_core']) and 
            int(row['id_core']) in existing_obs_ids):
            
            duplicates[row['asset_uuid']] = ('obs_id', str(int(row['id_core'])))
    
    print(f"Pass A complete: Found {len(duplicates)} ID-based duplicates")
    return duplicates

def pass_b_hash_matching(manifest_df: pd.DataFrame, db_conn, 
                        existing_duplicates: Set[str]) -> Dict[str, Tuple[str, str]]:
    """
    Pass B: Match anthophila hashes against photos table.
    
    Only processes entries not already marked as duplicates from Pass A.
    Returns: dict mapping asset_uuid to (dup_reason, matched_key)
    """
    duplicates = {}
    
    # Filter to non-duplicate entries from Pass A
    remaining_df = manifest_df[~manifest_df['asset_uuid'].isin(existing_duplicates)]
    
    if len(remaining_df) == 0:
        print("Pass B: No remaining entries to check after Pass A")
        return duplicates
    
    print(f"Pass B: Checking {len(remaining_df)} remaining entries for hash collisions...")
    
    # Get SHA256 hashes to check
    sha256_hashes = remaining_df[remaining_df['sha256'].notna()]['sha256'].unique()
    
    if len(sha256_hashes) == 0:
        print("No SHA256 hashes found for Pass B matching")
        return duplicates
    
    # Check for SHA256 matches in photos table
    # Note: We need to be careful about the photos table schema
    # Let's first check what hash fields exist
    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute("""
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'photos' 
        AND column_name LIKE '%hash%'
        """)
        hash_columns = [row['column_name'] for row in cursor.fetchall()]
    
    print(f"Available hash columns in photos table: {hash_columns}")
    
    # If we have a sha256 column, check against it
    if 'sha256' in hash_columns or 'hash' in hash_columns:
        hash_col = 'sha256' if 'sha256' in hash_columns else 'hash'
        
        # Check hashes in batches to avoid query size limits
        batch_size = 1000
        for i in tqdm(range(0, len(sha256_hashes), batch_size), desc="Checking SHA256 batches"):
            batch_hashes = sha256_hashes[i:i+batch_size]
            hash_list = "','".join(batch_hashes)
            
            query = f"""
            SELECT {hash_col}, photo_id, observation_id
            FROM photos 
            WHERE {hash_col} IN ('{hash_list}')
            """
            
            cursor.execute(query)
            matching_photos = cursor.fetchall()
            
            for photo in matching_photos:
                # Find anthophila entries with this hash
                matching_entries = remaining_df[remaining_df['sha256'] == photo[hash_col]]
                for _, entry in matching_entries.iterrows():
                    duplicates[entry['asset_uuid']] = ('sha256', str(photo['photo_id']))
    
    print(f"Pass B complete: Found {len(duplicates)} additional hash-based duplicates")
    return duplicates

def write_dedup_results(manifest_df: pd.DataFrame, 
                       all_duplicates: Dict[str, Tuple[str, str]], 
                       output_path: Path):
    """Write deduplication results to CSV."""
    
    # Add duplicate info to manifest
    manifest_df['dup_reason'] = manifest_df['asset_uuid'].map(
        lambda uuid: all_duplicates.get(uuid, ('', ''))[0]
    )
    manifest_df['matched_key'] = manifest_df['asset_uuid'].map(
        lambda uuid: all_duplicates.get(uuid, ('', ''))[1]
    )
    manifest_df['keep_flag'] = manifest_df['asset_uuid'].map(
        lambda uuid: uuid not in all_duplicates
    )
    
    # Write to CSV
    print(f"Writing deduplication results to {output_path}")
    manifest_df.to_csv(output_path, index=False)
    
    # Print summary statistics
    total_entries = len(manifest_df)
    duplicates_count = len(all_duplicates)
    keep_count = total_entries - duplicates_count
    
    print(f"\n=== DEDUPLICATION SUMMARY ===")
    print(f"Total entries: {total_entries}")
    print(f"Duplicates found: {duplicates_count} ({duplicates_count/total_entries*100:.1f}%)")
    print(f"Entries to keep: {keep_count} ({keep_count/total_entries*100:.1f}%)")
    
    if duplicates_count > 0:
        dup_reasons = manifest_df['dup_reason'].value_counts()
        print("\nDuplication breakdown:")
        for reason, count in dup_reasons.items():
            if reason:  # Skip empty reasons
                print(f"  {reason}: {count}")

def main():
    parser = argparse.ArgumentParser(description="Deduplicate anthophila dataset")
    parser.add_argument(
        "--manifest", 
        required=True,
        help="Path to anthophila_manifest.csv"
    )
    parser.add_argument(
        "--output",
        required=True, 
        help="Path for output CSV with deduplication results"
    )
    parser.add_argument(
        "--db-connection",
        default="postgresql://postgres:ooglyboogly69@localhost/ibrida-v0",
        help="PostgreSQL connection string"
    )
    
    args = parser.parse_args()
    
    manifest_path = Path(args.manifest)
    output_path = Path(args.output)
    
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
        # Load manifest
        manifest_df = load_manifest(manifest_path)
        
        # Pass A: ID-based matching
        pass_a_duplicates = pass_a_id_matching(manifest_df, db_conn)
        
        # Pass B: Hash-based matching
        pass_b_duplicates = pass_b_hash_matching(
            manifest_df, db_conn, set(pass_a_duplicates.keys())
        )
        
        # Combine results
        all_duplicates = {**pass_a_duplicates, **pass_b_duplicates}
        
        # Write results
        write_dedup_results(manifest_df, all_duplicates, output_path)
        
        print(f"\nDeduplication complete: {output_path}")
        return 0
        
    finally:
        db_conn.close()

if __name__ == "__main__":
    exit(main())