#!/usr/bin/env python3

import argparse
import os
import logging
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
import pandas as pd
import time

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def get_db_engine(db_user, db_password, db_host, db_port, db_name):
    connection_string = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    return create_engine(connection_string)

def add_columns_if_not_exists(session):
    """Add the four new immediate ancestor columns if they don't already exist."""
    logger.info("Checking if immediate ancestor columns exist...")
    
    # Check if columns already exist
    check_sql = text("""
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'expanded_taxa' 
        AND column_name IN ('immediateMajorAncestor_taxonID', 'immediateMajorAncestor_rankLevel', 
                           'immediateAncestor_taxonID', 'immediateAncestor_rankLevel');
    """)
    
    existing_columns = [row[0] for row in session.execute(check_sql)]
    
    if len(existing_columns) == 4:
        logger.info("All immediate ancestor columns already exist.")
        return False
    
    # Add columns
    logger.info("Adding immediate ancestor columns to expanded_taxa table...")
    
    alter_statements = []
    if 'immediateMajorAncestor_taxonID' not in existing_columns:
        alter_statements.append('ADD COLUMN "immediateMajorAncestor_taxonID" INTEGER')
    if 'immediateMajorAncestor_rankLevel' not in existing_columns:
        alter_statements.append('ADD COLUMN "immediateMajorAncestor_rankLevel" DOUBLE PRECISION')
    if 'immediateAncestor_taxonID' not in existing_columns:
        alter_statements.append('ADD COLUMN "immediateAncestor_taxonID" INTEGER')
    if 'immediateAncestor_rankLevel' not in existing_columns:
        alter_statements.append('ADD COLUMN "immediateAncestor_rankLevel" DOUBLE PRECISION')
    
    if alter_statements:
        alter_sql = text(f"ALTER TABLE expanded_taxa {', '.join(alter_statements)};")
        session.execute(alter_sql)
        session.commit()
        logger.info("Successfully added immediate ancestor columns.")
    
    return True

def compute_immediate_ancestors(row, all_rank_levels, major_rank_levels):
    """Compute immediate ancestors for a single taxon."""
    taxon_rank = row['rankLevel']
    
    # Find immediate ancestor (any rank)
    immediate_ancestor_id = None
    immediate_ancestor_rank = None
    min_rank_diff = float('inf')
    
    for rank_level in all_rank_levels:
        col_name = f"L{str(rank_level).replace('.', '_')}_taxonID"
        if col_name in row:
            ancestor_id = row[col_name]
            
            if pd.notna(ancestor_id) and rank_level > taxon_rank:
                if rank_level - taxon_rank < min_rank_diff:
                    min_rank_diff = rank_level - taxon_rank
                    immediate_ancestor_id = int(ancestor_id)
                    immediate_ancestor_rank = rank_level
    
    # Find immediate major-rank ancestor
    immediate_major_ancestor_id = None
    immediate_major_ancestor_rank = None
    
    for rank_level in major_rank_levels:
        col_name = f"L{rank_level}_taxonID"
        if col_name in row:
            ancestor_id = row[col_name]
            
            if pd.notna(ancestor_id) and rank_level > taxon_rank:
                immediate_major_ancestor_id = int(ancestor_id)
                immediate_major_ancestor_rank = float(rank_level)
                break
    
    return {
        'immediateAncestor_taxonID': immediate_ancestor_id,
        'immediateAncestor_rankLevel': immediate_ancestor_rank,
        'immediateMajorAncestor_taxonID': immediate_major_ancestor_id,
        'immediateMajorAncestor_rankLevel': immediate_major_ancestor_rank
    }

def populate_immediate_ancestors(session, engine, batch_size=50000):
    """Populate the immediate ancestor columns for all taxa."""
    logger.info("Starting to populate immediate ancestor columns...")
    
    # Define all rank levels in order
    all_rank_levels = [5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30, 32, 33, 33.5, 34, 34.5, 35, 37, 40, 43, 44, 45, 47, 50, 53, 57, 60, 67, 70]
    major_rank_levels = [10, 20, 30, 40, 50, 60, 70]
    
    # Build list of columns to select
    base_cols = ['"taxonID"', '"rankLevel"']
    ancestor_cols = []
    for rank_level in all_rank_levels:
        col_name = f'"L{str(rank_level).replace(".", "_")}_taxonID"'
        ancestor_cols.append(col_name)
    
    select_cols = ', '.join(base_cols + ancestor_cols)
    
    # Get total count
    count_result = session.execute(text("SELECT COUNT(*) FROM expanded_taxa"))
    total_count = count_result.scalar()
    logger.info(f"Total taxa to process: {total_count}")
    
    # Process in batches
    processed = 0
    start_time = time.time()
    
    for offset in range(0, total_count, batch_size):
        # Read batch
        query = f"""
            SELECT {select_cols}
            FROM expanded_taxa
            ORDER BY "taxonID"
            LIMIT {batch_size} OFFSET {offset}
        """
        
        df = pd.read_sql_query(query, engine)
        
        # Compute immediate ancestors for each row
        updates = []
        for _, row in df.iterrows():
            result = compute_immediate_ancestors(row, all_rank_levels, major_rank_levels)
            updates.append({
                'taxonID': row['taxonID'],
                **result
            })
        
        # Update database
        if updates:
            update_df = pd.DataFrame(updates)
            
            # Create temporary table for bulk update
            temp_table = f"temp_immediate_ancestors_{int(time.time())}"
            update_df.to_sql(temp_table, engine, if_exists='replace', index=False)
            
            # Perform bulk update
            update_sql = text(f"""
                UPDATE expanded_taxa et
                SET 
                    "immediateAncestor_taxonID" = t."immediateAncestor_taxonID",
                    "immediateAncestor_rankLevel" = t."immediateAncestor_rankLevel",
                    "immediateMajorAncestor_taxonID" = t."immediateMajorAncestor_taxonID",
                    "immediateMajorAncestor_rankLevel" = t."immediateMajorAncestor_rankLevel"
                FROM {temp_table} t
                WHERE et."taxonID" = t."taxonID"
            """)
            
            session.execute(update_sql)
            session.commit()
            
            # Drop temporary table
            session.execute(text(f"DROP TABLE {temp_table}"))
            session.commit()
        
        processed += len(df)
        elapsed = time.time() - start_time
        rate = processed / elapsed if elapsed > 0 else 0
        eta = (total_count - processed) / rate if rate > 0 else 0
        
        logger.info(f"Processed {processed}/{total_count} taxa "
                   f"({100 * processed / total_count:.1f}%) "
                   f"Rate: {rate:.0f} taxa/sec, ETA: {eta/60:.1f} minutes")

def create_indexes(session):
    """Create indexes on the new taxonID columns for efficient lookups."""
    logger.info("Creating indexes on immediate ancestor columns...")
    
    index_statements = [
        'CREATE INDEX IF NOT EXISTS idx_immediate_ancestor_taxon_id ON expanded_taxa("immediateAncestor_taxonID")',
        'CREATE INDEX IF NOT EXISTS idx_immediate_major_ancestor_taxon_id ON expanded_taxa("immediateMajorAncestor_taxonID")'
    ]
    
    for stmt in index_statements:
        session.execute(text(stmt))
    
    session.commit()
    logger.info("Indexes created successfully.")

def verify_results(session):
    """Verify that the immediate ancestor columns were populated correctly."""
    logger.info("Verifying results...")
    
    # Check a few examples
    sample_sql = text("""
        SELECT 
            "taxonID", 
            name, 
            "rankLevel",
            "immediateAncestor_taxonID",
            "immediateAncestor_rankLevel",
            "immediateMajorAncestor_taxonID",
            "immediateMajorAncestor_rankLevel"
        FROM expanded_taxa 
        WHERE "immediateAncestor_taxonID" IS NOT NULL
        LIMIT 10;
    """)
    
    results = session.execute(sample_sql)
    logger.info("Sample of populated immediate ancestors:")
    for row in results:
        logger.info(f"  Taxon {row[0]} ({row[1]}, rank {row[2]}): "
                   f"immediate={row[3]} (rank {row[4]}), "
                   f"major={row[5]} (rank {row[6]})")
    
    # Check specific examples - verify ancestors are correct
    test_sql = text("""
        SELECT 
            et."taxonID",
            et.name,
            et."rankLevel",
            et."immediateAncestor_taxonID",
            ia.name as immediate_name,
            et."immediateAncestor_rankLevel",
            et."immediateMajorAncestor_taxonID",
            ima.name as major_name,
            et."immediateMajorAncestor_rankLevel"
        FROM expanded_taxa et
        LEFT JOIN expanded_taxa ia ON et."immediateAncestor_taxonID" = ia."taxonID"
        LEFT JOIN expanded_taxa ima ON et."immediateMajorAncestor_taxonID" = ima."taxonID"
        WHERE et.name IN ('Apis mellifera', 'Vespa mandarinia', 'Anthophila')
    """)
    
    test_results = session.execute(test_sql)
    logger.info("\nVerifying specific taxa:")
    for row in test_results:
        logger.info(f"  {row[1]} (rank {row[2]}): immediate={row[4]} (rank {row[5]}), major={row[7]} (rank {row[8]})")
    
    # Check counts
    count_sql = text("""
        SELECT 
            COUNT(*) as total,
            COUNT("immediateAncestor_taxonID") as with_immediate,
            COUNT("immediateMajorAncestor_taxonID") as with_major
        FROM expanded_taxa;
    """)
    
    count_result = session.execute(count_sql).fetchone()
    logger.info(f"\nTotal taxa: {count_result[0]}")
    logger.info(f"Taxa with immediate ancestor: {count_result[1]} ({100*count_result[1]/count_result[0]:.1f}%)")
    logger.info(f"Taxa with immediate major ancestor: {count_result[2]} ({100*count_result[2]/count_result[0]:.1f}%)")

def main():
    parser = argparse.ArgumentParser(description="Add and populate immediate ancestor columns in expanded_taxa.")
    parser.add_argument("--db-user", default=os.getenv("DB_USER", "postgres"))
    parser.add_argument("--db-password", default=os.getenv("DB_PASSWORD", "password"))
    parser.add_argument("--db-host", default=os.getenv("DB_HOST", "localhost"))
    parser.add_argument("--db-port", default=os.getenv("DB_PORT", "5432"))
    parser.add_argument("--db-name", default=os.getenv("DB_NAME", "ibrida-v0-r1"))
    parser.add_argument("--batch-size", type=int, default=50000, help="Batch size for updates")
    parser.add_argument("--skip-add-columns", action="store_true", help="Skip adding columns if they already exist")
    parser.add_argument("--skip-populate", action="store_true", help="Skip populating the columns")
    parser.add_argument("--skip-indexes", action="store_true", help="Skip creating indexes")
    parser.add_argument("--verify-only", action="store_true", help="Only verify existing data")
    
    args = parser.parse_args()
    
    engine = get_db_engine(args.db_user, args.db_password, args.db_host, args.db_port, args.db_name)
    Session = sessionmaker(bind=engine)
    session = Session()
    
    try:
        if args.verify_only:
            verify_results(session)
        else:
            # Add columns
            if not args.skip_add_columns:
                add_columns_if_not_exists(session)
            
            # Populate data
            if not args.skip_populate:
                populate_immediate_ancestors(session, engine, args.batch_size)
            
            # Create indexes
            if not args.skip_indexes:
                create_indexes(session)
            
            # Verify results
            verify_results(session)
            
        logger.info("Process completed successfully!")
        
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        session.rollback()
        raise
    finally:
        session.close()

if __name__ == "__main__":
    main()