Okay, great! We have a clear path forward.

Here's the implementation plan for the Python scripts and the wrapper, broken down into the phases we discussed.

**Assumed Directory Structure for Python code:**

```
ibridaDB/
├── scripts/
│   └── ingest_coldp/
│       ├── __init__.py
│       ├── load_tables.py           # Phase 1, Step 4
│       ├── map_taxa.py              # Phase 2, Step 1
│       ├── populate_common_names.py # Phase 2, Step 2
│       └── wrapper_ingest_coldp.sh  # Phase 3, Step 1
└── models/
    ├── __init__.py
    ├── base.py                      # Defines SQLAlchemy Base
    ├── coldp_models.py              # ORMs for ColDP tables
    └── expanded_taxa_models.py      # ORM for expanded_taxa and expanded_taxa_cmn
```

**Phase 1, Step 4: `ibridaDB/scripts/ingest_coldp/load_tables.py`**

This script will load data from the ColDP `.tsv` files into newly created PostgreSQL tables, using the ORMs.

```python
# ibridaDB/scripts/ingest_coldp/load_tables.py
import argparse
import os
import pandas as pd
import csv
import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Assuming models are in a sibling directory 'models'
# Adjust import paths if your structure is different
from ibridaDB.models.base import Base
from ibridaDB.models.coldp_models import (
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
# Most are direct, but some might need explicit mapping if ORM field names differ significantly
# For now, we'll assume a simple prefix removal.
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
    # Create dummy model files if they don't exist for the script to run
    # In a real setup, these would be properly managed Python packages/modules
    MODELS_DIR = os.path.join(os.path.dirname(__file__), "..", "models")
    os.makedirs(MODELS_DIR, exist_ok=True)
    
    # Dummy base.py
    if not os.path.exists(os.path.join(MODELS_DIR, "base.py")):
        with open(os.path.join(MODELS_DIR, "base.py"), "w") as f:
            f.write("from sqlalchemy.ext.declarative import declarative_base\n")
            f.write("Base = declarative_base()\n")
            
    # Dummy __init__.py in models
    if not os.path.exists(os.path.join(MODELS_DIR, "__init__.py")):
        with open(os.path.join(MODELS_DIR, "__init__.py"), "w") as f:
            f.write("# Models __init__\n")
            f.write("from .base import Base\n")
            f.write("from .coldp_models import *\n") # Ensure coldp_models.py is also created
            f.write("from .expanded_taxa_models import *\n")

    # Dummy __init__.py in scripts.ingest_coldp
    SCRIPTS_INGEST_COLDP_DIR = os.path.dirname(__file__)
    if not os.path.exists(os.path.join(SCRIPTS_INGEST_COLDP_DIR, "__init__.py")):
        with open(os.path.join(SCRIPTS_INGEST_COLDP_DIR, "__init__.py"), "w") as f:
            f.write("# Scripts __init__\n")
            
    # Dummy __init__.py in scripts
    SCRIPTS_DIR = os.path.join(SCRIPTS_INGEST_COLDP_DIR, "..")
    if not os.path.exists(os.path.join(SCRIPTS_DIR, "__init__.py")):
        with open(os.path.join(SCRIPTS_DIR, "__init__.py"), "w") as f:
            f.write("# Scripts __init__\n")

    # Dummy __init__.py in ibridaDB (root of models/scripts)
    IBRIDADB_DIR = os.path.join(SCRIPTS_DIR, "..")
    if not os.path.exists(os.path.join(IBRIDADB_DIR, "__init__.py")):
         with open(os.path.join(IBRIDADB_DIR, "__init__.py"), "w") as f:
            f.write("# ibridaDB __init__\n")


    # Create dummy coldp_models.py if it doesn't exist
    if not os.path.exists(os.path.join(MODELS_DIR, "coldp_models.py")):
        with open(os.path.join(MODELS_DIR, "coldp_models.py"), "w") as f:
            f.write("from sqlalchemy import Column, String, Text, Boolean, Date, Numeric, Integer, Float\n")
            f.write("from .base import Base\n\n")
            # Paste the ORM definitions here from your previous response
            f.write("""
class ColdpVernacularName(Base):
    __tablename__ = "coldp_vernacular_name"
    _synthetic_id   = Column("id", Integer, primary_key=True, autoincrement=True)
    taxonID         = Column("taxonID", String(64), index=True) 
    name            = Column("name", Text, nullable=False) 
    language        = Column("language", String(3), index=True) 
    sourceID        = Column("sourceID", String(64))
    transliteration = Column("transliteration", Text)
    preferred       = Column("preferred", Boolean)
    country         = Column("country", String(2))
    area            = Column("area", Text)
    sex             = Column("sex", String(20))
    referenceID     = Column("referenceID", String(64))
    remarks         = Column("remarks", Text)

class ColdpDistribution(Base):
    __tablename__ = "coldp_distribution"
    id              = Column("id", Integer, primary_key=True, autoincrement=True)
    taxonID         = Column("taxonID", String(64), index=True)
    sourceID        = Column("sourceID", String(64))
    areaID          = Column("areaID", String(64))
    area            = Column("area", Text)
    gazetteer       = Column("gazetteer", String(50))
    status          = Column("status", String(50))
    referenceID     = Column("referenceID", String(64))
    remarks         = Column("remarks", Text)

class ColdpMedia(Base):
    __tablename__ = "coldp_media"
    id              = Column("id", Integer, primary_key=True, autoincrement=True)
    taxonID         = Column("taxonID", String(64), index=True)
    sourceID        = Column("sourceID", String(64))
    url             = Column("url", Text, nullable=False)
    type            = Column("type", String(50))
    format          = Column("format", String(100))
    title           = Column("title", Text)
    created         = Column("created", String(50))
    creator         = Column("creator", Text)
    license         = Column("license", String(100))
    link            = Column("link", Text)
    remarks         = Column("remarks", Text)

class ColdpReference(Base):
    __tablename__ = "coldp_reference"
    ID              = Column("ID", String(255), primary_key=True)
    alternativeID   = Column("alternativeID", Text)
    sourceID        = Column("sourceID", String(64))
    citation        = Column("citation", Text)
    type            = Column("type", String(50))
    author          = Column("author", Text)
    editor          = Column("editor", Text)
    title           = Column("title", Text)
    titleShort      = Column("titleShort", Text)
    containerAuthor = Column("containerAuthor", Text)
    containerTitle  = Column("containerTitle", Text)
    containerTitleShort = Column("containerTitleShort", Text)
    issued          = Column("issued", String(50))
    accessed        = Column("accessed", String(50))
    collectionTitle = Column("collectionTitle", Text)
    collectionEditor= Column("collectionEditor", Text)
    volume          = Column("volume", String(50))
    issue           = Column("issue", String(50))
    edition         = Column("edition", String(50))
    page            = Column("page", String(100))
    publisher       = Column("publisher", Text)
    publisherPlace  = Column("publisherPlace", Text)
    version         = Column("version", String(50))
    isbn            = Column("isbn", String(30))
    issn            = Column("issn", String(30))
    doi             = Column("doi", String(100))
    link            = Column("link", Text)
    remarks         = Column("remarks", Text)

class ColdpTypeMaterial(Base):
    __tablename__ = "coldp_type_material"
    ID                = Column("ID", String(255), primary_key=True)
    nameID            = Column("nameID", String(64), index=True, nullable=False)
    sourceID          = Column("sourceID", String(64))
    citation          = Column("citation", Text)
    status            = Column("status", String(50))
    referenceID       = Column("referenceID", String(64))
    page              = Column("page", String(50))
    country           = Column("country", String(2))
    locality          = Column("locality", Text)
    latitude          = Column("latitude", Float)
    longitude         = Column("longitude", Float)
    altitude          = Column("altitude", String(50))
    sex               = Column("sex", String(20))
    host              = Column("host", Text)
    associatedSequences = Column("associatedSequences", Text)
    date              = Column("date", String(50))
    collector         = Column("collector", Text)
    institutionCode   = Column("institutionCode", String(50))
    catalogNumber     = Column("catalogNumber", String(100))
    link              = Column("link", Text)
    remarks           = Column("remarks", Text)

class ColdpNameUsage(Base):
    __tablename__ = "coldp_name_usage_staging"
    ID = Column("ID", String(64), primary_key=True)
    # Minimal other columns for mapping
    scientificName = Column("scientificName", Text, index=True)
    authorship = Column("authorship", Text)
    rank = Column("rank", String(50), index=True)
    status = Column("status", String(50), index=True)
    parentID = Column("parentID", String(64))
    # Add any other columns from NameUsage.tsv that are needed for mapping/disambiguation
    # For example, 'uninomial', 'genus', 'specificEpithet', 'infraspecificEpithet'
    # from ColDP spec can be useful for robust name parsing and matching.
    # For now, keeping it minimal.
    uninomial = Column("uninomial", Text)
    genericName = Column("genericName", Text) # Note: ColDP uses 'genus' for genus part of binomial
    infragenericEpithet = Column("infragenericEpithet", Text)
    specificEpithet = Column("specificEpithet", Text)
    infraspecificEpithet = Column("infraspecificEpithet", Text)
    basionymID = Column("basionymID", String(64))
    # ... any other fields from NameUsage.tsv you might want to stage
""")

    # Dummy expanded_taxa_models.py
    if not os.path.exists(os.path.join(MODELS_DIR, "expanded_taxa_models.py")):
         with open(os.path.join(MODELS_DIR, "expanded_taxa_models.py"), "w") as f:
            f.write("from sqlalchemy import Column, Integer, String, Text, Boolean, Float, Index\n")
            f.write("from .base import Base\n\n")
            # Paste the ExpandedTaxaCmn ORM here
            f.write("""
class ExpandedTaxaCmn(Base):
    __tablename__ = "expanded_taxa_cmn"
    taxonID       = Column("taxonID", Integer, primary_key=True, nullable=False)
    rankLevel     = Column("rankLevel", Float, index=True)
    rank          = Column("rank", String(255))
    name          = Column("name", String(255), index=True)
    commonName    = Column("commonName", String(255))
    taxonActive   = Column("taxonActive", Boolean, index=True)
    L5_taxonID    = Column("L5_taxonID", Integer)
    L5_name       = Column("L5_name", Text)
    L5_commonName = Column("L5_commonName", String(255))
    L10_taxonID    = Column("L10_taxonID", Integer, index=True)
    L10_name       = Column("L10_name", Text)
    L10_commonName = Column("L10_commonName", String(255))
    L11_taxonID    = Column("L11_taxonID", Integer)
    L11_name       = Column("L11_name", Text)
    L11_commonName = Column("L11_commonName", String(255))
    L12_taxonID    = Column("L12_taxonID", Integer)
    L12_name       = Column("L12_name", Text)
    L12_commonName = Column("L12_commonName", String(255))
    L13_taxonID    = Column("L13_taxonID", Integer)
    L13_name       = Column("L13_name", Text)
    L13_commonName = Column("L13_commonName", String(255))
    L15_taxonID    = Column("L15_taxonID", Integer)
    L15_name       = Column("L15_name", Text)
    L15_commonName = Column("L15_commonName", String(255))
    L20_taxonID    = Column("L20_taxonID", Integer, index=True)
    L20_name       = Column("L20_name", Text)
    L20_commonName = Column("L20_commonName", String(255))
    L24_taxonID    = Column("L24_taxonID", Integer)
    L24_name       = Column("L24_name", Text)
    L24_commonName = Column("L24_commonName", String(255))
    L25_taxonID    = Column("L25_taxonID", Integer)
    L25_name       = Column("L25_name", Text)
    L25_commonName = Column("L25_commonName", String(255))
    L26_taxonID    = Column("L26_taxonID", Integer)
    L26_name       = Column("L26_name", Text)
    L26_commonName = Column("L26_commonName", String(255))
    L27_taxonID    = Column("L27_taxonID", Integer)
    L27_name       = Column("L27_name", Text)
    L27_commonName = Column("L27_commonName", String(255))
    L30_taxonID    = Column("L30_taxonID", Integer, index=True)
    L30_name       = Column("L30_name", Text)
    L30_commonName = Column("L30_commonName", String(255))
    L32_taxonID    = Column("L32_taxonID", Integer)
    L32_name       = Column("L32_name", Text)
    L32_commonName = Column("L32_commonName", String(255))
    L33_taxonID    = Column("L33_taxonID", Integer)
    L33_name       = Column("L33_name", Text)
    L33_commonName = Column("L33_commonName", String(255))
    L33_5_taxonID    = Column("L33_5_taxonID", Integer)
    L33_5_name       = Column("L33_5_name", Text)
    L33_5_commonName = Column("L33_5_commonName", String(255))
    L34_taxonID    = Column("L34_taxonID", Integer)
    L34_name       = Column("L34_name", Text)
    L34_commonName = Column("L34_commonName", String(255))
    L34_5_taxonID    = Column("L34_5_taxonID", Integer)
    L34_5_name       = Column("L34_5_name", Text)
    L34_5_commonName = Column("L34_5_commonName", String(255))
    L35_taxonID    = Column("L35_taxonID", Integer)
    L35_name       = Column("L35_name", Text)
    L35_commonName = Column("L35_commonName", String(255))
    L37_taxonID    = Column("L37_taxonID", Integer)
    L37_name       = Column("L37_name", Text)
    L37_commonName = Column("L37_commonName", String(255))
    L40_taxonID    = Column("L40_taxonID", Integer, index=True)
    L40_name       = Column("L40_name", Text)
    L40_commonName = Column("L40_commonName", String(255))
    L43_taxonID    = Column("L43_taxonID", Integer)
    L43_name       = Column("L43_name", Text)
    L43_commonName = Column("L43_commonName", String(255))
    L44_taxonID    = Column("L44_taxonID", Integer)
    L44_name       = Column("L44_name", Text)
    L44_commonName = Column("L44_commonName", String(255))
    L45_taxonID    = Column("L45_taxonID", Integer)
    L45_name       = Column("L45_name", Text)
    L45_commonName = Column("L45_commonName", String(255))
    L47_taxonID    = Column("L47_taxonID", Integer)
    L47_name       = Column("L47_name", Text)
    L47_commonName = Column("L47_commonName", String(255))
    L50_taxonID    = Column("L50_taxonID", Integer, index=True)
    L50_name       = Column("L50_name", Text)
    L50_commonName = Column("L50_commonName", String(255))
    L53_taxonID    = Column("L53_taxonID", Integer)
    L53_name       = Column("L53_name", Text)
    L53_commonName = Column("L53_commonName", String(255))
    L57_taxonID    = Column("L57_taxonID", Integer)
    L57_name       = Column("L57_name", Text)
    L57_commonName = Column("L57_commonName", String(255))
    L60_taxonID    = Column("L60_taxonID", Integer, index=True)
    L60_name       = Column("L60_name", Text)
    L60_commonName = Column("L60_commonName", String(255))
    L67_taxonID    = Column("L67_taxonID", Integer)
    L67_name       = Column("L67_name", Text)
    L67_commonName = Column("L67_commonName", String(255))
    L70_taxonID    = Column("L70_taxonID", Integer, index=True)
    L70_name       = Column("L70_name", Text)
    L70_commonName = Column("L70_commonName", String(255))
""")
    main()
```

**Phase 2, Step 1: `ibridaDB/scripts/ingest_coldp/map_taxa.py`**

This script implements the mapping recipe.

```python
# ibridaDB/scripts/ingest_coldp/map_taxa.py
import argparse
import os
import pandas as pd
import logging
from sqlalchemy import create_engine, Column, Integer, String, Float, Index, Text, ForeignKey
from sqlalchemy.orm import sessionmaker, relationship
from sqlalchemy.ext.declarative import declarative_base

from ibridaDB.models.base import Base # Assumes Base = declarative_base() is in base.py
from ibridaDB.models.expanded_taxa_models import ExpandedTaxaCmn # Target for common names
from ibridaDB.models.coldp_models import ColdpNameUsage # Staging table for ColDP names

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- ORM for the crosswalk table ---
class InatToColdpMap(Base):
    __tablename__ = "inat_to_coldp_taxon_map"
    inat_taxon_id = Column(Integer, ForeignKey(f'{ExpandedTaxaCmn.__tablename__}."taxonID"'), primary_key=True)
    col_taxon_id = Column(String(64), ForeignKey(f'{ColdpNameUsage.__tablename__}."ID"'), primary_key=True) # From ColDP NameUsage.ID
    
    match_type = Column(String(50), nullable=False) # e.g., 'exact_name_rank', 'exact_name_only', 'fuzzy_name'
    match_score = Column(Float, nullable=True)
    inat_scientific_name = Column(Text)
    col_scientific_name = Column(Text)

    # Relationships (optional but good practice)
    # inat_taxon = relationship("ExpandedTaxaCmn") # If ExpandedTaxaCmn is the ORM for your main taxa table
    # col_name_usage = relationship("ColdpNameUsage")


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

def perform_mapping(session):
    logger.info("Starting iNaturalist to ColDP taxon mapping process...")

    # 0. Clear existing mapping data
    logger.info("Clearing existing data from 'inat_to_coldp_taxon_map'...")
    session.query(InatToColdpMap).delete(synchronize_session=False)
    session.commit()

    # 1. Load iNat taxa data (from expanded_taxa, which should be the table ExpandedTaxaCmn ORM points to)
    logger.info("Loading iNaturalist taxa from 'expanded_taxa' table...")
    # We use the table name directly if ExpandedTaxaCmn ORM points to "expanded_taxa_cmn"
    # If ExpandedTaxaCmn ORM points to "expanded_taxa", then use that.
    # The user's prompt says the ORM for "expanded_taxa_cmn" will be ExpandedTaxaCmn.
    # The user also said they modified expand_taxa.sh to add commonName to "expanded_taxa"
    # This implies "expanded_taxa" is the table we are populating. Let's assume the ORM
    # provided as dbTools/taxa/models/expanded_taxa.py (class ExpandedTaxa) is the one for "expanded_taxa".
    # For clarity, let's rename the ORM in this script to reflect it's iNat source.
    
    # Path to the actual iNat taxa table:
    # The user confirmed `expanded_taxa.py` ORM maps to the table `expanded_taxa`
    # So, we should query that table for iNat names.
    # For common name population, the target table is `expanded_taxa` as well.
    # The ORM provided in `dbTools/taxa/models/expanded_taxa.py` is called `ExpandedTaxa`
    
    from ibridaDB.models.expanded_taxa_models import ExpandedTaxa # User confirmed this maps to 'expanded_taxa'

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
    coldp_names_df = pd.read_sql_query(
        session.query(ColdpNameUsage.ID, ColdpNameUsage.scientificName, ColdpNameUsage.rank, ColdpNameUsage.status)
               .statement, # Add .filter(ColdpNameUsage.status == 'accepted') if desired here
        session.bind
    )
    coldp_names_df.rename(columns={'ID': 'col_taxon_id', 'scientificName': 'col_scientific_name', 'rank': 'col_rank', 'status': 'col_status'}, inplace=True)
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
                'inat_taxon_id': row['inat_taxon_id_x'], # Pandas appends _x, _y on merge
                'col_taxon_id': row['col_taxon_id'],
                'match_type': 'exact_name_only_accepted' if row['col_status'] == 'accepted' else 'exact_name_only_other_status',
                'match_score': 0.95, # Slightly lower score than name+rank
                'inat_scientific_name': row['inat_scientific_name_x'],
                'col_scientific_name': row['col_scientific_name']
            })
        logger.info(f"Found {len(merged_exact_name_only_unique)} matches on name only.")
        inat_taxa_df = inat_taxa_df[~inat_taxa_df['inat_taxon_id'].isin(merged_exact_name_only_unique['inat_taxon_id_x'])]

    # --- Step 5: Fuzzy Match (Optional, using RapidFuzz or similar) ---
    # This step is more involved and requires careful tuning.
    # For now, we'll skip it to keep the initial script simpler.
    # If implementing, use `rapidfuzz.process.extractOne`
    # CLAUDE: ADD TO TODO, add print statements to gather context needed to implement the precise matching logics
    if not inat_taxa_df.empty:
        logger.info(f"{len(inat_taxa_df)} iNat taxa remain unmatched after exact methods.")
        # Placeholder for fuzzy matching logic
        # from rapidfuzz import process, fuzz
        # choices = coldp_names_df['norm_col_name'].dropna().unique().tolist()
        # for index, irow in inat_taxa_df.iterrows():
        #     if not irow['norm_inat_name'] or not choices:
        #         continue
        #     # Consider only accepted names from ColDP for fuzzy matching to reduce noise
        #     accepted_coldp_names_df = coldp_names_df[coldp_names_df['col_status'] == 'accepted']
        #     accepted_choices = accepted_coldp_names_df['norm_col_name'].dropna().unique().tolist()
        #     if not accepted_choices: continue

        #     match = process.extractOne(irow['norm_inat_name'], accepted_choices, scorer=fuzz.WRatio, score_cutoff=90)
        #     if match:
        #         matched_col_name, score, _ = match
        #         # Find the col_taxon_id for this matched_col_name
        #         col_entry = accepted_coldp_names_df[accepted_coldp_names_df['norm_col_name'] == matched_col_name].iloc[0]
        #         all_mappings.append({
        #             'inat_taxon_id': irow['inat_taxon_id'],
        #             'col_taxon_id': col_entry['col_taxon_id'],
        #             'match_type': 'fuzzy_name_accepted',
        #             'match_score': score / 100.0,
        #             'inat_scientific_name': irow['inat_scientific_name'],
        #             'col_scientific_name': col_entry['col_scientific_name']
        #         })
        # logger.info("Fuzzy matching (stub) completed.")


    # --- Step 6: Persist mappings ---
    if all_mappings:
        logger.info(f"Bulk inserting {len(all_mappings)} mappings into 'inat_to_coldp_taxon_map'...")
        session.bulk_insert_mappings(InatToColdpMap, all_mappings)
        session.commit()
        logger.info("Successfully populated 'inat_to_coldp_taxon_map'.")
    else:
        logger.info("No mappings found to insert.")


def main():
    parser = argparse.ArgumentParser(description="Map iNaturalist taxa to ColDP taxa.")
    parser.add_argument("--db-user", default=os.getenv("DB_USER", "postgres"))
    parser.add_argument("--db-password", default=os.getenv("DB_PASSWORD", "password"))
    parser.add_argument("--db-host", default=os.getenv("DB_HOST", "localhost"))
    parser.add_argument("--db-port", default=os.getenv("DB_PORT", "5432"))
    parser.add_argument("--db-name", default=os.getenv("DB_NAME", "ibrida-v0-r1"))
    args = parser.parse_args()

    engine = get_db_engine(args.db_user, args.db_password, args.db_host, args.db_port, args.db_name)
    create_crosswalk_table(engine) # Ensure table exists

    Session = sessionmaker(bind=engine)
    session = Session()

    try:
        perform_mapping(session)
    except Exception as e:
        logger.error(f"An error occurred during the mapping process: {e}")
        session.rollback()
    finally:
        session.close()

if __name__ == "__main__":
    # Dummy model/script __init__ creations (same as in load_tables.py)
    MODELS_DIR = os.path.join(os.path.dirname(__file__), "..", "models")
    os.makedirs(MODELS_DIR, exist_ok=True)
    if not os.path.exists(os.path.join(MODELS_DIR, "base.py")):
        with open(os.path.join(MODELS_DIR, "base.py"), "w") as f: f.write("from sqlalchemy.ext.declarative import declarative_base\nBase = declarative_base()\n")
    if not os.path.exists(os.path.join(MODELS_DIR, "__init__.py")):
        with open(os.path.join(MODELS_DIR, "__init__.py"), "w") as f: f.write("from .base import Base\nfrom .coldp_models import *\nfrom .expanded_taxa_models import *\n")
    if not os.path.exists(os.path.join(MODELS_DIR, "expanded_taxa_models.py")): # Create if missing
        with open(os.path.join(MODELS_DIR, "expanded_taxa_models.py"), "w") as f:
             f.write("from sqlalchemy import Column, Integer, String, Text, Boolean, Float, Index\n")
             f.write("from .base import Base\n\n")
             f.write("class ExpandedTaxaCmn(Base):\n    __tablename__ = \"expanded_taxa_cmn\"\n    taxonID = Column(Integer, primary_key=True)\n    # Add other fields if needed for testing\n")
             f.write("class ExpandedTaxa(Base):\n    __tablename__ = \"expanded_taxa\"\n    taxonID = Column(Integer, primary_key=True)\n    name = Column(String)\n    rank = Column(String)\n    taxonActive = Column(Boolean)\n    # Add other fields if needed for testing\n") # Simplified for dummy
    if not os.path.exists(os.path.join(MODELS_DIR, "coldp_models.py")): # Create if missing
        with open(os.path.join(MODELS_DIR, "coldp_models.py"), "w") as f:
             f.write("from sqlalchemy import Column, Integer, String, Text, Boolean, Float\n")
             f.write("from .base import Base\n\n")
             f.write("class ColdpNameUsage(Base):\n    __tablename__ = \"coldp_name_usage_staging\"\n    ID = Column(String, primary_key=True)\n    scientificName = Column(Text)\n    rank = Column(String)\n    status = Column(String)\n    # Add other fields if needed for testing\n")


    SCRIPTS_INGEST_COLDP_DIR = os.path.dirname(__file__)
    if not os.path.exists(os.path.join(SCRIPTS_INGEST_COLDP_DIR, "__init__.py")):
        with open(os.path.join(SCRIPTS_INGEST_COLDP_DIR, "__init__.py"), "w") as f: f.write("\n")
    SCRIPTS_DIR = os.path.join(SCRIPTS_INGEST_COLDP_DIR, "..")
    if not os.path.exists(os.path.join(SCRIPTS_DIR, "__init__.py")):
        with open(os.path.join(SCRIPTS_DIR, "__init__.py"), "w") as f: f.write("\n")
    IBRIDADB_DIR = os.path.join(SCRIPTS_DIR, "..")
    if not os.path.exists(os.path.join(IBRIDADB_DIR, "__init__.py")):
         with open(os.path.join(IBRIDADB_DIR, "__init__.py"), "w") as f: f.write("\n")

    main()
```

**Phase 2, Step 2: `ibridaDB/scripts/ingest_coldp/populate_common_names.py`**

This script updates the `commonName` and `LXX_commonName` fields in your main `expanded_taxa` table.

```python
# ibridaDB/scripts/ingest_coldp/populate_common_names.py
import argparse
import os
import logging
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# Assuming models are in a sibling directory 'models'
# We don't strictly need the ORMs for direct SQL execution, but good for context.
# from ibridaDB.models.expanded_taxa_models import ExpandedTaxa # Your ORM for expanded_taxa
# from ibridaDB.scripts.ingest_coldp.map_taxa import InatToColdpMap # Crosswalk ORM
# from ibridaDB.models.coldp_models import ColdpVernacularName

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
    # Dummy model/script __init__ creations (same as in load_tables.py and map_taxa.py)
    MODELS_DIR = os.path.join(os.path.dirname(__file__), "..", "models")
    os.makedirs(MODELS_DIR, exist_ok=True)
    if not os.path.exists(os.path.join(MODELS_DIR, "base.py")):
        with open(os.path.join(MODELS_DIR, "base.py"), "w") as f: f.write("from sqlalchemy.ext.declarative import declarative_base\nBase = declarative_base()\n")
    if not os.path.exists(os.path.join(MODELS_DIR, "__init__.py")):
        with open(os.path.join(MODELS_DIR, "__init__.py"), "w") as f: f.write("from .base import Base\nfrom .coldp_models import *\nfrom .expanded_taxa_models import *\n")
    if not os.path.exists(os.path.join(MODELS_DIR, "expanded_taxa_models.py")): 
        with open(os.path.join(MODELS_DIR, "expanded_taxa_models.py"), "w") as f:
             f.write("from sqlalchemy import Column, Integer, String, Text, Boolean, Float, Index\n")
             f.write("from .base import Base\n\n")
             f.write("class ExpandedTaxa(Base):\n    __tablename__ = \"expanded_taxa\"\n    taxonID = Column(Integer, primary_key=True)\n    # Add other fields if needed for testing\n") 

    SCRIPTS_INGEST_COLDP_DIR = os.path.dirname(__file__)
    if not os.path.exists(os.path.join(SCRIPTS_INGEST_COLDP_DIR, "__init__.py")):
        with open(os.path.join(SCRIPTS_INGEST_COLDP_DIR, "__init__.py"), "w") as f: f.write("\n")
    SCRIPTS_DIR = os.path.join(SCRIPTS_INGEST_COLDP_DIR, "..")
    if not os.path.exists(os.path.join(SCRIPTS_DIR, "__init__.py")):
        with open(os.path.join(SCRIPTS_DIR, "__init__.py"), "w") as f: f.write("\n")
    IBRIDADB_DIR = os.path.join(SCRIPTS_DIR, "..")
    if not os.path.exists(os.path.join(IBRIDADB_DIR, "__init__.py")):
         with open(os.path.join(IBRIDADB_DIR, "__init__.py"), "w") as f: f.write("\n")

    main()
```

**Phase 3, Step 1: `ibridaDB/scripts/ingest/coldp/wrapper_ingest_coldp.sh`**

```bash
#!/bin/bash
# ibridaDB/scripts/ingest_coldp/wrapper_ingest_coldp.sh

# This wrapper orchestrates the ingestion of Catalogue of Life Data Package (ColDP)
# data into the ibridaDB. It loads raw ColDP tables, maps iNaturalist taxon IDs
# to ColDP taxon IDs, and then populates common name fields in the expanded_taxa table.

set -euo pipefail # Exit on error, undefined variable, or pipe failure

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${SCRIPT_DIR}/wrapper_ingest_coldp_$(date +%Y%m%d_%H%M%S).log"

# --- Configuration ---
# These can be overridden by environment variables if needed
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-password}" # Be cautious with passwords in scripts; use env vars or secrets manager in prod
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-ibrida-v0-r1}" # Target ibridaDB database

COLDP_DATA_DIR="${COLDP_DATA_DIR:-/datasets/taxa/catalogue_of_life/2024/ColDP}" # Path to unzipped ColDP files

PYTHON_EXE="${PYTHON_EXE:-python3}" # Path to python executable if not in PATH or using venv
## NOTE: Use venv interpreter at /home/caleb/repo/ibridaDB/.venv/bin/python

# --- Logging ---
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "Starting ColDP Ingestion Wrapper at $(date)"
echo "--------------------------------------------------"
echo "Configuration:"
echo "  DB User: ${DB_USER}"
echo "  DB Host: ${DB_HOST}"
echo "  DB Port: ${DB_PORT}"
echo "  DB Name: ${DB_NAME}"
echo "  ColDP Data Dir: ${COLDP_DATA_DIR}"
echo "  Python Executable: ${PYTHON_EXE}"
echo "  Log File: ${LOG_FILE}"
echo "--------------------------------------------------"

# --- Helper function to run Python scripts ---
run_python_script() {
    local script_name="$1"
    local script_path="${SCRIPT_DIR}/${script_name}.py"
    
    echo ""
    echo ">>> Running ${script_name}.py..."
    if [ ! -f "${script_path}" ]; then
        echo "ERROR: Python script not found: ${script_path}"
        exit 1
    fi

    # Pass database connection details as arguments
    "${PYTHON_EXE}" "${script_path}" \
        --coldp-dir "${COLDP_DATA_DIR}" \
        --db-user "${DB_USER}" \
        --db-password "${DB_PASSWORD}" \
        --db-host "${DB_HOST}" \
        --db-port "${DB_PORT}" \
        --db-name "${DB_NAME}" \
        "$@" # Pass through any additional arguments for the specific script
    
    if [ $? -ne 0 ]; then
        echo "ERROR: ${script_name}.py failed. Check logs above."
        exit 1
    fi
    echo ">>> Finished ${script_name}.py successfully."
}

# --- Main Orchestration ---

# Step 1: Load raw ColDP tables
# The load_tables.py script handles table creation and data loading from TSVs.
run_python_script "load_tables"
# No extra args needed for load_tables beyond the defaults passed by run_python_script

# Step 2: Map iNaturalist taxon IDs to ColDP taxon IDs
# This creates and populates the 'inat_to_coldp_taxon_map' table.
run_python_script "map_taxa"
# No extra args needed for map_taxa

# Step 3: Populate common names in the expanded_taxa table
# This uses the mapping table and vernacular names to update expanded_taxa.
# Adding --clear-first will wipe existing common names before populating.
run_python_script "populate_common_names" --clear-first

echo "--------------------------------------------------"
echo "ColDP Ingestion Wrapper finished successfully at $(date)."
echo "--------------------------------------------------"

exit 0
```

**Phase 3, Step 2: Documentation Updates**

1.  **`ibridaDB/docs/schemas.md`**:
    *   Add new sections for `coldp_name_usage_staging`, `coldp_vernacular_name`, `coldp_distribution`, `coldp_media`, `coldp_reference`, `coldp_type_material`, and `inat_to_coldp_taxon_map`. Include column names, types, and brief descriptions.
    *   Update the `expanded_taxa` section to note the presence and source of `commonName` and `LXX_commonName` fields.
2.  **`ibridaDB/docs/coldp_integration.md`**:
    *   Create this new file.
    *   Describe the purpose: integrating ColDP to enrich `ibridaDB`, primarily with common names.
    *   Outline the ColDP files used (`NameUsage.tsv`, `VernacularName.tsv`, etc.).
    *   Detail the mapping strategy (`inat_to_coldp_taxon_map` creation).
    *   Explain how common names are selected (preferred, English) and populated into `expanded_taxa`.
    *   Provide instructions on how to run `wrapper_ingest_coldp.sh`, including prerequisites (ColDP data path, DB credentials).
    *   List the new tables created and their purpose.

This set of scripts and documentation should provide a robust pipeline for integrating ColDP data. Remember to make the Python scripts executable (`chmod +x *.py`) and ensure necessary Python packages (`pandas`, `sqlalchemy`, `psycopg2-binary`) are installed in the environment where these scripts will run.Excellent! This is a comprehensive set of scripts and a solid plan. I've reviewed them and incorporated them into my local `ibridaDB` repository structure.

Here's a summary of the files created and their locations, based on your plan:

**Python Model Files (under `ibridaDB/models/`)**

1.  **`ibridaDB/models/base.py`**:
    ```python
    from sqlalchemy.ext.declarative import declarative_base
    Base = declarative_base()
    ```
2.  **`ibridaDB/models/coldp_models.py`**: Contains `ColdpVernacularName`, `ColdpDistribution`, `ColdpMedia`, `ColdpReference`, `ColdpTypeMaterial`, and `ColdpNameUsage` ORMs as you provided.
3.  **`ibridaDB/models/expanded_taxa_models.py`**: Contains the `ExpandedTaxaCmn` ORM (which will target the `expanded_taxa` table after we confirm its schema includes the top-level `commonName` and all `LXX_commonName` columns, which are populated by `expand_taxa.sh` and then updated by `populate_common_names.py`) and the `ExpandedTaxa` ORM (mapping to the table `expanded_taxa` as generated by `expand_taxa.sh`). *Self-correction: `ExpandedTaxaCmn` as an ORM name for the table `expanded_taxa` is fine. The key is that the `__tablename__` attribute in the ORM matches the actual table name in PostgreSQL.*

    *Self-correction based on your latest update*: The `ExpandedTaxaCmn` ORM is intended for a *new* table `expanded_taxa_cmn`. The existing `expanded_taxa` table (mapped by `ExpandedTaxa` ORM) has had the `commonName` (top-level) column added manually and `LXX_commonName` columns added by `expand_taxa.sh`. The `populate_common_names.py` script will update *these existing columns* in the `expanded_taxa` table directly. So, we will primarily work with the `ExpandedTaxa` ORM for the common name population step, ensuring it reflects the schema of the `expanded_taxa` table after `expand_taxa.sh` and your manual `ALTER TABLE`.

    Therefore, the `ExpandedTaxaCmn` ORM and the associated idea of creating a *separate* `expanded_taxa_cmn` table can be set aside. We will directly populate the `commonName` and `LXX_commonName` fields within the existing `expanded_taxa` table. The `populate_common_names.py` script's target table name will be `expanded_taxa`.

4.  **`ibridaDB/models/__init__.py`**:
    ```python
    from .base import Base
    from .coldp_models import (
        ColdpVernacularName,
        ColdpDistribution,
        ColdpMedia,
        ColdpReference,
        ColdpTypeMaterial,
        ColdpNameUsage
    )
    from .expanded_taxa_models import ExpandedTaxa # Assuming this is the ORM for "expanded_taxa" table
                                                 # and it includes commonName and LXX_commonName attributes.
    # Add InatToColdpMap when defined in map_taxa.py or a similar models file
    # from .crosswalk_models import InatToColdpMap 

    __all__ = [
        'Base',
        'ColdpVernacularName', 'ColdpDistribution', 'ColdpMedia',
        'ColdpReference', 'ColdpTypeMaterial', 'ColdpNameUsage',
        'ExpandedTaxa',
        # 'InatToColdpMap',
    ]
    ```

**Python Ingestion Scripts (under `ibridaDB/scripts/ingest_coldp/`)**

1.  **`ibridaDB/scripts/ingest_coldp/__init__.py`** (empty)
2.  **`ibridaDB/scripts/ingest_coldp/load_tables.py`** (as provided by you, loads ColDP TSVs into new PG tables).
3.  **`ibridaDB/scripts/ingest_coldp/map_taxa.py`** (as provided by you, creates and populates `inat_to_coldp_taxon_map`).
4.  **`ibridaDB/scripts/ingest_coldp/populate_common_names.py`** (as provided by you, updates `commonName` and `LXX_commonName` in the `expanded_taxa` table).
5.  **`ibridaDB/scripts/ingest_coldp/wrapper_ingest_coldp.sh`** (as provided by you, orchestrates the Python scripts).

**Shell Script Modification**

*   **`ibridaDB/dbTools/taxa/expand/expand_taxa.sh`**:
    *   Confirmed: I have already modified this script to add `ADD COLUMN "commonName" VARCHAR(255),` during the `CREATE TABLE "expanded_taxa"` step. The `LXX_commonName` columns were already being added. These will all be `NULL` initially.

**Next Steps & Readiness:**

1.  **Verify Python Environment**: I will ensure `pandas`, `sqlalchemy`, and `psycopg2-binary` are available in the Python environment where these scripts will be executed.
2.  **Database Credentials & ColDP Path**: I will set the necessary environment variables (`DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `COLDP_DATA_DIR`) before running the `wrapper_ingest_coldp.sh` script.
    Note: *COLDP_DATA_DIR* contents shared below. Other env vars can be found in one of many wrapper bashfiles in this repo.
3.  **Initial Run**: I will execute `wrapper_ingest_coldp.sh`.
    *   Expected outcome:
        *   New tables (`coldp_name_usage_staging`, `coldp_vernacular_name`, etc.) created and populated.
        *   The `inat_to_coldp_taxon_map` table created and populated.
        *   The `commonName` and `LXX_commonName` columns in the existing `expanded_taxa` table populated with preferred English common names.
4.  **Review and Verification**:
    *   Check logs for errors.
    *   Query the new tables and the updated `expanded_taxa` table to verify data integrity and the correctness of common name population.
    *   Pay close attention to the number of matches in `inat_to_coldp_taxon_map` and how many `expanded_taxa` rows received common names.
5.  **Documentation**: Once verified, I will proceed with drafting/updating the documentation files (`schemas.md` and `coldp_integration.md`).


COLDP_DATA_DIR: `/datasets/taxa/catalogue_of_life/2024/ColDP`
```bash
caleb@blade:/datasets/taxa/catalogue_of_life/2024/ColDP$ ls
Distribution.tsv  Media.tsv      NameRelation.tsv  reference.json  source               SpeciesInteraction.tsv    TaxonProperty.tsv  VernacularName.tsv
logo.png          metadata.yaml  NameUsage.tsv     Reference.tsv   SpeciesEstimate.tsv  TaxonConceptRelation.tsv  TypeMaterial.tsv
caleb@blade:/datasets/taxa/catalogue_of_life/2024/ColDP$ ls source
1005.yaml  1032.yaml  1053.yaml  1080.yaml  1093.yaml  1107.yaml  1124.yaml  1138.yaml  1152.yaml  1168.yaml  1180.yaml  1193.yaml  1204.yaml    2141.yaml    2317.yaml
1008.yaml  1033.yaml  1054.yaml  1081.yaml  1094.yaml  1108.yaml  1125.yaml  1139.yaml  1153.yaml  1169.yaml  1181.yaml  1194.yaml  1206.yaml    2144.yaml    2362.yaml
1010.yaml  1037.yaml  1055.yaml  1082.yaml  1095.yaml  1109.yaml  1126.yaml  1140.yaml  1154.yaml  1170.yaml  1182.yaml  1195.yaml  124661.yaml  219318.yaml  265709.yaml
1011.yaml  1039.yaml  1058.yaml  1085.yaml  1096.yaml  1110.yaml  1127.yaml  1141.yaml  1157.yaml  1171.yaml  1183.yaml  1196.yaml  125101.yaml  2207.yaml    268676.yaml
1014.yaml  1042.yaml  1059.yaml  1086.yaml  1099.yaml  1112.yaml  1128.yaml  1142.yaml  1158.yaml  1172.yaml  1184.yaml  1197.yaml  1502.yaml    2232.yaml    279229.yaml
1021.yaml  1044.yaml  1061.yaml  1087.yaml  1100.yaml  1113.yaml  1129.yaml  1143.yaml  1161.yaml  1173.yaml  1185.yaml  1198.yaml  170394.yaml  2256.yaml    296427.yaml
1026.yaml  1046.yaml  1062.yaml  1088.yaml  1101.yaml  1118.yaml  1130.yaml  1144.yaml  1162.yaml  1175.yaml  1186.yaml  1199.yaml  185410.yaml  2299.yaml    298081.yaml
1027.yaml  1048.yaml  1065.yaml  1089.yaml  1103.yaml  1119.yaml  1131.yaml  1146.yaml  1163.yaml  1176.yaml  1188.yaml  1200.yaml  2004.yaml    2300.yaml    54170.yaml
1029.yaml  1049.yaml  1068.yaml  1090.yaml  1104.yaml  1120.yaml  1132.yaml  1148.yaml  1164.yaml  1177.yaml  1190.yaml  1201.yaml  2007.yaml    2301.yaml    55353.yaml
1030.yaml  1050.yaml  1070.yaml  1091.yaml  1105.yaml  1122.yaml  1133.yaml  1149.yaml  1166.yaml  1178.yaml  1191.yaml  1202.yaml  2073.yaml    2302.yaml    55434.yaml
1031.yaml  1052.yaml  1078.yaml  1092.yaml  1106.yaml  1123.yaml  1134.yaml  1150.yaml  1167.yaml  1179.yaml  1192.yaml  1203.yaml  2130.yaml    2304.yaml
```