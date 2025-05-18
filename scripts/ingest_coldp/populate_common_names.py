#!/usr/bin/env python3

import argparse
import os
import logging
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# Import models from the top-level models directory
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from models.expanded_taxa import ExpandedTaxa  # ORM for expanded_taxa

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

TARGET_TABLE_NAME = "expanded_taxa" # The table created by expand_taxa.sh

def get_db_engine(db_user, db_password, db_host, db_port, db_name):
    connection_string = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    return create_engine(connection_string)

def clear_existing_common_names(session):
    logger.info(f"Clearing existing common name data from '{TARGET_TABLE_NAME}'...")
    
    # Base commonName
    stmt_base = text(f"""UPDATE "{TARGET_TABLE_NAME}" SET "commonName" = NULL;""")
    session.execute(stmt_base)

    # Ancestral commonNames
    ancestral_ranks = [5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30, 32, 33, '33_5', 34, '34_5', 35, 37, 40, 43, 44, 45, 47, 50, 53, 57, 60, 67, 70]
    for level in ancestral_ranks:
        safe_level = str(level).replace('.', '_')
        lxx_common_name_col = f"L{safe_level}_commonName"
        stmt_ancestor = text(f"""UPDATE "{TARGET_TABLE_NAME}" SET "{lxx_common_name_col}" = NULL;""")
        session.execute(stmt_ancestor)
    
    session.commit()
    logger.info("Finished clearing existing common names.")


def populate_common_names_in_expanded_taxa(session):
    logger.info(f"Populating 'commonName' in '{TARGET_TABLE_NAME}'...")
    
    # SQL to update the main commonName for each taxon in expanded_taxa
    # It joins expanded_taxa (aliased as et) with the crosswalk (xmap),
    # then with coldp_vernacular_name (cvn)
    # It selects the preferred English common name.
    update_main_common_name_sql = text(f"""
    UPDATE "{TARGET_TABLE_NAME}" AS et
    SET "commonName" = cvn.name
    FROM inat_to_coldp_taxon_map AS xmap
    JOIN coldp_vernacular_name AS cvn ON xmap.col_taxon_id = cvn."taxonID"
    WHERE et."taxonID" = xmap.inat_taxon_id
      AND cvn.language = 'eng' 
      AND cvn.preferred = TRUE;
    """)
    
    result = session.execute(update_main_common_name_sql)
    session.commit()
    logger.info(f"Populated 'commonName' for {result.rowcount} direct taxa in '{TARGET_TABLE_NAME}'.")

    logger.info(f"Populating ancestral 'LXX_commonName' fields in '{TARGET_TABLE_NAME}'...")
    ancestral_ranks = [5, 10, 11, 12, 13, 15, 20, 24, 25, 26, 27, 30, 32, 33, '33_5', 34, '34_5', 35, 37, 40, 43, 44, 45, 47, 50, 53, 57, 60, 67, 70]
    
    total_ancestor_updates = 0
    for level in ancestral_ranks:
        safe_level = str(level).replace('.', '_')
        lxx_taxon_id_col = f"L{safe_level}_taxonID"
        lxx_common_name_col = f"L{safe_level}_commonName"

        update_ancestor_common_name_sql = text(f"""
        UPDATE "{TARGET_TABLE_NAME}" AS et
        SET "{lxx_common_name_col}" = cvn.name
        FROM inat_to_coldp_taxon_map AS xmap
        JOIN coldp_vernacular_name AS cvn ON xmap.col_taxon_id = cvn."taxonID"
        WHERE et."{lxx_taxon_id_col}" = xmap.inat_taxon_id
          AND cvn.language = 'eng'
          AND cvn.preferred = TRUE
          AND et."{lxx_taxon_id_col}" IS NOT NULL; 
        """)
        # The 'et."{lxx_taxon_id_col}" IS NOT NULL' is important as that column can be NULL.
        
        logger.debug(f"Executing update for {lxx_common_name_col}...")
        result_ancestor = session.execute(update_ancestor_common_name_sql)
        session.commit() # Commit after each rank level for large tables
        logger.info(f"Populated '{lxx_common_name_col}' for {result_ancestor.rowcount} ancestral links.")
        total_ancestor_updates += result_ancestor.rowcount
        
    logger.info(f"Finished populating ancestral common names. Total updates made: {total_ancestor_updates}.")


def main():
    parser = argparse.ArgumentParser(description="Populate common names in the expanded_taxa table.")
    parser.add_argument("--db-user", default=os.getenv("DB_USER", "postgres"))
    parser.add_argument("--db-password", default=os.getenv("DB_PASSWORD", "password"))
    parser.add_argument("--db-host", default=os.getenv("DB_HOST", "localhost"))
    parser.add_argument("--db-port", default=os.getenv("DB_PORT", "5432"))
    parser.add_argument("--db-name", default=os.getenv("DB_NAME", "ibrida-v0-r1"))
    parser.add_argument("--clear-first", action="store_true", help="Clear existing common names before populating.")

    args = parser.parse_args()

    engine = get_db_engine(args.db_user, args.db_password, args.db_host, args.db_port, args.db_name)
    Session = sessionmaker(bind=engine)
    session = Session()

    try:
        if args.clear_first:
            clear_existing_common_names(session)
        populate_common_names_in_expanded_taxa(session)
        logger.info("Common name population process completed successfully.")
    except Exception as e:
        logger.error(f"An error occurred: {e}")
        session.rollback()
    finally:
        session.close()

if __name__ == "__main__":
    main()
