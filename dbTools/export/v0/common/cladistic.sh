#!/bin/bash
# ------------------------------------------------------------------------------
# cladistic.sh
# ------------------------------------------------------------------------------
# Creates filtered observation subsets for a specified clade/metaclade,
# referencing the "expanded_taxa" table instead of the old recursive string method.
#
# Usage pattern:
#   1) Environment variables set by an upstream wrapper or main script:
#      - METACLADE=...
#      - CLADE=...
#      - MACROCLADE=...
#      - DB_CONTAINER, DB_USER, DB_NAME
#      - REGION_TAG, MIN_OBS, ...
#      - MAX_RN (the max number of observations to keep per species)
#      - PRIMARY_ONLY (whether to restrict photos to position=0)
#   2) We load "clade_defns.sh" to define which integer columns to match
#      (e.g. "L50_taxonID" = 47120).
#   3) We create a final table <group>_observations joined to expanded_taxa
#      so only active, recognized taxonIDs appear.
#   4) We then export to CSV with a random subset of photos. 
#      The new requirement: we must include the entire ancestral taxonID set
#      (L5_taxonID, L10_taxonID, ... L70_taxonID) plus expanded_taxa.taxonID,
#      expanded_taxa.rankLevel, and expanded_taxa.name.
#   5) The environment variable "EXPORT_GROUP" is used to name the final table
#      and output CSV (e.g. "primary_terrestrial_arthropoda").
#
# NOTES:
#   - The final summary stats are now handled by main.sh, so we only
#     create the table and do the CSV export here.
#   - If you need partial stats or debugging, you can log them here, but do not
#     overwrite export_summary.txt. main.sh will unify everything at the end.
# ------------------------------------------------------------------------------
# Permission / Ownership Note:
#   If you see "Operation not permitted" when chmod-ing existing CSV files, it
#   usually means the container user (UID 998) cannot change permissions on a
#   file already owned by another user. As long as the directory is world-writable
#   (e.g. drwxrwxrwx) and the file is not locked down, Postgres should still be
#   able to write new CSV data. However, if you see actual "permission denied"
#   errors at export time, confirm the directory and file ownership allow writes.
# ------------------------------------------------------------------------------

source "${BASE_DIR}/common/functions.sh"
source "${BASE_DIR}/common/clade_defns.sh"

CLADE_CONDITION="$(get_clade_condition)"
print_progress "Creating filtered tables for ${EXPORT_GROUP}"

TABLE_NAME="${EXPORT_GROUP}_observations"
REGIONAL_TABLE="${REGION_TAG}_min${MIN_OBS}_all_taxa_obs"
OBS_COLUMNS="$(get_obs_columns)"

# Drop old table if it exists
execute_sql "
DROP TABLE IF EXISTS \"${TABLE_NAME}\" CASCADE;
"

# Create new table by joining region-based table to expanded_taxa
# We also apply the clade condition and ensure e."taxonActive"=TRUE.
send_notification "Joining regional table ${REGIONAL_TABLE} to expanded_taxa"
print_progress "Joining regional table ${REGIONAL_TABLE} to expanded_taxa"

execute_sql "
CREATE TABLE \"${TABLE_NAME}\" AS
SELECT
    ${OBS_COLUMNS},
    e.\"taxonID\"         AS expanded_taxonID,
    e.\"rankLevel\"       AS expanded_rankLevel,
    e.\"name\"            AS expanded_name,
    e.\"L5_taxonID\",
    e.\"L10_taxonID\",
    e.\"L11_taxonID\",
    e.\"L12_taxonID\",
    e.\"L13_taxonID\",
    e.\"L15_taxonID\",
    e.\"L20_taxonID\",
    e.\"L24_taxonID\",
    e.\"L25_taxonID\",
    e.\"L26_taxonID\",
    e.\"L27_taxonID\",
    e.\"L30_taxonID\",
    e.\"L32_taxonID\",
    e.\"L33_taxonID\",
    e.\"L33_5_taxonID\",
    e.\"L34_taxonID\",
    e.\"L34_5_taxonID\",
    e.\"L35_taxonID\",
    e.\"L37_taxonID\",
    e.\"L40_taxonID\",
    e.\"L43_taxonID\",
    e.\"L44_taxonID\",
    e.\"L45_taxonID\",
    e.\"L47_taxonID\",
    e.\"L50_taxonID\",
    e.\"L53_taxonID\",
    e.\"L57_taxonID\",
    e.\"L60_taxonID\",
    e.\"L67_taxonID\",
    e.\"L70_taxonID\"
FROM \"${REGIONAL_TABLE}\" obs
JOIN \"expanded_taxa\" e
   ON e.\"taxonID\" = obs.taxon_id
WHERE e.\"taxonActive\" = TRUE
  AND ${CLADE_CONDITION};
"

# Export to CSV with partition-based random sampling
send_notification "Exporting filtered observations"
print_progress "Exporting filtered observations"

if [ "${PRIMARY_ONLY}" = true ]; then
    # Only position=0 photos, research-grade, up to MAX_RN per species
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
    # All photos, but only up to MAX_RN for species-level
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

# Removed final summary from here. We do that in main.sh.
print_progress "Cladistic filtering complete"