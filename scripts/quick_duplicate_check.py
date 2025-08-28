#!/usr/bin/env python3
"""
Quick duplicate check using batch SQL queries.
"""

import subprocess
import random

def get_anthophila_ids():
    """Get all observation IDs from analysis file."""
    ids = []
    with open("/home/caleb/repo/ibridaDB/anthophila_analysis.txt", "r") as f:
        next(f)  # Skip header
        for line in f:
            parts = line.strip().split(',')
            if parts and parts[0].isdigit():
                ids.append(int(parts[0]))
    
    return list(set(ids))  # Remove duplicates

def check_batch_duplicates(ids_batch):
    """Check a batch of IDs against the database."""
    
    ids_str = ",".join(map(str, ids_batch))
    
    cmd = [
        "docker", "exec", "ibridaDB", "psql", "-U", "postgres", "-d", "ibrida-v0-r1", 
        "-t", "-c", f"SELECT COUNT(*) FROM photos WHERE photo_id IN ({ids_str});"
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode == 0:
        count = int(result.stdout.strip())
        return count
    else:
        print(f"Error checking batch: {result.stderr}")
        return 0

def main():
    """Run quick duplicate analysis."""
    
    print("=== Quick Anthophila Duplicate Check ===\n")
    
    # Get all observation IDs
    all_ids = get_anthophila_ids()
    print(f"Total unique observation IDs: {len(all_ids)}")
    
    # Take representative samples
    sample_sizes = [100, 500, 1000, 2000]
    
    for sample_size in sample_sizes:
        if sample_size > len(all_ids):
            sample_size = len(all_ids)
            
        sample_ids = random.sample(all_ids, sample_size)
        
        # Check in batches of 50 to avoid command line limits
        batch_size = 50
        total_duplicates = 0
        
        for i in range(0, len(sample_ids), batch_size):
            batch = sample_ids[i:i+batch_size]
            duplicates = check_batch_duplicates(batch)
            total_duplicates += duplicates
        
        duplicate_percentage = (total_duplicates / sample_size) * 100
        print(f"Sample size {sample_size:4d}: {total_duplicates:4d}/{sample_size:4d} duplicates ({duplicate_percentage:5.1f}%)")
        
        if sample_size == len(all_ids):
            break
    
    # Final comprehensive check if samples suggest high duplicate rate
    if duplicate_percentage > 80:
        print(f"\nHigh duplicate rate detected. Running full analysis...")
        
        # Process all IDs in batches
        batch_size = 100
        total_duplicates = 0
        
        for i in range(0, len(all_ids), batch_size):
            batch = all_ids[i:i+batch_size]
            duplicates = check_batch_duplicates(batch)
            total_duplicates += duplicates
            
            if i % (batch_size * 10) == 0:
                progress = (i / len(all_ids)) * 100
                print(f"Progress: {progress:5.1f}% ({i:5d}/{len(all_ids):5d})")
        
        final_duplicate_percentage = (total_duplicates / len(all_ids)) * 100
        new_count = len(all_ids) - total_duplicates
        new_percentage = (new_count / len(all_ids)) * 100
        
        print(f"\n=== FINAL RESULTS ===")
        print(f"Total unique anthophila observation IDs: {len(all_ids)}")
        print(f"Found in database (duplicates): {total_duplicates}")
        print(f"Duplicate percentage: {final_duplicate_percentage:.1f}%")
        print(f"New observations: {new_count}")
        print(f"New percentage: {new_percentage:.1f}%")
        
        # Save results
        with open("/home/caleb/repo/ibridaDB/anthophila_duplicates_final.txt", "w") as f:
            f.write(f"Anthophila Duplicate Analysis - Final Results\n")
            f.write(f"============================================\n\n")
            f.write(f"Total unique anthophila observation IDs: {len(all_ids)}\n")
            f.write(f"Found in database (duplicates): {total_duplicates}\n")
            f.write(f"Duplicate percentage: {final_duplicate_percentage:.1f}%\n")
            f.write(f"New observations: {new_count}\n")
            f.write(f"New percentage: {new_percentage:.1f}%\n")
        
        print(f"\nResults saved to: /home/caleb/repo/ibridaDB/anthophila_duplicates_final.txt")

if __name__ == "__main__":
    main()