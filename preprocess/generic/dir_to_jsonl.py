'''
Script: dir_to_jsonl.py

This script generates a JSONL mapping of image files to their corresponding taxon information.

Parses a sorted dir, where:
    - folders have names L<rank_level>_<genus>_<?species>_<?subspecies>
    - files have names <genus>_<?species>_<?subspecies>_<id>_<position>.<extension>

Usage:
    python dir_to_jsonl.py --db-user <username> --db-password <password> --db-host <host> --db-port <port> --db-name <database>

Arguments:
    --db-user (str): Database username (default: "postgres")
    --db-password (str): Database password (default: "password")
    --db-host (str): Database host (default: "localhost")
    --db-port (str): Database port (default: "5432")
    --db-name (str): Database name (default: "postgres")

Description:
    This script iterates through the subdirectories and files in a specified base directory ("/pond/Polli/Datasets/anthophila/imgs")
    and generates a JSONL mapping of each image file to its corresponding taxon information.

    The script assumes that the subdirectories have a specific naming convention: "L<rank_level>_<genus>_<?species>_<?subspecies>",
    where "L<rank_level>" represents the taxonomic rank level of the subdirectory.

    For each image file, the script extracts the taxon name by splitting the filename and joining the name parts.
    It then queries the PostgreSQL database to retrieve the taxon ID, base name, base level, and ancestry based on the taxon name and rank level.

    If a matching taxon is found, the script adds an entry to the JSONL mapping with the following information:
        - file_path: Absolute path to the image file
        - base_taxonID: Base taxon ID of the image
        - base_name: Base name of the taxon
        - base_level: Base taxonomic rank level
        - position: Position extracted from the filename
        - ancestry: Ancestry of the taxon (comma-separated list of ancestral taxon IDs)

    The JSONL mapping is saved to the specified output file ("/pond/Polli/Datasets/anthophila/image_mapping.jsonl").

Note:
    - The script requires a PostgreSQL database with the necessary tables and data.
    - Make sure to replace the placeholders in the database connection parameters with the appropriate values.
    - The script assumes a specific directory structure and naming convention for the image files and subdirectories.

Output:
    - A JSONL file containing the mapping of image files to their corresponding taxon information.
'''

import os
import json
from tqdm import tqdm
import argparse
from sqlalchemy import create_engine, Column, Integer, String, Boolean, Float
from sqlalchemy.orm import sessionmaker, declarative_base


Base = declarative_base()
class Taxa(Base):
    __tablename__ = 'taxa'
    taxon_id = Column(Integer, primary_key=True)
    ancestry = Column(String)
    rank_level = Column(Float)
    rank = Column(String)
    name = Column(String)
    active = Column(Boolean)
    origin = Column(String)
    
class CustomTqdm:
    def __init__(self, outer_iterable, inner_iterable, **tqdm_kwargs):
        self.outer_iterable = outer_iterable
        self.inner_iterable = inner_iterable
        self.tqdm_kwargs = tqdm_kwargs

    def __iter__(self):
        total = len(self.outer_iterable) * len(self.inner_iterable)
        with tqdm(total=total, **self.tqdm_kwargs) as pbar:
            for outer_item in self.outer_iterable:
                for inner_item in self.inner_iterable:
                    yield outer_item, inner_item
                    pbar.update(1)

def get_taxon_info(session, name, rank_level):
    taxon = session.query(Taxa).filter(Taxa.name == name, Taxa.rank_level == rank_level).first()
    if taxon:
        return taxon.taxon_id, taxon.name, taxon.rank_level, taxon.ancestry
    return None, None, None, None

def extract_position(filename):
    parts = filename.split('_')
    if len(parts) >= 5:
        return int(parts[-2])
    return None

def generate_jsonl_mapping(base_dir, output_file, db_user, db_password, db_host, db_port, db_name):
    # Establish a connection to the PostgreSQL database
    engine = create_engine(f'postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}')
    Session = sessionmaker(bind=engine)
    session = Session()

    with open(output_file, 'w') as f:
        subdirs = [os.path.join(base_dir, d) for d in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, d))]
        files_dict = {subdir: os.listdir(subdir) for subdir in subdirs}

        for subdir, files in CustomTqdm(subdirs, files_dict.values(), desc="Processing directories and files"):
            rank_code = os.path.basename(subdir).split('_')[0]
            rank_level = int(rank_code[1:])

            for file in files:
                filename = os.path.splitext(file)[0]
                name_parts = filename.split('_')[:-2]  # Exclude the id and position parts
                name = ' '.join(name_parts)

                taxon_id, base_name, base_level, ancestry = get_taxon_info(session, name, rank_level)

                if taxon_id:
                    file_path = os.path.join(subdir, file)
                    position = extract_position(filename)

                    mapping = {
                        'file_path': file_path,
                        'base_taxonID': taxon_id,
                        'base_name': base_name,
                        'base_level': base_level,
                        'position': position,
                        'ancestry': ancestry
                    }

                    f.write(json.dumps(mapping) + '\n')

    session.close()

    print(f"JSONL mapping saved to {output_file}")

# Parse command line arguments
parser = argparse.ArgumentParser()
parser.add_argument("--db-user", default="postgres", help="Database user")
parser.add_argument("--db-password", default="password", help="Database password")
parser.add_argument("--db-host", default="localhost", help="Database host")
parser.add_argument("--db-port", default="5432", help="Database port")
parser.add_argument("--db-name", default="postgres", help="Database name")
args = parser.parse_args()

# Usage example
base_dir = "/pond/Polli/Datasets/anthophila/imgs"
output_file = "/pond/Polli/Datasets/anthophila/image_mapping.jsonl"

generate_jsonl_mapping(base_dir, output_file, args.db_user, args.db_password, args.db_host, args.db_port, args.db_name)