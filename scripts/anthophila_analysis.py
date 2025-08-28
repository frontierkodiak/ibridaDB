#!/usr/bin/env python3
"""
Anthophila dataset analysis script.
Analyzes filename patterns and extracts potential iNaturalist observation IDs.
"""

import os
import re
from pathlib import Path
from collections import defaultdict, Counter

def analyze_anthophila_structure(anthophila_dir="/datasets/dataZoo/anthophila"):
    """Analyze the structure and filenames of the anthophila dataset."""
    
    print("=== Anthophila Dataset Analysis ===\n")
    
    # Basic statistics
    anthophila_path = Path(anthophila_dir)
    
    # Count directories (excluding GBIF_occurences)
    taxon_dirs = [d for d in anthophila_path.iterdir() 
                  if d.is_dir() and d.name != "GBIF_occurences"]
    
    print(f"Total taxonomic directories: {len(taxon_dirs)}")
    
    # Count total images
    jpg_files = list(anthophila_path.glob("**/*.jpg"))
    print(f"Total JPG files: {len(jpg_files)}")
    
    # Analyze filename patterns
    filename_pattern = re.compile(r'^([A-Z][a-z]+)_([a-z_]+)_(\d+)_(\d+)\.jpg$')
    
    parsed_files = []
    pattern_matches = 0
    
    for jpg_file in jpg_files:
        filename = jpg_file.name
        match = filename_pattern.match(filename)
        
        if match:
            pattern_matches += 1
            genus, species, observation_id, photo_num = match.groups()
            parsed_files.append({
                'filename': filename,
                'genus': genus,
                'species': species,
                'full_species': f"{genus}_{species}",
                'observation_id': int(observation_id),
                'photo_num': int(photo_num),
                'directory': jpg_file.parent.name
            })
    
    print(f"Files matching expected pattern: {pattern_matches} / {len(jpg_files)} ({pattern_matches/len(jpg_files)*100:.1f}%)")
    
    # Analyze observation IDs
    if parsed_files:
        observation_ids = [f['observation_id'] for f in parsed_files]
        genera = [f['genus'] for f in parsed_files]
        species = [f['full_species'] for f in parsed_files]
        
        print(f"\nObservation ID statistics:")
        print(f"Unique observation IDs: {len(set(observation_ids))}")
        print(f"Min observation ID: {min(observation_ids)}")
        print(f"Max observation ID: {max(observation_ids)}")
        
        # Photos per observation
        obs_counter = Counter(observation_ids)
        photos_per_obs = list(obs_counter.values())
        print(f"Average photos per observation: {sum(photos_per_obs)/len(photos_per_obs):.1f}")
        print(f"Max photos per observation: {max(photos_per_obs)}")
        
        # Taxa statistics
        print(f"\nTaxonomic diversity:")
        print(f"Unique genera: {len(set(genera))}")
        print(f"Unique species: {len(set(species))}")
        
        # Sample some observation IDs for validation
        sample_ids = list(set(observation_ids))[:10]
        print(f"\nSample observation IDs for validation:")
        for obs_id in sample_ids:
            print(f"  {obs_id} -> https://www.inaturalist.org/observations/{obs_id}")
        
        return parsed_files
    else:
        print("No files matched expected pattern!")
        return None

def analyze_gbif_data(anthophila_dir="/datasets/dataZoo/anthophila"):
    """Analyze GBIF occurrence data if present."""
    
    gbif_dir = Path(anthophila_dir) / "GBIF_occurences"
    
    if gbif_dir.exists():
        print(f"\n=== GBIF Data Analysis ===")
        
        occurrence_file = gbif_dir / "occurrence.txt"
        if occurrence_file.exists():
            # Read first few lines to understand structure
            with open(occurrence_file, 'r') as f:
                header = f.readline().strip().split('\t')
                print(f"GBIF occurrence columns: {len(header)}")
                print(f"Key columns: {[col for col in header if any(key in col.lower() for key in ['id', 'taxon', 'species', 'genus'])]}")
        
        multimedia_file = gbif_dir / "multimedia.txt"
        if multimedia_file.exists():
            with open(multimedia_file, 'r') as f:
                header = f.readline().strip().split('\t')
                print(f"GBIF multimedia columns: {len(header)}")
                print(f"Key columns: {[col for col in header if any(key in col.lower() for key in ['id', 'identifier', 'url'])]}")

if __name__ == "__main__":
    # Run analysis
    df = analyze_anthophila_structure()
    analyze_gbif_data()
    
    # Save results if we have data
    if df is not None:
        output_file = "/home/caleb/repo/ibridaDB/anthophila_analysis.txt"
        with open(output_file, 'w') as f:
            f.write("observation_id,genus,species,full_species,photo_num,filename,directory\n")
            for item in df:
                f.write(f"{item['observation_id']},{item['genus']},{item['species']},{item['full_species']},{item['photo_num']},{item['filename']},{item['directory']}\n")
        print(f"\nResults saved to: {output_file}")