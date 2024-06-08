import pandas as pd
import argparse
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from model import TaxaExpanded, Base
from tqdm import tqdm

# Define the rank level to rank name mapping
code_to_name = {
    'L5': 'subspecies',
    'L10': 'species',
    'L11': 'complex',
    'L12': 'subsection', 
    'L13': 'section',
    'L15': 'subgenus',
    'L20': 'genus',
    'L24': 'subtribe',
    'L25': 'tribe',
    'L26': 'supertribe',
    'L27': 'subfamily',
    'L30': 'family',
    'L32': 'epifamily',
    'L33': 'superfamily',
    'L33_5': 'zoosubsection',
    'L34': 'zoosection',
    'L34_5': 'parvorder',
    'L35': 'infraorder',
    'L37': 'suborder',
    'L40': 'order',
    'L43': 'superorder',
    'L44': 'subterclass',
    'L45': 'infraclass',
    'L47': 'subclass',
    'L50': 'class',
    'L53': 'superclass',
    'L57': 'subphylum',
    'L60': 'phylum',
    'L67': 'subkingdom',
    'L70': 'kingdom',
    'L100': 'stateofmatter'
}

# Create a mapping from rank_level int to rank name
rank_level_to_name = {int(k[1:]): v for k, v in code_to_name.items()}

def process_row(row):
    return TaxaExpanded(
        taxon_id=row['taxonID'],
        name=row['name'],
        common_name=row['commonName'],  # This will be empty for now
        rank=rank_level_to_name.get(row['rank'], ''),
        rank_level=row['rank'],
        taxon_active=row['taxon_active'] == 't',  # Convert to boolean
        L5_taxon_id=row['L5_taxonID'],
        L5_name=row['L5_name'],
        L5_common_name=row['L5_commonName'],
        L10_taxon_id=row['L10_taxonID'],
        L10_name=row['L10_name'],
        L10_common_name=row['L10_commonName'],
        L11_taxon_id=row['L11_taxonID'],
        L11_name=row['L11_name'],
        L11_common_name=row['L11_commonName'],
        L12_taxon_id=row['L12_taxonID'],
        L12_name=row['L12_name'],
        L12_common_name=row['L12_commonName'],
        L13_taxon_id=row['L13_taxonID'],
        L13_name=row['L13_name'],
        L13_common_name=row['L13_commonName'],
        L15_taxon_id=row['L15_taxonID'],
        L15_name=row['L15_name'],
        L15_common_name=row['L15_commonName'],
        L20_taxon_id=row['L20_taxonID'],
        L20_name=row['L20_name'],
        L20_common_name=row['L20_commonName'],
        L24_taxon_id=row['L24_taxonID'],
        L24_name=row['L24_name'],
        L24_common_name=row['L24_commonName'],
        L25_taxon_id=row['L25_taxonID'],
        L25_name=row['L25_name'],
        L25_common_name=row['L25_commonName'],
        L26_taxon_id=row['L26_taxonID'],
        L26_name=row['L26_name'],
        L26_common_name=row['L26_commonName'],
        L27_taxon_id=row['L27_taxonID'],
        L27_name=row['L27_name'],
        L27_common_name=row['L27_commonName'],
        L30_taxon_id=row['L30_taxonID'],
        L30_name=row['L30_name'],
        L30_common_name=row['L30_commonName'],
        L32_taxon_id=row['L32_taxonID'],
        L32_name=row['L32_name'],
        L32_common_name=row['L32_commonName'],
        L33_taxon_id=row['L33_taxonID'],
        L33_name=row['L33_name'],
        L33_common_name=row['L33_commonName'],
        L33_5_taxon_id=row['L33_5_taxonID'],
        L33_5_name=row['L33_5_name'],
        L33_5_common_name=row['L33_5_commonName'],
        L34_taxon_id=row['L34_taxonID'],
        L34_name=row['L34_name'],
        L34_common_name=row['L34_commonName'],
        L34_5_taxon_id=row['L34_5_taxonID'],
        L34_5_name=row['L34_5_name'],
        L34_5_common_name=row['L34_5_commonName'],
        L35_taxon_id=row['L35_taxonID'],
        L35_name=row['L35_name'],
        L35_common_name=row['L35_commonName'],
        L37_taxon_id=row['L37_taxonID'],
        L37_name=row['L37_name'],
        L37_common_name=row['L37_commonName'],
        L40_taxon_id=row['L40_taxonID'],
        L40_name=row['L40_name'],
        L40_common_name=row['L40_commonName'],
        L43_taxon_id=row['L43_taxonID'],
        L43_name=row['L43_name'],
        L43_common_name=row['L43_commonName'],
        L44_taxon_id=row['L44_taxonID'],
        L44_name=row['L44_name'],
        L44_common_name=row['L44_commonName'],
        L45_taxon_id=row['L45_taxonID'],
        L45_name=row['L45_name'],
        L45_common_name=row['L45_commonName'],
        L47_taxon_id=row['L47_taxonID'],
        L47_name=row['L47_name'],
        L47_common_name=row['L47_commonName'],
        L50_taxon_id=row['L50_taxonID'],
        L50_name=row['L50_name'],
        L50_common_name=row['L50_commonName'],
        L53_taxon_id=row['L53_taxonID'],
        L53_name=row['L53_name'],
        L53_common_name=row['L53_commonName'],
        L57_taxon_id=row['L57_taxonID'],
        L57_name=row['L57_name'],
        L57_common_name=row['L57_commonName'],
        L60_taxon_id=row['L60_taxonID'],
        L60_name=row['L60_name'],
        L60_common_name=row['L60_commonName'],
        L67_taxon_id=row['L67_taxonID'],
        L67_name=row['L67_name'],
        L67_common_name=row['L67_commonName'],
        L70_taxon_id=row['L70_taxonID'],
        L70_name=row['L70_name'],
        L70_common_name=row['L70_commonName'],
        L100_taxon_id=row['L100_taxonID'],
        L100_name=row['L100_name'],
        L100_common_name=row['L100_commonName']
    )

def main(csv_path, db_url, drop_existing):
    # Database setup
    engine = create_engine(db_url)
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()

    # Drop existing rows if specified
    if drop_existing:
        session.query(TaxaExpanded).delete()
        session.commit()

    # Read the CSV file
    df = pd.read_csv(csv_path)

    # Add the rank column based on rank_level
    df['rank'] = df['rank'].apply(lambda x: rank_level_to_name.get(x, ''))

    # Populate the table
    for _, row in tqdm(df.iterrows(), total=len(df)):
        taxa_expanded = process_row(row)
        session.add(taxa_expanded)

    # Commit the session to save the data
    session.commit()

    # Close the session
    session.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Populate taxa_expanded table from CSV.")
    parser.add_argument('--csv_path', type=str, default='/pond/Polli/Assets/Taxonomy/expanded_taxa.csv', help='Path to the input CSV file.')
    parser.add_argument('--db_url', type=str, default='postgresql://postgres:password@localhost:5432/postgres', help='Database connection URL.')
    parser.add_argument('--drop_existing', action='store_true', help='Drop existing rows in the taxa_expanded table before adding new rows.')

    args = parser.parse_args()
    main(args.csv_path, args.db_url, args.drop_existing)
