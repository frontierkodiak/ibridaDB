import os
import csv
from sqlalchemy import create_engine, Column, Integer, String, Float, Date, Boolean, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from ibridaDB.schema import Observations, Photos, Taxa, TaxaTemp, Observers
import logging

# Setup basic configuration for logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')


def create_db_engine(db_user, db_password, db_host, db_port, db_name):
    connection_string = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"
    return create_engine(connection_string)

def analyze_taxa_changes(origin, session):
    output_dir = f"diffs/{origin}"
    try:
        os.makedirs(output_dir, exist_ok=True)
        TaxaTemp.__table__.create(session.bind, checkfirst=True)

        csv_file_path = f'/ibrida/metadata/{origin}/taxa.csv'
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
    except Exception as e:
        logging.error(f"Failed to import new taxa data to temp table: {e}")
        session.rollback()
    else:
        logging.info("Imported new taxa data to temp table successfully.")

    # Count the number of taxon IDs in the new taxa data
    new_taxon_count = session.query(TaxaTemp).count()
    with open(f"{output_dir}/new_taxon_count.csv", "w") as f:
        f.write(f"new_taxon_count\n{new_taxon_count}\n")

    # Find taxon IDs that exist in the existing table but not in the new data
    deprecated_taxon_ids = session.query(Taxa.taxon_id).filter(~Taxa.taxon_id.in_(session.query(TaxaTemp.taxon_id))).all()
    with open(f"{output_dir}/deprecated_taxon_ids.csv", "w") as f:
        f.write("taxon_id\n")
        for taxon_id in deprecated_taxon_ids:
            f.write(f"{taxon_id[0]}\n")

    # Find taxon IDs that exist in the new data but not in the existing table
    new_taxon_ids = session.query(TaxaTemp.taxon_id, TaxaTemp.ancestry, TaxaTemp.rank_level, TaxaTemp.active).filter(~TaxaTemp.taxon_id.in_(session.query(Taxa.taxon_id))).all()
    with open(f"{output_dir}/new_taxon_ids.csv", "w") as f:
        f.write("taxon_id,ancestry,rank_level,active\n")
        for taxon_id, ancestry, rank_level, active in new_taxon_ids:
            f.write(f"{taxon_id},{ancestry},{rank_level},{active}\n")

    # Find taxon IDs that have changed attributes
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

    # List taxon IDs whose 'active' values have changed
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

    # List taxon IDs whose 'name' value differs
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

    # Count observations with inactive taxon IDs
    inactive_observations_count = session.query(Observations).join(Taxa, Observations.taxon_id == Taxa.taxon_id).filter(Taxa.active == False).count()
    with open(f"{output_dir}/inactive_observations_count.csv", "w") as f:
        f.write(f"inactive_observations_count\n{inactive_observations_count}\n")

def main():
    db_user = "postgres"
    db_password = "password"
    db_host = "localhost"
    db_port = "5432"
    db_name = "postgres"

    engine = create_db_engine(db_user, db_password, db_host, db_port, db_name)
    Session = sessionmaker(bind=engine)
    session = Session()

    origin = "May2024"
    analyze_taxa_changes(origin, session)

    session.close()

if __name__ == "__main__":
    main()
