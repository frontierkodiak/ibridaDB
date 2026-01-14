#!/usr/bin/env python3
"""
Two-pass deduplication for anthophila dataset.

Pass A: ID-based matching (candidate IDs vs photos.photo_id)
Pass B: Hash-based matching against existing media + within-anthophila duplicates

Usage: 
  uv run python3 scripts/deduplicate_anthophila.py \
    --manifest anthophila_manifest.csv \
    --output anthophila_duplicates.csv \
    --db-connection "postgresql://postgres:ooglyboogly69@localhost/ibrida-v0"
"""

import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Set
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

ROW_ID_COL = "asset_row_uuid"


def pass_a_id_matching(manifest_df: pd.DataFrame, db_conn) -> Dict[str, Tuple[str, str]]:
    """
    Pass A: Match candidate IDs from filenames against photos.photo_id.

    Returns: dict mapping row_id to (dup_reason, matched_key)
    """
    duplicates: Dict[str, Tuple[str, str]] = {}

    id_series = manifest_df['id_core'].dropna()
    if id_series.empty:
        print("No numeric IDs found for Pass A matching")
        return duplicates

    candidate_ids = sorted({int(x) for x in id_series if str(x).strip() != ""})
    if not candidate_ids:
        print("No numeric IDs found for Pass A matching")
        return duplicates

    print(f"Pass A: Checking {len(candidate_ids)} candidate IDs against photos.photo_id...")

    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            "SELECT photo_id FROM photos WHERE photo_id = ANY(%s)",
            (candidate_ids,),
        )
        existing_photo_ids = {row['photo_id'] for row in cursor.fetchall()}

    print(f"Found {len(existing_photo_ids)} matching photo_ids in database")

    for _, row in manifest_df.iterrows():
        if pd.notna(row['id_core']):
            try:
                id_core = int(row['id_core'])
            except Exception:
                continue
            if id_core in existing_photo_ids:
                duplicates[row[ROW_ID_COL]] = ('photo_id', str(id_core))

    print(f"Pass A complete: Found {len(duplicates)} ID-based duplicates")
    return duplicates

def pass_b_hash_matching(
    manifest_df: pd.DataFrame,
    db_conn,
    existing_duplicates: Set[str]
) -> Dict[str, Tuple[str, str]]:
    """
    Pass B: Match anthophila hashes against existing media table.

    Only processes entries not already marked as duplicates from Pass A.
    Returns: dict mapping row_id to (dup_reason, matched_key)
    """
    duplicates: Dict[str, Tuple[str, str]] = {}

    remaining_df = manifest_df[~manifest_df[ROW_ID_COL].isin(existing_duplicates)]
    if remaining_df.empty:
        print("Pass B: No remaining entries to check after Pass A")
        return duplicates

    sha256_hashes = remaining_df[remaining_df['sha256'].notna()]['sha256'].unique().tolist()
    if not sha256_hashes:
        print("Pass B: No SHA256 hashes found")
        return duplicates

    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute("SELECT to_regclass('public.media') AS media_tbl;")
        media_tbl = cursor.fetchone().get("media_tbl")

    if not media_tbl:
        print("Pass B: media table not found; skipping media hash matching")
        return duplicates

    print(f"Pass B: Checking {len(sha256_hashes)} hashes against media.sha256_hex...")
    batch_size = 1000
    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        for i in tqdm(range(0, len(sha256_hashes), batch_size), desc="Checking media hashes"):
            batch_hashes = sha256_hashes[i:i + batch_size]
            cursor.execute(
                "SELECT sha256_hex FROM media WHERE sha256_hex = ANY(%s)",
                (batch_hashes,),
            )
            existing_hashes = {row["sha256_hex"] for row in cursor.fetchall()}

            if not existing_hashes:
                continue

            for _, entry in remaining_df[remaining_df['sha256'].isin(existing_hashes)].iterrows():
                duplicates[entry[ROW_ID_COL]] = ('media_sha256', entry['sha256'])

    print(f"Pass B complete: Found {len(duplicates)} media hash duplicates")
    return duplicates

def dedup_within_dataset(manifest_df: pd.DataFrame, existing_duplicates: Set[str]) -> Dict[str, Tuple[str, str]]:
    """Mark duplicates within anthophila by sha256 (keep largest file)."""
    duplicates: Dict[str, Tuple[str, str]] = {}

    working_df = manifest_df[~manifest_df[ROW_ID_COL].isin(existing_duplicates)].copy()
    if working_df.empty:
        return duplicates

    working_df = working_df[working_df['sha256'].notna() & (working_df['sha256'] != "")]
    if working_df.empty:
        return duplicates

    # Prefer larger files when keeping a representative
    working_df['file_bytes'] = pd.to_numeric(working_df['file_bytes'], errors='coerce').fillna(0)
    working_df = working_df.sort_values(by=['sha256', 'file_bytes'], ascending=[True, False])

    dup_mask = working_df.duplicated(subset=['sha256'], keep='first')
    dup_rows = working_df[dup_mask]

    for _, row in dup_rows.iterrows():
        duplicates[row[ROW_ID_COL]] = ('sha256_within', row['sha256'])

    return duplicates

def write_dedup_results(manifest_df: pd.DataFrame, 
                       all_duplicates: Dict[str, Tuple[str, str]], 
                       output_path: Path):
    """Write deduplication results to CSV."""
    
    # Add duplicate info to manifest
    manifest_df['dup_reason'] = manifest_df[ROW_ID_COL].map(
        lambda row_id: all_duplicates.get(row_id, ('', ''))[0]
    )
    manifest_df['matched_key'] = manifest_df[ROW_ID_COL].map(
        lambda row_id: all_duplicates.get(row_id, ('', ''))[1]
    )
    manifest_df['keep_flag'] = manifest_df[ROW_ID_COL].map(
        lambda row_id: row_id not in all_duplicates
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
    
    if ROW_ID_COL not in df.columns:
        print(f"Error: manifest missing required column {ROW_ID_COL}")
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
        
    # Pass A: ID-based matching (photo_id)
    pass_a_duplicates = pass_a_id_matching(manifest_df, db_conn)

    # Pass B: Hash-based matching against existing media
    pass_b_duplicates = pass_b_hash_matching(
        manifest_df, db_conn, set(pass_a_duplicates.keys())
    )

    # Pass C: Within-anthophila sha256 duplicates
    pass_c_duplicates = dedup_within_dataset(
        manifest_df, set(pass_a_duplicates.keys()) | set(pass_b_duplicates.keys())
    )

    all_duplicates = {**pass_a_duplicates, **pass_b_duplicates, **pass_c_duplicates}
        
        # Write results
        write_dedup_results(manifest_df, all_duplicates, output_path)
        
        print(f"\nDeduplication complete: {output_path}")
        return 0
        
    finally:
        db_conn.close()

if __name__ == "__main__":
    exit(main())
