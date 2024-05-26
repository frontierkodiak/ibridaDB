"""
Script: add_ancestry_to_jsonl.py

This script adds ancestral taxonomy information to a JSONL file containing image records.

Usage:
    python add_ancestry_to_jsonl.py --input_file <input_file> --output_file <output_file> [--redis_host <host>] [--redis_port <port>] [--redis_db <db>]

Arguments:
    --input_file (str): Path to the input JSONL file
    --output_file (str): Path to the output JSONL file
    --redis_host (str): Redis host (default: "localhost")
    --redis_port (int): Redis port (default: 6379)
    --redis_db (int): Redis database (default: 0)

Description:
    This script reads an input JSONL file containing image records and adds ancestral taxonomy information to each record.
    The ancestral taxonomy is retrieved from a Redis taxa database based on the 'ancestry' field in each image record.

    The script performs the following steps:
        1. Establishes a connection to the Redis taxa database using the provided connection details.
        2. Reads the input JSONL file line by line.
        3. For each line (image record):
            - Loads the JSON record.
            - Retrieves the 'ancestry' field from the record and removes it.
            - Calls the `get_ancestral_taxonomy` function to fetch the ancestral taxonomy from Redis using the ancestry string.
            - Creates a new record by merging the original image record with the ancestral taxonomy.
            - Writes the new record to the output JSONL file.

    The `get_ancestral_taxonomy` function takes the Redis client and the ancestry string as input.
    It splits the ancestry string by '/' to get the ancestral taxon IDs. For each taxon ID:
        - Retrieves the taxon information from Redis using the taxon ID.
        - Extracts the rank and constructs the level key (e.g., "L10", "L20", etc.).
        - Adds the taxon ID and name to the ancestral taxonomy dictionary using the level key.

    The script outputs a new JSONL file with the full ancestral taxonomy added to each image record.
    The ancestral taxonomy includes the taxon IDs and names for each available level.

Note:
    - The script requires a Redis taxa database with the necessary taxon information.
    - Make sure to provide the correct Redis connection details (host, port, db).
    - The input JSONL file should contain image records with an 'ancestry' field containing the ancestral taxon IDs.

Output:
    - A JSONL file with the full ancestral taxonomy added to each image record.
"""

import argparse
import json
import redis
from tqdm import tqdm

def get_ancestral_taxonomy(redis_client, ancestry_str):
    ancestral_taxonomy = {}
    ancestral_taxon_ids = ancestry_str.split('/')
    for taxon_id in ancestral_taxon_ids:
        taxon_id = int(taxon_id)
        taxon_info = redis_client.hgetall(f"taxon:{taxon_id}")
        if taxon_info:
            taxon_info = {k.decode('utf-8'): v.decode('utf-8') for k, v in taxon_info.items()}
            rank = int(taxon_info['rank'])
            level_key = f"L{rank}"
            ancestral_taxonomy[level_key] = {
                f"{level_key}_taxonID": taxon_id,
                f"{level_key}_name": taxon_info['name']
            }
    return ancestral_taxonomy

def main(args):
    redis_client = redis.Redis(host=args.redis_host, port=args.redis_port, db=args.redis_db)

    with open(args.input_file, 'r') as input_file, open(args.output_file, 'w') as output_file:
        lines = input_file.readlines()
        for line in tqdm(lines, desc="Processing records"):
            image_record = json.loads(line)
            ancestry_str = image_record.pop('ancestry', '')
            ancestral_taxonomy = get_ancestral_taxonomy(redis_client, ancestry_str)

            new_record = {
                **image_record,
                **ancestral_taxonomy
            }

            output_file.write(json.dumps(new_record) + '\n')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Add ancestral taxonomy to JSONL file')
    parser.add_argument('--input_file', required=True, help='Path to input JSONL file')
    parser.add_argument('--output_file', required=True, help='Path to output JSONL file')
    parser.add_argument('--redis_host', default='localhost', help='Redis host')
    parser.add_argument('--redis_port', default=6379, type=int, help='Redis port')
    parser.add_argument('--redis_db', default=0, type=int, help='Redis database')
    args = parser.parse_args()

    main(args)