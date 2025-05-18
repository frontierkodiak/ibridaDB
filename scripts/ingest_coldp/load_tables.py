#!/usr/bin/env python3

import argparse
import os
import pandas as pd
import csv
import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Import models from the top-level models directory
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from models.base import Base
from models.coldp_models import (
    ColdpNameUsage,
    ColdpVernacularName,
    ColdpDistribution,
    ColdpMedia,
    ColdpReference,
    ColdpTypeMaterial
)

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# --- Column Mappings (from 'col:FieldName' in TSV to 'fieldName' in ORM) ---
COLDP_TSV_FILES_AND_MODELS = {
    "NameUsage.tsv": ColdpNameUsage,
    "VernacularName.tsv": ColdpVernacularName,
    "Distribution.tsv": ColdpDistribution,
    "Media.tsv": ColdpMedia,
    "Reference.tsv": ColdpReference,
    "TypeMaterial.tsv": ColdpTypeMaterial,
}

def get_db_engine(db_user, db_password, db_host, db_port, db_name):
    connection_string = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    return create_engine(connection_string)

def create_schemas(engine):
    logger.info("Creating ColDP tables in the database (if they don't exist)...")
    tables_to_create = [
        model.__table__ for model in COLDP_TSV_FILES_AND_MODELS.values()
    ]
    Base.metadata.create_all(engine, tables=tables_to_create, checkfirst=True)
    logger.info("ColDP table schemas ensured.")

def clean_column_name(col_name, prefix="col:"):
    if col_name.startswith(prefix):
        return col_name[len(prefix):]
    return col_name

def safe_bool_convert(value):
    if isinstance(value, str):
        val_lower = value.lower()
        if val_lower == 'true':
            return True
        elif val_lower == 'false':
            return False
    elif isinstance(value, bool):
        return value
    return None # Or raise error, or return default

def load_table_from_tsv(session, model_class, tsv_path, col_prefix="col:"):
    logger.info(f"Loading data for {model_class.__tablename__} from {tsv_path}...")
    if not os.path.exists(tsv_path):
        logger.error(f"TSV file not found: {tsv_path}")
        return

    try:
        # Read with dtype=str to handle various inputs, convert specific columns later
        df = pd.read_csv(
            tsv_path,
            sep='\t',
            header=0,
            quoting=csv.QUOTE_NONE,
            dtype=str, # Read all as string initially
            keep_default_na=False,
            na_values=['', 'NA', 'N/A', '#N/A'] # Define what pandas should see as NaN
        )

        # Clean column names (e.g., 'col:taxonID' -> 'taxonID')
        df.columns = [clean_column_name(col, prefix=col_prefix) for col in df.columns]

        # Convert to None where appropriate (pandas reads empty strings as '', not NaN with keep_default_na=False)
        df = df.replace({ '': None })


        # --- Specific Column Type Conversions ---
        # Example for boolean columns (adjust based on your actual ColDP files/models)
        if model_class == ColdpVernacularName:
            if 'preferred' in df.columns:
                df['preferred'] = df['preferred'].apply(safe_bool_convert)
        
        # Example for numeric types (float, integer) - pandas might infer some, but explicit is safer
        # For SQLAlchemy, None will be interpreted as SQL NULL.
        # SQLAlchemy will handle type conversion for basic types like int, float if pandas df has them as objects
        # that can be cast. For stricter control, cast in pandas:
        # if 'latitude' in df.columns and model_class == ColdpTypeMaterial:
        #     df['latitude'] = pd.to_numeric(df['latitude'], errors='coerce') # Coerce will turn errors to NaT/NaN

        # Clear existing data from the table
        logger.info(f"Clearing existing data from {model_class.__tablename__}...")
        session.query(model_class).delete(synchronize_session=False)
        
        records = df.to_dict(orient='records')
        
        if records:
            logger.info(f"Bulk inserting {len(records)} records into {model_class.__tablename__}...")
            session.bulk_insert_mappings(model_class, records)
            session.commit()
            logger.info(f"Successfully loaded data into {model_class.__tablename__}.")
        else:
            logger.info(f"No records to load for {model_class.__tablename__}.")

    except Exception as e:
        session.rollback()
        logger.error(f"Error loading data for {model_class.__tablename__} from {tsv_path}: {e}")
        raise

def main():
    parser = argparse.ArgumentParser(description="Load ColDP TSV data into PostgreSQL database.")
    parser.add_argument("--coldp-dir", required=True, help="Path to the unzipped ColDP directory.")
    parser.add_argument("--db-user", default=os.getenv("DB_USER", "postgres"), help="Database user.")
    parser.add_argument("--db-password", default=os.getenv("DB_PASSWORD", "password"), help="Database password.")
    parser.add_argument("--db-host", default=os.getenv("DB_HOST", "localhost"), help="Database host.")
    parser.add_argument("--db-port", default=os.getenv("DB_PORT", "5432"), help="Database port.")
    parser.add_argument("--db-name", default=os.getenv("DB_NAME", "ibrida-v0-r1"), help="Database name.")
    args = parser.parse_args()

    engine = get_db_engine(args.db_user, args.db_password, args.db_host, args.db_port, args.db_name)
    
    # 1. Create table schemas
    create_schemas(engine)

    Session = sessionmaker(bind=engine)
    session = Session()

    try:
        # 2. Load data for each table
        for tsv_file, model_cls in COLDP_TSV_FILES_AND_MODELS.items():
            full_tsv_path = os.path.join(args.coldp_dir, tsv_file)
            load_table_from_tsv(session, model_cls, full_tsv_path)
        logger.info("All ColDP tables loaded successfully.")
    except Exception as e:
        logger.error(f"An error occurred during the loading process: {e}")
    finally:
        session.close()

if __name__ == "__main__":
    main()
