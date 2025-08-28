#!/usr/bin/env python3
"""
Check anthophila observation IDs against ibridaDB to identify duplicates.
"""

import re
import psycopg2
from pathlib import Path
from collections import Counter

def connect_to_db():
    """Connect to the ibridaDB database."""
    return psycopg2.connect(
        host="localhost",
        port="5432", 
        database="ibrida-v0-r1",
        user="postgres",
        password="ooglyboogly69"
    )

def extract_anthophila_ids(anthophila_dir="/datasets/dataZoo/anthophila"):
    """Extract all observation IDs from anthophila filenames."""
    
    anthophila_path = Path(anthophila_dir)
    filename_pattern = re.compile(r'^([A-Z][a-z]+)_([a-z_]+)_(\d+)_(\d+)\.jpg$')
    
    observation_ids = []
    
    for jpg_file in anthophila_path.glob("**/*.jpg"):
        filename = jpg_file.name
        match = filename_pattern.match(filename)
        
        if match:
            genus, species, observation_id, photo_num = match.groups()
            observation_ids.append(int(observation_id))
    
    print(f"Extracted {len(observation_ids)} observation IDs from anthophila")
    print(f"Unique observation IDs: {len(set(observation_ids))}")
    
    return list(set(observation_ids))

def check_duplicates_in_photos(conn, observation_ids):
    """Check if anthophila observation IDs exist in the photos table."""
    
    cursor = conn.cursor()
    
    # Check photos.photo_id matches (batch query for efficiency)
    duplicates_photos = set()
    batch_size = 1000
    
    for i in range(0, len(observation_ids), batch_size):
        batch = observation_ids[i:i+batch_size]
        
        # Check against photo_id
        cursor.execute(
            "SELECT photo_id FROM photos WHERE photo_id = ANY(%s)",
            (batch,)
        )
        
        batch_duplicates = cursor.fetchall()
        duplicates_photos.update([row[0] for row in batch_duplicates])
        
        if i % (batch_size * 10) == 0:
            print(f"Processed {i}/{len(observation_ids)} IDs...")
    
    return duplicates_photos

def check_duplicates_by_url_lookup(conn, observation_ids):
    """
    Check if observation IDs exist by looking for iNaturalist URLs in the database.
    This is a more comprehensive check since the anthophila IDs are observation IDs,
    not necessarily photo IDs.
    """
    
    cursor = conn.cursor()
    
    # Check if we can find observations that originated from these specific iNat observation IDs
    # This is tricky since we don't store the original observation ID directly
    
    # Let's check a sample first to understand the data better
    sample_ids = observation_ids[:10]
    
    for obs_id in sample_ids:
        # Try to find any reference to this observation ID
        cursor.execute("""
            SELECT COUNT(*) FROM observations o 
            JOIN photos p ON o.observation_uuid = p.observation_uuid 
            WHERE p.photo_id = %s
        """, (obs_id,))
        
        result = cursor.fetchone()
        if result[0] > 0:
            print(f"Found observation {obs_id} in database")
    
    return set()

def main():
    """Main analysis function."""
    
    print("=== Anthophila Duplicate Analysis ===\n")
    
    # Extract observation IDs from anthophila
    observation_ids = extract_anthophila_ids()
    
    if not observation_ids:
        print("No observation IDs found!")
        return
    
    # Connect to database
    print("\nConnecting to database...")
    conn = connect_to_db()
    
    try:
        # Check duplicates in photos table
        print("Checking for duplicates in photos table...")
        duplicates_photos = check_duplicates_in_photos(conn, observation_ids)
        
        print(f"\n=== RESULTS ===")
        print(f"Total unique anthophila observation IDs: {len(observation_ids)}")
        print(f"Found in photos.photo_id: {len(duplicates_photos)}")
        print(f"Duplicate percentage: {len(duplicates_photos)/len(observation_ids)*100:.1f}%")
        print(f"New (non-duplicate) observations: {len(observation_ids) - len(duplicates_photos)}")
        print(f"New percentage: {(len(observation_ids) - len(duplicates_photos))/len(observation_ids)*100:.1f}%")
        
        # Sample some duplicates for verification
        if duplicates_photos:
            sample_dups = list(duplicates_photos)[:5]
            print(f"\nSample duplicate observation IDs:")
            for dup_id in sample_dups:
                print(f"  {dup_id} -> https://www.inaturalist.org/observations/{dup_id}")
        
        # Sample some non-duplicates
        non_duplicates = [obs_id for obs_id in observation_ids if obs_id not in duplicates_photos]
        if non_duplicates:
            sample_new = non_duplicates[:5]
            print(f"\nSample NEW observation IDs (not in database):")
            for new_id in sample_new:
                print(f"  {new_id} -> https://www.inaturalist.org/observations/{new_id}")
        
        # Save results
        with open("/home/caleb/repo/ibridaDB/anthophila_duplicates_analysis.txt", "w") as f:
            f.write(f"Anthophila Duplicate Analysis Results\n")
            f.write(f"=====================================\n\n")
            f.write(f"Total unique anthophila observation IDs: {len(observation_ids)}\n")
            f.write(f"Found in database (duplicates): {len(duplicates_photos)}\n")
            f.write(f"Duplicate percentage: {len(duplicates_photos)/len(observation_ids)*100:.1f}%\n")
            f.write(f"New observations: {len(observation_ids) - len(duplicates_photos)}\n")
            f.write(f"New percentage: {(len(observation_ids) - len(duplicates_photos))/len(observation_ids)*100:.1f}%\n\n")
            
            f.write("Duplicate observation IDs:\n")
            for dup_id in sorted(duplicates_photos):
                f.write(f"{dup_id}\n")
            
            f.write("\nNew observation IDs:\n")
            for new_id in sorted(non_duplicates):
                f.write(f"{new_id}\n")
                
        print(f"\nDetailed results saved to: /home/caleb/repo/ibridaDB/anthophila_duplicates_analysis.txt")
        
    finally:
        conn.close()

if __name__ == "__main__":
    main()