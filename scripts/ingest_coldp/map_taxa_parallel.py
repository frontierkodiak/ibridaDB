#!/usr/bin/env python3

import argparse
import os
import pandas as pd
import logging
import time
import multiprocessing
from functools import partial
from sqlalchemy import create_engine, Column, Integer, String, Float, Text, ForeignKey
from sqlalchemy.orm import sessionmaker
from rapidfuzz import process, fuzz
import tempfile
import json

# Import models from the top-level models directory
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from models.base import Base 
from models.expanded_taxa import ExpandedTaxa # Target for common names
from models.coldp_models import ColdpNameUsage # Staging table for ColDP names

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- ORM for the crosswalk table ---
class InatToColdpMap(Base):
    __tablename__ = "inat_to_coldp_taxon_map"
    inat_taxon_id = Column(Integer, ForeignKey(f'{ExpandedTaxa.__tablename__}.taxonID'), primary_key=True)
    col_taxon_id = Column(String(64), ForeignKey(f'{ColdpNameUsage.__tablename__}.ID'), primary_key=True) # From ColDP NameUsage.ID
    
    match_type = Column(String(50), nullable=False) # e.g., 'exact_name_rank', 'exact_name_only', 'fuzzy_name'
    match_score = Column(Float, nullable=True)
    inat_scientific_name = Column(Text)
    col_scientific_name = Column(Text)


def get_db_engine(db_user, db_password, db_host, db_port, db_name):
    connection_string = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    return create_engine(connection_string)

def normalize_name(name):
    if pd.isna(name) or name is None:
        return None
    return ' '.join(str(name).lower().split()) # Lowercase and normalize whitespace

def create_crosswalk_table(engine):
    logger.info("Creating/ensuring 'inat_to_coldp_taxon_map' table exists...")
    Base.metadata.create_all(engine, tables=[InatToColdpMap.__table__], checkfirst=True)
    logger.info("'inat_to_coldp_taxon_map' table ensured.")

def get_taxon_ancestor_info(session, inat_taxa_df):
    """
    Retrieve ancestor information for resolving homonyms during fuzzy matching.
    """
    # Get a full list of taxa including ancestor levels for unmatched iNat taxa
    taxon_ids = inat_taxa_df['inat_taxon_id'].tolist()
    
    # Retrieve the full expanded_taxa rows including ancestor info
    ancestor_data = pd.read_sql_query(
        session.query(
            ExpandedTaxa.taxonID,
            ExpandedTaxa.L20_taxonID, ExpandedTaxa.L20_name,   # Genus
            ExpandedTaxa.L30_taxonID, ExpandedTaxa.L30_name,   # Family
            ExpandedTaxa.L40_taxonID, ExpandedTaxa.L40_name,   # Order 
            ExpandedTaxa.L50_taxonID, ExpandedTaxa.L50_name,   # Class
            ExpandedTaxa.L60_taxonID, ExpandedTaxa.L60_name    # Phylum
        )
        .filter(ExpandedTaxa.taxonID.in_(taxon_ids))
        .statement,
        session.bind
    )
    
    # Convert to dict for faster lookups in the worker processes
    ancestor_dict = {}
    for _, row in ancestor_data.iterrows():
        taxon_id = row['taxonID']
        ancestor_dict[taxon_id] = {
            'L20_name': row.get('L20_name'),
            'L30_name': row.get('L30_name'),
            'L40_name': row.get('L40_name'),
            'L50_name': row.get('L50_name'),
            'L60_name': row.get('L60_name')
        }
    
    return ancestor_dict

def build_col_ancestors_map(coldp_names_df):
    """
    Create a map of ColDP taxon IDs to their ancestor information from the NameUsage data
    """
    ancestor_map = {}
    
    # Extract and organize ancestor data
    for _, row in coldp_names_df.iterrows():
        col_taxon_id = row['col_taxon_id']
        ancestor_info = {
            'genus': row.get('genericName'),
            'family': row.get('family'),
            'order': row.get('order'),
            'class': row.get('class'),
            'phylum': row.get('phylum')
        }
        ancestor_map[col_taxon_id] = ancestor_info
    
    return ancestor_map

def resolve_homonyms_lightweight(row, matches_with_taxon_info, ancestor_data, ancestor_map):
    """
    Lightweight version of resolve_homonyms that works with taxon info dictionaries instead of DataFrames.
    """
    # Filter matches to only include those above threshold
    good_matches = [(name, score, taxon_info) for name, score, taxon_info in matches_with_taxon_info if score > 89.0]
    
    if not good_matches:
        return None
    
    # If only one match, return it
    if len(good_matches) == 1:
        match_name, score, taxon_info = good_matches[0]
        return {
            'inat_taxon_id': row['inat_taxon_id'],
            'col_taxon_id': taxon_info['col_taxon_id'],
            'match_type': 'fuzzy_name_single_match',
            'match_score': score / 100.0,
            'inat_scientific_name': row['inat_scientific_name'],
            'col_scientific_name': taxon_info['col_scientific_name']
        }
    
    # Multiple matches - try to use ancestor data to disambiguate
    inat_taxon_id = row['inat_taxon_id']
    if inat_taxon_id not in ancestor_data:
        # No ancestry data available for this taxon - take highest score match
        good_matches.sort(key=lambda x: x[1], reverse=True)
        match_name, score, taxon_info = good_matches[0]
        return {
            'inat_taxon_id': row['inat_taxon_id'],
            'col_taxon_id': taxon_info['col_taxon_id'],
            'match_type': 'fuzzy_name_highest_score',
            'match_score': score / 100.0,
            'inat_scientific_name': row['inat_scientific_name'],
            'col_scientific_name': taxon_info['col_scientific_name']
        }
    
    # Get iNat ancestor info
    inat_ancestors = ancestor_data[inat_taxon_id]
    
    # Score each candidate match by comparing ancestors
    ancestor_scores = []
    for match_name, score, taxon_info in good_matches:
        col_taxon_id = taxon_info['col_taxon_id']
        
        if col_taxon_id not in ancestor_map:
            # No ancestor data for this COL taxon - just use the fuzzy match score
            ancestor_scores.append((taxon_info, 0, score))
            continue
        
        col_ancestors = ancestor_map[col_taxon_id]
        
        # Check for matching ancestors at different ranks (genus, family, order, class, phylum)
        ancestor_matches = 0
        
        # Check genus
        inat_genus = normalize_name(inat_ancestors.get('L20_name'))
        col_genus = normalize_name(col_ancestors.get('genus'))
        if inat_genus and col_genus and inat_genus == col_genus:
            ancestor_matches += 2
        
        # Check family
        inat_family = normalize_name(inat_ancestors.get('L30_name'))
        col_family = normalize_name(col_ancestors.get('family'))
        if inat_family and col_family and inat_family == col_family:
            ancestor_matches += 1
        
        # Check order
        inat_order = normalize_name(inat_ancestors.get('L40_name'))
        col_order = normalize_name(col_ancestors.get('order'))
        if inat_order and col_order and inat_order == col_order:
            ancestor_matches += 1
        
        # Check class
        inat_class = normalize_name(inat_ancestors.get('L50_name'))
        col_class = normalize_name(col_ancestors.get('class'))
        if inat_class and col_class and inat_class == col_class:
            ancestor_matches += 1
        
        # Check phylum
        inat_phylum = normalize_name(inat_ancestors.get('L60_name'))
        col_phylum = normalize_name(col_ancestors.get('phylum'))
        if inat_phylum and col_phylum and inat_phylum == col_phylum:
            ancestor_matches += 1
        
        # Store the total score (combines fuzzy match score and ancestor matches)
        ancestor_scores.append((taxon_info, ancestor_matches, score))
    
    if not ancestor_scores:
        return None
        
    # Find the best match by prioritizing ancestor matches, then fuzzy score
    ancestor_scores.sort(key=lambda x: (x[1], x[2]), reverse=True)
    best_taxon_info, ancestor_match_count, fuzzy_score = ancestor_scores[0]
    
    match_type = 'fuzzy_name_with_ancestors' if ancestor_match_count > 0 else 'fuzzy_name_no_ancestors'
    return {
        'inat_taxon_id': row['inat_taxon_id'],
        'col_taxon_id': best_taxon_info['col_taxon_id'],
        'match_type': match_type,
        'match_score': fuzzy_score / 100.0,
        'inat_scientific_name': row['inat_scientific_name'],
        'col_scientific_name': best_taxon_info['col_scientific_name']
    }

def resolve_homonyms(row, matches, coldp_names_df, ancestor_data, ancestor_map):
    """
    Resolve homonyms by comparing ancestor taxonomy.
    Returns the most likely match or None if no good match can be determined.
    """
    matches_df = pd.DataFrame(matches, columns=['col_name', 'score', 'idx'])
    
    # Filter matches to only include those above threshold
    matches_df = matches_df[matches_df['score'] > 89.0]  # Adjust threshold as needed
    
    if matches_df.empty:
        return None
    
    # If only one match, return it
    if len(matches_df) == 1:
        match_idx = matches_df.iloc[0]['idx']
        return {
            'inat_taxon_id': row['inat_taxon_id'],
            'col_taxon_id': coldp_names_df.iloc[match_idx]['col_taxon_id'],
            'match_type': 'fuzzy_name_single_match',
            'match_score': matches_df.iloc[0]['score'] / 100.0,
            'inat_scientific_name': row['inat_scientific_name'],
            'col_scientific_name': coldp_names_df.iloc[match_idx]['col_scientific_name']
        }
    
    # Multiple matches - try to use ancestor data to disambiguate
    inat_taxon_id = row['inat_taxon_id']
    if inat_taxon_id not in ancestor_data:
        # No ancestry data available for this taxon
        # Take highest score match
        matches_df = matches_df.sort_values('score', ascending=False)
        match_idx = matches_df.iloc[0]['idx']
        return {
            'inat_taxon_id': row['inat_taxon_id'],
            'col_taxon_id': coldp_names_df.iloc[match_idx]['col_taxon_id'],
            'match_type': 'fuzzy_name_highest_score',
            'match_score': matches_df.iloc[0]['score'] / 100.0,
            'inat_scientific_name': row['inat_scientific_name'],
            'col_scientific_name': coldp_names_df.iloc[match_idx]['col_scientific_name']
        }
    
    # Get iNat ancestor info
    inat_ancestors = ancestor_data[inat_taxon_id]
    
    # Score each candidate match by comparing ancestors
    ancestor_scores = []
    for _, match in matches_df.iterrows():
        match_idx = match['idx']
        col_taxon_id = coldp_names_df.iloc[match_idx]['col_taxon_id']
        
        if col_taxon_id not in ancestor_map:
            # No ancestor data for this COL taxon - just use the fuzzy match score
            ancestor_scores.append((match_idx, 0, match['score']))
            continue
        
        col_ancestors = ancestor_map[col_taxon_id]
        
        # Check for matching ancestors at different ranks (genus, family, order, class, phylum)
        ancestor_matches = 0
        
        # Check genus
        inat_genus = normalize_name(inat_ancestors.get('L20_name'))
        col_genus = normalize_name(col_ancestors.get('genus'))
        if inat_genus and col_genus and inat_genus == col_genus:
            ancestor_matches += 2
        
        # Check family
        inat_family = normalize_name(inat_ancestors.get('L30_name'))
        col_family = normalize_name(col_ancestors.get('family'))
        if inat_family and col_family and inat_family == col_family:
            ancestor_matches += 1
        
        # Check order
        inat_order = normalize_name(inat_ancestors.get('L40_name'))
        col_order = normalize_name(col_ancestors.get('order'))
        if inat_order and col_order and inat_order == col_order:
            ancestor_matches += 1
        
        # Check class
        inat_class = normalize_name(inat_ancestors.get('L50_name'))
        col_class = normalize_name(col_ancestors.get('class'))
        if inat_class and col_class and inat_class == col_class:
            ancestor_matches += 1
        
        # Check phylum
        inat_phylum = normalize_name(inat_ancestors.get('L60_name'))
        col_phylum = normalize_name(col_ancestors.get('phylum'))
        if inat_phylum and col_phylum and inat_phylum == col_phylum:
            ancestor_matches += 1
        
        # Store the total score (combines fuzzy match score and ancestor matches)
        ancestor_scores.append((match_idx, ancestor_matches, match['score']))
    
    if not ancestor_scores:
        return None
        
    # Find the best match by prioritizing ancestor matches, then fuzzy score
    ancestor_scores.sort(key=lambda x: (x[1], x[2]), reverse=True)
    best_match_idx, ancestor_match_count, fuzzy_score = ancestor_scores[0]
    
    match_type = 'fuzzy_name_with_ancestors' if ancestor_match_count > 0 else 'fuzzy_name_no_ancestors'
    return {
        'inat_taxon_id': row['inat_taxon_id'],
        'col_taxon_id': coldp_names_df.iloc[best_match_idx]['col_taxon_id'],
        'match_type': match_type,
        'match_score': fuzzy_score / 100.0,
        'inat_scientific_name': row['inat_scientific_name'],
        'col_scientific_name': coldp_names_df.iloc[best_match_idx]['col_scientific_name']
    }

def process_fuzzy_batch(batch_data, fuzzy_threshold=90):
    """
    Process a batch of taxa for fuzzy matching in a separate process.
    
    Args:
        batch_data: Dictionary containing all data needed for processing:
            - batch: DataFrame of iNat taxa to process
            - accepted_coldp_names: List of accepted ColDP normalized names
            - all_coldp_names: List of all ColDP normalized names
            - coldp_lookup: Dictionary for name -> taxon info lookup
            - ancestor_data: Dictionary of iNat ancestor data
            - ancestor_map: Dictionary of ColDP ancestor data
    
    Returns:
        List of match results
    """
    batch = batch_data['batch']
    accepted_coldp_names = batch_data['accepted_coldp_names']
    all_coldp_names = batch_data['all_coldp_names']
    coldp_lookup = batch_data['coldp_lookup']
    ancestor_data = batch_data['ancestor_data']
    ancestor_map = batch_data['ancestor_map']
    
    fuzzy_matches = []
    start_time = time.time()
    
    batch_size = len(batch)
    batch_id = batch_data.get('batch_id', 0)
    
    # Process each taxon in the batch
    for i, (_, row) in enumerate(batch.iterrows()):
        if i % 100 == 0 and i > 0:
            elapsed = time.time() - start_time
            progress = i / batch_size * 100
            logger.info(f"Batch {batch_id}: Processed {i}/{batch_size} ({progress:.1f}%) in {elapsed:.2f}s")
        
        # First try to match against accepted names only
        if accepted_coldp_names:  # Skip if empty
            matches = process.extract(
                query=row['norm_inat_name'],
                choices=accepted_coldp_names, 
                scorer=fuzz.WRatio,  # WRatio is good for scientific names with different word orders
                score_cutoff=fuzzy_threshold,
                limit=5
            )
            
            # If no good matches in accepted names, try all names
            if not matches and all_coldp_names:
                matches = process.extract(
                    query=row['norm_inat_name'],
                    choices=all_coldp_names,
                    scorer=fuzz.WRatio,
                    score_cutoff=fuzzy_threshold,
                    limit=5
                )
            
            # Convert matches to format expected by resolve_homonyms
            if matches:
                matches_with_taxon_info = []
                for match_tuple in matches:
                    # Handle both (string, score) and (string, score, index) formats from rapidfuzz
                    if len(match_tuple) == 2:
                        match_name, score = match_tuple
                    else:
                        match_name, score, _ = match_tuple
                    
                    # Look up taxon info using our lookup dictionary
                    if match_name in coldp_lookup:
                        for taxon_info in coldp_lookup[match_name]:
                            matches_with_taxon_info.append((match_name, score, taxon_info))
                
                # Resolve homonyms and get the best match
                match_result = resolve_homonyms_lightweight(row, matches_with_taxon_info, ancestor_data, ancestor_map)
                if match_result:
                    fuzzy_matches.append(match_result)
    
    elapsed = time.time() - start_time
    logger.info(f"Batch {batch_id} completed: Processed {batch_size} taxa in {elapsed:.2f}s")
    
    return fuzzy_matches

def perform_mapping_parallel(session, num_processes=None, fuzzy_match=True, fuzzy_threshold=90):
    """
    Perform the mapping process with parallel processing for the fuzzy matching.
    """
    if num_processes is None:
        num_processes = multiprocessing.cpu_count() - 1  # Leave one core free
        
    logger.info(f"Will use {num_processes} parallel processes for fuzzy matching")
    
    logger.info("Starting iNaturalist to ColDP taxon mapping process...")

    # 0. Clear existing mapping data
    logger.info("Clearing existing data from 'inat_to_coldp_taxon_map'...")
    session.query(InatToColdpMap).delete(synchronize_session=False)
    session.commit()

    # 1. Load iNat taxa data from expanded_taxa
    logger.info("Loading iNaturalist taxa from 'expanded_taxa' table...")
    inat_taxa_df = pd.read_sql_query(
        session.query(ExpandedTaxa.taxonID, ExpandedTaxa.name, ExpandedTaxa.rank)
               .filter(ExpandedTaxa.taxonActive == True) # Only map active iNat taxa
               .statement,
        session.bind
    )
    inat_taxa_df.rename(columns={'taxonID': 'inat_taxon_id', 'name': 'inat_scientific_name', 'rank': 'inat_rank'}, inplace=True)
    inat_taxa_df['norm_inat_name'] = inat_taxa_df['inat_scientific_name'].apply(normalize_name)
    inat_taxa_df['norm_inat_rank'] = inat_taxa_df['inat_rank'].apply(normalize_name)
    logger.info(f"Loaded {len(inat_taxa_df)} active iNaturalist taxa.")

    # 2. Load ColDP NameUsage data (from coldp_name_usage_staging)
    logger.info("Loading ColDP NameUsage data from 'coldp_name_usage_staging' table...")
    
    # For fuzzy matching, we need to load more columns to help with ancestor comparison
    if fuzzy_match:
        coldp_names_df = pd.read_sql_query(
            session.query(
                ColdpNameUsage.ID, 
                ColdpNameUsage.scientificName, 
                ColdpNameUsage.rank, 
                ColdpNameUsage.status,
                ColdpNameUsage.genericName,
                ColdpNameUsage.specificEpithet,
                ColdpNameUsage.family,
                ColdpNameUsage.order,
                ColdpNameUsage.class_,
                ColdpNameUsage.phylum
            )
            .statement, 
            session.bind
        )
    else:
        coldp_names_df = pd.read_sql_query(
            session.query(ColdpNameUsage.ID, ColdpNameUsage.scientificName, ColdpNameUsage.rank, ColdpNameUsage.status)
                   .statement,
            session.bind
        )
    
    coldp_names_df.rename(columns={'ID': 'col_taxon_id', 'scientificName': 'col_scientific_name', 
                          'rank': 'col_rank', 'status': 'col_status'}, inplace=True)
    coldp_names_df['norm_col_name'] = coldp_names_df['col_scientific_name'].apply(normalize_name)
    coldp_names_df['norm_col_rank'] = coldp_names_df['col_rank'].apply(normalize_name)
    logger.info(f"Loaded {len(coldp_names_df)} ColDP NameUsage entries.")

    all_mappings = []

    # --- Step 3: Exact Match (Name + Rank), prioritize 'accepted' ColDP status ---
    logger.info("Attempting exact match on scientific name and rank...")
    merged_exact_rank = pd.merge(
        inat_taxa_df,
        coldp_names_df,
        left_on=['norm_inat_name', 'norm_inat_rank'],
        right_on=['norm_col_name', 'norm_col_rank'],
        how='inner'
    )
    # Prioritize 'accepted' status
    merged_exact_rank.sort_values(by=['inat_taxon_id', 'col_status'], ascending=[True, True], inplace=True) # 'accepted' often comes first alphabetically
    merged_exact_rank_unique = merged_exact_rank.drop_duplicates(subset=['inat_taxon_id'], keep='first')

    for _, row in merged_exact_rank_unique.iterrows():
        all_mappings.append({
            'inat_taxon_id': row['inat_taxon_id'],
            'col_taxon_id': row['col_taxon_id'],
            'match_type': 'exact_name_rank_accepted' if row['col_status'] == 'accepted' else 'exact_name_rank_other_status',
            'match_score': 1.0,
            'inat_scientific_name': row['inat_scientific_name'],
            'col_scientific_name': row['col_scientific_name']
        })
    logger.info(f"Found {len(merged_exact_rank_unique)} matches on name and rank.")
    
    # Update iNat taxa df to exclude matched items
    inat_taxa_df = inat_taxa_df[~inat_taxa_df['inat_taxon_id'].isin(merged_exact_rank_unique['inat_taxon_id'])]

    # --- Step 4: Exact Match (Name only), prioritize 'accepted' ---
    if not inat_taxa_df.empty:
        logger.info(f"Attempting exact match on scientific name only for {len(inat_taxa_df)} remaining iNat taxa...")
        merged_exact_name_only = pd.merge(
            inat_taxa_df,
            coldp_names_df, # Could filter coldp_names_df for status='accepted' first for efficiency
            left_on=['norm_inat_name'],
            right_on=['norm_col_name'],
            how='inner'
        )
        merged_exact_name_only.sort_values(by=['inat_taxon_id', 'col_status'], ascending=[True, True], inplace=True)
        merged_exact_name_only_unique = merged_exact_name_only.drop_duplicates(subset=['inat_taxon_id'], keep='first')

        for _, row in merged_exact_name_only_unique.iterrows():
             all_mappings.append({
                'inat_taxon_id': row['inat_taxon_id'],
                'col_taxon_id': row['col_taxon_id'],
                'match_type': 'exact_name_only_accepted' if row['col_status'] == 'accepted' else 'exact_name_only_other_status',
                'match_score': 0.95, # Slightly lower score than name+rank
                'inat_scientific_name': row['inat_scientific_name'],
                'col_scientific_name': row['col_scientific_name']
            })
        logger.info(f"Found {len(merged_exact_name_only_unique)} matches on name only.")
        inat_taxa_df = inat_taxa_df[~inat_taxa_df['inat_taxon_id'].isin(merged_exact_name_only_unique['inat_taxon_id'])]

    # --- Step 5: Fuzzy Match ---
    fuzzy_match_count = 0
    if fuzzy_match and not inat_taxa_df.empty:
        logger.info(f"Attempting fuzzy matching for {len(inat_taxa_df)} remaining iNat taxa...")
        
        # Prepare for homonym resolution: get ancestor information
        ancestor_data = get_taxon_ancestor_info(session, inat_taxa_df)
        logger.info(f"Retrieved ancestor data for {len(ancestor_data)} unmatched taxa")
        
        # Build a map of ColDP taxon IDs to their ancestor information
        ancestor_map = build_col_ancestors_map(coldp_names_df)
        logger.info(f"Built ancestor map for {len(ancestor_map)} ColDP taxa")
        
        # Filter out null/None values before fuzzy matching
        inat_taxa_filtered = inat_taxa_df[inat_taxa_df['norm_inat_name'].notna()]
        
        # Use a conservative batch size to manage memory usage
        batch_size = 1000
        parallel_batch_size = batch_size  # Keep batch size at 1000 to prevent OOM
        
        # Create lightweight batch data - only pass essential data to reduce memory copying
        # Extract just the normalized names and IDs to minimize data transfer
        accepted_coldp_names = coldp_names_df[coldp_names_df['col_status'] == 'accepted']['norm_col_name'].dropna().tolist()
        all_coldp_names = coldp_names_df['norm_col_name'].dropna().tolist()
        
        # Create lookup dictionaries for faster access (instead of copying full DataFrames)
        coldp_lookup = {}
        for _, row in coldp_names_df.iterrows():
            norm_name = row['norm_col_name']
            if pd.notna(norm_name):
                if norm_name not in coldp_lookup:
                    coldp_lookup[norm_name] = []
                coldp_lookup[norm_name].append({
                    'col_taxon_id': row['col_taxon_id'],
                    'col_scientific_name': row['col_scientific_name'],
                    'col_status': row['col_status']
                })
        
        # Split the data into batches for parallel processing
        all_batches = []
        for start_idx in range(0, len(inat_taxa_filtered), parallel_batch_size):
            end_idx = min(start_idx + parallel_batch_size, len(inat_taxa_filtered))
            batch = inat_taxa_filtered.iloc[start_idx:end_idx].copy()
            
            batch_data = {
                'batch': batch,
                'accepted_coldp_names': accepted_coldp_names,
                'all_coldp_names': all_coldp_names,
                'coldp_lookup': coldp_lookup,
                'ancestor_data': ancestor_data,
                'ancestor_map': ancestor_map,
                'batch_id': len(all_batches) + 1
            }
            all_batches.append(batch_data)
            
        logger.info(f"Split data into {len(all_batches)} large batches for parallel processing")
        
        # Create a multiprocessing pool
        with multiprocessing.Pool(processes=num_processes) as pool:
            process_func = partial(process_fuzzy_batch, fuzzy_threshold=fuzzy_threshold)
            
            # Process batches in parallel
            logger.info(f"Processing {len(all_batches)} batches with {num_processes} workers...")
            results = pool.map(process_func, all_batches)
            
            # Combine results
            fuzzy_matches = []
            for batch_results in results:
                fuzzy_matches.extend(batch_results)
            
            fuzzy_match_count = len(fuzzy_matches)
            all_mappings.extend(fuzzy_matches)
            logger.info(f"Found {fuzzy_match_count} fuzzy matches across all batches.")
    
    # Calculate how many unmatched taxa remain
    total_exact_matches = len(all_mappings) - fuzzy_match_count
    total_unmatched = len(inat_taxa_df) - fuzzy_match_count
    logger.info(f"Summary: {total_exact_matches} exact matches, {fuzzy_match_count} fuzzy matches, {total_unmatched} remaining unmatched taxa.")
    
    # Save match statistics by type
    match_types = {}
    for mapping in all_mappings:
        match_type = mapping['match_type']
        if match_type not in match_types:
            match_types[match_type] = 0
        match_types[match_type] += 1
    
    logger.info("Match statistics by type:")
    for match_type, count in match_types.items():
        logger.info(f"  {match_type}: {count}")

    # --- Step 6: Persist mappings ---
    if all_mappings:
        logger.info(f"Bulk inserting {len(all_mappings)} mappings into 'inat_to_coldp_taxon_map'...")
        # Insert in chunks to avoid memory issues
        chunk_size = 10000
        for i in range(0, len(all_mappings), chunk_size):
            chunk = all_mappings[i:i+chunk_size]
            session.bulk_insert_mappings(InatToColdpMap, chunk)
            session.commit()
            logger.info(f"Inserted chunk {i//chunk_size + 1}/{(len(all_mappings) + chunk_size - 1)//chunk_size}")
        
        logger.info("Successfully populated 'inat_to_coldp_taxon_map'.")
    else:
        logger.info("No mappings found to insert.")


def main():
    parser = argparse.ArgumentParser(description="Map iNaturalist taxa to ColDP taxa using parallel processing.")
    parser.add_argument("--db-user", default=os.getenv("DB_USER", "postgres"))
    parser.add_argument("--db-password", default=os.getenv("DB_PASSWORD", "password"))
    parser.add_argument("--db-host", default=os.getenv("DB_HOST", "localhost"))
    parser.add_argument("--db-port", default=os.getenv("DB_PORT", "5432"))
    parser.add_argument("--db-name", default=os.getenv("DB_NAME", "ibrida-v0-r1"))
    parser.add_argument("--fuzzy-match", action="store_true", help="Enable fuzzy matching for unmatched taxa")
    parser.add_argument("--fuzzy-threshold", type=int, default=90, help="Threshold score (0-100) for fuzzy matching")
    parser.add_argument("--processes", type=int, default=None, help="Number of parallel processes to use (default: CPU count - 1)")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    engine = get_db_engine(args.db_user, args.db_password, args.db_host, args.db_port, args.db_name)
    create_crosswalk_table(engine) # Ensure table exists

    Session = sessionmaker(bind=engine)
    session = Session()

    try:
        perform_mapping_parallel(
            session, 
            num_processes=args.processes, 
            fuzzy_match=args.fuzzy_match, 
            fuzzy_threshold=args.fuzzy_threshold
        )
    except Exception as e:
        logger.error(f"An error occurred during the mapping process: {e}")
        session.rollback()
    finally:
        session.close()

if __name__ == "__main__":
    main()