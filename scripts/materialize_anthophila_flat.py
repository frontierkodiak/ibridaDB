#!/usr/bin/env python3
"""
Materialize anthophila_flat/ directory and insert kept items into media,
observations, and observation_media tables.

Creates hardlinks/copies of kept anthophila images into a flat directory structure
and inserts metadata into media + observation tables for database integration.

Usage:
  uv run python3 scripts/materialize_anthophila_flat.py \
    --manifest anthophila_duplicates.csv \
    --flat-dir /datasets/ibrida-data/anthophila_flat \
    --db-connection "postgresql://postgres@localhost/ibrida-v0"
"""

import argparse
import json
import os
import shutil
import uuid
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor, execute_values
from tqdm import tqdm

OBSERVATION_UUID_NAMESPACE = uuid.UUID("6f1d9c3a-84e5-4c6a-9a53-46b773a1d57c")

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

    if 'keep_flag' not in df.columns:
        print("Error: keep_flag column missing from manifest")
        return pd.DataFrame()

    keep_series = df['keep_flag'].astype(str).str.lower().isin(['true', '1', 'yes'])
    kept_df = df[keep_series].copy()

    if 'taxon_id' not in kept_df.columns:
        print("Error: taxon_id column missing; run resolve_anthophila_taxa.py first")
        return pd.DataFrame()

    print(f"Found {len(kept_df)} kept items out of {len(df)} total")
    
    return kept_df

def create_flat_directory(flat_dir: Path):
    """Create the flat directory structure."""
    flat_dir.mkdir(parents=True, exist_ok=True)
    print(f"Created/verified flat directory: {flat_dir}")

def get_table_columns(conn, table_name: str) -> List[str]:
    with conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s
            """,
            (table_name,),
        )
        return [row["column_name"] for row in cursor.fetchall()]

def get_column_type(conn, table_name: str, column_name: str) -> str:
    with conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT data_type
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s AND column_name = %s
            """,
            (table_name, column_name),
        )
        row = cursor.fetchone()
        return row["data_type"] if row else ""

def add_observation_keys(kept_df: pd.DataFrame) -> pd.DataFrame:
    """Assign deterministic observation_uuid based on name+id_core or asset_uuid."""
    obs_keys = []
    obs_uuids = []

    for _, row in kept_df.iterrows():
        id_core = row.get("id_core", "")
        scientific_name = str(row.get("scientific_name_norm", "")).strip()
        if not scientific_name:
            raise ValueError("scientific_name_norm missing or empty; cannot build observation_key safely")
        obs_key = None
        if pd.notna(id_core) and str(id_core).strip() != "":
            try:
                obs_key = f"name:{scientific_name}|id:{int(float(id_core))}"
            except Exception:
                obs_key = f"asset:{row['asset_uuid']}"
        else:
            obs_key = f"asset:{row['asset_uuid']}"

        obs_uuid = str(uuid.uuid5(OBSERVATION_UUID_NAMESPACE, obs_key))
        obs_keys.append(obs_key)
        obs_uuids.append(obs_uuid)

    kept_df = kept_df.copy()
    kept_df["observation_key"] = obs_keys
    kept_df["observation_uuid"] = obs_uuids

    # Sanity check: prevent cross-taxon merges
    if "scientific_name_norm" in kept_df.columns:
        collisions = (
            kept_df.groupby("observation_key")["scientific_name_norm"]
            .nunique()
            .reset_index()
        )
        bad = collisions[collisions["scientific_name_norm"] > 1]
        if not bad.empty:
            sample_keys = bad["observation_key"].head(5).tolist()
            sample_rows = kept_df[kept_df["observation_key"].isin(sample_keys)][
                ["observation_key", "scientific_name_norm"]
            ].drop_duplicates()
            raise ValueError(
                "Observation key collision across taxa detected; aborting.\n"
                f"Sample:\n{sample_rows.to_string(index=False)}"
            )

    return kept_df

def safe_int(value):
    try:
        if value is None:
            return None
        if isinstance(value, str) and value.strip() == "":
            return None
        return int(float(value))
    except Exception:
        return None

def parse_phash_64(value):
    """Parse a hex pHash string into signed int64 for PostgreSQL BIGINT storage."""
    if value is None:
        return None

    text = str(value).strip().lower()
    if not text:
        return None
    if text.startswith("0x"):
        text = text[2:]
    if not text:
        return None

    try:
        raw = int(text, 16)
    except ValueError:
        return None

    # pHash should be 64-bit; ignore malformed wider values.
    if raw >= (1 << 64):
        return None

    # PostgreSQL BIGINT is signed.
    if raw >= (1 << 63):
        raw -= (1 << 64)
    return raw

def insert_observations(
    kept_df: pd.DataFrame,
    db_conn,
    origin: str,
    version: str,
    release: str,
) -> int:
    """Insert observations grouped by observation_key."""
    if kept_df.empty:
        return 0

    obs_columns = get_table_columns(db_conn, "observations")
    required_cols = {
        "observation_uuid",
        "observer_id",
        "latitude",
        "longitude",
        "positional_accuracy",
        "taxon_id",
        "quality_grade",
        "observed_on",
        "anomaly_score",
    }
    available_cols = [c for c in obs_columns if c in required_cols or c in {"origin", "version", "release"}]

    if "observation_uuid" not in obs_columns or "taxon_id" not in obs_columns:
        print("Error: observations table missing required columns (observation_uuid, taxon_id)")
        return 0

    records = []
    missing_taxon_keys = []
    grouped = kept_df.groupby("observation_key")
    for obs_key, group in grouped:
        obs_uuid = group["observation_uuid"].iloc[0]
        taxon_ids = pd.to_numeric(group["taxon_id"], errors="coerce").dropna().astype(int)
        if taxon_ids.empty:
            missing_taxon_keys.append(str(obs_key))
            continue

        if taxon_ids.nunique() > 1:
            print(f"Warning: Multiple taxon_ids for {obs_key}; using most common")

        taxon_id = int(taxon_ids.mode().iloc[0])

        record = {
            "observation_uuid": obs_uuid,
            "observer_id": None,
            "latitude": None,
            "longitude": None,
            "positional_accuracy": None,
            "taxon_id": taxon_id,
            "quality_grade": "research",
            "observed_on": None,
            "anomaly_score": None,
        }
        if "origin" in obs_columns:
            record["origin"] = origin
        if "version" in obs_columns:
            record["version"] = version
        if "release" in obs_columns:
            record["release"] = release

        records.append({col: record.get(col) for col in available_cols})

    if missing_taxon_keys:
        sample = ", ".join(missing_taxon_keys[:10])
        print(
            f"Warning: missing taxon_id for {len(missing_taxon_keys)} observations; skipped. "
            f"Sample keys: {sample}"
        )

    if not records:
        return 0

    # Filter out observations that already exist
    obs_uuids = [r["observation_uuid"] for r in records]
    obs_uuid_type = get_column_type(db_conn, "observations", "observation_uuid")
    any_param = "%s::uuid[]" if obs_uuid_type == "uuid" else "%s"
    existing = set()
    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            f"SELECT observation_uuid FROM observations WHERE observation_uuid = ANY({any_param})",
            (obs_uuids,),
        )
        existing = {str(row["observation_uuid"]) for row in cursor.fetchall() if row["observation_uuid"] is not None}

    records = [r for r in records if str(r["observation_uuid"]) not in existing]
    if not records:
        print("Observations already present; skipping insert")
        return 0

    with db_conn.cursor() as cursor:
        columns = list(records[0].keys())
        values = [[record[col] for col in columns] for record in records]
        execute_values(
            cursor,
            f"INSERT INTO observations ({', '.join(columns)}) VALUES %s",
            values,
        )
    db_conn.commit()
    print(f"Inserted {len(records)} observations")
    return len(records)

def fetch_media_id_map(db_conn, sha256_list: List[str]) -> Dict[str, int]:
    if not sha256_list:
        return {}
    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            "SELECT media_id, sha256_hex FROM media WHERE sha256_hex = ANY(%s)",
            (sha256_list,),
        )
        return {row["sha256_hex"]: row["media_id"] for row in cursor.fetchall()}

def insert_observation_media(
    kept_df: pd.DataFrame,
    media_id_map: Dict[str, int],
    db_conn,
    role: str = "primary",
) -> int:
    if kept_df.empty:
        return 0

    if "observation_uuid" not in kept_df.columns:
        print("Error: observation_uuid missing from manifest")
        return 0

    obs_media_table = None
    with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute("SELECT to_regclass('public.observation_media') AS tbl")
        obs_media_table = cursor.fetchone().get("tbl")

    if not obs_media_table:
        print("Warning: observation_media table not found; skipping observation_media insert")
        return 0

    obs_uuid_type = get_column_type(db_conn, "observations", "observation_uuid")
    any_param = "%s::uuid[]" if obs_uuid_type == "uuid" else "%s"
    candidate_obs_uuids = sorted({str(value) for value in kept_df["observation_uuid"].dropna().tolist()})
    existing_obs_uuids = set()
    if candidate_obs_uuids:
        with db_conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(
                f"SELECT observation_uuid FROM observations WHERE observation_uuid = ANY({any_param})",
                (candidate_obs_uuids,),
            )
            existing_obs_uuids = {
                str(row["observation_uuid"])
                for row in cursor.fetchall()
                if row.get("observation_uuid") is not None
            }

    records = []
    seen = set()
    skipped_missing_observation = 0
    for _, row in kept_df.iterrows():
        sha256 = row.get("sha256", "")
        media_id = media_id_map.get(sha256)
        if not media_id:
            continue
        obs_uuid = str(row["observation_uuid"])
        if obs_uuid not in existing_obs_uuids:
            skipped_missing_observation += 1
            continue
        key = (obs_uuid, media_id)
        if key in seen:
            continue
        seen.add(key)
        records.append((obs_uuid, media_id, role))

    if not records:
        return 0

    with db_conn.cursor() as cursor:
        execute_values(
            cursor,
            "INSERT INTO observation_media (observation_uuid, media_id, role) VALUES %s ON CONFLICT DO NOTHING",
            records,
        )
    db_conn.commit()
    if skipped_missing_observation:
        print(
            f"Skipped {skipped_missing_observation} observation_media candidate rows "
            "because observation_uuid was not present in observations"
        )
    print(f"Inserted {len(records)} observation_media rows")
    return len(records)

def create_sidecar_metadata(
    row: pd.Series,
    observation_uuid: str,
    obs_key: str,
    remote_key: str = "",
    remote_uri: str = "",
) -> Dict:
    """Create sidecar JSONB metadata for media table."""
    taxon_id = None
    id_core = None
    id_suffix = None

    try:
        if pd.notna(row.get('taxon_id')):
            taxon_id = int(row['taxon_id'])
    except Exception:
        taxon_id = None

    try:
        if pd.notna(row.get('id_core')):
            id_core = int(float(row['id_core']))
    except Exception:
        id_core = None

    try:
        if pd.notna(row.get('id_suffix')):
            id_suffix = int(float(row['id_suffix']))
    except Exception:
        id_suffix = None

    sidecar = {
        "original_path": row['original_path'],
        "original_filename": row.get('original_filename', ''),
        "source_tag": row.get('source_tag', ''),
        "sha256": row.get('sha256', ''),
        "phash": row.get('phash', ''),
        "scientific_name_norm": row.get('scientific_name_norm', ''),
        "taxon_id": taxon_id,
        "width": safe_int(row.get('width')),
        "height": safe_int(row.get('height')),
        "file_bytes": safe_int(row.get('file_bytes')),
        "id_core": id_core,
        "id_suffix": id_suffix,
        "id_type_guess": row.get('id_type_guess', ''),
        "observation_uuid": observation_uuid,
        "observation_key": obs_key,
    }
    if remote_key:
        sidecar["remote_key"] = remote_key
    if remote_uri:
        sidecar["remote_uri"] = remote_uri
    return sidecar

def materialize_files(kept_df: pd.DataFrame, flat_dir: Path, use_hardlinks: bool = True):
    """Copy or hardlink files to flat directory."""
    
    materialized_files = []
    failed_files = []
    created_count = 0
    existing_count = 0
    
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
                existing_count += 1
                materialized_files.append({
                    'asset_uuid': row['asset_uuid'],
                    'original_path': str(original_path),
                    'flat_path': str(target_path),
                    'flat_name': flat_name
                })
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
            created_count += 1
            
        except Exception as e:
            print(f"Error materializing {original_path}: {e}")
            failed_files.append(row['asset_uuid'])
    
    print(
        "Materialization complete: "
        f"{len(materialized_files)} ready "
        f"({created_count} created, {existing_count} already present), "
        f"{len(failed_files)} failed"
    )
    return materialized_files, failed_files

def insert_media_records(
    kept_df: pd.DataFrame,
    materialized_files: List[Dict],
    flat_dir: Path,
    db_conn,
    dataset: str,
    release: str,
    remote_key_prefix: str = "",
    remote_uri_prefix: str = "",
):
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
        
        remote_key = ""
        remote_uri = ""
        flat_name = mat_file["flat_name"]
        if remote_key_prefix:
            remote_key = f"{remote_key_prefix.rstrip('/')}/{flat_name}"
        if remote_uri_prefix:
            base = remote_uri_prefix.rstrip("/")
            key_part = remote_key if remote_key else flat_name
            remote_uri = f"{base}/{key_part}"

        # Create sidecar metadata
        sidecar = create_sidecar_metadata(
            row,
            row["observation_uuid"],
            row["observation_key"],
            remote_key=remote_key,
            remote_uri=remote_uri,
        )

        phash_64 = parse_phash_64(row.get("phash"))
        
        media_record = {
            'dataset': dataset,
            'release': release,
            'source_tag': row.get('source_tag', ''),
            'uri': file_uri,
            'license': row.get('license_guess', 'unknown'),
            'sha256_hex': row.get('sha256', ''),
            'phash_64': phash_64,
            'width_px': safe_int(row.get('width')),
            'height_px': safe_int(row.get('height')),
            'mime_type': 'image/jpeg',
            'file_bytes': safe_int(row.get('file_bytes')),
            'sidecar': json.dumps(sidecar),
        }
        
        insert_data.append(media_record)
    
    if not insert_data:
        print("No records to insert")
        return 0
    
    # Batch insert into media table
    with db_conn.cursor() as cursor:
        insert_query = """
        INSERT INTO media (
            dataset, release, source_tag, uri, license,
            sha256_hex, phash_64, width_px, height_px, mime_type, file_bytes, sidecar
        )
        VALUES (
            %(dataset)s, %(release)s, %(source_tag)s, %(uri)s, %(license)s,
            %(sha256_hex)s, %(phash_64)s, %(width_px)s, %(height_px)s, %(mime_type)s, %(file_bytes)s, %(sidecar)s
        )
        ON CONFLICT (sha256_hex) DO UPDATE SET
            dataset = EXCLUDED.dataset,
            release = EXCLUDED.release,
            source_tag = EXCLUDED.source_tag,
            uri = EXCLUDED.uri,
            license = EXCLUDED.license,
            phash_64 = EXCLUDED.phash_64,
            width_px = EXCLUDED.width_px,
            height_px = EXCLUDED.height_px,
            mime_type = EXCLUDED.mime_type,
            file_bytes = EXCLUDED.file_bytes,
            sidecar = EXCLUDED.sidecar
        """
        
        cursor.executemany(insert_query, insert_data)
        db_conn.commit()
        
        inserted_count = cursor.rowcount
    
    print(f"Inserted/updated {inserted_count} media records")
    return inserted_count

def verify_results(flat_dir: Path, expected_count: int, db_conn, dataset: str, release: str):
    """Verify materialization and database insertion results."""
    
    # Check flat directory
    actual_files = list(flat_dir.glob("*.jpg"))
    print(f"\nVERIFICATION:")
    print(f"Expected files: {expected_count}")
    print(f"Actual files in {flat_dir}: {len(actual_files)}")
    
    # Check media table
    with db_conn.cursor() as cursor:
        cursor.execute(
            "SELECT COUNT(*) FROM media WHERE dataset = %s AND release = %s",
            (dataset, release),
        )
        db_count = cursor.fetchone()[0]
        
    print(f"Media table records ({dataset} {release}): {db_count}")
    
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
        default=os.getenv("IBRIDADB_DSN", "postgresql://postgres@localhost/ibrida-v0"),
        help="PostgreSQL connection string (prefer env/.pgpass over inline passwords)"
    )
    parser.add_argument(
        "--dataset",
        default="anthophila",
        help="Dataset label for media table"
    )
    parser.add_argument(
        "--origin",
        default="anthophila",
        help="Origin tag for observations"
    )
    parser.add_argument(
        "--version",
        default="v0",
        help="Version tag for observations"
    )
    parser.add_argument(
        "--release",
        default="r2",
        help="Release tag for observations/media"
    )
    parser.add_argument(
        "--remote-key-prefix",
        default="",
        help="Remote object key prefix (e.g., datasets/v0/r2/media/anthophila/flat)"
    )
    parser.add_argument(
        "--remote-uri-prefix",
        default="",
        help="Remote URI prefix (e.g., b2://ibrida-1)"
    )
    parser.add_argument(
        "--role",
        default="primary",
        help="observation_media.role value"
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

        # Assign deterministic observation UUIDs
        kept_df = add_observation_keys(kept_df)
        
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
        
        materialized_ids = {f["asset_uuid"] for f in materialized_files}
        kept_df = kept_df[kept_df["asset_uuid"].isin(materialized_ids)].copy()

        # Insert observations first (for FK on observation_media)
        obs_inserted = insert_observations(
            kept_df,
            db_conn,
            origin=args.origin,
            version=args.version,
            release=args.release,
        )

        # Insert media records
        inserted_count = insert_media_records(
            kept_df,
            materialized_files,
            flat_dir,
            db_conn,
            dataset=args.dataset,
            release=args.release,
            remote_key_prefix=args.remote_key_prefix,
            remote_uri_prefix=args.remote_uri_prefix,
        )

        media_id_map = fetch_media_id_map(db_conn, kept_df["sha256"].dropna().tolist())
        obs_media_inserted = insert_observation_media(
            kept_df,
            media_id_map,
            db_conn,
            role=args.role,
        )
        
        # Verify results
        success = verify_results(flat_dir, len(materialized_files), db_conn, args.dataset, args.release)
        
        print(f"\nMaterialization complete!")
        print(f"Files materialized: {len(materialized_files)}")
        print(f"Observation records inserted: {obs_inserted}")
        print(f"Media records inserted: {inserted_count}")
        print(f"Observation_media records inserted: {obs_media_inserted}")
        print(f"Failed files: {len(failed_files)}")
        
        return 0 if success else 1
        
    finally:
        db_conn.close()

if __name__ == "__main__":
    exit(main())
