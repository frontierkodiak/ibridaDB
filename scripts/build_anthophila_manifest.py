#!/usr/bin/env python3
"""
Build anthophila_manifest.csv with file metadata for deduplication.

Scans /datasets/dataZoo/anthophila/ tree and computes:
- SHA-256 hash for exact duplicate detection
- Image dimensions (width, height)
- File size and basic metadata
- Extract numeric IDs from filename (if present)
- Deterministic IDs (asset_uuid from sha256; asset_row_uuid from path)
- Flat filename keyed by sha256
"""

import re
import csv
import hashlib
import uuid
from pathlib import Path
import argparse
from typing import Dict, List, Optional, Tuple
from PIL import Image
import imagehash

def extract_id_from_filename(filename: str) -> Tuple[Optional[int], Optional[int], str]:
    """
    Extract numeric ID(s) from anthophila filename.

    Expected pattern: Genus_species_<id>_<idx>.jpg
    Returns: (id_core, id_suffix, id_type_guess)
    """
    pattern = re.compile(
        r'^(?P<genus>[A-Z][a-z]+)_(?P<species>[A-Za-z_]+)_(?P<id_core>\d+)(?:_(?P<id_suffix>\d+))?\.jpg$'
    )
    match = pattern.match(filename)

    if match:
        id_core = int(match.group("id_core"))
        id_suffix = match.group("id_suffix")
        return id_core, int(id_suffix) if id_suffix else None, "pattern_id"

    # Fallback: try to extract any numeric sequence
    numbers = re.findall(r"\d+", filename)
    if numbers:
        longest_num = max(numbers, key=len)
        if len(longest_num) >= 6:
            return int(longest_num), None, "extracted_number"

    return None, None, "no_id_found"

def compute_sha256(file_path: Path) -> str:
    """Compute SHA-256 hash of file."""
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)
    return sha256_hash.hexdigest()

def get_image_dimensions(file_path: Path) -> Tuple[Optional[int], Optional[int]]:
    """Get image width and height using PIL."""
    try:
        with Image.open(file_path) as img:
            return img.width, img.height
    except Exception as e:
        print(f"Warning: Could not get dimensions for {file_path}: {e}")
        return None, None

def compute_phash(file_path: Path) -> str:
    """Compute perceptual hash using imagehash."""
    try:
        with Image.open(file_path) as img:
            phash = imagehash.phash(img)
            return str(phash)
    except Exception as e:
        print(f"Warning: Could not compute pHash for {file_path}: {e}")
        return ""

def normalize_scientific_name(directory_name: str) -> str:
    """
    Normalize directory name to scientific name.
    e.g., 'Osmia_chalybea' -> 'Osmia chalybea'
    """
    return directory_name.replace('_', ' ')

def guess_rank(scientific_name: str) -> str:
    """Guess rank from token count in scientific name."""
    tokens = [t for t in scientific_name.split(" ") if t]
    if len(tokens) == 1:
        return "genus"
    if len(tokens) == 2:
        return "species"
    if len(tokens) >= 3:
        return "subspecies"
    return "unknown"

def generate_flat_name(sha256_hex: str, extension: str) -> str:
    """
    Generate flattened filename for anthophila_flat/ directory.
    Format: <sha256_hex>.<ext>
    """
    ext = extension.lower()
    if not ext.startswith("."):
        ext = f".{ext}"
    return f"{sha256_hex}{ext}"

ASSET_UUID_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "polli/anthophila/asset")
ASSET_ROW_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "polli/anthophila/asset-row")

def scan_anthophila_directory(anthophila_dir: Path) -> List[Dict]:
    """Scan anthophila directory and build manifest data."""
    
    manifest_data = []
    processed_count = 0
    error_count = 0
    
    print(f"Scanning {anthophila_dir}")
    
    # Walk through all subdirectories
    for species_dir in anthophila_dir.iterdir():
        if not species_dir.is_dir():
            continue
            
        if species_dir.name == "GBIF_occurences":
            print(f"Skipping metadata directory: {species_dir.name}")
            continue
            
        print(f"Processing {species_dir.name}...")
        
        # Process all JPG files in species directory
        jpg_files = list(species_dir.glob("*.jpg"))
        
        for jpg_file in jpg_files:
            try:
                # Extract ID(s) from filename
                id_core, id_suffix, id_type = extract_id_from_filename(jpg_file.name)

                # Get scientific name from directory
                scientific_name_raw = species_dir.name
                scientific_name = normalize_scientific_name(species_dir.name)
                rank_guess = guess_rank(scientific_name)

                # Compute file hash (used for deterministic IDs + filenames)
                sha256 = compute_sha256(jpg_file)

                # Deterministic asset identifiers
                asset_uuid = str(uuid.uuid5(ASSET_UUID_NAMESPACE, sha256))
                asset_row_uuid = str(uuid.uuid5(ASSET_ROW_NAMESPACE, str(jpg_file)))

                # Get image dimensions and pHash
                width, height = get_image_dimensions(jpg_file)
                phash = compute_phash(jpg_file)

                # Generate flat filename (sha256-based)
                flat_name = generate_flat_name(sha256, jpg_file.suffix)
                
                # File stats
                file_stats = jpg_file.stat()
                file_bytes = file_stats.st_size
                
                manifest_entry = {
                    'asset_uuid': asset_uuid,
                    'asset_row_uuid': asset_row_uuid,
                    'original_path': str(jpg_file),
                    'original_filename': jpg_file.name,
                    'flat_name': flat_name,
                    'scientific_name_raw': scientific_name_raw,
                    'scientific_name_norm': scientific_name,
                    'rank_guess': rank_guess,
                    'id_core': id_core if id_core is not None else '',
                    'id_suffix': id_suffix if id_suffix is not None else '',
                    'id_type_guess': id_type,
                    'width': width if width else '',
                    'height': height if height else '',
                    'sha256': sha256,
                    'phash': phash,
                    'source_tag': 'expert-taxonomist',
                    'license_guess': 'unknown',
                    'file_bytes': file_bytes,
                    'keep_flag': True  # Will be updated by deduplication step
                }
                
                manifest_data.append(manifest_entry)
                processed_count += 1
                
                if processed_count % 1000 == 0:
                    print(f"  Processed {processed_count} files...")
                    
            except Exception as e:
                print(f"Error processing {jpg_file}: {e}")
                error_count += 1
    
    print(f"Scan complete: {processed_count} files processed, {error_count} errors")
    return manifest_data

def write_manifest_csv(manifest_data: List[Dict], output_path: Path):
    """Write manifest data to CSV file."""
    
    fieldnames = [
        'asset_uuid', 'asset_row_uuid', 'original_path', 'original_filename', 'flat_name',
        'scientific_name_raw', 'scientific_name_norm', 'rank_guess',
        'id_core', 'id_suffix', 'id_type_guess',
        'width', 'height', 'sha256', 'phash',
        'source_tag', 'license_guess', 'file_bytes', 'keep_flag'
    ]
    
    print(f"Writing manifest to {output_path}")
    
    with open(output_path, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(manifest_data)
    
    print(f"Manifest written: {len(manifest_data)} entries")

def print_summary_stats(manifest_data: List[Dict]):
    """Print summary statistics."""
    
    total_files = len(manifest_data)
    
    # Count by ID type
    id_types = {}
    for entry in manifest_data:
        id_type = entry['id_type_guess']
        id_types[id_type] = id_types.get(id_type, 0) + 1
    
    # Count by species
    species_count = len(set(entry['scientific_name_norm'] for entry in manifest_data))
    
    # File sizes
    file_sizes = [entry['file_bytes'] for entry in manifest_data]
    total_bytes = sum(file_sizes)
    avg_bytes = total_bytes / len(file_sizes) if file_sizes else 0
    
    print(f"\n=== SUMMARY STATISTICS ===")
    print(f"Total files: {total_files}")
    print(f"Unique species: {species_count}")
    print(f"Total size: {total_bytes / (1024**3):.2f} GB")
    print(f"Average file size: {avg_bytes / (1024**2):.2f} MB")
    
    print(f"\nID extraction results:")
    for id_type, count in sorted(id_types.items()):
        percentage = (count / total_files) * 100
        print(f"  {id_type}: {count} ({percentage:.1f}%)")

def main():
    parser = argparse.ArgumentParser(description="Build anthophila manifest")
    parser.add_argument(
        "--anthophila-dir",
        default="/datasets/dataZoo/anthophila",
        help="Path to anthophila directory"
    )
    parser.add_argument(
        "--output",
        default="/home/caleb/repo/ibridaDB/anthophila_manifest.csv",
        help="Output CSV path"
    )
    
    args = parser.parse_args()
    
    anthophila_dir = Path(args.anthophila_dir)
    output_path = Path(args.output)
    
    if not anthophila_dir.exists():
        print(f"Error: Anthophila directory not found: {anthophila_dir}")
        return 1
    
    # Scan directory and build manifest
    manifest_data = scan_anthophila_directory(anthophila_dir)
    
    if not manifest_data:
        print("No files found to process")
        return 1
    
    # Write CSV
    write_manifest_csv(manifest_data, output_path)
    
    # Print summary
    print_summary_stats(manifest_data)
    
    print(f"\nManifest complete: {output_path}")
    return 0

if __name__ == "__main__":
    exit(main())
