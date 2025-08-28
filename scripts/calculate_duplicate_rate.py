#!/usr/bin/env python3
"""
Calculate duplicate rate using statistical sampling.
"""

import subprocess
import random

def get_unique_anthophila_ids():
    """Get all unique observation IDs from analysis file."""
    ids = set()
    with open("/home/caleb/repo/ibridaDB/anthophila_analysis.txt", "r") as f:
        next(f)  # Skip header
        for line in f:
            parts = line.strip().split(',')
            if parts and parts[0].isdigit():
                ids.add(int(parts[0]))
    
    return list(ids)

def check_ids_in_database(ids_list):
    """Check which IDs exist in the database."""
    
    ids_str = ",".join(map(str, ids_list))
    
    cmd = [
        "docker", "exec", "ibridaDB", "psql", "-U", "postgres", "-d", "ibrida-v0-r1", 
        "-t", "-c", f"SELECT photo_id FROM photos WHERE photo_id IN ({ids_str});"
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        found_ids = []
        for line in result.stdout.strip().split('\n'):
            line = line.strip()
            if line and line.isdigit():
                found_ids.append(int(line))
        return found_ids
    else:
        print(f"Error: {result.stderr}")
        return []

def main():
    """Calculate duplicate rate."""
    
    print("=== Anthophila Duplicate Rate Calculation ===\n")
    
    # Get all unique observation IDs
    all_ids = get_unique_anthophila_ids()
    print(f"Total unique observation IDs: {len(all_ids)}")
    
    # Take a representative sample
    sample_size = min(1000, len(all_ids))
    sample_ids = random.sample(all_ids, sample_size)
    
    print(f"Analyzing sample of {sample_size} IDs...")
    
    # Check sample in smaller batches to avoid command line limits
    batch_size = 20
    all_found_ids = []
    
    for i in range(0, len(sample_ids), batch_size):
        batch = sample_ids[i:i+batch_size]
        found_ids = check_ids_in_database(batch)
        all_found_ids.extend(found_ids)
        
        progress = ((i + batch_size) / len(sample_ids)) * 100
        print(f"Progress: {progress:5.1f}%")
    
    # Calculate statistics
    duplicate_count = len(all_found_ids)
    duplicate_rate = (duplicate_count / sample_size) * 100
    new_count = sample_size - duplicate_count
    new_rate = (new_count / sample_size) * 100
    
    # Estimate for full dataset
    estimated_total_duplicates = int((duplicate_rate / 100) * len(all_ids))
    estimated_new_observations = len(all_ids) - estimated_total_duplicates
    
    print(f"\n=== SAMPLE RESULTS ===")
    print(f"Sample size: {sample_size}")
    print(f"Found in database: {duplicate_count}")
    print(f"Duplicate rate: {duplicate_rate:.1f}%")
    print(f"New observations in sample: {new_count}")
    print(f"New rate: {new_rate:.1f}%")
    
    print(f"\n=== ESTIMATED FULL DATASET ===")
    print(f"Total unique observation IDs: {len(all_ids)}")
    print(f"Estimated duplicates: {estimated_total_duplicates}")
    print(f"Estimated new observations: {estimated_new_observations}")
    print(f"Estimated duplicate rate: {duplicate_rate:.1f}%")
    print(f"Estimated new rate: {new_rate:.1f}%")
    
    # Show some examples
    print(f"\n=== SAMPLE DUPLICATES (found in database) ===")
    for obs_id in sorted(all_found_ids)[:5]:
        print(f"  {obs_id} -> https://www.inaturalist.org/observations/{obs_id}")
    
    print(f"\n=== SAMPLE NEW IDs (not in database) ===")
    new_ids = [obs_id for obs_id in sample_ids if obs_id not in all_found_ids]
    for obs_id in sorted(new_ids)[:5]:
        print(f"  {obs_id} -> https://www.inaturalist.org/observations/{obs_id}")
    
    # Save results
    with open("/home/caleb/repo/ibridaDB/anthophila_duplicate_estimate.txt", "w") as f:
        f.write("Anthophila Duplicate Analysis - Statistical Estimate\n")
        f.write("===================================================\n\n")
        f.write(f"Sample Analysis:\n")
        f.write(f"Sample size: {sample_size}\n")
        f.write(f"Found in database: {duplicate_count}\n")
        f.write(f"Duplicate rate: {duplicate_rate:.1f}%\n")
        f.write(f"New rate: {new_rate:.1f}%\n\n")
        f.write(f"Full Dataset Estimates:\n")
        f.write(f"Total unique observation IDs: {len(all_ids)}\n")
        f.write(f"Estimated duplicates: {estimated_total_duplicates}\n")
        f.write(f"Estimated new observations: {estimated_new_observations}\n")
        f.write(f"Estimated duplicate rate: {duplicate_rate:.1f}%\n")
        f.write(f"Estimated new rate: {new_rate:.1f}%\n")
    
    print(f"\nResults saved to: /home/caleb/repo/ibridaDB/anthophila_duplicate_estimate.txt")
    
    # Decision recommendation
    print(f"\n=== RECOMMENDATION ===")
    if duplicate_rate > 90:
        print("❌ HIGH DUPLICATE RATE (>90%) - Integration likely NOT worthwhile")
    elif duplicate_rate > 70:
        print("⚠️  MODERATE DUPLICATE RATE (70-90%) - Analyze taxonomic value of new data")
    else:
        print("✅ LOW DUPLICATE RATE (<70%) - Integration likely worthwhile")

if __name__ == "__main__":
    main()