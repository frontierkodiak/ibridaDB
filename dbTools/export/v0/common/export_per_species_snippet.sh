#!/bin/bash
#
# export_per_species_snippet.sh
#
# This script performs a per-species random sampling export from an
# already-existing table. It does NOT drop or re-create the table.
# It's intended for quick usage to avoid re-running all upstream steps.
#
# Usage: set environment variables before calling, e.g.:
#   export DB_CONTAINER="ibridaDB"
#   export DB_USER="postgres"
#   export DB_NAME="ibrida-v0-r1"
#   export EXPORT_GROUP="primary_terrestrial_arthropoda"
#   export EXPORT_DIR="/exports/v0/r1/primary_only_50min_4000max"
#   export MAX_RN=4000
#   export PRIMARY_ONLY=true
#   Then run:
#   ./export_per_species_snippet.sh
#

# CLARIFY: We assume that the user already has a table named ${EXPORT_GROUP}_observations
#          that includes all columns needed, and a 'photos' table too.
# ASSUMPTION: The container user has write access to $EXPORT_DIR.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/functions.sh"

TABLE_NAME="${EXPORT_GROUP}_observations"

print_progress "Starting quick per-species export from existing table: ${TABLE_NAME}"

# The actual COPY logic is adapted from cladistic.sh, focusing on partition-based random sampling:
if [ "${PRIMARY_ONLY}" = true ]; then
    # Photos with position=0, quality_grade='research'
    execute_sql "
COPY (
  WITH per_species AS (
    SELECT
      o.*,
      p.photo_uuid,
      p.photo_id,
      p.extension,
      p.license,
      p.width,
      p.height,
      p.position,
      ROW_NUMBER() OVER (
        PARTITION BY o.\"L10_taxonID\"
        ORDER BY random()
      ) AS species_rand_idx
    FROM \"${TABLE_NAME}\" o
    JOIN photos p ON o.observation_uuid = p.observation_uuid
    WHERE p.position = 0
      AND o.quality_grade = 'research'
  )
  SELECT *
  FROM per_species
  WHERE
    (\"L10_taxonID\" IS NULL)
    OR (\"L10_taxonID\" IS NOT NULL AND species_rand_idx <= ${MAX_RN})
) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv'
WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"
else
    # All photos for the final set, restricted to quality_grade='research'
    execute_sql "
COPY (
  WITH per_species AS (
    SELECT
      o.*,
      p.photo_uuid,
      p.photo_id,
      p.extension,
      p.license,
      p.width,
      p.height,
      p.position,
      ROW_NUMBER() OVER (
        PARTITION BY o.\"L10_taxonID\"
        ORDER BY random()
      ) AS species_rand_idx
    FROM \"${TABLE_NAME}\" o
    JOIN photos p ON o.observation_uuid = p.observation_uuid
    WHERE o.quality_grade = 'research'
  )
  SELECT *
  FROM per_species
  WHERE
    (\"L10_taxonID\" IS NULL)
    OR (\"L10_taxonID\" IS NOT NULL AND species_rand_idx <= ${MAX_RN})
) TO '${EXPORT_DIR}/${EXPORT_GROUP}_photos.csv'
WITH (FORMAT CSV, HEADER, DELIMITER E'\t');
"
fi

print_progress "Quick per-species export complete."