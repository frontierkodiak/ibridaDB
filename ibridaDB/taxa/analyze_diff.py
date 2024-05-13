import os
import csv
import argparse
from sqlalchemy import create_engine, Column, Integer, String, Float, Date, Boolean, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from ibridaDB.schema import Observations, Photos, Taxa, TaxaTemp, Observers
from ibridaDB.taxa.analysis_utils import (
    count_new_taxa,
    count_deprecated_taxa,
    count_active_status_changes,
    count_name_changes,
    count_other_attribute_changes,
    count_observations_for_taxa,
    count_observations_for_common_taxa
)
import logging


# Setup basic configuration for logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')


def create_db_engine(db_user, db_password, db_host, db_port, db_name):
    connection_string = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    return create_engine(connection_string)


def create_temp_taxa_table(session):
    TaxaTemp.__table__.create(session.bind, checkfirst=True)


def drop_temp_taxa_table(session):
    TaxaTemp.__table__.drop(session.bind, checkfirst=True)


def load_temp_taxa_data(origin, session, csv_file_path):
    with open(csv_file_path, 'r') as f:
        next(f)  # Skip the header row
        reader = csv.reader(f, delimiter='\t', quotechar='\b')
        for row in reader:
            if len(row) < 6:
                logging.warning(f"Skipping incomplete row: {row}")
                continue
            try:
                new_taxa = TaxaTemp(
                    taxon_id=int(row[0]),
                    ancestry=row[1],
                    rank_level=float(row[2]) if row[2] else None,
                    rank=row[3],
                    name=row[4],
                    active=row[5].lower() == 'true'
                )
                session.add(new_taxa)
            except ValueError as e:
                logging.error(f"Error processing row {row}: {e}")
                session.rollback()
                continue
    session.commit()


def analyze_specific_taxa_changes(origin, session, taxa_groups):
    output_dir = f"diffs/{origin}"
    os.makedirs(output_dir, exist_ok=True)

    for rank_level, taxa_ids in taxa_groups.items():
        print(f"Analyzing changes for {rank_level} taxa...")
        with open(f"{output_dir}/{rank_level}_analysis.txt", "w") as f:
            f.write(f"Analysis for {rank_level} taxa:\n\n")

            for taxon_id in taxa_ids:
                print(f"Analyzing changes for taxon ID: {taxon_id}")
                f.write(f"Taxon ID: {taxon_id}\n")

                new_taxa_count = count_new_taxa(session, taxon_id)
                f.write(f"New taxa count: {new_taxa_count}\n")

                deprecated_taxa_count = count_deprecated_taxa(session, taxon_id)
                f.write(f"Deprecated taxa count: {deprecated_taxa_count}\n")

                active_status_changes_count = count_active_status_changes(session, taxon_id)
                f.write(f"Active status changes count: {active_status_changes_count}\n")

                name_changes_count = count_name_changes(session, taxon_id)
                f.write(f"Name changes count: {name_changes_count}\n")

                other_attribute_changes_count = count_other_attribute_changes(session, taxon_id)
                f.write(f"Other attribute changes count: {other_attribute_changes_count}\n")

                observations_new_taxa_count = count_observations_for_taxa(session, taxon_id, 'new')
                f.write(f"Observations with new taxa count: {observations_new_taxa_count}\n")

                observations_deprecated_taxa_count = count_observations_for_taxa(session, taxon_id, 'deprecated')
                f.write(f"Observations with deprecated taxa count: {observations_deprecated_taxa_count}\n")

                observations_active_status_changes_count = count_observations_for_taxa(session, taxon_id, 'active_status_changes')
                f.write(f"Observations with active status changes count: {observations_active_status_changes_count}\n")

                observations_common_new_taxa_count = count_observations_for_common_taxa(session, taxon_id, 'new')
                f.write(f"Observations with common new taxa count: {observations_common_new_taxa_count}\n")

                observations_common_deprecated_taxa_count = count_observations_for_common_taxa(session, taxon_id, 'deprecated')
                f.write(f"Observations with common deprecated taxa count: {observations_common_deprecated_taxa_count}\n")

                observations_common_active_status_changes_count = count_observations_for_common_taxa(session, taxon_id, 'active_status_changes')
                f.write(f"Observations with common active status changes count: {observations_common_active_status_changes_count}\n")

                f.write("\n")


def analyze_taxa_changes(origin, session, output_dir):
    print("Analyzing overall taxa changes...")
    
    print("Counting taxon IDs in the new taxa data...")
    new_taxon_count = session.query(TaxaTemp).count()
    with open(f"{output_dir}/new_taxon_count.csv", "w") as f:
        f.write(f"new_taxon_count\n{new_taxon_count}\n")

    print("Finding deprecated taxon IDs...")
    deprecated_taxon_ids = session.query(Taxa.taxon_id).filter(~Taxa.taxon_id.in_(session.query(TaxaTemp.taxon_id))).all()
    with open(f"{output_dir}/deprecated_taxon_ids.csv", "w") as f:
        f.write("taxon_id\n")
        for taxon_id in deprecated_taxon_ids:
            f.write(f"{taxon_id[0]}\n")

    print("Finding new taxon IDs...")
    new_taxon_ids = session.query(TaxaTemp.taxon_id, TaxaTemp.ancestry, TaxaTemp.rank_level, TaxaTemp.active).filter(~TaxaTemp.taxon_id.in_(session.query(Taxa.taxon_id))).all()
    with open(f"{output_dir}/new_taxon_ids.csv", "w") as f:
        f.write("taxon_id,ancestry,rank_level,active\n")
        for taxon_id, ancestry, rank_level, active in new_taxon_ids:
            f.write(f"{taxon_id},{ancestry},{rank_level},{active}\n")

    print("Finding taxon IDs with changed attributes...")
    changed_attributes = session.query(
        Taxa.taxon_id,
        Taxa.ancestry, TaxaTemp.ancestry,
        Taxa.rank_level, TaxaTemp.rank_level,
        Taxa.rank, TaxaTemp.rank,
        Taxa.name, TaxaTemp.name,
        Taxa.active, TaxaTemp.active
    ).join(TaxaTemp, Taxa.taxon_id == TaxaTemp.taxon_id).filter(
        (Taxa.ancestry != TaxaTemp.ancestry) |
        (Taxa.rank_level != TaxaTemp.rank_level) |
        (Taxa.rank != TaxaTemp.rank) |
        (Taxa.name != TaxaTemp.name) |
        (Taxa.active != TaxaTemp.active)
    ).all()

    with open(f"{output_dir}/changed_attributes.csv", "w") as f:
        f.write("taxon_id,existing_ancestry,new_ancestry,existing_rank_level,new_rank_level,existing_rank,new_rank,existing_name,new_name,existing_active,new_active\n")
        for row in changed_attributes:
            f.write(",".join(str(value) for value in row) + "\n")

    print("Listing taxon IDs with changed 'active' values...")
    active_status_changes = session.query(
        Taxa.taxon_id,
        Taxa.rank_level,
        Taxa.active,
        TaxaTemp.active
    ).join(TaxaTemp, Taxa.taxon_id == TaxaTemp.taxon_id).filter(
        Taxa.active != TaxaTemp.active
    ).all()

    with open(f"{output_dir}/active_status_changes.csv", "w") as f:
        f.write("taxon_id,rank_level,existing_active,new_active\n")
        for taxon_id, rank_level, existing_active, new_active in active_status_changes:
            f.write(f"{taxon_id},{rank_level},{existing_active},{new_active}\n")

    print("Listing taxon IDs with changed 'name' values...")
    name_changes = session.query(
        Taxa.taxon_id,
        Taxa.rank_level,
        Taxa.name,
        TaxaTemp.name
    ).join(TaxaTemp, Taxa.taxon_id == TaxaTemp.taxon_id).filter(
        Taxa.name != TaxaTemp.name
    ).all()

    with open(f"{output_dir}/name_changes.csv", "w") as f:
        f.write("taxon_id,rank_level,existing_name,new_name\n")
        for taxon_id, rank_level, existing_name, new_name in name_changes:
            f.write(f"{taxon_id},{rank_level},{existing_name},{new_name}\n")

    print("Counting observations with inactive taxon IDs...")
    inactive_observations_count = session.query(Observations).join(Taxa, Observations.taxon_id == Taxa.taxon_id).filter(Taxa.active == False).count()
    with open(f"{output_dir}/inactive_observations_count.csv", "w") as f:
        f.write(f"inactive_observations_count\n{inactive_observations_count}\n")


def main():
    parser = argparse.ArgumentParser(description="Analyze taxa changes between existing database and new CSV")
    parser.add_argument("--origin", required=True, help="Date code of the new taxa CSV (e.g., May2024)")
    parser.add_argument("--db-user", default="postgres", help="Database user")
    parser.add_argument("--db-password", default="password", help="Database password")
    parser.add_argument("--db-host", default="localhost", help="Database host")
    parser.add_argument("--db-port", default="5432", help="Database port")
    parser.add_argument("--db-name", default="postgres", help="Database name")
    parser.add_argument("--csv-file-path", help="Path to the new taxa CSV file")
    parser.add_argument("--use-existing-temp-table", action="store_true", help="Use existing TaxaTemp table instead of loading a new one")
    parser.add_argument("--clear-temp", action="store_true", help="Drop the existing TaxaTemp table if it exists")

    args = parser.parse_args()

    engine = create_db_engine(args.db_user, args.db_password, args.db_host, args.db_port, args.db_name)
    Session = sessionmaker(bind=engine)
    session = Session()

    if args.clear_temp:
        if args.use_existing_temp_table:
            logging.error("Cannot use both --clear-temp and --use-existing-temp-table flags together.")
            return
        drop_temp_taxa_table(session)
        create_temp_taxa_table(session)
        if args.csv_file_path:
            load_temp_taxa_data(args.origin, session, args.csv_file_path)
        else:
            csv_file_path = f'/ibrida/metadata/{args.origin}/taxa.csv'
            load_temp_taxa_data(args.origin, session, csv_file_path)
    else:
        create_temp_taxa_table(session)
        if not args.use_existing_temp_table:
            if args.csv_file_path:
                load_temp_taxa_data(args.origin, session, args.csv_file_path)
            else:
                csv_file_path = f'/ibrida/metadata/{args.origin}/taxa.csv'
                load_temp_taxa_data(args.origin, session, csv_file_path)

    output_dir = f"diffs/{args.origin}"
    os.makedirs(output_dir, exist_ok=True)

    analyze_taxa_changes(args.origin, session, output_dir)

    taxa_groups = {
        "L60": [47120],
        "L50": [47163, 47124, 40151, 3, 26036, 20978, 47119, 47158],
        "L40": [47744, 47157, 47792, 47651, 47208, 47822, 47201]
    }
    analyze_specific_taxa_changes(args.origin, session, taxa_groups)

    session.close()


if __name__ == "__main__":
    main()