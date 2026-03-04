#!/usr/bin/env python3
"""
Resolve anthophila scientific names to taxon_id using taxa/expanded_taxa tables.

Usage:
  uv run python3 scripts/resolve_anthophila_taxa.py \
    --manifest anthophila_duplicates.csv \
    --output anthophila_duplicates_resolved.csv \
    --db-connection "postgresql://postgres@localhost/ibrida-v0"
"""

import argparse
import os
from pathlib import Path
from typing import Dict, List, Tuple

import pandas as pd
import psycopg2
from psycopg2.extras import RealDictCursor

RANK_LEVEL_GUESS = {
    "subspecies": 5.0,
    "species": 10.0,
    "genus": 20.0,
}


def connect_to_database(connection_string: str):
    try:
        return psycopg2.connect(connection_string)
    except psycopg2.Error as exc:
        raise RuntimeError(f"Error connecting to database: {exc}") from exc


def choose_best_candidate(candidates: List[Dict], rank_guess: str) -> Dict:
    if not candidates:
        return {}

    target_level = RANK_LEVEL_GUESS.get(rank_guess)
    if target_level is None:
        # Prefer lowest rank_level (closest to species) if no rank guess
        return sorted(candidates, key=lambda row: (row.get("rank_level") is None, row.get("rank_level", 1e9), row["taxon_id"]))[0]

    def score(row: Dict) -> Tuple[float, int]:
        rank_level = row.get("rank_level")
        if rank_level is None:
            return (1e9, row["taxon_id"])
        return (abs(rank_level - target_level), row["taxon_id"])

    return sorted(candidates, key=score)[0]


def get_table_columns(conn, table_name: str) -> List[str]:
    with conn.cursor(cursor_factory=RealDictCursor) as cursor:
        cursor.execute(
            """
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s
            """,
            (table_name,),
        )
        return [row["column_name"] for row in cursor.fetchall()]


def quote_ident(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def resolve_column_mapping(columns: List[str], table_name: str) -> Dict[str, str]:
    column_set = set(columns)
    candidates: Dict[str, List[str]] = {
        "taxon_id": ["taxon_id", "taxonID", "id"],
        "name": ["name"],
        "rank_level": ["rank_level", "rankLevel"],
        "rank": ["rank"],
        "active": ["active", "taxonActive"],
    }

    mapping: Dict[str, str] = {}
    for logical_name, options in candidates.items():
        for option in options:
            if option in column_set:
                mapping[logical_name] = option
                break

    required = ["taxon_id", "name", "rank_level", "rank"]
    missing = [key for key in required if key not in mapping]
    if missing:
        raise RuntimeError(
            f"{table_name} missing required columns for taxa resolution: {missing} "
            f"(available={sorted(columns)})"
        )

    return mapping


def fetch_name_map(conn, names: List[str], table_name: str) -> Dict[str, List[Dict]]:
    name_map: Dict[str, List[Dict]] = {name: [] for name in names}
    if not names:
        return name_map

    batch_size = 1000
    columns = get_table_columns(conn, table_name)
    column_mapping = resolve_column_mapping(columns, table_name)
    select_cols = [
        f"{quote_ident(column_mapping['taxon_id'])} AS taxon_id",
        f"{quote_ident(column_mapping['name'])} AS name",
        f"{quote_ident(column_mapping['rank_level'])} AS rank_level",
        f"{quote_ident(column_mapping['rank'])} AS rank",
    ]
    if "active" in column_mapping:
        select_cols.append(f"{quote_ident(column_mapping['active'])} AS active")

    table_ident = quote_ident(table_name)
    name_col = quote_ident(column_mapping["name"])

    with conn.cursor(cursor_factory=RealDictCursor) as cursor:
        for i in range(0, len(names), batch_size):
            batch = names[i : i + batch_size]
            cursor.execute(
                f"SELECT {', '.join(select_cols)} FROM {table_ident} WHERE lower({name_col}) = ANY(%s)",
                (batch,),
            )
            for row in cursor.fetchall():
                key = row["name"].lower()
                name_map.setdefault(key, []).append(row)

    return name_map


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve anthophila scientific names to taxon IDs")
    parser.add_argument("--manifest", required=True, help="Input CSV (deduped manifest)")
    parser.add_argument("--output", required=True, help="Output CSV with taxon_id columns")
    parser.add_argument(
        "--db-connection",
        default=os.getenv("IBRIDADB_DSN", "postgresql://postgres@localhost/ibrida-v0"),
        help="PostgreSQL connection string (prefer env/.pgpass over inline passwords)",
    )
    parser.add_argument(
        "--prefer-expanded-taxa",
        action="store_true",
        help="Force using expanded_taxa when available",
    )

    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    output_path = Path(args.output)

    if not manifest_path.exists():
        print(f"Error: Manifest file not found: {manifest_path}")
        return 1

    df = pd.read_csv(manifest_path)
    if "scientific_name_norm" not in df.columns:
        print("Error: manifest missing scientific_name_norm column")
        return 1

    df["scientific_name_norm"] = df["scientific_name_norm"].astype(str)
    df["rank_guess"] = df.get("rank_guess", pd.Series(["unknown"] * len(df)))

    names = sorted({name.lower() for name in df["scientific_name_norm"].dropna() if name})

    conn = connect_to_database(args.db_connection)
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute("SELECT to_regclass('public.expanded_taxa') AS tbl")
            expanded_tbl = cursor.fetchone().get("tbl")

        table_name = "expanded_taxa" if (expanded_tbl and args.prefer_expanded_taxa) else "taxa"
        if expanded_tbl and not args.prefer_expanded_taxa:
            # If expanded_taxa exists, prefer it by default (more columns + indexing)
            table_name = "expanded_taxa"

        print(f"Resolving taxa using table: {table_name}")

        name_map = fetch_name_map(conn, names, table_name)

        taxon_ids = []
        taxon_ranks = []
        taxon_rank_levels = []
        taxonomy_status = []

        for _, row in df.iterrows():
            name_key = str(row["scientific_name_norm"]).lower()
            candidates = name_map.get(name_key, [])
            if not candidates:
                taxon_ids.append("")
                taxon_ranks.append("")
                taxon_rank_levels.append("")
                taxonomy_status.append("no_match")
                continue

            chosen = choose_best_candidate(candidates, row.get("rank_guess", "unknown"))
            taxon_ids.append(chosen.get("taxon_id", ""))
            taxon_ranks.append(chosen.get("rank", ""))
            taxon_rank_levels.append(chosen.get("rank_level", ""))
            taxonomy_status.append("multiple_match" if len(candidates) > 1 else "exact_match")

        df["taxon_id"] = taxon_ids
        df["taxon_rank"] = taxon_ranks
        df["taxon_rank_level"] = taxon_rank_levels
        df["taxonomy_status"] = taxonomy_status

        df.to_csv(output_path, index=False)
        print(f"Resolved manifest written to {output_path}")

        unresolved = df[df["taxonomy_status"] == "no_match"]["scientific_name_norm"].unique().tolist()
        if unresolved:
            unresolved_path = output_path.with_suffix(".unresolved.csv")
            pd.DataFrame({"scientific_name_norm": unresolved}).to_csv(unresolved_path, index=False)
            print(f"Unresolved names written to {unresolved_path}")

    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
