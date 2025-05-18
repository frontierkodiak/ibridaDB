import pandas as pd
import argparse
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from model import TaxaExpanded, Base
from tqdm import tqdm
import numpy as np

class RankMapper:
    def __init__(self):
        self.name_to_level = {
            'subspecies': 5,
            'species': 10,
            'complex': 11,
            'subsection': 12,
            'section': 13,
            'subgenus': 15,
            'genus': 20,
            'subtribe': 24,
            'tribe': 25,
            'supertribe': 26,
            'subfamily': 27,
            'family': 30,
            'epifamily': 32,
            'superfamily': 33,
            'zoosubsection': 33.5,
            'zoosection': 34,
            'parvorder': 34.5,
            'infraorder': 35,
            'suborder': 37,
            'order': 40,
            'superorder': 43,
            'subterclass': 44,
            'infraclass': 45,
            'subclass': 47,
            'class': 50,
            'superclass': 53,
            'subphylum': 57,
            'phylum': 60,
            'subkingdom': 67,
            'kingdom': 70,
            'stateofmatter': 100
        }
        # Reverse mapping from level to name, assuming unique levels for simplicity
        self.level_to_name = {v: k for k, v in self.name_to_level.items()}

    def get_level(self, name):
        return self.name_to_level.get(name, None)

    def get_name(self, level):
        return self.level_to_name.get(level, None)

def convert_to_int(value):
    try:
        return int(float(value)) if not pd.isna(value) else -1
    except ValueError:
        return -1
    
# Write row filter to check for bad data
## Filter from pd row before processing:
### 1. All of ancestral columns are nan
### 2. row['rank'] is nan
### 3. row['taxonID'] is nan
### 4. row['name'] is nan
### 6. row['taxon_active'] is nan or 'f'

def preprocess_row(row, debug=False):
    flags = {
        'all_ancestral_nan': False,
        'rank_nan': False,
        'taxonID_nan': False,
        'name_nan': False,
        'taxon_active_nan_or_f': False
    }

    # Define the ancestral columns and check if all are NaN
    ancestral_columns = ['L5_taxonID', 'L10_taxonID', 'L11_taxonID', 'L12_taxonID', 'L13_taxonID', 'L15_taxonID', 'L20_taxonID', 'L24_taxonID', 'L25_taxonID', 'L26_taxonID', 'L27_taxonID', 'L30_taxonID', 'L32_taxonID', 'L33_taxonID', 'L33_5_taxonID', 'L34_taxonID', 'L34_5_taxonID', 'L35_taxonID', 'L37_taxonID', 'L40_taxonID', 'L43_taxonID', 'L44_taxonID', 'L45_taxonID', 'L47_taxonID', 'L50_taxonID', 'L53_taxonID', 'L57_taxonID', 'L60_taxonID', 'L67_taxonID', 'L70_taxonID', 'L100_taxonID']
    if all(pd.isna(row[col]) for col in ancestral_columns):
        flags['all_ancestral_nan'] = True

    if pd.isna(row['rank']):
        flags['rank_nan'] = True

    if pd.isna(row['taxonID']):
        flags['taxonID_nan'] = True

    if pd.isna(row['name']):
        flags['name_nan'] = True

    if pd.isna(row['taxon_active']) or row['taxon_active'] == 'f':
        flags['taxon_active_nan_or_f'] = True

    if debug and any(flags.values()):
        print(f"Row skipped due to flags: {flags}")

    return not any(flags.values()), flags

def process_row(row, rank_mapper):
    debug = True
    rank_level = int(row['rank']) # Comes in like '20', goes out as int(20)
    rank_name = rank_mapper.get_name(rank_level) # this is for new column 'rank'
    if debug:
        print(f"computed: rank_level: {rank_level}, rank_name: {rank_name}")
        print(f"row['taxonID']: {row['taxonID']}, type: {type(row['taxonID'])}")
        print(f"row['name']: {row['name']}, type: {type(row['name'])}")
        print(f"row['commonName']: {row['commonName']}, type: {type(row['commonName'])}")
        print(f"row['taxon_active']: {row['taxon_active']}, type: {type(row['taxon_active'])}")
    return TaxaExpanded(
        taxon_id=row['taxonID'],
        name=row['name'],
        common_name=row['commonName'] if not pd.isna(row['commonName']) else None,
        rank=rank_name,
        rank_level=rank_level, # TODO: This needs to be int of row['rank'] (pre-conversion)
        taxon_active=row['taxon_active'] == 't',  # Convert to boolean
        L5_taxon_id=convert_to_int(row['L5_taxonID']),
        L5_name=row['L5_name'] if not pd.isna(row['L5_name']) else None,
        L5_common_name=row['L5_commonName'] if not pd.isna(row['L5_commonName']) else None,
        L10_taxon_id=convert_to_int(row['L10_taxonID']), # VERIFY root taxa is reflected in corresponding (by rank_level) ancestor cols
        L10_name=row['L10_name'] if not pd.isna(row['L10_name']) else None,
        L10_common_name=row['L10_commonName'] if not pd.isna(row['L10_commonName']) else None,
        L11_taxon_id=convert_to_int(row['L11_taxonID']),
        L11_name=row['L11_name'] if not pd.isna(row['L11_name']) else None,
        L11_common_name=row['L11_commonName'] if not pd.isna(row['L11_commonName']) else None,
        L12_taxon_id=convert_to_int(row['L12_taxonID']),
        L12_name=row['L12_name'] if not pd.isna(row['L12_name']) else None,
        L12_common_name=row['L12_commonName'] if not pd.isna(row['L12_commonName']) else None,
        L13_taxon_id=convert_to_int(row['L13_taxonID']),
        L13_name=row['L13_name'] if not pd.isna(row['L13_name']) else None,
        L13_common_name=row['L13_commonName'] if not pd.isna(row['L13_commonName']) else None,
        L15_taxon_id=convert_to_int(row['L15_taxonID']),
        L15_name=row['L15_name'] if not pd.isna(row['L15_name']) else None,
        L15_common_name=row['L15_commonName'] if not pd.isna(row['L15_commonName']) else None,
        L20_taxon_id=convert_to_int(row['L20_taxonID']),
        L20_name=row['L20_name'] if not pd.isna(row['L20_name']) else None,
        L20_common_name=row['L20_commonName'] if not pd.isna(row['L20_commonName']) else None,
        L24_taxon_id=convert_to_int(row['L24_taxonID']),
        L24_name=row['L24_name'] if not pd.isna(row['L24_name']) else None,
        L24_common_name=row['L24_commonName'] if not pd.isna(row['L24_commonName']) else None,
        L25_taxon_id=convert_to_int(row['L25_taxonID']),
        L25_name=row['L25_name'] if not pd.isna(row['L25_name']) else None,
        L25_common_name=row['L25_commonName'] if not pd.isna(row['L25_commonName']) else None,
        L26_taxon_id=convert_to_int(row['L26_taxonID']),
        L26_name=row['L26_name'] if not pd.isna(row['L26_name']) else None,
        L26_common_name=row['L26_commonName'] if not pd.isna(row['L26_commonName']) else None,
        L27_taxon_id=convert_to_int(row['L27_taxonID']),
        L27_name=row['L27_name'] if not pd.isna(row['L27_name']) else None,
        L27_common_name=row['L27_commonName'] if not pd.isna(row['L27_commonName']) else None,
        L30_taxon_id=convert_to_int(row['L30_taxonID']),
        L30_name=row['L30_name'] if not pd.isna(row['L30_name']) else None,
        L30_common_name=row['L30_commonName'] if not pd.isna(row['L30_commonName']) else None,
        L32_taxon_id=convert_to_int(row['L32_taxonID']),
        L32_name=row['L32_name'] if not pd.isna(row['L32_name']) else None,
        L32_common_name=row['L32_commonName'] if not pd.isna(row['L32_commonName']) else None,
        L33_taxon_id=convert_to_int(row['L33_taxonID']),
        L33_name=row['L33_name'] if not pd.isna(row['L33_name']) else None,
        L33_common_name=row['L33_commonName'] if not pd.isna(row['L33_commonName']) else None,
        L33_5_taxon_id=convert_to_int(row['L33_5_taxonID']),
        L33_5_name=row['L33_5_name'] if not pd.isna(row['L33_5_name']) else None,
        L33_5_common_name=row['L33_5_commonName'] if not pd.isna(row['L33_5_commonName']) else None,
        L34_taxon_id=convert_to_int(row['L34_taxonID']),
        L34_name=row['L34_name'] if not pd.isna(row['L34_name']) else None,
        L34_common_name=row['L34_commonName'] if not pd.isna(row['L34_commonName']) else None,
        L34_5_taxon_id=convert_to_int(row['L34_5_taxonID']),
        L34_5_name=row['L34_5_name'] if not pd.isna(row['L34_5_name']) else None,
        L34_5_common_name=row['L34_5_commonName'] if not pd.isna(row['L34_5_commonName']) else None,
        L35_taxon_id=convert_to_int(row['L35_taxonID']),
        L35_name=row['L35_name'] if not pd.isna(row['L35_name']) else None,
        L35_common_name=row['L35_commonName'] if not pd.isna(row['L35_commonName']) else None,
        L37_taxon_id=convert_to_int(row['L37_taxonID']),
        L37_name=row['L37_name'] if not pd.isna(row['L37_name']) else None,
        L37_common_name=row['L37_commonName'] if not pd.isna(row['L37_commonName']) else None,
        L40_taxon_id=convert_to_int(row['L40_taxonID']),
        L40_name=row['L40_name'] if not pd.isna(row['L40_name']) else None,
        L40_common_name=row['L40_commonName'] if not pd.isna(row['L40_commonName']) else None,
        L43_taxon_id=convert_to_int(row['L43_taxonID']),
        L43_name=row['L43_name'] if not pd.isna(row['L43_name']) else None,
        L43_common_name=row['L43_commonName'] if not pd.isna(row['L43_commonName']) else None,
        L44_taxon_id=convert_to_int(row['L44_taxonID']),
        L44_name=row['L44_name'] if not pd.isna(row['L44_name']) else None,
        L44_common_name=row['L44_commonName'] if not pd.isna(row['L44_commonName']) else None,
        L45_taxon_id=convert_to_int(row['L45_taxonID']),
        L45_name=row['L45_name'] if not pd.isna(row['L45_name']) else None,
        L45_common_name=row['L45_commonName'] if not pd.isna(row['L45_commonName']) else None,
        L47_taxon_id=convert_to_int(row['L47_taxonID']),
        L47_name=row['L47_name'] if not pd.isna(row['L47_name']) else None,
        L47_common_name=row['L47_commonName'] if not pd.isna(row['L47_commonName']) else None,
        L50_taxon_id=convert_to_int(row['L50_taxonID']),
        L50_name=row['L50_name'] if not pd.isna(row['L50_name']) else None,
        L50_common_name=row['L50_commonName'] if not pd.isna(row['L50_commonName']) else None,
        L53_taxon_id=convert_to_int(row['L53_taxonID']),
        L53_name=row['L53_name'] if not pd.isna(row['L53_name']) else None,
        L53_common_name=row['L53_commonName'] if not pd.isna(row['L53_commonName']) else None,
        L57_taxon_id=convert_to_int(row['L57_taxonID']),
        L57_name=row['L57_name'] if not pd.isna(row['L57_name']) else None,
        L57_common_name=row['L57_commonName'] if not pd.isna(row['L57_commonName']) else None,
        L60_taxon_id=convert_to_int(row['L60_taxonID']),
        L60_name=row['L60_name'] if not pd.isna(row['L60_name']) else None,
        L60_common_name=row['L60_commonName'] if not pd.isna(row['L60_commonName']) else None,
        L67_taxon_id=convert_to_int(row['L67_taxonID']),
        L67_name=row['L67_name'] if not pd.isna(row['L67_name']) else None,
        L67_common_name=row['L67_commonName'] if not pd.isna(row['L67_commonName']) else None,
        L70_taxon_id=convert_to_int(row['L70_taxonID']),
        L70_name=row['L70_name'] if not pd.isna(row['L70_name']) else None,
        L70_common_name=row['L70_commonName'] if not pd.isna(row['L70_commonName']) else None,
        L100_taxon_id=convert_to_int(row['L100_taxonID']),
        L100_name=row['L100_name'] if not pd.isna(row['L100_name']) else None,
        L100_common_name=row['L100_commonName'] if not pd.isna(row['L100_commonName']) else None
    )

def main(csv_path, db_url, drop_existing, debug=False):
    # Database setup
    engine = create_engine(db_url)
    Base.metadata.create_all(engine)
    rank_mapper = RankMapper()
    Session = sessionmaker(bind=engine)
    session = Session()

    # Drop existing rows if specified
    if drop_existing:
        session.query(TaxaExpanded).delete()
        session.commit()

    # Read the CSV file
    df = pd.read_csv(csv_path, dtype=str)  # Read all columns as strings to avoid dtype issues
    
    # Initialize flag counters
    flag_counters = {
        'all_ancestral_nan': 0,
        'rank_nan': 0,
        'taxonID_nan': 0,
        'name_nan': 0,
        'taxon_active_nan_or_f': 0
    }

    # Populate the table
    for _, row in tqdm(df.iterrows(), total=len(df)):
        process, flags = preprocess_row(row, debug)
        if process:
            taxa_expanded = process_row(row, rank_mapper)
            session.add(taxa_expanded)
        else:
            for key in flags:
                if flags[key]:
                    flag_counters[key] += 1

    if debug:
        print("Total flags triggered during preprocessing:", flag_counters)

    # Commit the session to save the data
    session.commit()

    # Close the session
    session.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Populate taxa_expanded table from CSV.")
    parser.add_argument('--csv_path', type=str, default='/pond/Polli/Assets/Taxonomy/expanded_taxa.csv', help='Path to the input CSV file.')
    parser.add_argument('--db_url', type=str, default='postgresql://postgres:password@localhost:5432/postgres', help='Database connection URL.')
    parser.add_argument('--drop_existing', action='store_true', help='Drop existing rows in the taxa_expanded table before adding new rows.')
    parser.add_argument('--debug', action='store_true', help='Run in debug mode.')

    args = parser.parse_args()
    
    if args.debug:
        args.db_url = "mysql+pymysql://polli:polli@localhost:3307/taxaDB"
        args.drop_existing = True
    
    main(args.csv_path, args.db_url, args.drop_existing, args.debug)
